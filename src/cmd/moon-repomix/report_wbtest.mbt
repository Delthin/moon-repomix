///|
async test "report finishes before pending cancellation propagates" {
  let mut completed = false
  finish_report(() => {
    @async.pause()
    completed = true
  })
  assert_true(completed)
  completed = false
  let mut entered = false
  let mut release = false
  let mut resumed = false
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      finish_report(() => {
        entered = true
        while !release {
          @async.pause()
        }
        completed = true
      })
      resumed = true
    })
    while !entered {
      @async.pause()
    }
    task.cancel()
    release = true
    try task.wait() catch {
      @async.WaitedTaskAlreadyCancelled => ()
      err => raise err
    } noraise {
      _ => fail("report turned cancellation into success")
    }
  })
  assert_true(completed)
  assert_false(resumed)
}
