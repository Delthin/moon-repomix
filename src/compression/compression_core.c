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
  if (ts_node_is_null(node)) return (TSNode){0};
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

static int same_name(Selection *s, TSNode a, TSNode b) {
  return !ts_node_is_null(a) && !ts_node_is_null(b) &&
    ts_node_end_byte(a) - ts_node_start_byte(a) == ts_node_end_byte(b) - ts_node_start_byte(b) &&
    memcmp(s->source + ts_node_start_byte(a), s->source + ts_node_start_byte(b),
           ts_node_end_byte(a) - ts_node_start_byte(a)) == 0;
}

/* Search only one lexical environment. A shadowing parameter/import/pattern is
 * returned too, but never mistaken for a provable const data binding. */
static TSNode scope_binding(Selection *s, TSNode node, TSNode name, unsigned depth) {
  if (depth > 512) { s->plan.status = 3; return (TSNode){0}; }
  if (ts_node_is_null(node)) return (TSNode){0};
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
    /* Initializers/types are not declarations in this environment. */
    if (ts_node_eq(child, field(node, "value")) || ts_node_eq(child, field(node, "type"))) continue;
    TSNode found = scope_binding(s, child, name, depth + 1);
    if (!ts_node_is_null(found)) return found;
  }
  return (TSNode){0};
}

/* var declarations can shadow an outer const even when nested in a branch.
 * Block functions are also treated as shadowing, including Annex B cases. */
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
      found = hoisted_binding(s, field(scope, "body"), name, 0);
      if (!ts_node_is_null(found)) return found;
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

static unsigned type_declarations(Selection *s, TSNode node, TSNode name, unsigned depth) {
  if (depth > 512) { s->plan.status = 3; return 2; }
  unsigned count = (type_declaration(node) || classlike(node)) && same_name(s, field(node, "name"), name);
  for (uint32_t i = 0; i < ts_node_named_child_count(node) && count < 2; ++i)
    count += type_declarations(s, ts_node_named_child(node, i), name, depth + 1);
  return count;
}

static int exported_type_reference(Selection *s, TSNode node, TSNode name, unsigned depth, int clause) {
  if (depth > 512) { s->plan.status = 3; return 1; }
  if (clause && same_name(s, node, name)) return 1;
  clause = clause || is(node, "export_clause");
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
    if (exported_type_reference(s, ts_node_named_child(node, i), name, depth + 1, clause)) return 1;
  return 0;
}

static int private_interface(Selection *s, TSNode declaration) {
  TSNode root = declaration;
  while (!ts_node_is_null(ts_node_parent(root))) {
    root = ts_node_parent(root);
    if (is(root, "export_statement")) return 0;
  }
  int module = 0;
  for (uint32_t i = 0; i < ts_node_named_child_count(root); ++i) {
    TSNode child = ts_node_named_child(root, i);
    if (importlike(child) || is(child, "export_statement")) module = 1;
  }
  /* Script-global/exported interfaces can be augmented outside this file. */
  TSNode name = field(declaration, "name");
  return module && type_declarations(s, root, name, 0) == 1 &&
    !exported_type_reference(s, root, name, 0, 0);
}

/* Structural TS data types only: unknown/imported types, callable properties,
 * inheritance, literal assertions and recursive types are deliberately opaque. */
static int data_type(Selection *s, TSNode type, unsigned depth) {
  if (depth > 32 || ts_node_is_null(type)) return 0;
  if (text_is(s, type, "string") || text_is(s, type, "number") ||
      text_is(s, type, "boolean") || text_is(s, type, "undefined") || text_is(s, type, "null")) return 1;
  if (is(type, "type_identifier")) {
    TSNode declaration = binding(s, type, type);
    if (is(declaration, "interface_declaration")) {
      if (!private_interface(s, declaration)) return 0;
      /* Any extends clause can add behavior not visible in this body. */
      for (uint32_t i = 0; i < ts_node_named_child_count(declaration); ++i)
        if (is(ts_node_named_child(declaration, i), "extends_type_clause")) return 0;
      return data_type(s, field(declaration, "body"), depth + 1);
    }
    if (is(declaration, "type_alias_declaration"))
      return data_type(s, field(declaration, "value"), depth + 1);
    return 0;
  }
  if (is(type, "generic_type")) {
    TSNode name = ts_node_named_child(type, 0), args = ts_node_named_child(type, 1);
    if (!ts_node_is_null(binding(s, type, name))) return 0;
    if (text_is(s, name, "Record") && ts_node_named_child_count(args) == 2 &&
        (text_is(s, ts_node_named_child(args, 0), "string") ||
         text_is(s, ts_node_named_child(args, 0), "number")))
      return data_type(s, ts_node_named_child(args, 1), depth + 1);
    if ((text_is(s, name, "Array") || text_is(s, name, "ReadonlyArray")) &&
        ts_node_named_child_count(args) == 1)
      return data_type(s, ts_node_named_child(args, 0), depth + 1);
    return 0;
  }
  if (is(type, "property_signature")) {
    if (is(field(type, "name"), "computed_property_name")) return 0;
    return data_type(s, field(type, "type"), depth + 1);
  }
  if (!(is(type, "type_annotation") || is(type, "array_type") ||
        is(type, "union_type") || is(type, "parenthesized_type") ||
        is(type, "object_type") || is(type, "interface_body"))) return 0;
  unsigned count = 0;
  for (uint32_t i = 0; i < ts_node_named_child_count(type); ++i) {
    TSNode child = ts_node_named_child(type, i);
    if (is(child, "comment")) continue;
    if (!data_type(s, child, depth + 1)) return 0;
    ++count;
  }
  return count > 0;
}

static int const_binding(TSNode node) {
  if (ts_node_is_null(node)) return 0;
  TSNode declaration = ts_node_parent(node);
  return is(node, "variable_declarator") && is(declaration, "lexical_declaration") &&
    is(ts_node_child(declaration, 0), "const");
}

static int data_receiver(Selection *s, TSNode from, TSNode name, unsigned depth) {
  if (depth > 16 || !is(name, "identifier")) return 0;
  TSNode declared = binding(s, from, name);
  if (ts_node_is_null(declared)) return 0;
  if (const_binding(declared)) {
    if (data_type(s, field(declared, "type"), 0)) return 1;
    TSNode value = field(declared, "value");
    if (is(value, "identifier")) return data_receiver(s, declared, value, depth + 1);
    /* A local Map<K, Data>.get() yields data, not an API object. */
    if (is(value, "call_expression")) {
      TSNode fn = field(value, "function"), object = field(fn, "object");
      TSNode map = binding(s, declared, object);
      TSNode init = field(map, "value"), args = field(init, "type_arguments");
      if (is(fn, "member_expression") && text_is(s, field(fn, "property"), "get") &&
          const_binding(map) && is(init, "new_expression") &&
          text_is(s, field(init, "constructor"), "Map") &&
          ts_node_is_null(binding(s, init, field(init, "constructor"))) &&
          ts_node_named_child_count(args) == 2)
        return data_type(s, ts_node_named_child(args, 1), 0);
    }
  }
  /* The accumulator of a reduce with an explicitly widened data seed. Do not
   * infer data from an untyped {}, or from other callback parameters. */
  TSNode fn = ts_node_parent(declared);
  while (is(fn, "formal_parameters") || is(fn, "required_parameter") || is(fn, "optional_parameter")) {
    TSNode annotation = field(fn, "type");
    if (!ts_node_is_null(annotation) && !data_type(s, annotation, 0)) return 0;
    fn = ts_node_parent(fn);
  }
  if (callable(fn)) {
    TSNode params = field(fn, "parameters"), args = ts_node_parent(fn);
    if (!is(args, "arguments")) return 0;
    TSNode call = ts_node_parent(args);
    TSNode first = ts_node_named_child(params, 0), callee = field(call, "function");
    TSNode seed = ts_node_named_child(args, 1);
    if ((ts_node_eq(first, declared) || same_name(s, field(first, "pattern"), name)) &&
        is(args, "arguments") && is(call, "call_expression") &&
        ts_node_eq(ts_node_named_child(args, 0), fn) && is(callee, "member_expression") &&
        text_is(s, field(callee, "property"), "reduce") && is(seed, "as_expression") &&
        is(ts_node_named_child(seed, 0), "object") &&
        data_type(s, ts_node_named_child(seed, 1), 0)) return 1;
  }
  return 0;
}

static int member_assignment(Selection *s, TSNode node) {
  if (!js_assignment(node)) return 0;
  TSNode left = field(node, "left"), right = field(node, "right");
  if (!(is(left, "member_expression") || is(left, "subscript_expression"))) return 0;
  TSNode base = left;
  while (is(base, "member_expression") || is(base, "subscript_expression")) {
    TSNode object = field(base, "object");
    TSNode property = field(base, is(base, "member_expression") ? "property" : "index");
    if (text_is(s, property, "prototype") || text_is(s, property, "'prototype'") ||
        text_is(s, property, "\"prototype\"")) return 1;
    if (text_is(s, object, "module") &&
        (text_is(s, property, "exports") || text_is(s, property, "'exports'") ||
         text_is(s, property, "\"exports\""))) return 1;
    base = object;
  }
  if (text_is(s, base, "exports") || is(base, "this")) return 1;
  if (callable(right) || classlike(right)) return 1;
  if (data_receiver(s, node, base, 0)) return 0;
  return is(right, "identifier") ||
    is(right, "member_expression") || is(right, "subscript_expression") ||
    js_assignment(right);
}

static int public_schema_call(Selection *s, TSNode node) {
  if (!is(node, "call_expression")) return 0;
  TSNode fn = field(node, "function");
  return is(fn, "member_expression") &&
    (text_is(s, field(fn, "property"), "registerTool") ||
     text_is(s, field(fn, "property"), "registerResource") ||
     text_is(s, field(fn, "property"), "registerPrompt"));
}

/* Keep enclosing conditions only when they contain an outline declaration.
 * Comments are restored separately, including their physical line breaks. */
static int contains_outline(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status || ts_node_is_null(node)) return 0;
  if (depth > 512) { s->plan.status = 3; return 0; }
  if (classlike(node) || type_declaration(node) || importlike(node) ||
      is(node, "function_declaration") || is(node, "generator_function_declaration") ||
      is(node, "function_definition") || is(node, "method_definition") ||
      member_assignment(s, node) || public_schema_call(s, node)) return 1;
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
  int scalars = 1, constructors = !ts_node_is_null(value_type);
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

/* A bare/aliased/serialized table exposes its keys as a schema. Only lookup
 * reads are private implementation; same-spelled shadowed locals do not count. */
static int index_only(Selection *s, TSNode node, TSNode declaration, unsigned depth) {
  if (depth > 512) { s->plan.status = 3; return 0; }
  TSNode name = field(declaration, "name");
  if ((is(node, "identifier") || is(node, "shorthand_property_identifier")) &&
      same_name(s, node, name) && !ts_node_eq(node, name) &&
      ts_node_eq(binding(s, node, node), declaration)) {
    TSNode parent = ts_node_parent(node);
    for (TSNode ancestor = parent; !ts_node_is_null(ancestor); ancestor = ts_node_parent(ancestor))
      if (is(ancestor, "type_query")) return 0;
    if (!is(parent, "subscript_expression") || !ts_node_eq(field(parent, "object"), node)) return 0;
    TSNode use = ts_node_parent(parent);
    if ((js_assignment(use) && ts_node_eq(field(use, "left"), parent)) ||
        is(use, "augmented_assignment_expression") || is(use, "update_expression") ||
        is(use, "unary_expression")) return 0;
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

static int static_require(Selection *s, TSNode node) {
  return is(node, "call_expression") && text_is(s, field(node, "function"), "require") &&
    ts_node_named_child_count(field(node, "arguments")) == 1 &&
    is(ts_node_named_child(field(node, "arguments"), 0), "string");
}

/* Behavior origins protect installations, not the state aliases inside bodies.
 * Members of imported APIs are opaque; this/req/parameters alone prove nothing. */
static int behavior_value(Selection *s, TSNode node, unsigned depth) {
  if (depth > 32 || ts_node_is_null(node)) return 0;
  if (callable(node) || classlike(node) || static_require(s, node)) return 1;
  if (is(node, "identifier")) {
    TSNode bound = binding(s, node, node);
    if (callable(bound) || classlike(bound)) return 1;
    for (TSNode parent = bound; !ts_node_is_null(parent); parent = ts_node_parent(parent)) {
      if (importlike(parent)) return 1;
      if (is(parent, "program") || is(parent, "statement_block") || callable(parent)) break;
    }
    TSNode type = field(bound, "type");
    if (!ts_node_is_null(type)) type = ts_node_named_child(type, 0);
    if (is(type, "function_type") || is(type, "constructor_type")) return 1;
    return is(bound, "variable_declarator") && behavior_value(s, field(bound, "value"), depth + 1);
  }
  if (is(node, "member_expression") || is(node, "subscript_expression"))
    return behavior_value(s, field(node, "object"), depth + 1);
  if (is(node, "as_expression") || is(node, "satisfies_expression") || is(node, "parenthesized_expression"))
    return behavior_value(s, ts_node_named_child(node, 0), depth + 1);
  if (js_assignment(node)) return behavior_value(s, field(node, "right"), depth + 1);
  if (is(node, "call_expression")) {
    TSNode fn = field(node, "function");
    return is(fn, "member_expression") && text_is(s, field(fn, "property"), "bind") &&
      behavior_value(s, field(fn, "object"), depth + 1);
  }
  return 0;
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
  } else if (static_require(s, node)) {
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

static int escapes(Selection *s, TSNode node, TSNode declaration, unsigned depth) {
  if (s->plan.status) return 1;
  if (depth > 512) { s->plan.status = 3; return 1; }
  if ((is(node, "identifier") || is(node, "shorthand_property_identifier")) &&
      same_name(s, node, field(declaration, "name")) &&
      ts_node_eq(binding(s, node, node), declaration)) {
    TSNode reference = node, parent = ts_node_parent(node);
    for (;;) {
      if (is(parent, "arguments")) {
        TSNode call = ts_node_parent(parent), fn = field(call, "function");
        if (public_schema_call(s, call) ||
            (is(fn, "member_expression") && text_is(s, field(fn, "object"), "JSON") &&
             text_is(s, field(fn, "property"), "stringify") &&
             ts_node_is_null(binding(s, call, field(fn, "object"))))) return 1;
        /* An ordinary call exposes a schema only if its result escapes too. */
        reference = call;
        parent = ts_node_parent(call);
      } else if (is(parent, "object") || is(parent, "pair") || is(parent, "spread_element") ||
                 is(parent, "parenthesized_expression") || is(parent, "as_expression") ||
                 is(parent, "satisfies_expression") || is(parent, "await_expression") ||
                 ((is(parent, "member_expression") || is(parent, "subscript_expression")) &&
                  ts_node_eq(field(parent, "object"), reference))) {
        reference = parent;
        parent = ts_node_parent(parent);
      } else break;
    }
    if (is(parent, "return_statement") ||
        (member_assignment(s, parent) && ts_node_eq(field(parent, "right"), reference))) return 1;
    if (is(parent, "variable_declarator") && ts_node_eq(field(parent, "value"), reference) &&
        is(field(parent, "name"), "identifier")) {
      TSNode root = parent;
      while (!ts_node_is_null(ts_node_parent(root))) root = ts_node_parent(root);
      if (escapes(s, root, parent, depth + 1)) return 1;
    }
  }
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
    if (escapes(s, ts_node_named_child(node, i), declaration, depth + 1)) return 1;
  return 0;
}

static int schema_source(Selection *s, TSNode node, unsigned depth) {
  if (s->plan.status) return 1;
  if (depth > 512) { s->plan.status = 3; return 1; }
  if (!is(node, "variable_declarator")) return 0;
  TSNode value = field(node, "value");
  for (unsigned i = 0; i < 32; ++i) {
    if (is(value, "as_expression") || is(value, "satisfies_expression") ||
        is(value, "parenthesized_expression")) value = ts_node_named_child(value, 0);
    else if (is(value, "member_expression") || is(value, "subscript_expression"))
      value = field(value, "object");
    else break;
  }
  if (is(value, "object")) return 1;
  return is(value, "identifier") && schema_source(s, binding(s, node, value), depth + 1);
}

/* Keep returned/serialized/API object schemas and their aliases independently
 * of implementation assignments in their values (notably reduce callbacks). */
static int object_schema(Selection *s, TSNode node, unsigned depth) {
  if (!is(node, "variable_declarator") || !is(field(node, "name"), "identifier") ||
      !schema_source(s, node, depth + 1)) return 0;
  TSNode scope = ts_node_parent(node);
  while (!ts_node_is_null(ts_node_parent(scope)) && !callable(scope)) scope = ts_node_parent(scope);
  return callable(scope) && escapes(s, field(scope, "body"), node, depth + 1);
}

static int api_alias_reference(Selection *s, TSNode node, TSNode declaration,
                               unsigned depth, int api) {
  if (depth > 512) { s->plan.status = 3; return 1; }
  if (api) {
    if (is(node, "identifier")) {
      TSNode bound = binding(s, node, node);
      if (same_name(s, node, field(declaration, "name")) && ts_node_eq(bound, declaration)) return 1;
      TSNode value = field(bound, "value");
      return is(bound, "variable_declarator") &&
        api_alias_reference(s, value, declaration, depth + 1, 1);
    }
    if (is(node, "member_expression") || is(node, "subscript_expression"))
      return api_alias_reference(s, field(node, "object"), declaration, depth + 1, 1) ||
        (is(node, "subscript_expression") &&
         api_alias_reference(s, field(node, "index"), declaration, depth + 1, 1));
    if (is(node, "as_expression") || is(node, "satisfies_expression") || is(node, "parenthesized_expression"))
      return api_alias_reference(s, ts_node_named_child(node, 0), declaration, depth + 1, 1);
    if (js_assignment(node))
      return api_alias_reference(s, field(node, "right"), declaration, depth + 1, 1);
    if (is(node, "call_expression"))
      return api_alias_reference(s, field(node, "function"), declaration, depth + 1, 1);
    /* Installing a function/class does not expose the aliases in its body. */
    return 0;
  }
  if (member_assignment(s, node)) {
    int behavior = behavior_value(s, field(node, "right"), 0);
    /* An opaque explicit receiver type may describe behavior outside this AST.
     * Keep its annotation, without promoting untyped state in the function. */
    TSNode type = field(declaration, "type");
    int typed_receiver = !ts_node_is_null(type) && !data_type(s, type, 0);
    if ((behavior && api_alias_reference(s, field(node, "right"), declaration, depth + 1, 1)) ||
        ((behavior || typed_receiver) &&
         api_alias_reference(s, field(node, "left"), declaration, depth + 1, 1))) return 1;
  }
  for (uint32_t i = 0; i < ts_node_named_child_count(node); ++i)
    if (api_alias_reference(s, ts_node_named_child(node, i), declaration, depth + 1, api)) return 1;
  return 0;
}

static int api_alias(Selection *s, TSNode node, unsigned depth) {
  if (!is(node, "variable_declarator")) return 0;
  TSNode value = field(node, "value");
  if (static_require(s, value)) return 1;
  if (!(is(value, "identifier") || is(value, "member_expression") ||
        is(value, "subscript_expression"))) return 0;
  TSNode root = node;
  while (!ts_node_is_null(ts_node_parent(root))) root = ts_node_parent(root);
  return api_alias_reference(s, root, node, depth + 1, 0);
}

/* Local data statements are implementation, but locally named functions and
 * classes still belong to the outline (including arrow/lambda bindings). */
static int signature_binding(Selection *s, TSNode node, unsigned depth) {
  if (depth > 512 || ts_node_is_null(node)) return 0;
  if (callable(node) || classlike(node) || object_schema(s, node, depth + 1) ||
      api_alias(s, node, depth + 1)) return 1;
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
      presentation(&s, ts_tree_root_node(tree), 0);
      merge_omissions(&s);
    }
  }
  if (tree) ts_tree_delete(tree);
  ts_parser_delete(parser);
  if (s.plan.status) { free(s.plan.keep); s.plan.keep = NULL; }
  return s.plan;
}
