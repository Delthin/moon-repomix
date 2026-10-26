///|
// Explicit request-local, single-threaded storage. The strong owner field keeps
// the immutable vocabulary alive; C borrows it only for the duration of a call.
struct CountSession {
  owner : Encoder
  native : NativeCountSession?
}

///|
// Create independent bounded memo/scratch storage without I/O. Native allocation
// failure is represented by a null inner pointer, never an approximate count.
pub fn Encoder::session(self : Encoder) -> CountSession {
  {
    owner: self,
    native: match self.native {
      Some(_) => Some(native_session_new())
      None => None
    },
  }
}

///|
// Count the complete document each time; fragment counts are not additive.
// A scratch failure rejects only this native call. Exact cached pieces survive;
// subsequent calls remain usable. Memo OOM disables caching for this session.
pub fn CountSession::count(self : CountSession, text : String) -> Int32 {
  match (self.native, self.owner.native) {
    (Some(session), Some(owner)) => {
      // Preserve the original strict UTF-16 rejection before entering C.
      let count = native_session_count(session, owner, @utf8.encode(text))
      if count >= 0 {
        return count
      }
    }
    _ => ()
  }
  // Do not retry native or reuse a partial total: count the entire input with
  // the retained exact MoonBit implementation, including its bounded local memo.
  self.owner.encode_text(text, None)
}
