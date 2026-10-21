///|
#cfg(not(platform="windows"))
async fn readonly_fixture(path : String) -> Unit {
  @fs.chmod(path, 0o444)
}

///|
#cfg(platform="windows")
async fn readonly_fixture(_path : String) -> Unit {
  ()
}

///|
async test "owned tree removal: hidden files, read-only files and no-follow boundaries" {
  let outer = @fs.tmpdir(prefix="moon-owned-tree-test-")
  defer @platform.remove_owned_tree(outer)
  let foreign = outer + "/foreign"
  @fs.mkdir(foreign)
  @fs.write_file(foreign + "/keep", "outside", create_mode=CreateNew)
  let tree = outer + "/owned"
  @fs.mkdir(tree + "/.hidden/nested", recursive=true)
  @fs.write_file(
    tree + "/.hidden/nested/readonly",
    "owned",
    create_mode=CreateNew,
  )
  if !@platform.is_windows() {
    readonly_fixture(tree + "/.hidden/nested/readonly")
    readonly_fixture(foreign + "/keep")
    @fs.symlink(target=foreign, tree + "/directory-link")
    @fs.symlink(target=foreign + "/keep", tree + "/file-link")
    @fs.symlink(target=foreign + "/absent", tree + "/dangling-link")
    let root_link = outer + "/root-link"
    @fs.symlink(target=foreign, root_link)
    try @platform.remove_owned_tree(root_link) catch {
      @os_error.OSError(_, context=_) => ()
      err => raise err
    } noraise {
      _ => fail("linked root accepted")
    }
    assert_true(@fs.kind(root_link, follow_symlink=false) is SymLink)
    assert_eq(@fs.read_file(foreign + "/keep").text(), "outside")
  }
  @platform.remove_owned_tree(tree)
  assert_false(@fs.exists(tree))
  assert_eq(@fs.read_file(foreign + "/keep").text(), "outside")
  if !@platform.is_windows() {
    assert_false(@fs.can_write(foreign + "/keep"))
  }
  try @platform.remove_owned_tree(tree) catch {
    @os_error.OSError(_, context=_) => ()
    err => raise err
  } noraise {
    _ => fail("missing tree deletion became success")
  }
}
