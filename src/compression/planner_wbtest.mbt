///|
async fn check_ordered_batches() -> Unit {
  let fixtures : Array[Source] = [
    {
      path: "x.js",
      text: "// café\r\nexport function f(x) {\r\n  return x + 123456789;\r\n}\r\n",
    },
    {
      path: "x.ts",
      text: "export function f(x: number): number { return x + 123456789; }\n",
    },
    {
      path: "x.tsx",
      text: "export function F() { return <div>hello world</div>; }\n",
    },
    {
      path: "x.py",
      text: "# café\r\ndef f(x):\r\n    return x + 123456789\r\n",
    },
    { path: "x.mbt", text: "pub fn f(x : Int) -> Int { x + 123456789 }\n", },
    {
      path: "x.go",
      text: "package p\nfunc F(x int) int { return x + 123456789 }\n",
    },
    { path: "x.rs", text: "pub fn f(x: i32) -> i32 { x + 123456789 }\n", },
    {
      path: "x.java",
      text: "class C { int f(int x) { return x + 123456789; } }\n",
    },
    { path: "empty.ts", text: "", },
    { path: "plain.txt", text: "unchanged 😀\r\n", },
    { path: "broken.ts", text: "export function {", },
    { path: "tiny.ts", text: "interface X {}\n", },
  ]
  for workers in [1, 2, 4] {
    let planner = Planner::new(workers~)
    defer planner.close()
    assert_eq(pool_live(planner.handle), workers)
    assert_eq(planner.compress([]), [])
    for start = 0; start < fixtures.length(); start = start + 4 {
      let batch = fixtures[start:start + 4].to_owned()
      let expected = batch.map(s => compress(s.path, s.text))
      let ticket = planner.submit(batch)
      // Replacing the caller's array does not replace the ticket's snapshot.
      batch[0] = { path: "replaced.txt", text: "wrong", }
      let actual = ticket.finish()
      assert_eq(actual, expected)
      assert_eq(pool_live(planner.handle), workers)
      try ticket.finish() catch {
        Finished => ()
        err => raise err
      } noraise {
        _ => fail("ticket reused")
      }
    }
    planner.close()
    planner.close()
    assert_eq(pool_live(planner.handle), 0)
    try planner.submit([]) catch {
      Closed => ()
      err => raise err
    } noraise {
      _ => fail("closed planner accepted batch")
    }
  }
}

///|
async fn check_limits_and_close() -> Unit {
  for workers in [0, 5] {
    try Planner::new(workers~) catch {
      InvalidWorkers => ()
      err => raise err
    } noraise {
      _ => fail("invalid worker count")
    }
  }
  let planner = Planner::new(workers=2)
  defer planner.close()
  let small : Source = { path: "x.ts", text: "const x = 1;", }
  try planner.submit([small, small, small, small, small]) catch {
    BatchLimit => ()
    err => raise err
  } noraise {
    _ => fail("five tasks accepted")
  }
  let full : Source = { path: "full.ts", text: " ".repeat(8 * 1024 * 1024), }
  try planner.submit([full, full, small]) catch {
    BatchLimit => ()
    err => raise err
  } noraise {
    _ => fail("over 16 MiB accepted")
  }
  let oversize : Source = { path: "large.ts", text: full.text + " ", }
  assert_eq(planner.compress([oversize]), [
    compress(oversize.path, oversize.text),
  ])
  let ticket = planner.submit([small])
  try planner.submit([]) catch {
    Busy => ()
    err => raise err
  } noraise {
    _ => fail("overlapping batch accepted")
  }
  planner.close()
  assert_eq(pool_live(planner.handle), 0)
  try ticket.finish() catch {
    Closed => ()
    err => raise err
  } noraise {
    _ => fail("closed pending batch became success")
  }
}

///|
async fn check_cancelled_finish() -> Unit {
  let planner = Planner::new(workers=4)
  defer planner.close()
  let source : Source = {
    path: "cancel.ts",
    text: "export function f() { return 123456789; }\n".repeat(12000),
  }
  let ticket = planner.submit([source, source, source, source])
  let mut entered = false
  let mut release = false
  @async.with_task_group(async fn(group) {
    let task = group.spawn(
      async fn() {
        // Arrange cancellation before finish deterministically, without a wall
        // clock race against a fast parser or the shared machine's CPU load.
        @async.protect_from_cancel(
          async fn() {
            entered = true
            while !release {
              @async.pause()
            }
          },
          resume_on_cancel=true,
        )
        ignore(ticket.finish())
      },
      allow_failure=true,
    )
    while !entered {
      @async.pause()
    }
    task.cancel()
    release = true
    try task.wait() catch {
      err => assert_true(@async.is_cancellation_error(err))
    } noraise {
      _ => fail("cancellation became success")
    }
  })
  assert_eq(pool_live(planner.handle), 0)
  assert_true(planner.closed)
  planner.close()
}

///|
async test "worker pool: ordered batches, ownership, limits, protected cancellation and close" {
  // Native async tests may run concurrently in one process. These scenarios
  // deliberately share the process-wide hard quota, so execute them in order.
  check_ordered_batches()
  check_limits_and_close()
  check_cancelled_finish()
}
