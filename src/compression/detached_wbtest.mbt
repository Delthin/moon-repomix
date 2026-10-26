///|
async fn check_detached_batches() -> Unit {
  let sources : Array[Source] = [
    {
      path: "a.js",
      text: "// 😀\r\nexport function f(x) { return x + 123456789; }\r\n",
    },
    {
      path: "b.ts",
      text: "export function f(x: number): number { return x + 123456789; }\n",
    },
    {
      path: "c.tsx",
      text: "export function F() { return <div>hello world</div>; }\n",
    },
    {
      path: "d.py",
      text: "# café\r\ndef f(x):\r\n    return x + 123456789\r\n",
    },
    { path: "e.mbt", text: "pub fn f(x : Int) -> Int { x + 123456789 }\n", },
    {
      path: "f.go",
      text: "package p\nfunc F(x int) int { return x + 123456789 }\n",
    },
    { path: "g.rs", text: "pub fn f(x: i32) -> i32 { x + 123456789 }\n", },
    {
      path: "h.java",
      text: "class C { int f(int x) { return x + 123456789; } }\n",
    },
  ]
  for workers in [1, 2, 4] {
    let planner = Planner::new(workers~)
    defer planner.close()
    let retained : Array[(PlannedBatch, Array[Outcome])] = []
    for start in [0, 4] {
      let batch = sources[start:start + 4].to_owned()
      let expected = batch.map(s => compress(s.path, s.text))
      let ticket = planner.submit(batch)
      let planned = ticket.collect()
      assert_false(planner.busy)
      assert_true(ticket.finished)
      assert_true(ticket.is_ready())
      // Full four-job submission proves native leases and active state were
      // released, not merely made to look idle. Do not collect the next batch
      // until after materializing the old one.
      let next = planner.submit(batch)
      assert_true(planner.busy)
      assert_true(ticket.is_ready()) // never reads the next batch's state
      batch[0] = { path: "replaced.txt", text: "not the original source", }
      try ticket.collect() catch {
        Finished => ()
        err => raise err
      } noraise {
        _ => fail("duplicate collect accepted")
      }
      try ticket.finish() catch {
        Finished => ()
        err => raise err
      } noraise {
        _ => fail("finish after collect accepted")
      }
      assert_true(planner.busy) // stale ticket must not release the next batch
      assert_eq(planned.materialize(), expected)
      let exposed = planned.materialize()
      exposed[0].ranges.push({ start_line: 999, end_line: 999, })
      assert_eq(planned.materialize(), expected)
      assert_eq(next.finish(), expected)
      try next.collect() catch {
        Finished => ()
        err => raise err
      } noraise {
        _ => fail("collect after finish accepted")
      }
      retained.push((planned, expected))
    }
    planner.close()
    assert_eq(pool_live(planner.handle), 0)
    for (planned, expected) in retained {
      assert_eq(planned.materialize(), expected)
    }
  }
}

///|
async fn detached_after_owner_scope(sources : Array[Source]) -> PlannedBatch {
  let planner = Planner::new(workers=4)
  defer planner.close()
  // Returning only PlannedBatch drops both ticket and planner references;
  // deferred close also frees every native source/result before the return.
  planner.submit(sources).collect()
}

///|
async fn check_detached_fallbacks_and_errors() -> Unit {
  let oversize : Source = {
    path: "large.ts",
    text: " ".repeat(8 * 1024 * 1024 + 1),
  }
  let mixed : Array[Source] = [
    { path: "unknown.txt", text: "keep 😀\r\n", },
    { path: "broken.ts", text: "export function {", },
    oversize,
    { path: "ok.ts", text: "export function f() { return 123456789; }\n", },
  ]
  let expected = mixed.map(s => compress(s.path, s.text))
  let planned = detached_after_owner_scope(mixed)
  mixed.clear()
  // Constructing a full new pool also verifies the old owner was closed and
  // all four worker reservations were released before detached conversion.
  let planner = Planner::new(workers=4)
  defer planner.close()
  assert_eq(planned.materialize(), expected)
  let exposed = planned.materialize()
  exposed[0].ranges.push({ start_line: 999, end_line: 999, })
  assert_eq(planned.materialize(), expected)
  let empty_ticket = planner.submit([])
  assert_true(empty_ticket.is_ready())
  let empty = empty_ticket.collect()
  let fallback_ticket = planner.submit([
    oversize,
    { path: "raw.txt", text: "raw", },
  ])
  let fallbacks = fallback_ticket.collect()
  assert_eq(empty.materialize(), [])
  assert_eq(fallbacks.materialize(), [
    compress(oversize.path, oversize.text),
    compress("raw.txt", "raw"),
  ])
  let source : Source = { path: "one.ts", text: "const x = 1;", }
  let guarded = planner.submit([source])
  guarded.finishing = true
  try guarded.collect() catch {
    Busy => ()
    err => raise err
  } noraise {
    _ => fail("concurrent collector accepted")
  }
  assert_true(planner.busy)
  assert_false(planner.closed)
  guarded.finishing = false
  ignore(guarded.collect())
  let closed_ticket = planner.submit([source])
  planner.close()
  assert_true(closed_ticket.is_ready())
  try closed_ticket.collect() catch {
    Closed => ()
    err => raise err
  } noraise {
    _ => fail("closed collection became success")
  }
  assert_true(closed_ticket.finished)
  assert_eq(pool_live(planner.handle), 0)
  assert_eq(planned.materialize(), expected)
  assert_eq(fallbacks.materialize()[1], compress("raw.txt", "raw"))
  // White-box missing-result injection: one job, two expected native wires.
  // This exercises the real bridge's empty-Bytes error after one successful
  // owning copy, without changing production C or exposing mutable wire data.
  let failing = Planner::new(workers=4)
  defer failing.close()
  let ticket = failing.submit([source])
  ticket.inputs.push(ticket.inputs[0])
  try ticket.collect() catch {
    Unavailable => ()
    err => raise err
  } noraise {
    _ => fail("missing wire became success")
  }
  assert_true(failing.closed)
  assert_true(ticket.finished)
  assert_false(ticket.finishing)
  assert_eq(pool_live(failing.handle), 0)
  try ticket.finish() catch {
    Finished => ()
    err => raise err
  } noraise {
    _ => fail("failed collection ticket reused")
  }
  assert_eq(planned.materialize(), expected)
}
