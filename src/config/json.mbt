///|
fn object_fields(
  value : Json,
  field : String,
) -> Map[String, Json] raise ConfigError {
  match value {
    Object(fields) => fields
    _ => raise InvalidValue(field)
  }
}

///|
fn json_string(value : Json, field : String) -> String raise ConfigError {
  match value {
    String(text) => text
    _ => raise InvalidValue(field)
  }
}

///|
fn json_bool(value : Json, field : String) -> Bool raise ConfigError {
  match value {
    True => true
    False => false
    _ => raise InvalidValue(field)
  }
}

///|
fn json_positive_int(value : Json, field : String) -> Int32 raise ConfigError {
  match value {
    Number(n, ..) if n > 0 && n <= 2147483647.0 && n.to_int().to_double() == n =>
      n.to_int()
    _ => raise InvalidValue(field)
  }
}

///|
fn json_patterns(
  value : Json,
  field : String,
) -> Array[String] raise ConfigError {
  match value {
    Array(items) => items.map(item => json_string(item, field))
    _ => raise InvalidValue(field)
  }
}

///|
/// Strict supported subset of Repomix JSON. No reads, path normalization or defaults.
pub fn parse_json(text : String) -> Patch raise ConfigError {
  let value = @json.parse(text) catch { _ => raise InvalidJson }
  let patch = Patch::empty()
  for key, value in object_fields(value, "root") {
    match key {
      "include" => patch.include_patterns = json_patterns(value, "include")
      "output" =>
        for key, value in object_fields(value, "output") {
          match key {
            "filePath" =>
              patch.output = Some(json_string(value, "output.filePath"))
            "style" =>
              patch.style = Some(
                parse_style(json_string(value, "output.style")),
              )
            "tokenBudget" =>
              patch.token_budget = Some(
                json_positive_int(value, "output.tokenBudget"),
              )
            _ => raise UnknownField("output." + key)
          }
        }
      "ignore" =>
        for key, value in object_fields(value, "ignore") {
          match key {
            "customPatterns" =>
              patch.ignore = json_patterns(value, "ignore.customPatterns")
            "useGitignore" =>
              patch.use_gitignore = Some(
                json_bool(value, "ignore.useGitignore"),
              )
            "useDotIgnore" =>
              patch.use_dot_ignore = Some(
                json_bool(value, "ignore.useDotIgnore"),
              )
            "useDefaultPatterns" =>
              patch.use_default_patterns = Some(
                json_bool(value, "ignore.useDefaultPatterns"),
              )
            _ => raise UnknownField("ignore." + key)
          }
        }
      "security" =>
        for key, value in object_fields(value, "security") {
          match key {
            "enableSecurityCheck" =>
              patch.security_check = Some(
                json_bool(value, "security.enableSecurityCheck"),
              )
            _ => raise UnknownField("security." + key)
          }
        }
      "tokenCount" =>
        for key, value in object_fields(value, "tokenCount") {
          match key {
            "encoding" =>
              patch.encoding = Some(json_string(value, "tokenCount.encoding"))
            _ => raise UnknownField("tokenCount." + key)
          }
        }
      "input" =>
        for key, value in object_fields(value, "input") {
          match key {
            "maxFileSize" =>
              patch.max_file_size = Some(
                json_positive_int(value, "input.maxFileSize"),
              )
            _ => raise UnknownField("input." + key)
          }
        }
      _ => raise UnknownField(key)
    }
  }
  validate_patch(patch)
  patch
}
