///|
#cfg(not(platform="windows"))
async fn canonical(path : String) -> String {
  normalize(@fs.realpath(path))
}

///|
// async 0.19.2's Windows realpath uses GetFullPathNameW, which does not resolve
// junctions. Resolve a metadata handle instead; this is never used on walked
// candidate files, only on the root and the output's existing ancestor.
#cfg(platform="windows")
fn canonical(path : String) -> String raise @os_error.OSError {
  let code = FixedArray::make(1, 0)
  let result = windows_final_path(path, code)
  if code[0] != 0 {
    raise @os_error.OSError(
      code[0],
      context="selection canonical path: " + path,
    )
  }
  let path = separators(result)
  normalize(
    if path.has_prefix("//?/UNC/") {
      "//" + path[8:].to_owned()
    } else if path.has_prefix("//?/") {
      path[4:].to_owned()
    } else {
      path
    },
  )
}

///|
#cfg(platform="windows")
#borrow(path, code)
extern "C" fn windows_final_path(
  path : String,
  code : FixedArray[Int32],
) -> String = "selection_windows_final_path"
