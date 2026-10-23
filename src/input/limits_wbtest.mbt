///|
// Reader implementations need this buffer even when testing exact OS requests.
#warnings("-alert_internal")
struct ProbeReader {
  buffer : @io.ReaderBuffer
  data : Bytes
  requests : Array[Int32]
  mut position : Int32
  fail_after : Int32?
}

///|
impl @io.Reader for ProbeReader with fn _get_internal_buffer(self) {
  self.buffer
}

///|
suberror ProbeFailure

///|
impl @io.Reader for ProbeReader with fn _direct_read(
  self,
  dst,
  offset~,
  max_len~,
) {
  @async.pause()
  self.requests.push(max_len)
  if self.fail_after is Some(limit) && self.position >= limit {
    raise ProbeFailure
  }
  let available = self.data.length() - self.position
  let mut count = if max_len < available { max_len } else { available }
  if self.fail_after is Some(limit) && count > limit - self.position {
    count = limit - self.position
  }
  for i in 0..<count {
    dst[offset + i] = self.data[self.position + i]
  }
  self.position += count
  count
}

///|
#warnings("-alert_internal")
fn probe(data : Bytes, fail_after~ : Int32? = None) -> ProbeReader {
  {
    buffer: @io.ReaderBuffer::new(),
    data,
    requests: [],
    position: 0,
    fail_after,
  }
}

///|
async test "raw read budgets bound actual reads, count probes and retain partial error consumption" {
  let large = FixedArray::make(100000, b'x').unsafe_reinterpret_as_bytes()
  let reader = probe(large)
  let consumed = Ref(0L)
  try read_bounded(reader, 100000, Some(65536L), consumed) catch {
    TotalSizeLimitExceeded => ()
    _ => fail("unexpected limit error")
  } noraise {
    _ => fail("must fail after exactly one excess byte")
  }
  assert_eq(reader.requests, [65536, 1])
  assert_eq(reader.position, 65537)
  assert_eq(consumed.val, 65537L)

  // Simulate growth after the stat: preserve TooLarge, but count its probe.
  let growing = probe(b"abcd")
  let growth_bytes = Ref(0L)
  assert_true(
    read_bounded(growing, 2, Some(20L), growth_bytes) is Skipped("TooLarge"),
  )
  assert_eq(growing.requests, [3])
  assert_eq(growth_bytes.val, 3L)
  let shared_probe = probe(b"abcd")
  let shared_bytes = Ref(0L)
  try read_bounded(shared_probe, 2, Some(2L), shared_bytes) catch {
    TotalSizeLimitExceeded => ()
    _ => fail("unexpected shared probe error")
  } noraise {
    _ => fail("a single-file skip cannot hide total exhaustion")
  }
  assert_eq(shared_probe.requests, [3])
  assert_eq(shared_bytes.val, 3L)

  let exact = probe(b"ab")
  let exact_bytes = Ref(0L)
  assert_true(read_bounded(exact, 20, Some(2L), exact_bytes) is Loaded(_))
  assert_eq(exact.requests, [3, 1])
  assert_eq(exact_bytes.val, 2L)
  let zero = probe(b"x")
  let zero_bytes = Ref(0L)
  try read_bounded(zero, 20, Some(0L), zero_bytes) catch {
    TotalSizeLimitExceeded => ()
    _ => fail("unexpected zero budget error")
  } noraise {
    _ => fail("zero budget permits only an EOF probe")
  }
  assert_eq(zero.requests, [1])
  assert_eq(zero_bytes.val, 1L)

  let broken = probe(b"abcdef", fail_after=Some(2))
  let partial_bytes = Ref(0L)
  assert_true(
    read_bounded(broken, 20, Some(20L), partial_bytes) is Skipped("Unreadable"),
  )
  assert_eq(partial_bytes.val, 2L)
  let cancelled = @async.with_task_group(group => {
    let task = group.spawn(async fn() {
      read_bounded(probe(large), 100000, Some(100000L), Ref(0L))
    })
    @async.pause()
    task.cancel()
    try {
      ignore(task.wait())
      false
    } catch {
      err => if @async.is_cancellation_error(err) { true } else { raise err }
    }
  })
  assert_true(cancelled)
}
