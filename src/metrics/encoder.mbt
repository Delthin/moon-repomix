///|
/// A validated o200k_base encoder. Initialization performs all resource I/O;
/// encoding is deterministic, does not normalize text, and treats special-token
/// spellings as ordinary text. Instances contain no mutable encoding cache.
struct Encoder {
  ranks : Map[Bytes, Int32]
  categories : FixedArray[Byte]
  native : NativeCounter?
}

///|
/// Invalid resource path, checksum, or resource contents. Filesystem errors and
/// cancellation propagate unchanged from the async filesystem layer.
pub suberror ResourceError {
  ResourceError(String)
} derive(@debug.Debug)

///|
#deprecated
pub extend ResourceError with @debug.Debug::{to_repr}

///|
/// Load the bundled ranks from an absolute path and Unicode categories from
/// `tokenizer-unicode-16.0.0.txt` in the same directory. Both SHA-256 digests
/// are checked before parsing. No network access or cwd-based lookup occurs.
pub async fn Encoder::load(path : String) -> Encoder {
  let ranks_path = @path.Path(path)
  if !ranks_path.is_absolute() {
    raise ResourceError("o200k ranks path must be absolute")
  }
  let ranks_bytes = read_resource(path, 3613922)
  check_digest(
    ranks_bytes, "446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d",
    "o200k ranks",
  )
  let unicode_path = ranks_path
    .dirname()
    .join(@path.Path("tokenizer-unicode-16.0.0.txt"))
    .to_string()
  let unicode_bytes = read_resource(unicode_path, 274423)
  check_digest(
    unicode_bytes, "7676ab755a41ef82108460238569e60ad65c191ddafe61b36c6765ec1353f293",
    "Unicode categories",
  )
  // Preserve all original format validation before constructing from the same
  // digest-checked raw snapshots. The C side copies, never retains these bytes.
  let ranks = read_ranks(ranks_bytes)
  let categories = read_categories(@utf8.decode(unicode_bytes))
  {
    ranks,
    categories,
    native: Some(native_counter_new(ranks_bytes, unicode_bytes)),
  }
}

///|
fn check_digest(
  bytes : Bytes,
  expected : String,
  resource : String,
) -> Unit raise {
  let actual = @hex.encode(Bytes::from_array(@crypto.sha256(bytes)[:]))
  if actual != expected {
    raise ResourceError("SHA-256 mismatch: \{resource}")
  }
}

///|
/// Encode complete text with o200k_base's ordinary-text policy. Token IDs are
/// the original OpenAI mergeable ranks, not remapped vocabulary indices.
pub fn Encoder::encode(self : Encoder, text : String) -> Array[Int32] {
  let result : Array[Int32] = []
  ignore(self.encode_text(text, Some(result)))
  result
}

///|
fn Encoder::encode_text(
  self : Encoder,
  text : String,
  output : Array[Int32]?,
) -> Int32 {
  let bytes = @utf8.encode(text)
  let mut start = 0
  let mut count = 0
  // A call-local memo never sums separately tokenized documents: keys are exact
  // pre-tokenized byte pieces, whose BPE merges cannot cross piece boundaries.
  // Keep Encoder immutable/reentrant, and bound retained keys to 2 MiB.
  let counts : Map[Bytes, Int32] = Map([])
  while start < bytes.length() {
    let end = self.piece_end(bytes, start)
    // The immutable UTF-8 snapshot supplies borrowed slices for every rank
    // lookup; neither pre-tokenized pieces nor candidate merges copy bytes.
    let piece = bytes[start:end]
    if output is None {
      if piece.length() == 1 {
        // Loading validates that every possible single byte is a rank.
        count += 1
      } else if counts.get_from_bytes(piece) is Some(known) {
        count += known
      } else {
        let size = self.encode_piece(piece, None)
        count += size
        if piece.length() <= 256 && counts.length() < 8192 {
          counts[piece.to_owned()] = size
        }
      }
    } else {
      count += self.encode_piece(piece, output)
    }
    start = end
  }
  count
}

///|
/// Count one complete text. Counts of separate fragments are not additive:
/// callers must count the final rendered document for an exact total.
pub fn Encoder::count(self : Encoder, text : String) -> Int32 {
  if self.native is Some(counter) {
    // Keep strict UTF-16 rejection (including unsafe surrogate constructions)
    // in the existing encoder. No readonly MoonBit object is mutated by C.
    let count = native_counter_count(counter, @utf8.encode(text))
    if count >= 0 {
      return count
    }
  }
  self.encode_text(text, None)
}
