///|
priv struct ContextTexts {
  header : String
  instructions : String
}

///|
let max_context_text_bytes : Int32 = 1048576

///|
/// Load the explicit local instruction once, before repository acquisition.
/// Errors name fields only; template contents never enter diagnostics.
async fn prepare_context_texts(options : Options) -> ContextTexts {
  let header = options.header_text
  if header.contains("\u0000") ||
    @utf8.encode(header).length() > max_context_text_bytes {
    raise ContextTextError("output.headerText")
  }
  let instructions = match options.instruction_file_path {
    None | Some("") => ""
    Some(path) => {
      let cwd = @env.current_dir().unwrap_or(".")
      match @input.read(@platform.absolute(path, cwd), max_context_text_bytes) {
        Loaded(snapshot) => snapshot.text
        Skipped(_) => raise ContextTextError("output.instructionFilePath")
      }
    }
  }
  for
    (field, text) in [
      ("output.headerText", header),
      ("output.instructionFilePath", instructions),
    ] {
    if text.is_empty() {
      continue
    }
    if options.security_check {
      let findings = @security.scan(field, text, 0) catch {
        _ => raise ScanError
      }
      if !findings.is_empty() {
        raise ContextSecurityFinding(field)
      }
    }
    if options.style is Xml && !@output.xml_representable(text) {
      raise ContextTextError(field)
    }
  }
  { header, instructions, }
}
