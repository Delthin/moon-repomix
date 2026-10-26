///|
/// A snapshot produced by the bounded reader after strict UTF-8 decoding.
/// Its fields are private so callers cannot attach this proof to arbitrary text.
struct ValidatedSnapshot {
  proof : @validated_text.Text
}

///|
/// Return the immutable snapshot facts. Updating a returned value creates a new
/// Snapshot and does not alter this validated value.
pub fn ValidatedSnapshot::snapshot(self : ValidatedSnapshot) -> Snapshot {
  {
    text: self.proof.text(),
    disk_bytes: self.proof.disk_bytes(),
    bom_bytes: self.proof.bom_bytes(),
  }
}

///|
/// Share the decoder's opaque proof with consumers that accept validated text.
pub fn ValidatedSnapshot::validated_text(
  self : ValidatedSnapshot,
) -> @validated_text.Text {
  self.proof
}

///|
pub(all) enum ValidatedReadResult {
  Loaded(ValidatedSnapshot)
  Skipped(String)
}

///|
pub(all) struct ValidatedMeteredRead {
  result : ValidatedReadResult
  read_bytes : Int64
}

///|
fn ordinary_result(result : ValidatedReadResult) -> ReadResult {
  match result {
    Loaded(value) => Loaded(value.snapshot())
    Skipped(reason) => Skipped(reason)
  }
}
