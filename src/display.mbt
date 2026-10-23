///|
fn path_volume(path : String) -> String {
  if path.has_prefix("//") {
    let parts = path.split("/").to_array()
    if parts.length() >= 4 {
      return "//" + parts[2].to_owned() + "/" + parts[3].to_owned()
    }
  }
  if path.length() >= 2 && path[1] == ':' {
    return path[0:2].to_owned()
  }
  "/"
}

///|
fn relative_label_root(root : String, cwd : String, windows : Bool) -> String {
  let root = if windows { root.replace_all(old="\\", new="/") } else { root }
  let cwd = if windows { cwd.replace_all(old="\\", new="/") } else { cwd }
  if windows && path_volume(root).to_lower() != path_volume(cwd).to_lower() {
    // A path on another Windows drive/share has no cwd-relative spelling.
    return root
  }
  let root_parts = root.split("/").filter(part => !part.is_empty()).to_array()
  let cwd_parts = cwd.split("/").filter(part => !part.is_empty()).to_array()
  let mut common = 0
  while common < root_parts.length() && common < cwd_parts.length() {
    let same = if windows {
      root_parts[common].to_owned().to_lower() ==
      cwd_parts[common].to_owned().to_lower()
    } else {
      root_parts[common] == cwd_parts[common]
    }
    if !same {
      break
    }
    common += 1
  }
  let parts : Array[String] = []
  for _ in common..<cwd_parts.length() {
    parts.push("..")
  }
  for i in common..<root_parts.length() {
    parts.push(root_parts[i].to_owned())
  }
  parts.join("/")
}

///|
fn display_for(
  options : Options,
  root : String,
  cwd : String,
) -> @output.Display raise {
  let path_prefix = match options.output_file_path_style {
    TargetRelative => ""
    CwdRelative => relative_label_root(root, cwd, @platform.is_windows())
    Absolute => @platform.separators(root)
  }
  if options.style is Xml && !@output.xml_representable(path_prefix) {
    raise ConfigurationError
  }
  {
    file_summary: options.file_summary,
    directory_structure: options.directory_structure,
    files: options.include_files,
    git_sections: options.git_sections,
    metadata: options.metadata,
    line_numbers: options.show_line_numbers,
    path_prefix,
  }
}

///|
fn render_document(
  document : Document,
  style : Style,
  full_metadata : Bool,
  display : @output.Display,
) -> String {
  match style {
    Xml => @output.xml(document, full_metadata~, display~)
    Markdown => @output.markdown(document, full_metadata~, display~)
    Json => @output.json(document, full_metadata~, display~)
    Plain => @output.plain(document, full_metadata~, display~)
  }
}
