///|
test "remote URLs and revisions reject credentials, protocols and parameters" {
  // Keep complete hostile inputs at runtime, not credential-shaped source text.
  let synthetic = "credential-secret"
  for
    url in [
      "https://github.com/octocat/Hello-World.git", "https://git.example.org:8443/team/repo%20name.git",
    ] {
    validate_url(url)
  }
  for
    url in [
      "/tmp/repository",
      "../repository",
      "-c",
      "http://example.com/repo",
      "file:///tmp/repo",
      "ssh://example.com/repo",
      "git://example.com/repo",
      "ext::command",
      "https://" + synthetic + "@example.com/repo",
      "https://" + "user:" + synthetic + "@example.com/repo",
      "https://user%40example.com/repo",
      "https://example.com/repo?token" + "=" + synthetic,
      "https://example.com/repo#--upload-pack=command",
      "https://example.com\\evil/repo",
      "https://example.com/repo\ncommand",
      "https://example.com/repo%0acommand",
      "https://example.com/repo%00",
      "https://example.com/repo%xx",
      "https://example.com:0/repo",
      "https://example.com:65536/repo",
      "https://localhost/repo",
      "https://127.0.0.1/repo",
      "https://foo.local/repo",
      "https://[::1]/repo",
      "https://-bad.example/repo",
    ] {
    try validate_url(url) catch {
      InvalidInput(message) => assert_false(message.contains(synthetic))
      err => raise err
    } noraise {
      _ => fail("unsafe URL accepted")
    }
  }
  for
    revision in [
      "main", "feature/topic", "v1.0.0", "refs/tags/v1.0", "0123456789abcdef0123456789abcdef01234567",
    ] {
    validate_revision(revision)
  }
  for
    revision in [
      "", "-c", "--upload-pack=command", "/main", "../main", "HEAD^", "main:other",
      "main~1", "a//b", "a/.hidden", "a.lock/b", "a b", "a\ncommand",
    ] {
    try validate_revision(revision) catch {
      InvalidInput(_) => ()
      err => raise err
    } noraise {
      _ => fail("unsafe revision accepted")
    }
  }
}

///|
async test "remote lifecycle: Git failure, cancellation, protected cleanup and foreign handles" {
  let url = "https://github.com/octocat/Hello-World.git"
  let mut failed_directory = ""
  try
    temporary_checkout(url, directory => {
      failed_directory = directory
      let budget = { remaining: 8192, filters: [], }
      ignore(
        git(
          directory,
          ["init", "--quiet", "--template=", "--object-format=sha1"],
          budget,
        ),
      )
      // --stdin must see EOF, not an inherited terminal or an async NUL file.
      // Writing the empty SHA-1 blob also creates a read-only Windows Git object
      // before the operation fails, exercising failure-path cleanup.
      assert_eq(
        git(directory, ["hash-object", "-w", "--stdin"], budget),
        "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391\n",
      )
      let object = directory +
        "/.git/objects/e6/9de29bb2d1d6434b8b29ae775ad8c2e48c5391"
      assert_true(@fs.exists(object))
      if @platform.is_windows() {
        assert_false(@fs.can_write(object))
      }
      git(directory, ["not-a-git-command"], budget)
    })
  catch {
    CommandFailed(operation, code) => {
      assert_eq(operation, "not-a-git-command")
      assert_true(code != 0)
    }
    err => raise err
  } noraise {
    _ => fail("expected Git failure")
  }
  assert_false(failed_directory.is_empty())
  assert_false(@fs.exists(failed_directory))
  assert_false(owned_checkouts.contains(failed_directory))
  let mut cancelled_directory = ""
  try
    @async.with_timeout(10, () => {
      temporary_checkout(url, directory => {
        cancelled_directory = directory
        @async.sleep(10000)
        "unreachable"
      })
    })
  catch {
    @async.TimeoutError => ()
    err => raise err
  } noraise {
    _ => fail("cancellation became success")
  }
  assert_false(cancelled_directory.is_empty())
  assert_false(@fs.exists(cancelled_directory))
  assert_false(owned_checkouts.contains(cancelled_directory))
  let foreign = @fs.tmpdir(prefix="moon-git-foreign-test-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(foreign))
  @fs.write_file(foreign + "/keep", "user data", create_mode=CreateOrTruncate)
  let handle = temporary_checkout(url, directory => {
    @fs.write_file(
      directory + "/fixture",
      "fixture",
      create_mode=CreateOrTruncate,
    )
    let budget = { remaining: 8192, filters: [], }
    ignore(
      git(
        directory,
        ["init", "--quiet", "--template=", "--object-format=sha1"],
        budget,
      ),
    )
    assert_eq(
      git(directory, ["hash-object", "-w", "--stdin"], budget),
      "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391\n",
    )
    if !@platform.is_windows() {
      @fs.symlink(target=foreign, directory + "/outside-link")
      @fs.symlink(target=foreign + "/keep", directory + "/outside-file")
      @fs.chmod(foreign + "/keep", 0o444)
    }
    "0123456789abcdef0123456789abcdef01234567"
  })
  assert_true(@fs.exists(handle.directory))
  if @platform.is_windows() {
    assert_false(
      @fs.can_write(
        handle.directory +
        "/.git/objects/e6/9de29bb2d1d6434b8b29ae775ad8c2e48c5391",
      ),
    )
  }
  // A failed deletion must retain ownership, permitting recovery and retry.
  let saved = handle.directory + ".saved"
  @fs.rename(handle.directory, saved)
  try cleanup(handle) catch {
    @os_error.OSError(_, context=_) => ()
    err => raise err
  } noraise {
    _ => fail("cleanup of missing tree became success")
  }
  assert_true(owned_checkouts.contains(handle.directory))
  assert_true(@fs.exists(saved + "/fixture"))
  @fs.rename(saved, handle.directory)
  try
    @async.with_timeout(10, () => {
      defer cleanup(handle)
      @async.sleep(10000)
    })
  catch {
    @async.TimeoutError => ()
    err => raise err
  } noraise {
    _ => fail("cleanup swallowed cancellation")
  }
  assert_false(@fs.exists(handle.directory))
  assert_false(owned_checkouts.contains(handle.directory))
  assert_eq(@fs.read_file(foreign + "/keep").text(), "user data")
  if !@platform.is_windows() {
    assert_false(@fs.can_write(foreign + "/keep"))
  }
  try cleanup(handle) catch {
    InvalidInput(_) => ()
    err => raise err
  } noraise {
    _ => fail("already cleaned checkout accepted")
  }
  let forged : Checkout = { directory: foreign, url, revision: "forged", }
  try cleanup(forged) catch {
    InvalidInput(_) => ()
    err => raise err
  } noraise {
    _ => fail("foreign checkout accepted")
  }
  assert_true(@fs.exists(foreign + "/keep"))
  // Public API rejects before allocating a directory or starting Git/network.
  let revision = "main"
  try
    checkout(
      "https://" + "credential-secret@example.com/repo",
      revision~,
      history=1,
    )
  catch {
    InvalidInput(_) => ()
    err => raise err
  } noraise {
    _ => fail("credential URL accepted")
  }
}
