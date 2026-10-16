// Adapted from howtomakeaname/tokenizers-moonbit 0.16.3 src/model/bpe.mbt
// (Apache-2.0; see LICENSES/tokenizer-tokenizers-moonbit-Apache-2.0.txt).
// Kept its linked-symbol/priority-queue core and leftmost rank tie-breaking.
// Replaced HF pair-merges, byte-to-character mapping, dropout, token offsets,
// and caches with direct OpenAI byte ranks and original-byte span lookups.

///|
priv struct Symbol {
  mut end : Int32
  mut prev : Int32
  mut next : Int32
  mut alive : Bool
}

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
  word : Bytes,
  output : Array[Int32],
) -> Unit {
  let n = word.length()
  if self.ranks.get(word) is Some(id) {
    output.push(id)
    return
  }
  let symbols : Array[Symbol] = []
  for i in 0..<n {
    symbols.push({ end: i + 1, prev: i - 1, next: i + 1, alive: true, })
  }
  symbols[n - 1].next = -1
  let heap : @pq.PriorityQueue[Merge] = @pq.PriorityQueue([])
  fn try_push(pos : Int32) -> Unit {
    if pos < 0 || !symbols[pos].alive {
      return
    }
    let right = symbols[pos].next
    if right < 0 {
      return
    }
    let end = symbols[right].end
    if self.ranks.get(word[pos:end].to_owned()) is Some(rank) {
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
    if !symbols[pos].alive ||
      symbols[pos].next != right ||
      symbols[right].end != merge.end {
      continue
    }
    symbols[pos].end = symbols[right].end
    symbols[pos].next = symbols[right].next
    symbols[right].alive = false
    if symbols[right].next >= 0 {
      symbols[symbols[right].next].prev = pos
    }
    try_push(symbols[pos].prev)
    try_push(pos)
  }
  let mut pos = 0
  while pos >= 0 {
    // Resource validation guarantees all single bytes exist; every longer
    // surviving span was formed only after its rank was found above.
    output.push(self.ranks[word[pos:symbols[pos].end].to_owned()])
    pos = symbols[pos].next
  }
}
