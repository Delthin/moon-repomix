///|
// An external object owns an immutable C arena/index. A null inner pointer
// records allocation failure and requests the unchanged exact MoonBit path.
priv type NativeCounter

///|
#borrow(ranks, unicode)
extern "c" fn native_counter_new(
  ranks : Bytes,
  unicode : Bytes,
) -> NativeCounter = "moon_repomix_counter_new"

///|
#borrow(counter, text)
extern "c" fn native_counter_count(
  counter : NativeCounter,
  text : Bytes,
) -> Int32 = "moon_repomix_counter_count"

///|
// Owns only mutable C memo/scratch, never an Encoder or borrowed MoonBit bytes.
priv type NativeCountSession

///|
extern "c" fn native_session_new() -> NativeCountSession = "moon_repomix_count_session_new"

///|
#borrow(session, owner, text)
extern "c" fn native_session_count(
  session : NativeCountSession,
  owner : NativeCounter,
  text : Bytes,
) -> Int32 = "moon_repomix_count_session_count"
