#include "compression_core.h"
#include "vendor/runtime/lib/include/tree_sitter/api.h"
#include <stdlib.h>
#include <string.h>
#include "compression_predicates.h"

/* Actual type-name pointers are immutable for the lifetime of the parsed tree.
 * No grammar symbol numbers or canonical-symbol/alias assumptions are used. */
#define TYPE_SLOTS 1024u
typedef struct { const char *name; NodeKind kind; } TypeEntry;
_Static_assert(sizeof(TypeEntry) * TYPE_SLOTS <= 16 * 1024, "bounded type cache");

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
  const SCAtomicBool *cancel;
  TypeEntry *types; /* Optional <=16 KiB; allocation failure keeps string predicates. */
  TSNode type_node; /* Full key, not id alone: aliases/context may change the type. */
  NodeKind type_kind;
} Selection;

static int stopped(Selection *s) {
  if (s->cancel && sc_atomic_bool_load(s->cancel))
    s->plan.status = 5;
  return s->plan.status != 0;
}

/* Forward cursors retain the sibling position (including hidden/aliased
 * grammar nodes). Indexed ts_node[_named]_child restarts at the first child,
 * making complete enumeration of a wide node quadratic. Filter the cursor's
 * visible children for named-only walks, using the alias-aware public API.
 * Exhaustion/cancellation closes automatically; early returns close explicitly.
 * Each iterator is local to this walk and owns its cursor, never parser state. */
typedef struct {
  TSTreeCursor cursor;
  int active, started, named;
} Children;

static Children children(TSNode node, int named) {
  Children it = {0};
  it.named = named;
  if (!ts_node_is_null(node) &&
      (named ? ts_node_named_child_count(node) : ts_node_child_count(node))) {
    it.cursor = ts_tree_cursor_new(node);
    it.active = 1;
  }
  return it;
}

static void children_close(Children *it) {
  if (it->active) {
    ts_tree_cursor_delete(&it->cursor);
    it->active = 0;
  }
}

static int children_next(Selection *s, Children *it, TSNode *child) {
  if (!it->active) return 0;
  if (!stopped(s)) {
    int found = it->started ? ts_tree_cursor_goto_next_sibling(&it->cursor)
                            : ts_tree_cursor_goto_first_child(&it->cursor);
    it->started = 1;
    while (found && !stopped(s)) {
      TSNode node = ts_tree_cursor_current_node(&it->cursor);
      if (!it->named || ts_node_is_named(node)) {
        *child = node;
        return 1;
      }
      found = ts_tree_cursor_goto_next_sibling(&it->cursor);
    }
  }
  children_close(it);
  return 0;
}

static NodeKind node_kind(Selection *s, TSNode node) {
  if (!node.id) return K_other;
  if (s->type_node.id == node.id && s->type_node.tree == node.tree &&
      !memcmp(s->type_node.context, node.context, sizeof(node.context))) return s->type_kind;
  const char *name = ts_node_type(node);
  uintptr_t hash = (uintptr_t)name;
  hash ^= hash >> 11;
  hash ^= hash >> 21;
  TypeEntry *entry = &s->types[hash & (TYPE_SLOTS - 1)];
  if (entry->name == name) {
    s->type_node = node;
    return s->type_kind = entry->kind;
  }
  NodeKind kind = K_other;
  for (unsigned i = 1; i < K_count; ++i)
    if (strcmp(name, kind_names[i]) == 0) { kind = (NodeKind)i; break; }
  /* A collision is a full original name classification, never a false hit.
   * Direct replacement bounds memory and probe work even when all slots fill. */
  *entry = (TypeEntry){name, kind};
  s->type_node = node;
  return s->type_kind = kind;
}

static int is(Selection *s, TSNode node, NodeKind kind) {
  return node.id && (s->types ? node_kind(s, node) == kind :
    strcmp(ts_node_type(node), kind_names[kind]) == 0);
}

static TSNode field(TSNode node, const char *name) {
  return ts_node_is_null(node) ? (TSNode){0} :
    ts_node_child_by_field_name(node, name, (uint32_t)strlen(name));
}

static void select_node(Selection *s, TSNode node, int keep) {
  if (stopped(s) || ts_node_is_null(node)) return;
  uint32_t start = ts_node_start_byte(node), end = ts_node_end_byte(node);
  if (start <= end && end <= s->plan.length)
    memset(s->plan.keep + start, keep, end - start);
}

/* Remove entire physical lines only when the statement occupies them alone.
 * Inline bodies still use exact AST byte bounds. */
static void remove_statement(Selection *s, TSNode node) {
  if (stopped(s)) return;
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

static int callable(Selection *s, TSNode node) {
  if (s->types) switch (node_kind(s, node)) {
    case K_function_declaration: case K_generator_function_declaration:
    case K_function_expression: case K_function: case K_generator_function:
    case K_arrow_function: case K_method_definition: case K_function_definition:
    case K_lambda: return 1;
    default: return 0;
  }
  return is(s, node, K_function_declaration) || is(s, node, K_generator_function_declaration) ||
    is(s, node, K_function_expression) || is(s, node, K_function) ||
    is(s, node, K_generator_function) || is(s, node, K_arrow_function) ||
    is(s, node, K_method_definition) || is(s, node, K_function_definition) ||
    is(s, node, K_lambda);
}

static int classlike(Selection *s, TSNode node) {
  if (s->types) switch (node_kind(s, node)) {
    case K_class_declaration: case K_class: case K_abstract_class_declaration:
    case K_class_definition: return 1;
    default: return 0;
  }
  return is(s, node, K_class_declaration) || is(s, node, K_class) ||
    is(s, node, K_abstract_class_declaration) || is(s, node, K_class_definition);
}

static int importlike(Selection *s, TSNode node) {
  if (s->types) switch (node_kind(s, node)) {
    case K_import_statement: case K_import_from_statement:
    case K_future_import_statement: case K_import_alias: return 1;
    default: return 0;
  }
  return is(s, node, K_import_statement) || is(s, node, K_import_from_statement) ||
    is(s, node, K_future_import_statement) || is(s, node, K_import_alias);
}

static int type_declaration(Selection *s, TSNode node) {
  if (s->types) switch (node_kind(s, node)) {
    case K_interface_declaration: case K_type_alias_declaration:
    case K_enum_declaration: case K_type_alias_statement: case K_function_signature:
    case K_method_signature: case K_abstract_method_signature: return 1;
    default: return 0;
  }
  return is(s, node, K_interface_declaration) || is(s, node, K_type_alias_declaration) ||
    is(s, node, K_enum_declaration) || is(s, node, K_type_alias_statement) ||
    is(s, node, K_function_signature) || is(s, node, K_method_signature) ||
    is(s, node, K_abstract_method_signature);
}

static int structural(Selection *s, TSNode node) {
  if (s->types) switch (node_kind(s, node)) {
    case K_if_statement: case K_elif_clause: case K_else_clause:
    case K_for_statement: case K_for_in_statement: case K_while_statement:
    case K_do_statement: case K_try_statement: case K_except_clause:
    case K_except_group_clause: case K_finally_clause: case K_catch_clause:
    case K_with_statement: case K_match_statement: case K_case_clause:
    case K_switch_statement: case K_switch_body: case K_switch_case:
    case K_switch_default: return 1;
    default: return 0;
  }
  return is(s, node, K_if_statement) || is(s, node, K_elif_clause) ||
    is(s, node, K_else_clause) || is(s, node, K_for_statement) ||
    is(s, node, K_for_in_statement) || is(s, node, K_while_statement) ||
    is(s, node, K_do_statement) || is(s, node, K_try_statement) ||
    is(s, node, K_except_clause) || is(s, node, K_except_group_clause) ||
    is(s, node, K_finally_clause) || is(s, node, K_catch_clause) ||
    is(s, node, K_with_statement) || is(s, node, K_match_statement) ||
    is(s, node, K_case_clause) || is(s, node, K_switch_statement) ||
    is(s, node, K_switch_body) || is(s, node, K_switch_case) ||
    is(s, node, K_switch_default);
}

static void walk(Selection *, TSNode, unsigned, int);
static void statements(Selection *, TSNode, unsigned, int);
static int signature_binding(Selection *, TSNode, unsigned);

static int js_assignment(Selection *s, TSNode node) {
  return is(s, node, K_assignment_expression);
}

/* Member assignments describe JS APIs even when installed inside a callback.
 * Plain identifier assignments remain implementation unless directly callable. */
static int text_is(Selection *s, TSNode node, const char *text) {
  uint32_t start = ts_node_start_byte(node), end = ts_node_end_byte(node);
  return !ts_node_is_null(node) && end - start == strlen(text) &&
    memcmp(s->source + start, text, end - start) == 0;
}

static int member_assignment(Selection *s, TSNode node) {
  if (!js_assignment(s, node)) return 0;
  TSNode left = field(node, "left"), right = field(node, "right");
  if (!(is(s, left, K_member_expression) || is(s, left, K_subscript_expression))) return 0;
  TSNode base = left;
  while (!stopped(s) && (is(s, base, K_member_expression) || is(s, base, K_subscript_expression))) {
    TSNode object = field(base, "object");
    TSNode property = field(base, is(s, base, K_member_expression) ? "property" : "index");
    if (text_is(s, object, "module") &&
        (text_is(s, property, "exports") || text_is(s, property, "'exports'") ||
         text_is(s, property, "\"exports\""))) return 1;
    base = object;
  }
  if (text_is(s, base, "exports")) return 1;
  return callable(s, right) || classlike(s, right) || is(s, right, K_identifier) ||
    is(s, right, K_member_expression) || is(s, right, K_subscript_expression) ||
    js_assignment(s, right);
}

/* Keep enclosing conditions only when they contain an outline declaration.
 * Comments are restored separately, including their physical line breaks. */
static int contains_outline(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s) || ts_node_is_null(node)) return 0;
  if (depth > 512) { s->plan.status = 3; return 0; }
  if (classlike(s, node) || type_declaration(s, node) || importlike(s, node) ||
      is(s, node, K_function_declaration) || is(s, node, K_generator_function_declaration) ||
      is(s, node, K_function_definition) || is(s, node, K_method_definition) ||
      member_assignment(s, node)) return 1;
  if ((is(s, node, K_lexical_declaration) || is(s, node, K_variable_declaration) ||
       is(s, node, K_expression_statement)) && signature_binding(s, node, depth + 1)) return 1;
  if (s->python && is(s, node, K_expression_statement) &&
      is(s, ts_node_named_child(node, 0), K_string)) return 1;
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    if (contains_outline(s, child, depth + 1)) {
      children_close(&it);
      return 1;
    }
  return 0;
}

static int implementation_statement(Selection *s, TSNode node) {
  if (is(s, node, K_lexical_declaration) || is(s, node, K_variable_declaration)) {
    /* A loop header is not its single-statement body. Keep its binding. */
    TSNode parent = ts_node_parent(node);
    return !is(s, parent, K_for_statement) && !is(s, parent, K_for_in_statement);
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
  if (stopped(s)) return (TSNode){0};
  if (depth > 512) { s->plan.status = 3; return (TSNode){0}; }
  if (ts_node_is_null(node)) return (TSNode){0};
  if (is(s, node, K_assignment_pattern))
    return scope_binding(s, field(node, "left"), name, depth + 1);
  TSNode declared = field(node, "name");
  if (same_name(s, declared, name)) return node;
  if ((is(s, node, K_identifier) || is(s, node, K_shorthand_property_identifier_pattern)) &&
      same_name(s, node, name)) return node;
  if (callable(s, node) || classlike(s, node) || type_declaration(s, node)) return (TSNode){0};
  if (!(is(s, node, K_lexical_declaration) || is(s, node, K_variable_declaration) ||
        is(s, node, K_export_statement) || is(s, node, K_formal_parameters) ||
        is(s, node, K_required_parameter) || is(s, node, K_optional_parameter) ||
        is(s, node, K_object_pattern) || is(s, node, K_array_pattern) ||
        is(s, node, K_pair_pattern) || is(s, node, K_assignment_pattern) ||
        is(s, node, K_rest_pattern) || is(s, node, K_import_statement) ||
        is(s, node, K_import_clause) || is(s, node, K_named_imports) ||
        is(s, node, K_import_specifier) || is(s, node, K_namespace_import) ||
        is(s, node, K_variable_declarator))) return (TSNode){0};
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child)) {
    if (ts_node_eq(child, field(node, "value")) || ts_node_eq(child, field(node, "type"))) continue;
    TSNode found = scope_binding(s, child, name, depth + 1);
    if (!ts_node_is_null(found)) {
      children_close(&it);
      return found;
    }
  }
  return (TSNode){0};
}

/* var declarations and block functions can shadow an outer table even when
 * nested in a branch (including Annex B function declarations). */
static TSNode hoisted_binding(Selection *s, TSNode node, TSNode name, unsigned depth) {
  if (stopped(s)) return (TSNode){0};
  if (depth > 512) { s->plan.status = 3; return (TSNode){0}; }
  if (ts_node_is_null(node)) return (TSNode){0};
  if (is(s, node, K_variable_declaration) || callable(s, node) || classlike(s, node))
    return scope_binding(s, node, name, depth + 1);
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child)) {
    TSNode found = hoisted_binding(s, child, name, depth + 1);
    if (!ts_node_is_null(found)) {
      children_close(&it);
      return found;
    }
  }
  return (TSNode){0};
}

static TSNode binding(Selection *s, TSNode from, TSNode name) {
  if (ts_node_is_null(from) || ts_node_is_null(name)) return (TSNode){0};
  for (TSNode scope = ts_node_parent(from); !ts_node_is_null(scope) && !stopped(s); scope = ts_node_parent(scope)) {
    if (callable(s, scope)) {
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
    } else if (is(s, scope, K_for_in_statement) || is(s, scope, K_for_statement) || is(s, scope, K_catch_clause)) {
      TSNode pattern = field(scope, is(s, scope, K_catch_clause) ? "parameter" :
                                   is(s, scope, K_for_statement) ? "initializer" : "left");
      TSNode found = scope_binding(s, pattern, name, 0);
      if (!ts_node_is_null(found)) return found;
    } else if (is(s, scope, K_statement_block) || is(s, scope, K_program)) {
      Children it = children(scope, 1);
      TSNode child;
      while (children_next(s, &it, &child)) {
        TSNode found = scope_binding(s, child, name, 0);
        if (!ts_node_is_null(found)) {
          children_close(&it);
          return found;
        }
      }
    }
  }
  return (TSNode){0};
}

static int scalar_type(Selection *s, TSNode node) {
  for (unsigned depth = 0; depth < 32; ++depth) {
    if (text_is(s, node, "string") || text_is(s, node, "number") || text_is(s, node, "boolean")) return 1;
    if (!is(s, node, K_array_type)) return 0;
    node = ts_node_named_child(node, 0);
  }
  return 0;
}

static int scalar_value(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s) || depth > 32) return 0;
  if (is(s, node, K_string) || is(s, node, K_number) || is(s, node, K_true) || is(s, node, K_false)) return 1;
  if (!is(s, node, K_array)) return 0;
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child)) {
    if (!is(s, child, K_comment) && !scalar_value(s, child, depth + 1)) {
      children_close(&it);
      return 0;
    }
  }
  return 1;
}

static int opaque_value(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s) || depth > 32) return 0;
  if (callable(s, node) || classlike(s, node) || is(s, node, K_as_expression) ||
      is(s, node, K_satisfies_expression) || is(s, node, K_spread_element) ||
      is(s, node, K_computed_property_name) || is(s, node, K_object) ||
      is(s, node, K_call_expression)) return 0;
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    if (!opaque_value(s, child, depth + 1)) {
      children_close(&it);
      return 0;
    }
  return 1;
}

/* Widened scalar/array maps need two entries; inferred scalar and widened
 * constructor tables need eight. All require private index-only consumers. */
static int scalar_table(Selection *s, TSNode node) {
  if (!is(s, node, K_variable_declarator) || !is(s, field(node, "name"), K_identifier)) return 0;
  TSNode annotation = field(node, "type"), value_type = {0};
  int widened = 0;
  if (!ts_node_is_null(annotation)) {
    TSNode type = ts_node_named_child(annotation, 0);
    if (!is(s, type, K_generic_type) || ts_node_named_child_count(type) != 2 ||
        !text_is(s, ts_node_named_child(type, 0), "Record") ||
        !ts_node_is_null(binding(s, type, ts_node_named_child(type, 0)))) return 0;
    TSNode args = ts_node_named_child(type, 1);
    if (!is(s, args, K_type_arguments) || ts_node_named_child_count(args) != 2) return 0;
    TSNode key = ts_node_named_child(args, 0);
    if (!(text_is(s, key, "string") || text_is(s, key, "number"))) return 0;
    value_type = ts_node_named_child(args, 1);
    widened = scalar_type(s, value_type);
  }
  TSNode value = field(node, "value");
  if (!is(s, value, K_object)) return 0;
  unsigned pairs = 0;
  int scalars = 1, constructors = is(s, value_type, K_type_identifier) || is(s, value_type, K_generic_type);
  Children it = children(value, 1);
  TSNode pair;
  while (children_next(s, &it, &pair)) {
    if (is(s, pair, K_comment)) continue;
    TSNode k = field(pair, "key"), v = field(pair, "value");
    if (!is(s, pair, K_pair) ||
        !(is(s, k, K_property_identifier) || is(s, k, K_string) || is(s, k, K_number))) {
      children_close(&it);
      return 0;
    }
    scalars = scalars && scalar_value(s, v, 0);
    constructors = constructors && is(s, v, K_new_expression) && opaque_value(s, v, 0);
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
  if (stopped(s)) return 0;
  if (depth > 512) { s->plan.status = 3; return 0; }
  TSNode name = field(declaration, "name");
  if ((is(s, node, K_identifier) || is(s, node, K_shorthand_property_identifier)) &&
      same_name(s, node, name) && !ts_node_eq(node, name)) {
    TSNode bound = binding(s, node, node);
    if (!ts_node_eq(bound, declaration)) {
      /* Only definite value declarations prove that this is a different table.
       * Type-only names and mode-dependent block functions stay ambiguous. */
      int shadow = is(s, bound, K_variable_declarator) || is(s, bound, K_required_parameter) ||
        is(s, bound, K_optional_parameter);
      if (is(s, bound, K_identifier) || is(s, bound, K_shorthand_property_identifier_pattern)) {
        TSNode owner = ts_node_parent(bound);
        shadow = is(s, owner, K_formal_parameters) || is(s, owner, K_required_parameter) ||
          is(s, owner, K_optional_parameter) || is(s, owner, K_rest_pattern) ||
          is(s, owner, K_assignment_pattern) || is(s, owner, K_object_pattern) ||
          is(s, owner, K_array_pattern) || is(s, owner, K_pair_pattern) || is(s, owner, K_catch_clause);
        if (is(s, owner, K_for_in_statement)) {
          Children tokens = children(owner, 0);
          TSNode token;
          while (children_next(s, &tokens, &token)) {
            if (is(s, token, K_const) || is(s, token, K_let) || is(s, token, K_var)) shadow = 1;
          }
        }
      }
      if (!shadow) return 0;
    } else {
      TSNode parent = ts_node_parent(node);
      for (TSNode ancestor = parent; !ts_node_is_null(ancestor) && !stopped(s); ancestor = ts_node_parent(ancestor))
        if (is(s, ancestor, K_type_query)) return 0;
      if (!is(s, parent, K_subscript_expression) || !ts_node_eq(field(parent, "object"), node)) return 0;
      for (TSNode use = ts_node_parent(parent); !ts_node_is_null(use) && !stopped(s); use = ts_node_parent(use)) {
        TSNode left = field(use, "left");
        if (((js_assignment(s, use) || is(s, use, K_augmented_assignment_expression)) &&
             !ts_node_is_null(left) && ts_node_start_byte(left) <= ts_node_start_byte(parent) &&
             ts_node_end_byte(left) >= ts_node_end_byte(parent)) ||
            is(s, use, K_update_expression) || is(s, use, K_unary_expression)) return 0;
      }
    }
  }
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    if (!index_only(s, child, declaration, depth + 1)) {
      children_close(&it);
      return 0;
    }
  return 1;
}

static int private_scalar_table(Selection *s, TSNode node, unsigned depth) {
  if (!scalar_table(s, node)) return 0;
  TSNode root = node;
  while (!ts_node_is_null(ts_node_parent(root)) && !stopped(s)) {
    root = ts_node_parent(root);
    if (is(s, root, K_export_statement)) return 0;
  }
  return index_only(s, root, node, depth + 1);
}

static void literal_outline(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (callable(s, node) || classlike(s, node)) {
    walk(s, node, depth + 1, 0);
    return;
  }
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    literal_outline(s, child, depth + 1);
}

static void initializer(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s) || ts_node_is_null(node)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (callable(s, node) || classlike(s, node) || is(s, node, K_object)) {
    walk(s, node, depth + 1, 0);
  } else if (is(s, node, K_as_expression) || is(s, node, K_satisfies_expression)) {
    /* Literal assertions may define public unions through typeof/keyof. */
    literal_outline(s, node, depth + 1);
  } else if (is(s, node, K_identifier) || is(s, node, K_member_expression) ||
             is(s, node, K_subscript_expression)) {
    /* Binding aliases, especially CommonJS exports, are part of the outline. */
    return;
  } else if (is(s, node, K_call_expression) &&
             text_is(s, field(node, "function"), "require") &&
             ts_node_named_child_count(field(node, "arguments")) == 1 &&
             is(s, ts_node_named_child(field(node, "arguments"), 0), K_string)) {
    /* Static CommonJS imports/re-exports are binding aliases, not bodies. */
    return;
  } else if (js_assignment(s, node) || contains_outline(s, node, depth + 1)) {
    walk(s, node, depth + 1, 0);
  } else if (is(s, node, K_parenthesized_expression)) {
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
  if (stopped(s) || ts_node_is_null(node)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (callable(s, node)) {
    TSNode body = field(node, "body");
    if (is(s, body, K_statement_block) || is(s, body, K_block)) {
      statements(s, body, depth + 1, 1);
    } else {
      select_node(s, body, 0);
    }
    return;
  }
  if (classlike(s, node)) {
    TSNode body = field(node, "body");
    statements(s, body, depth + 1, 0);
    return;
  }
  if (type_declaration(s, node) || importlike(s, node) || is(s, node, K_comment)) return;
  if (local && (structural(s, node) || implementation_statement(s, node)) &&
      !contains_outline(s, node, depth + 1)) {
    remove_statement(s, node);
    return;
  }
  if (is(s, node, K_variable_declarator) || is(s, node, K_public_field_definition) ||
      is(s, node, K_field_definition) || is(s, node, K_pair)) {
    TSNode value = field(node, "value");
    if (private_scalar_table(s, node, depth + 1)) select_node(s, value, 0);
    else if (!ts_node_is_null(value)) initializer(s, value, depth + 1);
    return;
  }
  if (is(s, node, K_assignment) || is(s, node, K_augmented_assignment) || js_assignment(s, node)) {
    TSNode right = field(node, "right");
    /* Conventional Python type aliases are ordinary name assignments. Preserve
     * non-local bindings, as the upstream Python type-alias query does; inline
     * lambdas still need their implementation expression removed. */
    if (s->python && !local && is(s, node, K_assignment) &&
        is(s, field(node, "left"), K_identifier) && !callable(s, right)) return;
    initializer(s, right, depth + 1);
    return;
  }
  if (is(s, node, K_class_static_block)) {
    statements(s, field(node, "body"), depth + 1, 1);
    return;
  }
  if (is(s, node, K_statement_block) || is(s, node, K_block) ||
      is(s, node, K_program) || is(s, node, K_module) || is(s, node, K_class_body)) {
    statements(s, node, depth + 1, local);
    return;
  }
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    walk(s, child, depth + 1, local);
}

/* Local data statements are implementation, but locally named functions and
 * classes still belong to the outline (including arrow/lambda bindings). */
static int signature_binding(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s) || depth > 512 || ts_node_is_null(node)) return 0;
  if (callable(s, node) || classlike(s, node)) return 1;
  if (is(s, node, K_variable_declarator) || is(s, node, K_pair))
    return signature_binding(s, field(node, "value"), depth + 1);
  if (member_assignment(s, node)) return 1;
  if (is(s, node, K_assignment) || js_assignment(s, node))
    return signature_binding(s, field(node, "right"), depth + 1);
  if (!(is(s, node, K_lexical_declaration) || is(s, node, K_variable_declaration) ||
        is(s, node, K_expression_statement) || is(s, node, K_parenthesized_expression) ||
        is(s, node, K_object))) return 0;
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    if (signature_binding(s, child, depth + 1)) {
      children_close(&it);
      return 1;
    }
  return 0;
}

static void statements(Selection *s, TSNode node, unsigned depth, int local) {
  if (stopped(s) || ts_node_is_null(node)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  int first = 1;
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child)) {
    if (is(s, child, K_comment)) continue;
    int docstring = s->python && first && is(s, child, K_expression_statement) &&
      is(s, ts_node_named_child(child, 0), K_string);
    first = 0;
    if (docstring || importlike(s, child) || type_declaration(s, child)) continue;
    if (callable(s, child) || classlike(s, child) || is(s, child, K_decorated_definition) ||
        is(s, child, K_export_statement) || structural(s, child) ||
        is(s, child, K_class_static_block)) {
      walk(s, child, depth + 1, local);
    } else if (contains_outline(s, child, depth + 1)) {
      walk(s, child, depth + 1, local);
    } else if (!local && (is(s, child, K_lexical_declaration) ||
               is(s, child, K_variable_declaration) || is(s, child, K_public_field_definition) ||
               is(s, child, K_field_definition) || is(s, child, K_ambient_declaration) ||
               is(s, child, K_internal_module) || is(s, child, K_module) ||
               is(s, child, K_property_signature) || is(s, child, K_index_signature))) {
      walk(s, child, depth + 1, 0);
    } else if (!local && s->python && is(s, child, K_expression_statement) &&
               is(s, ts_node_named_child(child, 0), K_assignment)) {
      walk(s, child, depth + 1, 0);
    } else {
      remove_statement(s, child);
    }
  }
}

/* Preserve comments even inside discarded expressions, conservatively treating
 * every AST comment as significant. Never try to recognize comments lexically. */
static void comments(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  /* A folded table owns its implementation-category comments. Its binding
   * remains selected; ordinary discarded statements still restore comments. */
  if (is(s, node, K_object) && is(s, ts_node_parent(node), K_variable_declarator) &&
      s->plan.keep[ts_node_start_byte(ts_node_parent(node))] &&
      !s->plan.keep[ts_node_start_byte(node)]) return;
  if (is(s, node, K_comment) || is(s, node, K_block_comment) || is(s, node, K_line_comment)) {
    select_node(s, node, 1);
    /* A removed statement may have owned the following newline. Without it,
     * adjacent // comments become one line and swallow the next fragment. */
    uint32_t end = ts_node_end_byte(node);
    if (end < s->plan.length && s->source[end] == '\r') s->plan.keep[end++] = 1;
    if (end < s->plan.length && s->source[end] == '\n') s->plan.keep[end] = 1;
    return;
  }
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    comments(s, child, depth + 1);
}

static int whitespace(char c) {
  return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

/* Compact only whitespace between AST children of statement/type containers.
 * Never inspect literal/comment contents or Python indentation as source lines. */
static void presentation(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  int container = is(s, node, K_program) || is(s, node, K_module) ||
    is(s, node, K_statement_block) || is(s, node, K_block) || is(s, node, K_class_body) ||
    is(s, node, K_interface_body) || is(s, node, K_enum_body) || is(s, node, K_object);
  uint32_t previous = ts_node_start_byte(node);
  Children it = children(node, 0);
  TSNode child;
  while (children_next(s, &it, &child)) {
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
    if (!(is(s, child, K_string) || is(s, child, K_template_string) ||
          is(s, child, K_comment) || is(s, child, K_regex)))
      presentation(s, child, depth + 1);
    previous = ts_node_end_byte(child);
  }
}

static void merge_omissions(Selection *s) {
  for (uint32_t i = 0; i < s->plan.length;) {
    if ((i & 4095) == 0 && stopped(s)) return;
    if (!s->plan.keep[i]) { ++i; continue; }
    uint32_t start = i;
    int only_space = 1;
    while (i < s->plan.length && s->plan.keep[i]) {
      if ((i & 4095) == 0 && stopped(s)) return;
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
static int moonbit_callable(Selection *s, TSNode node) {
  return is(s, node, K_function_definition) || is(s, node, K_impl_definition) ||
    is(s, node, K_test_definition) || is(s, node, K_named_lambda_expression) ||
    is(s, node, K_anonymous_lambda_expression) ||
    is(s, node, K_named_matrix_expression) || is(s, node, K_anonymous_matrix_lambda_expression);
}

static int moonbit_type(Selection *s, TSNode node) {
  return is(s, node, K_struct_definition) || is(s, node, K_enum_definition) ||
    is(s, node, K_type_definition);
}

static void moonbit_walk(Selection *, TSNode, unsigned);

/* Recover locally named functions/types even below discarded control flow.
 * Their surrounding implementation is not necessary executable context. */
static void moonbit_nested(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (moonbit_type(s, node) || is(s, node, K_named_lambda_expression) ||
      is(s, node, K_named_matrix_expression)) {
    select_node(s, node, 1);
    moonbit_walk(s, node, depth + 1);
    return;
  }
  /* Literal interiors are indivisible original fragments, not declarations. */
  if (is(s, node, K_literal) || is(s, node, K_string_interpolation)) return;
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    moonbit_nested(s, child, depth + 1);
}

static void moonbit_body(Selection *s, TSNode body, unsigned depth) {
  /* Keep only the actual opening/closing AST tokens, including inline braces. */
  TSNode open = {0}, close = {0};
  Children tokens = children(body, 0);
  TSNode child;
  while (children_next(s, &tokens, &child)) {
    if (is(s, child, K_open_brace) && ts_node_is_null(open)) open = child;
    if (is(s, child, K_close_brace)) close = child;
  }
  if (!ts_node_is_null(open) && !ts_node_is_null(close)) {
    uint32_t start = ts_node_end_byte(open), end = ts_node_start_byte(close);
    if (start <= end) memset(s->plan.keep + start, 0, end - start);
    Children it = children(body, 1);
    while (children_next(s, &it, &child))
      moonbit_nested(s, child, depth + 1);
  }
}

static void moonbit_walk(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (is(s, node, K_named_matrix_expression) || is(s, node, K_anonymous_matrix_lambda_expression)) {
    moonbit_body(s, node, depth + 1);
    return;
  }
  int callable_node = moonbit_callable(s, node);
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child)) {
    if (callable_node && is(s, child, K_block_expression))
      moonbit_body(s, child, depth + 1);
    else if (callable_node && is(s, child, K_external_source)) {
      /* Foreign symbol/module strings are declaration linkage, not bodies.
       * Only an inline multiline implementation is safe to replace here. */
      Children sources = children(child, 1);
      TSNode source;
      while (children_next(s, &sources, &source)) {
        if (is(s, source, K_multiline_string_literal)) select_node(s, source, 0);
      }
    } else if (!callable_node)
      moonbit_walk(s, child, depth + 1);
  }
}

/* Go/Rust use a conservative, body-only outline: types, initializers and
 * unknown top-level syntax remain original. Only a known callable's `body`
 * field can lose bytes, never braces in a type, literal or macro token tree. */
static void systems_walk(Selection *, TSNode, unsigned, int);

static int rust_item(Selection *s, TSNode node) {
  const char *type = ts_node_type(node);
  size_t n = strlen(type);
  return (n >= 5 && strcmp(type + n - 5, "_item") == 0) ||
    is(s, node, K_associated_type) || is(s, node, K_use_declaration) ||
    is(s, node, K_extern_crate_declaration) || is(s, node, K_macro_definition) ||
    is(s, node, K_macro_invocation);
}

static int go_callable(Selection *s, TSNode node) {
  return is(s, node, K_function_declaration) || is(s, node, K_method_declaration) ||
    is(s, node, K_func_literal);
}

static int go_has_callable(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s)) return 0;
  if (depth > 512) { s->plan.status = 3; return 0; }
  if (go_callable(s, node)) return 1;
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    if (go_has_callable(s, child, depth + 1)) {
      children_close(&it);
      return 1;
    }
  return 0;
}

/* Recover nested items even below discarded control flow. Rust macro calls
 * can generate public items: retain both calls and definitions without looking
 * inside opaque tokens. Attributes are siblings, not part of their item node. */
static void systems_nested(Selection *s, TSNode node, unsigned depth, int rust) {
  if (stopped(s)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  int binding = !rust && (is(s, node, K_var_declaration) ||
    is(s, node, K_short_var_declaration) || is(s, node, K_assignment_statement)) &&
    go_has_callable(s, node, depth + 1);
  if ((rust && rust_item(s, node)) || (!rust &&
      (is(s, node, K_type_declaration) || go_callable(s, node) || binding))) {
    select_node(s, node, 1);
    systems_walk(s, node, depth + 1, rust);
    return;
  }
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    systems_nested(s, child, depth + 1, rust);
}

static void systems_body(Selection *s, TSNode body, unsigned depth, int rust) {
  TSNode open = {0}, close = {0};
  Children tokens = children(body, 0);
  TSNode token;
  while (children_next(s, &tokens, &token)) {
    if (is(s, token, K_open_brace) && ts_node_is_null(open)) open = token;
    if (is(s, token, K_close_brace)) close = token;
  }
  if (ts_node_is_null(open) || ts_node_is_null(close)) return;
  uint32_t start = ts_node_end_byte(open), end = ts_node_start_byte(close);
  if (start > end) return;
  memset(s->plan.keep + start, 0, end - start);
  Children it = children(body, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    systems_nested(s, child, depth + 1, rust);
}

static void systems_walk(Selection *s, TSNode node, unsigned depth, int rust) {
  if (stopped(s)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if ((!rust && go_callable(s, node)) || (rust && is(s, node, K_function_item))) {
    TSNode body = field(node, "body");
    if (is(s, body, K_block)) systems_body(s, body, depth + 1, rust);
    return;
  }
  if (rust) {
    /* Extern declarations, structs/enums/unions, associated types, macros,
     * attributes and unknown items are deliberately indivisible. */
    if (is(s, node, K_mod_item) || is(s, node, K_impl_item) || is(s, node, K_trait_item)) {
      TSNode body = field(node, "body");
      if (!ts_node_is_null(body)) systems_walk(s, body, depth + 1, rust);
      return;
    }
    if (!(is(s, node, K_source_file) || is(s, node, K_declaration_list))) return;
  } else if (is(s, node, K_type_declaration) || is(s, node, K_import_declaration) ||
             is(s, node, K_package_clause) || is(s, node, K_comment)) return;
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    systems_walk(s, child, depth + 1, rust);
}

/* Java declarations and field/schema values start selected. Only known
 * implementation regions are removed; visibility is not a safe API filter
 * (interface members and package-private enclosing types can expose APIs). */
static void java_walk(Selection *, TSNode, unsigned);

static void java_nested(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s) || ts_node_is_null(node)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  int type = is(s, node, K_class_declaration) || is(s, node, K_interface_declaration) ||
    is(s, node, K_enum_declaration) || is(s, node, K_record_declaration) ||
    is(s, node, K_annotation_type_declaration);
  /* An anonymous class has no name, but its implemented method signatures are
   * useful even in a returned/local instance. Retain its creation header too. */
  int anonymous = 0;
  if (is(s, node, K_object_creation_expression)) {
    Children it = children(node, 1);
    TSNode child;
    while (children_next(s, &it, &child))
      if (is(s, child, K_class_body)) anonymous = 1;
  }
  if (type || anonymous) {
    select_node(s, node, 1);
    java_walk(s, node, depth + 1);
    return;
  }
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    java_nested(s, child, depth + 1);
}

static void java_walk(Selection *s, TSNode node, unsigned depth) {
  if (stopped(s) || ts_node_is_null(node)) return;
  if (depth > 512) { s->plan.status = 3; return; }
  if (is(s, node, K_method_declaration) || is(s, node, K_constructor_declaration) ||
      is(s, node, K_compact_constructor_declaration) || is(s, node, K_lambda_expression)) {
    TSNode body = field(node, "body");
    if (is(s, body, K_block) || is(s, body, K_constructor_body)) {
      Children it = children(body, 1);
      TSNode child;
      while (children_next(s, &it, &child))
        remove_statement(s, child);
    } else {
      select_node(s, body, 0);
    }
    java_nested(s, body, depth + 1);
    return;
  }
  if (is(s, node, K_static_initializer) ||
      (is(s, node, K_block) && (is(s, ts_node_parent(node), K_class_body) ||
                              is(s, ts_node_parent(node), K_enum_body_declarations)))) {
    select_node(s, node, 0);
    java_nested(s, node, depth + 1);
    return;
  }
  Children it = children(node, 1);
  TSNode child;
  while (children_next(s, &it, &child))
    java_walk(s, child, depth + 1);
}

static const char *read_source(void *payload, uint32_t offset, TSPoint point,
                               uint32_t *length) {
  (void)point;
  Selection *s = payload;
  *length = offset < s->plan.length ? s->plan.length - offset : 0;
  return s->source + (offset < s->plan.length ? offset : s->plan.length);
}

static bool progress(TSParseState *state) {
  return stopped(state->payload) != 0;
}

SCPlan sc_plan(int32_t language, const char *source, uint32_t length,
               uint64_t timeout_micros) {
  return sc_plan_cancelable(language, source, length, timeout_micros, NULL);
}

SCPlan sc_plan_cancelable(int32_t language, const char *source, uint32_t length,
                          uint64_t timeout_micros, const SCAtomicBool *cancel) {
  Selection s = {.plan = {NULL, length, 0}, .python = language == 3,
                 .source = source, .cancel = cancel};
  if (stopped(&s)) return s.plan;
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
  TSInput input = {&s, read_source, TSInputEncodingUTF8, NULL};
  TSParseOptions options = {&s, progress};
  TSTree *tree = cancel ? ts_parser_parse_with_options(parser, NULL, input, options)
                        : ts_parser_parse_string(parser, NULL, source, length);
  if (stopped(&s)) {
    /* Cancellation is internal, never a successful fallback or a timeout. */
  } else if (!tree) {
    s.plan.status = 2;
  } else if (ts_node_has_error(ts_tree_root_node(tree))) {
    s.plan.status = 1;
  } else {
    s.plan.keep = malloc(length ? length : 1);
    if (!s.plan.keep) {
      s.plan.status = 3;
    } else {
      /* Classifications only: no depth/source/python-dependent predicate result
       * or parse is cached. A fresh optional table belongs to this Selection. */
      s.types = calloc(TYPE_SLOTS, sizeof(TypeEntry));
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
  free(s.types);
  if (tree) ts_tree_delete(tree);
  ts_parser_delete(parser);
  if (stopped(&s)) { free(s.plan.keep); s.plan.keep = NULL; }
  return s.plan;
}
