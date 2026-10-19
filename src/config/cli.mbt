///|
fn nonnegative_int(value : String, field : String) -> Int32 raise ConfigError {
  if value.is_empty() {
    raise InvalidValue(field)
  }
  let mut result = 0
  for c in value {
    if c < '0' || c > '9' {
      raise InvalidValue(field)
    }
    let digit = c.to_int() - 48
    if result > (2147483647 - digit) / 10 {
      raise InvalidValue(field)
    }
    result = result * 10 + digit
  }
  result
}

///|
fn cli_positive_int(value : String, field : String) -> Int32 raise ConfigError {
  let result = nonnegative_int(value, field)
  if result == 0 {
    raise InvalidValue(field)
  }
  result
}

///|
fn csv_patterns(value : String) -> Array[String] raise ConfigError {
  let result : Array[String] = []
  for item in value.split(",") {
    let pattern = item.to_owned().trim().to_owned()
    validate_pattern(pattern)
    result.push(pattern)
  }
  result
}

///|
fn set_action(current : Action, next : Action) -> Action raise ConfigError {
  if current != Pack && current != next {
    raise Conflict("action")
  }
  next
}

///|
/// Arguments exclude argv[0]. Supports --key=value and -- to end option parsing.
pub fn parse_cli(args : Array[String]) -> Cli raise ConfigError {
  let patch = Patch::empty()
  let mut directory : String? = None
  let mut config_path : String? = None
  let mut action = Pack
  let mut stdout = false
  let mut quiet = false
  let mut verbose = false
  let mut positional_only = false
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    index += 1
    if !positional_only && arg == "--" {
      positional_only = true
      continue
    }
    if positional_only || !arg.has_prefix("-") || arg == "-" {
      if directory is Some(_) {
        raise MultipleDirectories
      }
      validate_path(arg, "directory")
      directory = Some(arg)
      continue
    }
    let (key, inline) = match arg.split_once("=") {
      Some((key, value)) => (key.to_owned(), Some(value.to_owned()))
      None => (arg, None)
    }
    if key == "--token-count-tree" {
      // Like Repomix's optional argument, a following non-option is a threshold.
      let threshold = match inline {
        Some(value) => nonnegative_int(value, "output.tokenCountTree")
        None if index < args.length() && !args[index].has_prefix("-") => {
          let value = args[index]
          index += 1
          nonnegative_int(value, "output.tokenCountTree")
        }
        None => 0
      }
      patch.token_count_tree = Some(Enabled(threshold))
      continue
    }
    let takes_value = match key {
      "-o"
      | "--output"
      | "--style"
      | "--include"
      | "-i"
      | "--ignore"
      | "--token-count-encoding"
      | "--token-budget"
      | "--top-files-len"
      | "-c"
      | "--config"
      | "--tokenizer-path" => true
      _ => false
    }
    if takes_value {
      let value = match inline {
        Some(value) => value
        None => {
          if index >= args.length() || args[index].has_prefix("-") {
            raise MissingValue(key)
          }
          let value = args[index]
          index += 1
          value
        }
      }
      match key {
        "-o" | "--output" => {
          validate_path(value, "output.filePath")
          patch.output = Some(value)
        }
        "--style" => patch.style = Some(parse_style(value))
        "--include" =>
          patch.include_patterns = append_unique(
            patch.include_patterns,
            csv_patterns(value),
          )
        "-i" | "--ignore" =>
          patch.ignore = append_unique(patch.ignore, csv_patterns(value))
        "--token-count-encoding" => {
          if value != "o200k_base" {
            raise InvalidValue("tokenCount.encoding")
          }
          patch.encoding = Some(value)
        }
        "--token-budget" =>
          patch.token_budget = Some(
            cli_positive_int(value, "output.tokenBudget"),
          )
        "--top-files-len" =>
          patch.top_files_length = Some(
            nonnegative_int(value, "output.topFilesLength"),
          )
        "-c" | "--config" => {
          validate_path(value, "config")
          config_path = Some(value)
        }
        "--tokenizer-path" => {
          validate_path(value, "tokenizerPath")
          patch.tokenizer_path = Some(value)
        }
        _ => raise UnknownOption(key)
      }
    } else {
      // Boolean and action flags do not accept an attached value.
      if inline is Some(_) {
        raise InvalidValue(key)
      }
      match key {
        "--stdout" => stdout = true
        "--quiet" => quiet = true
        "--verbose" => verbose = true
        "--no-gitignore" => patch.use_gitignore = Some(false)
        "--no-dot-ignore" => patch.use_dot_ignore = Some(false)
        "--no-default-patterns" => patch.use_default_patterns = Some(false)
        "--no-security-check" => patch.security_check = Some(false)
        "--parsable-style" => ()
        "--init" => action = set_action(action, Init)
        "-h" | "--help" => action = set_action(action, Help)
        "-v" | "--version" => action = set_action(action, Version)
        _ => raise UnknownOption(key)
      }
    }
  }
  if quiet && verbose {
    raise Conflict("quiet/verbose")
  }
  if stdout && patch.output is Some(_) {
    raise Conflict("output/stdout")
  }
  validate_patch(patch)
  {
    directory: directory.unwrap_or("."),
    config_path,
    action,
    stdout,
    quiet,
    verbose,
    patch,
  }
}
