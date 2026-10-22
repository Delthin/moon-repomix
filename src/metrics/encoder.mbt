///|
/// A validated o200k_base encoder. Initialization performs all resource I/O;
/// encoding is deterministic, does not normalize text, and treats special-token
/// spellings as ordinary text. Instances contain no mutable encoding cache.
struct Encoder {
  ranks : Map[Bytes, Int32]
  categories : FixedArray[Byte]
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
  let ranks_bytes = @fs.read_file(path).binary()
  check_digest(
    ranks_bytes, "446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d",
    "o200k ranks",
  )
  let unicode_path = ranks_path
    .dirname()
    .join(@path.Path("tokenizer-unicode-16.0.0.txt"))
    .to_string()
  let unicode_bytes = @fs.read_file(unicode_path).binary()
  check_digest(
    unicode_bytes, "7676ab755a41ef82108460238569e60ad65c191ddafe61b36c6765ec1353f293",
    "Unicode categories",
  )
  let ranks : Map[Bytes, Int32] = Map([], capacity=199998)
  for line in @utf8.decode(ranks_bytes).split("\n") {
    if line.is_empty() {
      continue
    }
    let fields = line.split(" ").collect()
    guard fields.length() == 2 else {
      raise ResourceError("invalid o200k ranks record")
    }
    let token = @base64.decode(fields[0])
    let rank = @string.parse_int(fields[1])
    if rank != ranks.length() || ranks.contains(token) {
      raise ResourceError("invalid o200k rank sequence")
    }
    ranks[token] = rank
  }
  if ranks.length() != 199998 {
    raise ResourceError("incomplete o200k ranks")
  }
  for b in 0..<256 {
    if !ranks.contains(Bytes::make(1, b.to_byte())) {
      raise ResourceError("missing o200k byte token")
    }
  }
  { ranks, categories: read_categories(@utf8.decode(unicode_bytes)), }
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
  let chars = text.to_array()
  let bytes = @utf8.encode(text)
  let mut start = 0
  let mut byte_start = 0
  let mut count = 0
  while start < chars.length() {
    let end = self.piece_end(chars, start)
    let mut byte_end = byte_start
    for i in start..<end {
      let cp = chars[i].to_int()
      byte_end += if cp < 0x80 {
        1
      } else if cp < 0x800 {
        2
      } else if cp < 0x10000 {
        3
      } else {
        4
      }
    }
    // The immutable UTF-8 snapshot supplies borrowed slices for every rank
    // lookup; neither pre-tokenized pieces nor candidate merges copy bytes.
    count += self.encode_piece(bytes[byte_start:byte_end], output)
    start = end
    byte_start = byte_end
  }
  count
}

///|
/// Count one complete text. Counts of separate fragments are not additive:
/// callers must count the final rendered document for an exact total.
pub fn Encoder::count(self : Encoder, text : String) -> Int32 {
  self.encode_text(text, None)
}
