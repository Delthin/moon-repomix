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
