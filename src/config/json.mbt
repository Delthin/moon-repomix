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
fn json_nonnegative_int(
  value : Json,
  field : String,
) -> Int32 raise ConfigError {
  match value {
    Number(n, ..) if n >= 0 && n <= 2147483647.0 && n.to_int().to_double() == n =>
      n.to_int()
    _ => raise InvalidValue(field)
  }
}

///|
fn json_positive_int(value : Json, field : String) -> Int32 raise ConfigError {
  let result = json_nonnegative_int(value, field)
  if result == 0 {
    raise InvalidValue(field)
  }
  result
}

///|
fn json_token_tree(value : Json) -> TokenCountTree raise ConfigError {
  match value {
    False => Disabled
    True => Enabled(0)
    String(text) => Enabled(nonnegative_int(text, "output.tokenCountTree"))
    _ => Enabled(json_nonnegative_int(value, "output.tokenCountTree"))
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
            "topFilesLength" =>
              patch.top_files_length = Some(
                json_nonnegative_int(value, "output.topFilesLength"),
              )
            "tokenCountTree" =>
              patch.token_count_tree = Some(json_token_tree(value))
            "compress" =>
              patch.compress = Some(json_bool(value, "output.compress"))
            "keepFull" =>
              patch.keep_full_patterns = json_patterns(value, "output.keepFull")
            "headerText" =>
              patch.header_text = Some(json_string(value, "output.headerText"))
            "instructionFilePath" =>
              patch.instruction_file_path = Some(
                json_string(value, "output.instructionFilePath"),
              )
            "fullMetadata" =>
              patch.full_metadata = Some(
                json_bool(value, "output.fullMetadata"),
              )
            "fileSummary" =>
              patch.file_summary = Some(json_bool(value, "output.fileSummary"))
            "directoryStructure" =>
              patch.directory_structure = Some(
                json_bool(value, "output.directoryStructure"),
              )
            "files" =>
              patch.include_files = Some(json_bool(value, "output.files"))
            "gitSections" =>
              patch.git_sections = Some(json_bool(value, "output.gitSections"))
            "metadata" =>
              patch.metadata = Some(json_bool(value, "output.metadata"))
            "showLineNumbers" =>
              patch.show_line_numbers = Some(
                json_bool(value, "output.showLineNumbers"),
              )
            "filePathStyle" =>
              patch.output_file_path_style = Some(
                parse_path_style(json_string(value, "output.filePathStyle")),
              )
            "git" =>
              for key, value in object_fields(value, "output.git") {
                match key {
                  "includeDiffs" =>
                    patch.include_diffs = Some(
                      json_bool(value, "output.git.includeDiffs"),
                    )
                  "includeLogs" =>
                    patch.include_logs = Some(
                      json_bool(value, "output.git.includeLogs"),
                    )
                  "includeLogsCount" =>
                    patch.include_logs_count = Some(
                      json_positive_int(value, "output.git.includeLogsCount"),
                    )
                  _ => raise UnknownField("output.git." + key)
                }
              }
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
            "maxGitBytes" =>
              patch.max_git_bytes = Some(
                json_positive_int(value, "input.maxGitBytes"),
              )
            "maxFileSize" =>
              patch.max_file_size = Some(
                json_positive_int(value, "input.maxFileSize"),
              )
            _ => raise UnknownField("input." + key)
          }
        }
      "remote" =>
        for key, value in object_fields(value, "remote") {
          match key {
            "url" => patch.remote = Some(json_string(value, "remote.url"))
            "branch" =>
              patch.remote_branch = Some(json_string(value, "remote.branch"))
            _ => raise UnknownField("remote." + key)
          }
        }
      _ => raise UnknownField(key)
    }
  }
  validate_patch(patch)
  patch
}
