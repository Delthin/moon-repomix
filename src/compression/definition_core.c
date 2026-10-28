/* Copyright (c) 2026 moon-repomix contributors. MIT licensed. */
#include "definition_core.h"
#include "vendor/runtime/lib/include/tree_sitter/api.h"
#include <stdlib.h>
#include <string.h>

const TSLanguage *tree_sitter_javascript(void);
const TSLanguage *tree_sitter_typescript(void);
const TSLanguage *tree_sitter_tsx(void);
const TSLanguage *tree_sitter_python(void);

typedef struct { uint32_t start, length, hash; } Span;
typedef struct {
  SDIndex result;
  const char *source;
  uint32_t length, capacity, definitions, visits, total_refs;
  int python;
  char prefix[SD_MAX_NAME + 1];
  uint32_t prefix_length;
  TSNode decorators[SD_MAX_DEPTH];
  uint32_t decorator_count;
} Indexer;

static int is(TSNode node, const char *type) {
  return !ts_node_is_null(node) && !strcmp(ts_node_type(node), type);
}
static TSNode field(TSNode node, const char *name) {
  return ts_node_is_null(node) ? (TSNode){0} :
    ts_node_child_by_field_name(node, name, (uint32_t)strlen(name));
}
static int same(TSNode a, TSNode b) {
  return !ts_node_is_null(a) && !ts_node_is_null(b) && ts_node_eq(a, b);
}
static int visit(Indexer *s, unsigned depth) {
  if (s->result.status) return 0;
  if (depth > SD_MAX_DEPTH || ++s->visits > SD_MAX_VISITS) {
    s->result.status = 3;
    return 0;
  }
  return 1;
}
static int reserve(Indexer *s, uint32_t count) {
  if (s->result.status) return 0;
  if (count > SD_MAX_WIRE - s->result.length) {
    s->result.status = 3;
    return 0;
  }
  uint32_t need = s->result.length + count;
  if (need > s->capacity) {
    uint32_t capacity = s->capacity ? s->capacity : 1024;
    while (capacity < need) capacity *= 2;
    uint8_t *next = realloc(s->result.wire, capacity);
    if (!next) { s->result.status = 3; return 0; }
    s->result.wire = next;
    s->capacity = capacity;
  }
  return 1;
}
static void number(Indexer *s, uint32_t value) {
  if (!reserve(s, 4)) return;
  uint8_t *out = s->result.wire + s->result.length;
  for (unsigned i = 0; i < 4; ++i) out[i] = (uint8_t)(value >> (8 * i));
  s->result.length += 4;
}
static void bytes(Indexer *s, const char *value, uint32_t length) {
  if (!reserve(s, length)) return;
  memcpy(s->result.wire + s->result.length, value, length);
  s->result.length += length;
}
static Span span(Indexer *s, TSNode node) {
  Span value = {ts_node_start_byte(node), 0, 2166136261u};
  uint32_t end = ts_node_end_byte(node);
  if (value.start > end || end > s->length) { s->result.status = 1; return value; }
  value.length = end - value.start;
  if (value.length > SD_MAX_NAME) { s->result.status = 3; return value; }
  for (uint32_t i = 0; i < value.length; ++i)
    value.hash = (value.hash ^ (uint8_t)s->source[value.start + i]) * 16777619u;
  return value;
}
static int callable(TSNode node) {
  return is(node, "function_declaration") || is(node, "generator_function_declaration") ||
    is(node, "function_expression") || is(node, "function") ||
    is(node, "generator_function") || is(node, "arrow_function") ||
    is(node, "method_definition") || is(node, "function_definition");
}
static int classlike(TSNode node) {
  return is(node, "class_declaration") || is(node, "class") ||
    is(node, "abstract_class_declaration") || is(node, "class_definition");
}

/* All visible nodes, including anonymous and missing tokens, are validated once.
 * Cursors move forward: wide sibling lists never restart an indexed lookup. */
static int validate(Indexer *s, TSNode root) {
  TSTreeCursor cursor = ts_tree_cursor_new(root);
  unsigned depth = 0;
  uint32_t nodes = 0;
  for (;;) {
    TSNode node = ts_tree_cursor_current_node(&cursor);
    if (!visit(s, depth)) break;
    if (++nodes > SD_MAX_NODES) { s->result.status = 3; break; }
    if (ts_node_is_error(node) || ts_node_is_missing(node)) {
      s->result.status = 1;
      break;
    }
    if (ts_tree_cursor_goto_first_child(&cursor)) { ++depth; continue; }
    while (!ts_tree_cursor_goto_next_sibling(&cursor)) {
      if (!depth) { ts_tree_cursor_delete(&cursor); return 1; }
      ts_tree_cursor_goto_parent(&cursor);
      --depth;
    }
  }
  ts_tree_cursor_delete(&cursor);
  return 0;
}

/* Syntactic binding positions are not references. This deliberately does not
 * resolve shadowing: identifier uses of parameters/locals can still be returned. */
static int binding(TSNode node) {
  TSNode parent = ts_node_parent(node);
  if (same(node, field(parent, "name")) &&
      (callable(parent) || classlike(parent) || is(parent, "variable_declarator"))) return 1;
  if (same(node, field(parent, "left")) &&
      (is(parent, "assignment") || is(parent, "assignment_pattern") ||
       is(parent, "object_assignment_pattern") ||
       (is(parent, "assignment_expression") && callable(field(parent, "right"))))) return 1;
  if (is(parent, "member_expression") && same(node, field(parent, "property"))) {
    TSNode assignment = ts_node_parent(parent);
    if (is(assignment, "assignment_expression") &&
        same(parent, field(assignment, "left")) && callable(field(assignment, "right"))) return 1;
  }
  if (is(parent, "pair_pattern") && same(node, field(parent, "key"))) return 1;
  if (is(parent, "object_pattern") || is(parent, "array_pattern") ||
      is(parent, "pair_pattern") || is(parent, "rest_pattern")) return 1;
  if (is(parent, "parameters") || is(parent, "formal_parameters") ||
      is(parent, "lambda_parameters")) return 1;
  if (is(parent, "required_parameter") || is(parent, "optional_parameter") ||
      is(parent, "default_parameter") || is(parent, "typed_parameter") ||
      is(parent, "typed_default_parameter")) {
    return same(node, field(parent, "name")) || same(node, field(parent, "pattern")) ||
      same(node, ts_node_named_child(parent, 0));
  }
  return 0;
}
static void references(Indexer *s, TSNode root, Span refs[SD_MAX_REFS],
                       uint16_t slots[SD_MAX_REFS * 2], uint32_t *ref_count) {
  uint32_t count = *ref_count;
  TSTreeCursor cursor = ts_tree_cursor_new(root);
  unsigned depth = 0;
  for (;;) {
    TSNode node = ts_tree_cursor_current_node(&cursor);
    if (!visit(s, depth)) break;
    if ((is(node, "identifier") || is(node, "shorthand_property_identifier") ||
         is(node, "type_identifier") || is(node, "property_identifier") ||
         is(node, "private_property_identifier")) && !binding(node)) {
      Span ref = span(s, node);
      if (s->result.status) break;
      unsigned slot = ref.hash % (SD_MAX_REFS * 2);
      while (slots[slot]) {
        Span prior = refs[slots[slot] - 1];
        if (prior.hash == ref.hash && prior.length == ref.length &&
            !memcmp(s->source + prior.start, s->source + ref.start, ref.length)) break;
        slot = (slot + 1) % (SD_MAX_REFS * 2);
      }
      if (!slots[slot]) {
        if (count == SD_MAX_REFS || s->total_refs == SD_MAX_TOTAL_REFS) {
          s->result.status = 3;
          break;
        }
        refs[count] = ref;
        slots[slot] = (uint16_t)(++count);
        ++s->total_refs;
      }
    }
    if (ts_tree_cursor_goto_first_child(&cursor)) { ++depth; continue; }
    while (!ts_tree_cursor_goto_next_sibling(&cursor)) {
      if (!depth) {
        ts_tree_cursor_delete(&cursor);
        *ref_count = count;
        return;
      }
      ts_tree_cursor_goto_parent(&cursor);
      --depth;
    }
  }
  ts_tree_cursor_delete(&cursor);
}

/* Identifier/member chains only; dynamic computed names are not invented.
 * Stack depth is checked before every recursive step. Whitespace/comments in
 * member syntax disappear, but identifier UTF-8 bytes remain unchanged. */
static int qualified(Indexer *s, TSNode node, char *out, uint32_t *length,
                     TSNode *terminal, unsigned depth) {
  if (!visit(s, depth)) return 0;
  if (is(node, "member_expression")) {
    if (!qualified(s, field(node, "object"), out, length, terminal, depth + 1)) return 0;
    if (*length == SD_MAX_NAME) { s->result.status = 3; return 0; }
    out[(*length)++] = '.';
    return qualified(s, field(node, "property"), out, length, terminal, depth + 1);
  }
  if (!(is(node, "identifier") || is(node, "property_identifier") ||
        is(node, "private_property_identifier") || is(node, "type_identifier") ||
        is(node, "shorthand_property_identifier_pattern") || is(node, "this"))) return 0;
  Span name = span(s, node);
  if (s->result.status) return 0;
  if (name.length > SD_MAX_NAME - *length) { s->result.status = 3; return 0; }
  memcpy(out + *length, s->source + name.start, name.length);
  *length += name.length;
  *terminal = node;
  return name.length != 0;
}
static uint32_t inclusive_end(TSPoint start, TSPoint end) {
  return end.row + (end.column != 0 || end.row == start.row ? 1 : 0);
}
static void add(Indexer *s, TSNode name, TSNode envelope) {
  if (s->result.status || ts_node_is_null(name)) return;
  char qname[SD_MAX_NAME + 1];
  uint32_t qlength = s->prefix_length;
  memcpy(qname, s->prefix, qlength);
  TSNode terminal = {0};
  if (!qualified(s, name, qname, &qlength, &terminal, 0)) return;
  if (s->definitions == SD_MAX_DEFINITIONS) { s->result.status = 3; return; }
  Span last = span(s, terminal);
  Span refs[SD_MAX_REFS];
  uint16_t slots[SD_MAX_REFS * 2] = {0};
  uint32_t count = 0;
  for (uint32_t i = 0; i < s->decorator_count && !s->result.status; ++i)
    references(s, s->decorators[i], refs, slots, &count);
  if (!s->result.status) references(s, envelope, refs, slots, &count);
  if (s->result.status) return;
  TSPoint start = ts_node_start_point(s->decorator_count ? s->decorators[0] : envelope);
  TSPoint end = ts_node_end_point(envelope);
  number(s, start.row + 1);
  /* Tree-sitter end is exclusive; column zero belongs to the previous line. */
  number(s, inclusive_end(start, end));
  number(s, last.length);
  number(s, qlength);
  number(s, count);
  bytes(s, s->source + last.start, last.length);
  bytes(s, qname, qlength);
  for (uint32_t i = 0; i < count; ++i) {
    number(s, refs[i].length);
    bytes(s, s->source + refs[i].start, refs[i].length);
  }
  if (!s->result.status) ++s->definitions;
}

/* Destructuring contributes one entry per statically named binding, each
 * retaining the whole declaration. Defaults/computed keys are never names. */
static void add_bindings(Indexer *s, TSNode name, TSNode envelope, unsigned depth) {
  if (!visit(s, depth)) return;
  if (is(name, "identifier") || is(name, "shorthand_property_identifier_pattern")) {
    add(s, name, envelope);
  } else if (is(name, "assignment_pattern") || is(name, "object_assignment_pattern")) {
    add_bindings(s, field(name, "left"), envelope, depth + 1);
  } else if (is(name, "pair_pattern")) {
    add_bindings(s, field(name, "value"), envelope, depth + 1);
  } else if (is(name, "object_pattern") || is(name, "array_pattern") || is(name, "rest_pattern")) {
    TSTreeCursor cursor = ts_tree_cursor_new(name);
    if (ts_tree_cursor_goto_first_child(&cursor)) {
      do {
        TSNode child = ts_tree_cursor_current_node(&cursor);
        if (ts_node_is_named(child)) add_bindings(s, child, envelope, depth + 1);
      } while (!s->result.status && ts_tree_cursor_goto_next_sibling(&cursor));
    }
    ts_tree_cursor_delete(&cursor);
  }
}
static void discover(Indexer *, TSNode, TSNode, unsigned, int);
static void children(Indexer *s, TSNode node, unsigned depth, int in_class) {
  s->decorator_count = 0;
  TSTreeCursor cursor = ts_tree_cursor_new(node);
  if (ts_tree_cursor_goto_first_child(&cursor)) {
    do {
      TSNode child = ts_tree_cursor_current_node(&cursor);
      if (is(child, "decorator")) {
        if (s->decorator_count == SD_MAX_DEPTH) { s->result.status = 3; break; }
        s->decorators[s->decorator_count++] = child;
      } else if (ts_node_is_named(child) && !ts_node_is_extra(child)) {
        discover(s, child, child, depth + 1, in_class);
        s->decorator_count = 0;
      }
    } while (!s->result.status && ts_tree_cursor_goto_next_sibling(&cursor));
  }
  s->decorator_count = 0;
  ts_tree_cursor_delete(&cursor);
}
static void variables(Indexer *s, TSNode node, TSNode envelope, unsigned depth) {
  int constant = is(ts_node_child(node, 0), "const");
  TSTreeCursor cursor = ts_tree_cursor_new(node);
  if (ts_tree_cursor_goto_first_child(&cursor)) {
    do {
      TSNode child = ts_tree_cursor_current_node(&cursor);
      if (!visit(s, depth)) break;
      if (!is(child, "variable_declarator")) continue;
      TSNode name = field(child, "name"), value = field(child, "value");
      if (constant || callable(value)) add_bindings(s, name, envelope, depth + 1);
      if (classlike(value)) discover(s, value, value, depth + 1, 0);
    } while (!s->result.status && ts_tree_cursor_goto_next_sibling(&cursor));
  }
  ts_tree_cursor_delete(&cursor);
}
static void python_assignment(Indexer *s, TSNode node, TSNode envelope, unsigned depth) {
  if (!visit(s, depth)) return;
  if (!is(node, "assignment")) return;
  add(s, field(node, "left"), envelope);
  python_assignment(s, field(node, "right"), envelope, depth + 1);
}
static void discover(Indexer *s, TSNode node, TSNode envelope, unsigned depth, int in_class) {
  if (!visit(s, depth)) return;
  if (is(node, "export_statement")) {
    TSNode declaration = field(node, "declaration");
    if (ts_node_is_null(declaration)) declaration = field(node, "value");
    if (!ts_node_is_null(declaration)) discover(s, declaration, envelope, depth + 1, in_class);
  } else if (is(node, "decorated_definition")) {
    discover(s, field(node, "definition"), envelope, depth + 1, in_class);
  } else if (callable(node)) {
    add(s, field(node, "name"), envelope);
    /* Nested functions and their local bindings never become global entries. */
  } else if (classlike(node)) {
    TSNode name = field(node, "name"), terminal = {0};
    uint32_t saved = s->prefix_length;
    if (!qualified(s, name, s->prefix, &s->prefix_length, &terminal, depth + 1)) {
      s->prefix_length = saved;
      return;
    }
    if (s->prefix_length == SD_MAX_NAME) { s->result.status = 3; return; }
    s->prefix[s->prefix_length++] = '.';
    children(s, field(node, "body"), depth + 1, 1);
    s->prefix_length = saved;
  } else if (!in_class && (is(node, "lexical_declaration") || is(node, "variable_declaration"))) {
    variables(s, node, envelope, depth + 1);
  } else if (!in_class && is(node, "expression_statement")) {
    TSNode expression = ts_node_named_child(node, 0);
    if (s->python) python_assignment(s, expression, envelope, depth + 1);
    else if (is(expression, "assignment_expression") && callable(field(expression, "right")))
      add(s, field(expression, "left"), envelope);
  } else if (in_class && (is(node, "public_field_definition") || is(node, "field_definition")) &&
             callable(field(node, "value"))) {
    add(s, field(node, "name"), envelope);
  } else if (is(node, "program") || is(node, "module")) {
    children(s, node, depth, 0);
  }
}

SDIndex sd_index(int32_t language, const char *source, uint32_t length,
                 uint64_t timeout_micros) {
  Indexer s = {.source = source, .length = length, .python = language == 3};
  const TSLanguage *grammar = NULL;
  switch (language) {
    case 0: grammar = tree_sitter_javascript(); break;
    case 1: grammar = tree_sitter_typescript(); break;
    case 2: grammar = tree_sitter_tsx(); break;
    case 3: grammar = tree_sitter_python(); break;
    default: s.result.status = 6; return s.result;
  }
  if (length > SD_MAX_INPUT) { s.result.status = 3; return s.result; }
  TSParser *parser = ts_parser_new();
  if (!parser) { s.result.status = 3; return s.result; }
  if (!ts_parser_set_language(parser, grammar)) {
    ts_parser_delete(parser);
    s.result.status = 4;
    return s.result;
  }
  ts_parser_set_timeout_micros(parser, timeout_micros);
  TSTree *tree = ts_parser_parse_string(parser, NULL, source, length);
  if (!tree) s.result.status = 2;
  else if (ts_node_has_error(ts_tree_root_node(tree))) s.result.status = 1;
  else if (validate(&s, ts_tree_root_node(tree))) {
    number(&s, 0);
    number(&s, 0);
    discover(&s, ts_tree_root_node(tree), ts_tree_root_node(tree), 0, 0);
    if (!s.result.status)
      for (unsigned i = 0; i < 4; ++i) s.result.wire[4 + i] = (uint8_t)(s.definitions >> (8 * i));
  }
  if (tree) ts_tree_delete(tree);
  ts_parser_delete(parser);
  if (s.result.status) {
    free(s.result.wire);
    s.result.wire = NULL;
    s.result.length = 0;
  }
  return s.result;
}
