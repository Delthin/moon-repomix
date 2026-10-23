///|
async test "directory publication: staging failure, cancellation and commit-point no-replace" {
  let root = @fs.tmpdir(prefix="moon-directory-ownership-")
  defer remove_owned_tree(root)
  // A lookalike staging directory is not ours and must survive every failure.
  let foreign = root + "/.moon-repomix-dir-foreign.tmp"
  @fs.mkdir(foreign)
  @fs.write_file(foreign + "/keep", "foreign", create_mode=CreateNew)
  let before = @fs.readdir(root, include_hidden=true, sort=true)
  let target = root + "/failed"
  // This is a valid component but exceeds host filename limits. Failure occurs
  // during staging, after the first file was successfully written and closed.
  let long_name = String::make(1024, 'x')
  try
    commit_directory(target, [
      { name: "first", text: "already written", },
      { name: long_name, text: "cannot create", },
    ])
  catch {
    @os_error.OSError(_, context=_) => ()
    err => raise err
  } noraise {
    _ => fail("oversized staging filename unexpectedly succeeded")
  }
  assert_false(@fs.exists(target))
  assert_eq(@fs.readdir(root, include_hidden=true, sort=true), before)

  let cancelled_target = root + "/cancelled"
  let entries : Array[DirectoryEntry] = Array::makei(256, index => {
    name: "volume-\{index}.txt",
    text: String::make(1024, 'a'),
  })
  let cancelled = @async.with_task_group(group => {
    let task = group.spawn(async fn() {
      commit_directory(cancelled_target, entries)
    })
    let mut staged = false
    // Observe a real staging file rather than cancelling before the task has
    // acquired anything. The other 255 fsyncs keep publication from winning.
    for _ in 0..<1000 {
      for name in @fs.readdir(root, include_hidden=true) {
        if name.has_prefix(".moon-repomix-dir-") &&
          name != ".moon-repomix-dir-foreign.tmp" {
          if !@fs.readdir(root + "/" + name, include_hidden=true).is_empty() {
            staged = true
          }
        }
      }
      if staged {
        break
      }
      @async.pause()
    }
    assert_true(staged, msg="did not observe in-progress staging")
    assert_false(@fs.exists(cancelled_target))
    task.cancel()
    try {
      task.wait()
      false
    } catch {
      err => if @async.is_cancellation_error(err) { true } else { raise err }
    }
  })
  assert_true(cancelled)
  assert_false(@fs.exists(cancelled_target))
  assert_eq(@fs.readdir(root, include_hidden=true, sort=true), before)
  assert_eq(@fs.read_file(foreign + "/keep").text(), "foreign")

  // Independently exercise the publication primitive: the destination appears
  // AFTER the public preflight check. In particular plain rename would replace
  // the empty directory below, so this detects a check-then-rename substitute.
  let source = root + "/ready"
  @fs.mkdir(source)
  @fs.write_file(source + "/volume", "complete", create_mode=CreateNew)
  let late = directory_output_path("late", root)
  @fs.mkdir(late)
  try directory_noreplace(source, late) catch {
    @os_error.OSError(_, context=_) => ()
    err => raise err
  } noraise {
    _ => fail("atomic primitive replaced a late empty directory")
  }
  assert_eq(@fs.readdir(late, include_hidden=true), [])
  assert_eq(@fs.read_file(source + "/volume").text(), "complete")
  @fs.rmdir(late)
  @fs.write_file(late, "late file", create_mode=CreateNew)
  try directory_noreplace(source, late) catch {
    @os_error.OSError(_, context=_) => ()
    err => raise err
  } noraise {
    _ => fail("atomic primitive replaced a late file")
  }
  assert_eq(@fs.read_file(late).text(), "late file")
  @fs.remove(late)
  if !is_windows() {
    for destination in [foreign, foreign + "/keep", root + "/absent"] {
      @fs.symlink(target=destination, late)
      try directory_noreplace(source, late) catch {
        @os_error.OSError(_, context=_) => ()
        err => raise err
      } noraise {
        _ => fail("atomic primitive replaced a late symlink")
      }
      assert_true(@fs.kind(late, follow_symlink=false) is SymLink)
      assert_eq(@fs.read_file(source + "/volume").text(), "complete")
      assert_eq(@fs.read_file(foreign + "/keep").text(), "foreign")
      assert_false(@fs.exists(root + "/absent"))
      @fs.remove(late)
    }
  }
  directory_noreplace(source, late)
  assert_false(@fs.exists(source))
  assert_eq(@fs.readdir(late), ["volume"])
  assert_eq(@fs.read_file(late + "/volume").text(), "complete")
  let remaining = @fs.readdir(root, include_hidden=true)
  assert_eq(remaining.length(), 2)
  assert_true(remaining.contains(".moon-repomix-dir-foreign.tmp"))
  assert_true(remaining.contains("late"))
}
