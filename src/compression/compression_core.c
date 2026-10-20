#include "compression_core.h"
#include "vendor/runtime/lib/include/tree_sitter/api.h"
#include <stdlib.h>
#include <string.h>

const TSLanguage *tree_sitter_javascript(void);
const TSLanguage *tree_sitter_typescript(void);
const TSLanguage *tree_sitter_tsx(void);
const TSLanguage *tree_sitter_python(void);

typedef struct {
  SCPlan plan;
  int python;
  const char *source;
} Selection;

static int is(TSNode node, const char *type) {
  return !ts_node_is_null(node) && strcmp(ts_node_type(node), type) == 0;
}

static TSNode field(TSNode node, const char *name) {
  return ts_node_child_by_field_name(node, name, (uint32_t)strlen(name));
}

static void select_node(Selection *s, TSNode node, int keep) {
  if (ts_node_is_null(node)) return;
  uint32_t start = ts_node_start_byte(node), end = ts_node_end_byte(node);
  if (start <= end && end <= s->plan.length)
    memset(s->plan.keep + start, keep, end - start);
}

/* Remove entire physical lines only when the statement occupies them alone.
 * Inline bodies still use exact AST byte bounds. */
static void remove_statement(Selection *s, TSNode node) {
  uint32_t start = ts_node_start_byte(node), end = ts_node_end_byte(node);
  uint32_t a = start, b = end;
  while (a > 0 && (s->source[a - 1] == ' ' || s->source[a - 1] == '\t')) --a;
  while (b < s->plan.length && (s->source[b] == ' ' || s->source[b] == '\t' || s->source[b] == '\r')) ++b;
  if ((a == 0 || s->source[a - 1] == '\n') &&
      (b == s->plan.length || s->source[b] == '\n')) {
    if (b < s->plan.length) ++b;
    memset(s->plan.keep + a, 0, b - a);
  } else {
    select_node(s, node, 0);
  }
}

static int callable(TSNode node) {
  return is(node, "function_declaration") || is(node, "generator_function_declaration") ||
    is(node, "function_expression") || is(node, "function") ||
    is(node, "generator_function") || is(node, "arrow_function") ||
    is(node, "method_definition") || is(node, "function_definition") ||
    is(node, "lambda");
}

static int classlike(TSNode node) {
  return is(node, "class_declaration") || is(node, "class") ||
    is(node, "abstract_class_declaration") || is(node, "class_definition");
}

static int importlike(TSNode node) {
  return is(node, "import_statement") || is(node, "import_from_statement") ||
    is(node, "future_import_statement") || is(node, "import_alias");
}

static int type_declaration(TSNode node) {
  return is(node, "interface_declaration") || is(node, "type_alias_declaration") ||
    is(node, "enum_declaration") || is(node, "type_alias_statement") ||
    is(node, "function_signature") || is(node, "method_signature") ||
    is(node, "abstract_method_signature");
}

static int structural(TSNode node) {
  return is(node, "if_statement") || is(node, "elif_clause") ||
    is(node, "else_clause") || is(node, "for_statement") ||
    is(node, "for_in_statement") || is(node, "while_statement") ||
    is(node, "do_statement") || is(node, "try_statement") ||
    is(node, "except_clause") || is(node, "except_group_clause") ||
    is(node, "finally_clause") || is(node, "catch_clause") ||
    is(node, "with_statement") || is(node, "match_statement") ||
    is(node, "case_clause") || is(node, "switch_statement") ||
    is(node, "switch_body") || is(node, "switch_case") ||
    is(node, "switch_default");
}

static void walk(Selection *, TSNode, unsigned, int);
static void statements(Selection *, TSNode, unsigned, int);

/* Keep enclosing conditions only when they contain an outline declaration.
 * Comments are restored separately, including their physical line breaks. */
static int contains_outline(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status || ts_node_is_null(node)) return 0;
  if (depth > 512) { s->plan.status = 3; return 0; }
  if (callable(node) || classlike(node) || type_declaration(node) || importlike(node)) return 1;
  if (s->python && is(node, "expression_statement") &&
      is(ts_node_named_child(node, 0), "string")) return 1;
  uint32_t n = ts_node_named_child_count(node);
  for (uint32_t i = 0; i < n; ++i)
    if (contains_outline(s, ts_node_named_child(node, i), depth + 1)) return 1;
  return 0;
}

static int implementation_statement(TSNode node) {
  if (is(node, "lexical_declaration") || is(node, "variable_declaration")) {
    /* A loop header is not its single-statement body. Keep its binding. */
    TSNode parent = ts_node_parent(node);
    return !is(parent, "for_statement") && !is(parent, "for_in_statement");
  }
  const char *type = ts_node_type(node);
  size_t length = strlen(type);
  return length >= 10 && strcmp(type + length - 10, "_statement") == 0;
}

static void initializer(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status || ts_node_is_null(node)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (callable(node) || classlike(node) || is(node, "object")) {
    walk(s, node, depth + 1, 0);
  } else if (is(node, "parenthesized_expression")) {
    uint32_t n = ts_node_named_child_count(node);
    if (n == 1) initializer(s, ts_node_named_child(node, 0), depth + 1);
    else select_node(s, node, 0);
  } else if (ts_node_end_byte(node) - ts_node_start_byte(node) >
             (uint32_t)(s->python ? 3 : 9)) {
    /* Replacing a short scalar/reference with a longer omission marker loses
     * information and increases size. Keep the original fragment instead. */
    select_node(s, node, 0);
  }
}

static void walk(Selection *s, TSNode node, unsigned depth, int local) {
  if (s->plan.status || ts_node_is_null(node)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (callable(node)) {
    TSNode body = field(node, "body");
    if (is(body, "statement_block") || is(body, "block")) {
      statements(s, body, depth + 1, 1);
    } else {
      select_node(s, body, 0);
    }
    return;
  }
  if (classlike(node)) {
    TSNode body = field(node, "body");
    statements(s, body, depth + 1, 0);
    return;
  }
  if (type_declaration(node) || importlike(node) || is(node, "comment")) return;
  if (local && (structural(node) || implementation_statement(node)) &&
      !contains_outline(s, node, depth + 1)) {
    remove_statement(s, node);
    return;
  }
  if (is(node, "variable_declarator") || is(node, "public_field_definition") ||
      is(node, "field_definition") || is(node, "pair")) {
    TSNode value = field(node, "value");
    if (!ts_node_is_null(value)) initializer(s, value, depth + 1);
    return;
  }
  if (is(node, "assignment") || is(node, "augmented_assignment")) {
    TSNode right = field(node, "right");
    /* Conventional Python type aliases are ordinary name assignments. Preserve
     * non-local bindings, as the upstream Python type-alias query does; inline
     * lambdas still need their implementation expression removed. */
    if (s->python && !local && is(node, "assignment") &&
        is(field(node, "left"), "identifier") && !callable(right)) return;
    initializer(s, right, depth + 1);
    return;
  }
  if (is(node, "class_static_block")) {
    statements(s, field(node, "body"), depth + 1, 1);
    return;
  }
  if (is(node, "statement_block") || is(node, "block") ||
      is(node, "program") || is(node, "module") || is(node, "class_body")) {
    statements(s, node, depth + 1, local);
    return;
  }
  uint32_t n = ts_node_named_child_count(node);
  for (uint32_t i = 0; i < n; ++i)
    walk(s, ts_node_named_child(node, i), depth + 1, local);
}

/* Local data statements are implementation, but locally named functions and
 * classes still belong to the outline (including arrow/lambda bindings). */
static int signature_binding(TSNode node, unsigned depth) {
  if (depth > 512 || ts_node_is_null(node)) return 0;
  if (callable(node) || classlike(node)) return 1;
  if (is(node, "variable_declarator") || is(node, "pair"))
    return signature_binding(field(node, "value"), depth + 1);
  if (is(node, "assignment"))
    return signature_binding(field(node, "right"), depth + 1);
  if (!(is(node, "lexical_declaration") || is(node, "variable_declaration") ||
        is(node, "expression_statement") || is(node, "parenthesized_expression") ||
        is(node, "object"))) return 0;
  uint32_t n = ts_node_named_child_count(node);
  for (uint32_t i = 0; i < n; ++i)
    if (signature_binding(ts_node_named_child(node, i), depth + 1)) return 1;
  return 0;
}

static void statements(Selection *s, TSNode node, unsigned depth, int local) {
  if (s->plan.status || ts_node_is_null(node)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  uint32_t n = ts_node_named_child_count(node);
  int first = 1;
  for (uint32_t i = 0; i < n; ++i) {
    TSNode child = ts_node_named_child(node, i);
    if (is(child, "comment")) continue;
    int docstring = s->python && first && is(child, "expression_statement") &&
      is(ts_node_named_child(child, 0), "string");
    first = 0;
    if (docstring || importlike(child) || type_declaration(child)) continue;
    if (callable(child) || classlike(child) || is(child, "decorated_definition") ||
        is(child, "export_statement") || structural(child) ||
        is(child, "class_static_block")) {
      walk(s, child, depth + 1, local);
    } else if (local && signature_binding(child, depth + 1)) {
      walk(s, child, depth + 1, local);
    } else if (!local && (is(child, "lexical_declaration") ||
               is(child, "variable_declaration") || is(child, "public_field_definition") ||
               is(child, "field_definition") || is(child, "ambient_declaration") ||
               is(child, "internal_module") || is(child, "module") ||
               is(child, "property_signature") || is(child, "index_signature"))) {
      walk(s, child, depth + 1, 0);
    } else if (!local && s->python && is(child, "expression_statement") &&
               is(ts_node_named_child(child, 0), "assignment")) {
      walk(s, child, depth + 1, 0);
    } else {
      remove_statement(s, child);
    }
  }
}

/* Preserve comments even inside discarded expressions, conservatively treating
 * every AST comment as significant. Never try to recognize comments lexically. */
static void comments(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (is(node, "comment")) {
    select_node(s, node, 1);
    /* A removed statement may have owned the following newline. Without it,
     * adjacent // comments become one line and swallow the next fragment. */
    uint32_t end = ts_node_end_byte(node);
    if (end < s->plan.length && s->source[end] == '\r') s->plan.keep[end++] = 1;
    if (end < s->plan.length && s->source[end] == '\n') s->plan.keep[end] = 1;
    return;
  }
  uint32_t n = ts_node_named_child_count(node);
  for (uint32_t i = 0; i < n; ++i)
    comments(s, ts_node_named_child(node, i), depth + 1);
}

SCPlan sc_plan(int32_t language, const char *source, uint32_t length,
               uint64_t timeout_micros) {
  Selection s = {{NULL, length, 0}, language == 3, source};
  if (length > 8 * 1024 * 1024) { s.plan.status = 3; return s.plan; }
  const TSLanguage *grammar = NULL;
  switch (language) {
    case 0: grammar = tree_sitter_javascript(); break;
    case 1: grammar = tree_sitter_typescript(); break;
    case 2: grammar = tree_sitter_tsx(); break;
    case 3: grammar = tree_sitter_python(); break;
    default: s.plan.status = 4; return s.plan;
  }
  TSParser *parser = ts_parser_new();
  if (!parser || !ts_parser_set_language(parser, grammar)) {
    if (parser) ts_parser_delete(parser);
    s.plan.status = 4;
    return s.plan;
  }
  /* This API is available in the pinned 0.25.3 runtime, including Windows. */
  ts_parser_set_timeout_micros(parser, timeout_micros);
  TSTree *tree = ts_parser_parse_string(parser, NULL, source, length);
  if (!tree) {
    s.plan.status = 2;
  } else if (ts_node_has_error(ts_tree_root_node(tree))) {
    s.plan.status = 1;
  } else {
    s.plan.keep = malloc(length ? length : 1);
    if (!s.plan.keep) {
      s.plan.status = 3;
    } else {
      memset(s.plan.keep, 1, length);
      walk(&s, ts_tree_root_node(tree), 0, 0);
      comments(&s, ts_tree_root_node(tree), 0);
    }
  }
  if (tree) ts_tree_delete(tree);
  ts_parser_delete(parser);
  if (s.plan.status) { free(s.plan.keep); s.plan.keep = NULL; }
  return s.plan;
}
