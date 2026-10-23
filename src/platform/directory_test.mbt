///|
async test "directory publication: exact UTF-8, normalized paths and empty directory" {
  let root = @fs.tmpdir(prefix="moon-directory-success-")
  defer @platform.remove_owned_tree(root)
  let canonical = @platform.separators(@fs.realpath(root))
  let target = @platform.directory_output_path("volumes///", root)
  assert_eq(target, canonical + "/volumes")
  assert_false(@fs.exists(target))
  let entries : Array[@platform.DirectoryEntry] = [
    { name: "00-index.json", text: "{\"title\":\"月亮🌙\"}\r\n", },
    { name: "卷-001.xml", text: "<text>α\u0000β</text>\n", },
    { name: ".metadata", text: "", },
  ]
  @platform.commit_directory(target + "/", entries)
  let published = @fs.readdir(target, include_hidden=true)
  assert_eq(published.length(), 3)
  assert_true(published.contains(".metadata"))
  assert_true(published.contains("00-index.json"))
  assert_true(published.contains("卷-001.xml"))
  assert_eq(
    @fs.read_file(target + "/00-index.json").binary(),
    b"{\"title\":\"\xe6\x9c\x88\xe4\xba\xae\xf0\x9f\x8c\x99\"}\r\n",
  )
  assert_eq(
    @fs.read_file(target + "/卷-001.xml").text(),
    "<text>α\u0000β</text>\n",
  )
  assert_eq(@fs.read_file(target + "/.metadata").binary(), b"")
  let empty = @platform.directory_output_path("empty/", root)
  @platform.commit_directory(empty, [])
  assert_true(@fs.kind(empty) is Directory)
  assert_eq(@fs.readdir(empty, include_hidden=true), [])
  assert_eq(@fs.readdir(root, include_hidden=true, sort=true), [
    "empty", "volumes",
  ])
  if @platform.is_windows() {
    assert_eq(
      @platform.directory_output_path("backslash\\", root),
      canonical + "/backslash",
    )
  }
}

///|
async test "directory publication: existing targets, links and unsafe entries stay untouched" {
  let root = @fs.tmpdir(prefix="moon-directory-invalid-")
  defer @platform.remove_owned_tree(root)
  let foreign = root + "/foreign"
  @fs.mkdir(foreign)
  @fs.write_file(foreign + "/keep", "untouched", create_mode=CreateNew)
  @fs.mkdir(root + "/existing-empty")
  @fs.write_file(root + "/existing-file", "original", create_mode=CreateNew)
  let occupied = ["foreign", "existing-empty", "existing-file"]
  if !@platform.is_windows() {
    @fs.symlink(target=foreign, root + "/linked")
    @fs.symlink(target=root + "/missing", root + "/dangling")
    occupied.push("linked")
    occupied.push("dangling")
  }
  for name in occupied {
    try @platform.directory_output_path(name + "/", root) catch {
      @platform.OutputError => ()
      err => raise err
    } noraise {
      _ => fail("existing target was accepted: \{name}")
    }
    try @platform.commit_directory(root + "/" + name, []) catch {
      @platform.OutputError => ()
      err => raise err
    } noraise {
      _ => fail("existing target was replaced: \{name}")
    }
  }
  for path in ["", ".", "..", "./", "../", "/", "///", "bad\u0000name"] {
    try @platform.directory_output_path(path, root) catch {
      @platform.OutputError => ()
      err => raise err
    } noraise {
      _ => fail("invalid target was accepted")
    }
  }
  try @platform.directory_output_path("missing/child", root) catch {
    @os_error.OSError(_, context=_) as err if err.is_ENOENT() => ()
    err => raise err
  } noraise {
    _ => fail("missing parent was created")
  }
  let before = @fs.readdir(root, include_hidden=true, sort=true)
  for
    name in [
      "", ".", "..", "nested/file", "nested\\file", "stream:ads", "nul\u0000x", "CON",
      "aux.txt", "LPT1.xml", "COM¹", "trailing.", "trailing ", "a?b",
    ] {
    try
      @platform.commit_directory(root + "/invalid", [{ name, text: "bad", }])
    catch {
      @platform.OutputError => ()
      err => raise err
    } noraise {
      _ => fail("unsafe entry was accepted")
    }
  }
  try
    @platform.commit_directory(root + "/duplicate", [
      { name: "same", text: "first", },
      { name: "same", text: "second", },
    ])
  catch {
    @platform.OutputError => ()
    err => raise err
  } noraise {
    _ => fail("duplicate entry was accepted")
  }
  assert_eq(@fs.readdir(root, include_hidden=true, sort=true), before)
  assert_eq(@fs.readdir(root + "/existing-empty"), [])
  assert_eq(@fs.read_file(root + "/existing-file").text(), "original")
  assert_eq(@fs.read_file(foreign + "/keep").text(), "untouched")
  if !@platform.is_windows() {
    assert_true(@fs.kind(root + "/linked", follow_symlink=false) is SymLink)
    assert_true(@fs.kind(root + "/dangling", follow_symlink=false) is SymLink)
    assert_false(@fs.exists(root + "/missing"))
  }
}
