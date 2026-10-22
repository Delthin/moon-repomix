// Adapted from howtomakeaname/tokenizers-moonbit 0.16.3 src/model/bpe.mbt
// (Apache-2.0; see LICENSES/tokenizer-tokenizers-moonbit-Apache-2.0.txt).
// Kept its linked-symbol/priority-queue core and leftmost rank tie-breaking.
// Replaced HF pair-merges, byte-to-character mapping, dropout, token offsets,
// and caches with direct OpenAI byte ranks and original-byte span lookups.

///|
priv struct Merge {
  rank : Int32
  pos : Int32
  right : Int32
  end : Int32
} derive(Eq)

///|
impl Compare for Merge with fn compare(self, other) {
  if self.rank != other.rank {
    other.rank - self.rank
  } else {
    other.pos - self.pos
  }
}

///|
fn Encoder::encode_piece(
  self : Encoder,
  word : BytesView,
  output : Array[Int32]?,
) -> Int32 {
  let n = word.length()
  if n == 0 {
    return 0
  }
  if self.ranks.get_from_bytes(word) is Some(id) {
    if output is Some(ids) {
      ids.push(id)
    }
    return 1
  }
  // One flat array per link field avoids allocating one object per byte.
  // next = -2 marks a merged-away symbol; -1 remains the end-of-chain marker.
  let ends = FixedArray::make(n, 0)
  let prev = FixedArray::make(n, 0)
  let next = FixedArray::make(n, 0)
  for i in 0..<n {
    ends[i] = i + 1
    prev[i] = i - 1
    next[i] = i + 1
  }
  next[n - 1] = -1
  let mut count = n
  let heap : @pq.PriorityQueue[Merge] = @pq.PriorityQueue([])
  fn try_push(pos : Int32) -> Unit {
    if pos < 0 || next[pos] == -2 {
      return
    }
    let right = next[pos]
    if right < 0 {
      return
    }
    let end = ends[right]
    if self.ranks.get_from_bytes(word[pos:end]) is Some(rank) {
      heap.push({ rank, pos, right, end, })
    }
  }
  for i in 0..<(n - 1) {
    try_push(i)
  }
  while heap.pop() is Some(merge) {
    let pos = merge.pos
    let right = merge.right
    // Span end changes when the right node grows. Together with the links,
    // this rejects stale candidates without another rank lookup/allocation.
    if next[pos] == -2 || next[pos] != right || ends[right] != merge.end {
      continue
    }
    ends[pos] = ends[right]
    next[pos] = next[right]
    next[right] = -2
    count -= 1
    if next[pos] >= 0 {
      prev[next[pos]] = pos
    }
    try_push(prev[pos])
    try_push(pos)
  }
  if output is Some(ids) {
    let mut pos = 0
    while pos >= 0 {
      // Resource validation guarantees every surviving span has a rank.
      ids.push(self.ranks.get_from_bytes(word[pos:ends[pos]]).unwrap())
      pos = next[pos]
    }
  }
  count
}
