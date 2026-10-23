///|
/// Presentation controls. Canonical Document paths, bodies and metadata stay intact.
/// path_prefix is supplied by the caller for cwd-relative or absolute labels.
pub(all) struct Display {
  file_summary : Bool
  directory_structure : Bool
  files : Bool
  git_sections : Bool
  metadata : Bool
  line_numbers : Bool
  path_prefix : String
} derive(Eq, Debug)

///|
pub extend Display with Eq::{equal, not_equal}

///|
pub extend Display with Debug::{to_repr}

///|
pub fn Display::default() -> Display {
  {
    file_summary: true,
    directory_structure: true,
    files: true,
    git_sections: true,
    metadata: true,
    line_numbers: false,
    path_prefix: "",
  }
}

///|
fn numbered(text : String) -> String {
  if text.is_empty() {
    return text
  }
  let out = StringBuilder()
  let mut offset = 0
  let mut number = 1
  for line in text.split("\n") {
    // A terminating LF does not create an extra source line.
    if offset == text.length() {
      break
    }
    out.write_string(number.to_string() + ": ")
    out.write_string(line.to_owned())
    let end = offset + line.length()
    if end < text.length() {
      out.write_string("\n")
    }
    offset = end + 1
    number += 1
  }
  out.to_string()
}

///|
fn presentation(
  document : @document.Document,
  display : Display,
) -> @document.Document {
  if !display.line_numbers && display.path_prefix == "" && display.git_sections {
    return document
  }
  let prefix = display.path_prefix
  let files = document.files.map(file => {
    let path = if prefix == "" || prefix == "." {
      file.path
    } else if prefix.has_suffix("/") {
      prefix + file.path
    } else {
      prefix + "/" + file.path
    }
    let text = if display.line_numbers {
      numbered(file.text)
    } else {
      file.text
    }
    @document.File::{ path, text, }
  })
  let sections = if display.git_sections {
    document.sections
  } else {
    document.sections.filter(section => !section.kind.has_prefix("git_"))
  }
  { ..document, files, sections, }
}
