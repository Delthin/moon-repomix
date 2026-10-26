///|
#cfg(target="native")
#borrow(text)
extern "C" fn credential_candidates(text : String) -> Int32 = "moon_repomix_credential_candidates"

///|
#cfg(not(target="native"))
fn credential_candidates(text : String) -> Int32 {
  if text.contains("-----BEGIN ") {
    63
  } else {
    55
  }
}
