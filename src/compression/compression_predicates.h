/* Copyright (c) 2026 moon-repomix contributors. MIT licensed; see LICENSE.
 * Private selector names only, never grammar symbol IDs. Classification uses
 * actual alias-aware runtime strings; unknown names remain unmatched. */
#ifndef SC_PREDICATES_H
#define SC_PREDICATES_H

#define SC_NODE_KINDS(X) \
  X(function_declaration, "function_declaration") \
  X(generator_function_declaration, "generator_function_declaration") \
  X(function_expression, "function_expression") \
  X(function, "function") \
  X(generator_function, "generator_function") \
  X(arrow_function, "arrow_function") \
  X(method_definition, "method_definition") \
  X(function_definition, "function_definition") \
  X(lambda, "lambda") \
  X(class_declaration, "class_declaration") \
  X(class, "class") \
  X(abstract_class_declaration, "abstract_class_declaration") \
  X(class_definition, "class_definition") \
  X(import_statement, "import_statement") \
  X(import_from_statement, "import_from_statement") \
  X(future_import_statement, "future_import_statement") \
  X(import_alias, "import_alias") \
  X(interface_declaration, "interface_declaration") \
  X(type_alias_declaration, "type_alias_declaration") \
  X(enum_declaration, "enum_declaration") \
  X(type_alias_statement, "type_alias_statement") \
  X(function_signature, "function_signature") \
  X(method_signature, "method_signature") \
  X(abstract_method_signature, "abstract_method_signature") \
  X(if_statement, "if_statement") \
  X(elif_clause, "elif_clause") \
  X(else_clause, "else_clause") \
  X(for_statement, "for_statement") \
  X(for_in_statement, "for_in_statement") \
  X(while_statement, "while_statement") \
  X(do_statement, "do_statement") \
  X(try_statement, "try_statement") \
  X(except_clause, "except_clause") \
  X(except_group_clause, "except_group_clause") \
  X(finally_clause, "finally_clause") \
  X(catch_clause, "catch_clause") \
  X(with_statement, "with_statement") \
  X(match_statement, "match_statement") \
  X(case_clause, "case_clause") \
  X(switch_statement, "switch_statement") \
  X(switch_body, "switch_body") \
  X(switch_case, "switch_case") \
  X(switch_default, "switch_default") \
  X(assignment_expression, "assignment_expression") \
  X(member_expression, "member_expression") \
  X(subscript_expression, "subscript_expression") \
  X(identifier, "identifier") \
  X(lexical_declaration, "lexical_declaration") \
  X(variable_declaration, "variable_declaration") \
  X(expression_statement, "expression_statement") \
  X(string, "string") \
  X(assignment_pattern, "assignment_pattern") \
  X(shorthand_property_identifier_pattern, "shorthand_property_identifier_pattern") \
  X(export_statement, "export_statement") \
  X(formal_parameters, "formal_parameters") \
  X(required_parameter, "required_parameter") \
  X(optional_parameter, "optional_parameter") \
  X(object_pattern, "object_pattern") \
  X(array_pattern, "array_pattern") \
  X(pair_pattern, "pair_pattern") \
  X(rest_pattern, "rest_pattern") \
  X(import_clause, "import_clause") \
  X(named_imports, "named_imports") \
  X(import_specifier, "import_specifier") \
  X(namespace_import, "namespace_import") \
  X(variable_declarator, "variable_declarator") \
  X(statement_block, "statement_block") \
  X(program, "program") \
  X(array_type, "array_type") \
  X(number, "number") \
  X(true, "true") \
  X(false, "false") \
  X(array, "array") \
  X(comment, "comment") \
  X(as_expression, "as_expression") \
  X(satisfies_expression, "satisfies_expression") \
  X(spread_element, "spread_element") \
  X(computed_property_name, "computed_property_name") \
  X(object, "object") \
  X(call_expression, "call_expression") \
  X(generic_type, "generic_type") \
  X(type_arguments, "type_arguments") \
  X(type_identifier, "type_identifier") \
  X(pair, "pair") \
  X(property_identifier, "property_identifier") \
  X(new_expression, "new_expression") \
  X(shorthand_property_identifier, "shorthand_property_identifier") \
  X(const, "const") \
  X(let, "let") \
  X(var, "var") \
  X(type_query, "type_query") \
  X(augmented_assignment_expression, "augmented_assignment_expression") \
  X(update_expression, "update_expression") \
  X(unary_expression, "unary_expression") \
  X(parenthesized_expression, "parenthesized_expression") \
  X(block, "block") \
  X(public_field_definition, "public_field_definition") \
  X(field_definition, "field_definition") \
  X(assignment, "assignment") \
  X(augmented_assignment, "augmented_assignment") \
  X(class_static_block, "class_static_block") \
  X(module, "module") \
  X(class_body, "class_body") \
  X(decorated_definition, "decorated_definition") \
  X(ambient_declaration, "ambient_declaration") \
  X(internal_module, "internal_module") \
  X(property_signature, "property_signature") \
  X(index_signature, "index_signature") \
  X(block_comment, "block_comment") \
  X(line_comment, "line_comment") \
  X(interface_body, "interface_body") \
  X(enum_body, "enum_body") \
  X(template_string, "template_string") \
  X(regex, "regex") \
  X(impl_definition, "impl_definition") \
  X(test_definition, "test_definition") \
  X(named_lambda_expression, "named_lambda_expression") \
  X(anonymous_lambda_expression, "anonymous_lambda_expression") \
  X(named_matrix_expression, "named_matrix_expression") \
  X(anonymous_matrix_lambda_expression, "anonymous_matrix_lambda_expression") \
  X(struct_definition, "struct_definition") \
  X(enum_definition, "enum_definition") \
  X(type_definition, "type_definition") \
  X(literal, "literal") \
  X(string_interpolation, "string_interpolation") \
  X(open_brace, "{") \
  X(close_brace, "}") \
  X(block_expression, "block_expression") \
  X(external_source, "external_source") \
  X(multiline_string_literal, "multiline_string_literal") \
  X(associated_type, "associated_type") \
  X(use_declaration, "use_declaration") \
  X(extern_crate_declaration, "extern_crate_declaration") \
  X(macro_definition, "macro_definition") \
  X(macro_invocation, "macro_invocation") \
  X(method_declaration, "method_declaration") \
  X(func_literal, "func_literal") \
  X(var_declaration, "var_declaration") \
  X(short_var_declaration, "short_var_declaration") \
  X(assignment_statement, "assignment_statement") \
  X(type_declaration, "type_declaration") \
  X(function_item, "function_item") \
  X(mod_item, "mod_item") \
  X(impl_item, "impl_item") \
  X(trait_item, "trait_item") \
  X(source_file, "source_file") \
  X(declaration_list, "declaration_list") \
  X(import_declaration, "import_declaration") \
  X(package_clause, "package_clause") \
  X(record_declaration, "record_declaration") \
  X(annotation_type_declaration, "annotation_type_declaration") \
  X(object_creation_expression, "object_creation_expression") \
  X(constructor_declaration, "constructor_declaration") \
  X(compact_constructor_declaration, "compact_constructor_declaration") \
  X(lambda_expression, "lambda_expression") \
  X(constructor_body, "constructor_body") \
  X(static_initializer, "static_initializer") \
  X(enum_body_declarations, "enum_body_declarations")

typedef enum {
  K_other,
#define SC_KIND(id, name) K_##id,
  SC_NODE_KINDS(SC_KIND)
#undef SC_KIND
  K_count
} NodeKind;

static const char *const kind_names[K_count] = {
  [K_other] = NULL,
#define SC_NAME(id, name) [K_##id] = name,
  SC_NODE_KINDS(SC_NAME)
#undef SC_NAME
};
#undef SC_NODE_KINDS

#endif
