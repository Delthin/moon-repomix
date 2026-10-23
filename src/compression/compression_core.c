#include "compression_core.h"
#include "vendor/runtime/lib/include/tree_sitter/api.h"
#include <stdlib.h>
#include <string.h>

const TSLanguage *tree_sitter_javascript(void);
const TSLanguage *tree_sitter_typescript(void);
const TSLanguage *tree_sitter_tsx(void);
const TSLanguage *tree_sitter_python(void);
const TSLanguage *tree_sitter_moonbit(void);
const TSLanguage *tree_sitter_go(void);
const TSLanguage *tree_sitter_rust(void);
const TSLanguage *tree_sitter_java(void);

typedef struct {
  SCPlan plan;
  int python;
  const char *source;
} Selection;

static int is(TSNode node, const char *type) {
  return !ts_node_is_null(node) && strcmp(ts_node_type(node), type) == 0;
}

static TSNode field(TSNode node, const char *name) {
  return ts_node_is_null(node) ? (TSNode){0} :
    ts_node_child_by_field_name(node, name, (uint32_t)strlen(name));
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
static int signature_binding(Selection *, TSNode, unsigned);

static int js_assignment(TSNode node) {
  return is(node, "assignment_expression");
}

/* Member assignments describe JS APIs even when installed inside a callback.
 * Plain identifier assignments remain implementation unless directly callable. */
static int text_is(Selection *s, TSNode node, const char *text) {
  uint32_t start = ts_node_start_byte(node), end = ts_node_end_byte(node);
  return !ts_node_is_null(node) && end - start == strlen(text) &&
    memcmp(s->source + start, text, end - start) == 0;
}

static int member_assignment(Selection *s, TSNode node) {
  if (!js_assignment(node)) return 0;
  TSNode left = field(node, "left"), right = field(node, "right");
  if (!(is(left, "member_expression") || is(left, "subscript_expression"))) return 0;
  TSNode base = left;
  while (is(base, "member_expression") || is(base, "subscript_expression")) {
    TSNode object = field(base, "object");
    TSNode property = field(base, is(base, "member_expression") ? "property" : "index");
    if (text_is(s, object, "module") &&
        (text_is(s, property, "exports") || text_is(s, property, "'exports'") ||
         text_is(s, property, "\"exports\""))) return 1;
    base = object;
  }
  if (text_is(s, base, "exports")) return 1;
  return callable(right) || classlike(right) || is(right, "identifier") ||
    is(right, "member_expression") || is(right, "subscript_expression") ||
    js_assignment(right);
}

/* Keep enclosing conditions only when they contain an outline declaration.
 * Comments are restored separately, including their physical line breaks. */
static int contains_outline(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status || ts_node_is_null(node)) return 0;
  if (depth > 512) { s->plan.status = 3; return 0; }
  if (classlike(node) || type_declaration(node) || importlike(node) ||
      is(node, "function_declaration") || is(node, "generator_function_declaration") ||
      is(node, "function_definition") || is(node, "method_definition") ||
      member_assignment(s, node)) return 1;
  if ((is(node, "lexical_declaration") || is(node, "variable_declaration") ||
       is(node, "expression_statement")) && signature_binding(s, node, depth + 1)) return 1;
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

static int same_name(Selection *s, TSNode a, TSNode b) {
  return !ts_node_is_null(a) && !ts_node_is_null(b) &&
    ts_node_end_byte(a) - ts_node_start_byte(a) == ts_node_end_byte(b) - ts_node_start_byte(b) &&
    memcmp(s->source + ts_node_start_byte(a), s->source + ts_node_start_byte(b),
           ts_node_end_byte(a) - ts_node_start_byte(a)) == 0;
}

/* Search one lexical environment without entering initializers or types. */
static TSNode scope_binding(Selection *s, TSNode node, TSNode name, unsigned depth) {
  if (depth > 512) { s->plan.status = 3; return (TSNode){0}; }
  if (ts_node_is_null(node)) return (TSNode){0};
  if (is(node, "assignment_pattern"))
    return scope_binding(s, field(node, "left"), name, depth + 1);
  TSNode declared = field(node, "name");
  if (same_name(s, declared, name)) return node;
  if ((is(node, "identifier") || is(node, "shorthand_property_identifier_pattern")) &&
      same_name(s, node, name)) return node;
  if (callable(node) || classlike(node) || type_declaration(node)) return (TSNode){0};
  if (!(is(node, "lexical_declaration") || is(node, "variable_declaration") ||
        is(node, "export_statement") || is(node, "formal_parameters") ||
        is(node, "required_parameter") || is(node, "optional_parameter") ||
        is(node, "object_pattern") || is(node, "array_pattern") ||
        is(node, "pair_pattern") || is(node, "assignment_pattern") ||
        is(node, "rest_pattern") || is(node, "import_statement") ||
        is(node, "import_clause") || is(node, "named_imports") ||
        is(node, "import_specifier") || is(node, "namespace_import") ||
        is(node, "variable_declarator"))) return (TSNode){0};
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i) {
    TSNode child = ts_node_named_child(node, i);
    if (ts_node_eq(child, field(node, "value")) || ts_node_eq(child, field(node, "type"))) continue;
    TSNode found = scope_binding(s, child, name, depth + 1);
    if (!ts_node_is_null(found)) return found;
  }
  return (TSNode){0};
}

/* var declarations and block functions can shadow an outer table even when
 * nested in a branch (including Annex B function declarations). */
static TSNode hoisted_binding(Selection *s, TSNode node, TSNode name, unsigned depth) {
  if (depth > 512) { s->plan.status = 3; return (TSNode){0}; }
  if (ts_node_is_null(node)) return (TSNode){0};
  if (is(node, "variable_declaration") || callable(node) || classlike(node))
    return scope_binding(s, node, name, depth + 1);
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i) {
    TSNode found = hoisted_binding(s, ts_node_named_child(node, i), name, depth + 1);
    if (!ts_node_is_null(found)) return found;
  }
  return (TSNode){0};
}

static TSNode binding(Selection *s, TSNode from, TSNode name) {
  if (ts_node_is_null(from) || ts_node_is_null(name)) return (TSNode){0};
  for (TSNode scope = ts_node_parent(from); !ts_node_is_null(scope); scope = ts_node_parent(scope)) {
    if (callable(scope)) {
      TSNode found = scope_binding(s, field(scope, "parameters"), name, 0);
      if (!ts_node_is_null(found)) return found;
      if (same_name(s, field(scope, "parameter"), name)) return scope;
      TSNode body = field(scope, "body");
      /* Parameter defaults and signature types cannot see body-local vars. */
      if (!ts_node_is_null(body) && ts_node_start_byte(from) >= ts_node_start_byte(body) &&
          ts_node_end_byte(from) <= ts_node_end_byte(body)) {
        found = hoisted_binding(s, body, name, 0);
        if (!ts_node_is_null(found)) return found;
      }
    } else if (is(scope, "for_in_statement") || is(scope, "for_statement") || is(scope, "catch_clause")) {
      TSNode pattern = field(scope, is(scope, "catch_clause") ? "parameter" :
                                   is(scope, "for_statement") ? "initializer" : "left");
      TSNode found = scope_binding(s, pattern, name, 0);
      if (!ts_node_is_null(found)) return found;
    } else if (is(scope, "statement_block") || is(scope, "program")) {
      for (uint32_t i = 0; i < ts_node_named_child_count(scope); ++i) {
        TSNode found = scope_binding(s, ts_node_named_child(scope, i), name, 0);
        if (!ts_node_is_null(found)) return found;
      }
    }
  }
  return (TSNode){0};
}

static int scalar_type(Selection *s, TSNode node) {
  for (unsigned depth = 0; depth < 32; ++depth) {
    if (text_is(s, node, "string") || text_is(s, node, "number") || text_is(s, node, "boolean")) return 1;
    if (!is(node, "array_type")) return 0;
    node = ts_node_named_child(node, 0);
  }
  return 0;
}

static int scalar_value(TSNode node, unsigned depth) {
  if (depth > 32) return 0;
  if (is(node, "string") || is(node, "number") || is(node, "true") || is(node, "false")) return 1;
  if (!is(node, "array")) return 0;
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i) {
    TSNode child = ts_node_named_child(node, i);
    if (!is(child, "comment") && !scalar_value(child, depth + 1)) return 0;
  }
  return 1;
}

static int opaque_value(TSNode node, unsigned depth) {
  if (depth > 32) return 0;
  if (callable(node) || classlike(node) || is(node, "as_expression") ||
      is(node, "satisfies_expression") || is(node, "spread_element") ||
      is(node, "computed_property_name") || is(node, "object") ||
      is(node, "call_expression")) return 0;
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
    if (!opaque_value(ts_node_named_child(node, i), depth + 1)) return 0;
  return 1;
}

/* Widened scalar/array maps need two entries; inferred scalar and widened
 * constructor tables need eight. All require private index-only consumers. */
static int scalar_table(Selection *s, TSNode node) {
  if (!is(node, "variable_declarator") || !is(field(node, "name"), "identifier")) return 0;
  TSNode annotation = field(node, "type"), value_type = {0};
  int widened = 0;
  if (!ts_node_is_null(annotation)) {
    TSNode type = ts_node_named_child(annotation, 0);
    if (!is(type, "generic_type") || ts_node_named_child_count(type) != 2 ||
        !text_is(s, ts_node_named_child(type, 0), "Record") ||
        !ts_node_is_null(binding(s, type, ts_node_named_child(type, 0)))) return 0;
    TSNode args = ts_node_named_child(type, 1);
    if (!is(args, "type_arguments") || ts_node_named_child_count(args) != 2) return 0;
    TSNode key = ts_node_named_child(args, 0);
    if (!(text_is(s, key, "string") || text_is(s, key, "number"))) return 0;
    value_type = ts_node_named_child(args, 1);
    widened = scalar_type(s, value_type);
  }
  TSNode value = field(node, "value");
  if (!is(value, "object")) return 0;
  unsigned pairs = 0;
  int scalars = 1, constructors = is(value_type, "type_identifier") || is(value_type, "generic_type");
  for (uint32_t i = 0; i < ts_node_named_child_count(value); ++i) {
    TSNode pair = ts_node_named_child(value, i);
    if (is(pair, "comment")) continue;
    TSNode k = field(pair, "key"), v = field(pair, "value");
    if (!is(pair, "pair") ||
        !(is(k, "property_identifier") || is(k, "string") || is(k, "number"))) return 0;
    scalars = scalars && scalar_value(v, 0);
    constructors = constructors && is(v, "new_expression") && opaque_value(v, 0);
    ++pairs;
  }
  if (widened && scalars && pairs >= 2) return 1;
  /* Do not widen literal/union/object annotations on the strength of values. */
  if (pairs >= 8 && ((ts_node_is_null(annotation) && scalars) || constructors)) return 1;
  return 0;
}

/* Only indexed reads are private implementation. Bare/aliased/serialized uses
 * and type queries expose keys; same-spelled shadowed locals do not count. */
static int index_only(Selection *s, TSNode node, TSNode declaration, unsigned depth) {
  if (depth > 512) { s->plan.status = 3; return 0; }
  TSNode name = field(declaration, "name");
  if ((is(node, "identifier") || is(node, "shorthand_property_identifier")) &&
      same_name(s, node, name) && !ts_node_eq(node, name)) {
    TSNode bound = binding(s, node, node);
    if (!ts_node_eq(bound, declaration)) {
      /* Only definite value declarations prove that this is a different table.
       * Type-only names and mode-dependent block functions stay ambiguous. */
      int shadow = is(bound, "variable_declarator") || is(bound, "required_parameter") ||
        is(bound, "optional_parameter");
      if (is(bound, "identifier") || is(bound, "shorthand_property_identifier_pattern")) {
        TSNode owner = ts_node_parent(bound);
        shadow = is(owner, "formal_parameters") || is(owner, "required_parameter") ||
          is(owner, "optional_parameter") || is(owner, "rest_pattern") ||
          is(owner, "assignment_pattern") || is(owner, "object_pattern") ||
          is(owner, "array_pattern") || is(owner, "pair_pattern") || is(owner, "catch_clause");
        if (is(owner, "for_in_statement")) {
          for (uint32_t i = 0; i < ts_node_child_count(owner); ++i) {
            TSNode token = ts_node_child(owner, i);
            if (is(token, "const") || is(token, "let") || is(token, "var")) shadow = 1;
          }
        }
      }
      if (!shadow) return 0;
    } else {
      TSNode parent = ts_node_parent(node);
      for (TSNode ancestor = parent; !ts_node_is_null(ancestor); ancestor = ts_node_parent(ancestor))
        if (is(ancestor, "type_query")) return 0;
      if (!is(parent, "subscript_expression") || !ts_node_eq(field(parent, "object"), node)) return 0;
      for (TSNode use = ts_node_parent(parent); !ts_node_is_null(use); use = ts_node_parent(use)) {
        TSNode left = field(use, "left");
        if (((js_assignment(use) || is(use, "augmented_assignment_expression")) &&
             !ts_node_is_null(left) && ts_node_start_byte(left) <= ts_node_start_byte(parent) &&
             ts_node_end_byte(left) >= ts_node_end_byte(parent)) ||
            is(use, "update_expression") || is(use, "unary_expression")) return 0;
      }
    }
  }
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
    if (!index_only(s, ts_node_named_child(node, i), declaration, depth + 1)) return 0;
  return 1;
}

static int private_scalar_table(Selection *s, TSNode node, unsigned depth) {
  if (!scalar_table(s, node)) return 0;
  TSNode root = node;
  while (!ts_node_is_null(ts_node_parent(root))) {
    root = ts_node_parent(root);
    if (is(root, "export_statement")) return 0;
  }
  return index_only(s, root, node, depth + 1);
}

static void literal_outline(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (callable(node) || classlike(node)) {
    walk(s, node, depth + 1, 0);
    return;
  }
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
    literal_outline(s, ts_node_named_child(node, i), depth + 1);
}

static void initializer(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status || ts_node_is_null(node)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (callable(node) || classlike(node) || is(node, "object")) {
    walk(s, node, depth + 1, 0);
  } else if (is(node, "as_expression") || is(node, "satisfies_expression")) {
    /* Literal assertions may define public unions through typeof/keyof. */
    literal_outline(s, node, depth + 1);
  } else if (is(node, "identifier") || is(node, "member_expression") ||
             is(node, "subscript_expression")) {
    /* Binding aliases, especially CommonJS exports, are part of the outline. */
    return;
  } else if (is(node, "call_expression") &&
             text_is(s, field(node, "function"), "require") &&
             ts_node_named_child_count(field(node, "arguments")) == 1 &&
             is(ts_node_named_child(field(node, "arguments"), 0), "string")) {
    /* Static CommonJS imports/re-exports are binding aliases, not bodies. */
    return;
  } else if (js_assignment(node) || contains_outline(s, node, depth + 1)) {
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
    if (private_scalar_table(s, node, depth + 1)) select_node(s, value, 0);
    else if (!ts_node_is_null(value)) initializer(s, value, depth + 1);
    return;
  }
  if (is(node, "assignment") || is(node, "augmented_assignment") || js_assignment(node)) {
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
static int signature_binding(Selection *s, TSNode node, unsigned depth) {
  if (depth > 512 || ts_node_is_null(node)) return 0;
  if (callable(node) || classlike(node)) return 1;
  if (is(node, "variable_declarator") || is(node, "pair"))
    return signature_binding(s, field(node, "value"), depth + 1);
  if (member_assignment(s, node)) return 1;
  if (is(node, "assignment") || js_assignment(node))
    return signature_binding(s, field(node, "right"), depth + 1);
  if (!(is(node, "lexical_declaration") || is(node, "variable_declaration") ||
        is(node, "expression_statement") || is(node, "parenthesized_expression") ||
        is(node, "object"))) return 0;
  uint32_t n = ts_node_named_child_count(node);
  for (uint32_t i = 0; i < n; ++i)
    if (signature_binding(s, ts_node_named_child(node, i), depth + 1)) return 1;
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
    } else if (contains_outline(s, child, depth + 1)) {
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
  /* A folded table owns its implementation-category comments. Its binding
   * remains selected; ordinary discarded statements still restore comments. */
  if (is(node, "object") && is(ts_node_parent(node), "variable_declarator") &&
      s->plan.keep[ts_node_start_byte(ts_node_parent(node))] &&
      !s->plan.keep[ts_node_start_byte(node)]) return;
  if (is(node, "comment") || is(node, "block_comment") || is(node, "line_comment")) {
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

static int whitespace(char c) {
  return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

/* Compact only whitespace between AST children of statement/type containers.
 * Never inspect literal/comment contents or Python indentation as source lines. */
static void presentation(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status) return;
  if (depth > 512) { s->plan.status = 3; return; }
  int container = is(node, "program") || is(node, "module") ||
    is(node, "statement_block") || is(node, "block") || is(node, "class_body") ||
    is(node, "interface_body") || is(node, "enum_body") || is(node, "object");
  uint32_t n = ts_node_child_count(node), previous = ts_node_start_byte(node);
  for (uint32_t i = 0; i < n; ++i) {
    TSNode child = ts_node_child(node, i);
    uint32_t start = ts_node_start_byte(child), first = start, last = start;
    int only_space = 1;
    if (container) {
      for (uint32_t j = previous; j < start; ++j) {
        if (!whitespace(s->source[j])) { only_space = 0; break; }
        if (s->source[j] == '\n') {
          if (first == start) first = j;
          last = j;
        }
      }
      if (only_space && first < last)
        memset(s->plan.keep + first + 1, 0, last - first);
    }
    /* These nodes can contain raw text, including physical blank lines. */
    if (!(is(child, "string") || is(child, "template_string") ||
          is(child, "comment") || is(child, "regex")))
      presentation(s, child, depth + 1);
    previous = ts_node_end_byte(child);
  }
}

static void merge_omissions(Selection *s) {
  for (uint32_t i = 0; i < s->plan.length;) {
    if (!s->plan.keep[i]) { ++i; continue; }
    uint32_t start = i;
    int only_space = 1;
    while (i < s->plan.length && s->plan.keep[i]) {
      if (!whitespace(s->source[i])) only_space = 0;
      ++i;
    }
    if (only_space && start > 0 && i < s->plan.length)
      memset(s->plan.keep + start, 0, i - start);
  }
}

/* MoonBit has no body field: only a callable's direct block child is its
 * implementation. Never treat struct literals, record updates, attributes,
 * parameter defaults, return/effect types or type declaration braces as bodies.
 * The root grammar also handles .mbti declarations without bodies. */
static int moonbit_callable(TSNode node) {
  return is(node, "function_definition") || is(node, "impl_definition") ||
    is(node, "test_definition") || is(node, "named_lambda_expression") ||
    is(node, "anonymous_lambda_expression") ||
    is(node, "named_matrix_expression") || is(node, "anonymous_matrix_lambda_expression");
}

static int moonbit_type(TSNode node) {
  return is(node, "struct_definition") || is(node, "enum_definition") ||
    is(node, "type_definition");
}

static void moonbit_walk(Selection *, TSNode, unsigned);

/* Recover locally named functions/types even below discarded control flow.
 * Their surrounding implementation is not necessary executable context. */
static void moonbit_nested(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (moonbit_type(node) || is(node, "named_lambda_expression") ||
      is(node, "named_matrix_expression")) {
    select_node(s, node, 1);
    moonbit_walk(s, node, depth + 1);
    return;
  }
  /* Literal interiors are indivisible original fragments, not declarations. */
  if (is(node, "literal") || is(node, "string_interpolation")) return;
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
    moonbit_nested(s, ts_node_named_child(node, i), depth + 1);
}

static void moonbit_body(Selection *s, TSNode body, unsigned depth) {
  /* Keep only the actual opening/closing AST tokens, including inline braces. */
  uint32_t n = ts_node_child_count(body);
  TSNode open = {0}, close = {0};
  for (uint32_t i = 0; i < n; ++i) {
    TSNode child = ts_node_child(body, i);
    if (is(child, "{") && ts_node_is_null(open)) open = child;
    if (is(child, "}")) close = child;
  }
  if (!ts_node_is_null(open) && !ts_node_is_null(close)) {
    uint32_t start = ts_node_end_byte(open), end = ts_node_start_byte(close);
    if (start <= end) memset(s->plan.keep + start, 0, end - start);
    for (uint32_t i = 0; i < ts_node_named_child_count(body); ++i)
      moonbit_nested(s, ts_node_named_child(body, i), depth + 1);
  }
}

static void moonbit_walk(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (is(node, "named_matrix_expression") || is(node, "anonymous_matrix_lambda_expression")) {
    moonbit_body(s, node, depth + 1);
    return;
  }
  int callable_node = moonbit_callable(node);
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i) {
    TSNode child = ts_node_named_child(node, i);
    if (callable_node && is(child, "block_expression"))
      moonbit_body(s, child, depth + 1);
    else if (callable_node && is(child, "external_source")) {
      /* Foreign symbol/module strings are declaration linkage, not bodies.
       * Only an inline multiline implementation is safe to replace here. */
      for (uint32_t j = 0; j < ts_node_named_child_count(child); ++j) {
        TSNode source = ts_node_named_child(child, j);
        if (is(source, "multiline_string_literal")) select_node(s, source, 0);
      }
    } else if (!callable_node)
      moonbit_walk(s, child, depth + 1);
  }
}

/* Go/Rust use a conservative, body-only outline: types, initializers and
 * unknown top-level syntax remain original. Only a known callable's `body`
 * field can lose bytes, never braces in a type, literal or macro token tree. */
static void systems_walk(Selection *, TSNode, unsigned, int);

static int rust_item(TSNode node) {
  const char *type = ts_node_type(node);
  size_t n = strlen(type);
  return (n >= 5 && strcmp(type + n - 5, "_item") == 0) ||
    is(node, "associated_type") || is(node, "use_declaration") ||
    is(node, "extern_crate_declaration") || is(node, "macro_definition") ||
    is(node, "macro_invocation");
}

static int go_callable(TSNode node) {
  return is(node, "function_declaration") || is(node, "method_declaration") ||
    is(node, "func_literal");
}

static int go_has_callable(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status) return 0;
  if (depth > 512) { s->plan.status = 3; return 0; }
  if (go_callable(node)) return 1;
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
    if (go_has_callable(s, ts_node_named_child(node, i), depth + 1)) return 1;
  return 0;
}

/* Recover nested items even below discarded control flow. Rust macro calls
 * can generate public items: retain both calls and definitions without looking
 * inside opaque tokens. Attributes are siblings, not part of their item node. */
static void systems_nested(Selection *s, TSNode node, unsigned depth, int rust) {
  if (s->plan.status) return;
  if (depth > 512) { s->plan.status = 3; return; }
  int binding = !rust && (is(node, "var_declaration") ||
    is(node, "short_var_declaration") || is(node, "assignment_statement")) &&
    go_has_callable(s, node, depth + 1);
  if ((rust && rust_item(node)) || (!rust &&
      (is(node, "type_declaration") || go_callable(node) || binding))) {
    select_node(s, node, 1);
    systems_walk(s, node, depth + 1, rust);
    return;
  }
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
    systems_nested(s, ts_node_named_child(node, i), depth + 1, rust);
}

static void systems_body(Selection *s, TSNode body, unsigned depth, int rust) {
  TSNode open = {0}, close = {0};
  for (uint32_t i = 0; i < ts_node_child_count(body); ++i) {
    TSNode token = ts_node_child(body, i);
    if (is(token, "{") && ts_node_is_null(open)) open = token;
    if (is(token, "}")) close = token;
  }
  if (ts_node_is_null(open) || ts_node_is_null(close)) return;
  uint32_t start = ts_node_end_byte(open), end = ts_node_start_byte(close);
  if (start > end) return;
  memset(s->plan.keep + start, 0, end - start);
  for (uint32_t i = 0; i < ts_node_named_child_count(body); ++i)
    systems_nested(s, ts_node_named_child(body, i), depth + 1, rust);
}

static void systems_walk(Selection *s, TSNode node, unsigned depth, int rust) {
  if (s->plan.status) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if ((!rust && go_callable(node)) || (rust && is(node, "function_item"))) {
    TSNode body = field(node, "body");
    if (is(body, "block")) systems_body(s, body, depth + 1, rust);
    return;
  }
  if (rust) {
    /* Extern declarations, structs/enums/unions, associated types, macros,
     * attributes and unknown items are deliberately indivisible. */
    if (is(node, "mod_item") || is(node, "impl_item") || is(node, "trait_item")) {
      TSNode body = field(node, "body");
      if (!ts_node_is_null(body)) systems_walk(s, body, depth + 1, rust);
      return;
    }
    if (!(is(node, "source_file") || is(node, "declaration_list"))) return;
  } else if (is(node, "type_declaration") || is(node, "import_declaration") ||
             is(node, "package_clause") || is(node, "comment")) return;
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
    systems_walk(s, ts_node_named_child(node, i), depth + 1, rust);
}

/* Java declarations and field/schema values start selected. Only known
 * implementation regions are removed; visibility is not a safe API filter
 * (interface members and package-private enclosing types can expose APIs). */
static void java_walk(Selection *, TSNode, unsigned);

static void java_nested(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status || ts_node_is_null(node)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  int type = is(node, "class_declaration") || is(node, "interface_declaration") ||
    is(node, "enum_declaration") || is(node, "record_declaration") ||
    is(node, "annotation_type_declaration");
  /* An anonymous class has no name, but its implemented method signatures are
   * useful even in a returned/local instance. Retain its creation header too. */
  int anonymous = 0;
  if (is(node, "object_creation_expression"))
    for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
      if (is(ts_node_named_child(node, i), "class_body")) anonymous = 1;
  if (type || anonymous) {
    select_node(s, node, 1);
    java_walk(s, node, depth + 1);
    return;
  }
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
    java_nested(s, ts_node_named_child(node, i), depth + 1);
}

static void java_walk(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status || ts_node_is_null(node)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (is(node, "method_declaration") || is(node, "constructor_declaration") ||
      is(node, "compact_constructor_declaration") || is(node, "lambda_expression")) {
    TSNode body = field(node, "body");
    if (is(body, "block") || is(body, "constructor_body")) {
      for (uint32_t i = 0; i < ts_node_named_child_count(body); ++i)
        remove_statement(s, ts_node_named_child(body, i));
    } else {
      select_node(s, body, 0);
    }
    java_nested(s, body, depth + 1);
    return;
  }
  if (is(node, "static_initializer") ||
      (is(node, "block") && (is(ts_node_parent(node), "class_body") ||
                              is(ts_node_parent(node), "enum_body_declarations")))) {
    select_node(s, node, 0);
    java_nested(s, node, depth + 1);
    return;
  }
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
    java_walk(s, ts_node_named_child(node, i), depth + 1);
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
    case 4: grammar = tree_sitter_moonbit(); break;
    case 5: grammar = tree_sitter_go(); break;
    case 6: grammar = tree_sitter_rust(); break;
    case 7: grammar = tree_sitter_java(); break;
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
      if (language == 7) java_walk(&s, ts_tree_root_node(tree), 0);
      else if (language == 4) moonbit_walk(&s, ts_tree_root_node(tree), 0);
      else if (language == 5 || language == 6)
        systems_walk(&s, ts_tree_root_node(tree), 0, language == 6);
      else walk(&s, ts_tree_root_node(tree), 0, 0);
      comments(&s, ts_tree_root_node(tree), 0);
      if (language < 4) presentation(&s, ts_tree_root_node(tree), 0);
      merge_omissions(&s);
    }
  }
  if (tree) ts_tree_delete(tree);
  ts_parser_delete(parser);
  if (s.plan.status) { free(s.plan.keep); s.plan.keep = NULL; }
  return s.plan;
}
