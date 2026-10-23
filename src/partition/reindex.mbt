///|
/// Replace application index fields without changing any volume. The returned
/// text includes its final LF, and both index and total counts are recomputed.
pub fn Partition::with_index(
  self : Partition,
  index : Json,
  count~ : (String) -> Int32 raise,
) -> Partition raise {
  let text = index.stringify() + "\n"
  let _ = byte_length(text)
  let tokens = checked_count(text, count)
  let mut total = 0L
  for volume in self.volumes {
    total = add_tokens(total, volume.tokens)
  }
  total = add_tokens(total, tokens)
  {
    volumes: self.volumes,
    index,
    index_text: text,
    index_tokens: tokens,
    total_tokens: total,
  }
}
