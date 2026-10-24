///|
test "scoped relative paths reject traversal and ambiguous components" {
  for path in [".", "src", "src/中文"] {
    validate_relative(path)
  }
  for
    path in [
      "", "/tmp", "..", "a/../b", "a//b", "a/", "./a", "a\\b", "C:/x", "a\u0000b",
    ] {
    let rejected = try {
      validate_relative(path)
      false
    } catch {
      PublicError(400, _, _) => true
      _ => false
    }
    assert_true(rejected, msg=path)
  }
  assert_eq(workspace_path("/."), "/")
  assert_eq(workspace_path("C:/."), "C:/")
  assert_eq(workspace_path("C:/./."), "C:/")
  assert_true(contained("/workspace", "/workspace/child"))
  assert_false(contained("/workspace", "/workspace-other"))
}

///|
test "strict webui request schema and bounded patterns" {
  let valid : Json = {
    "directory": ".",
    "profile": "mixed",
    "tokenBudget": 8000,
    "includePatterns": ["src/**"],
    "keepFull": ["src/main.mbt"],
  }
  let parsed = pack_request(valid)
  assert_eq(parsed.profile, "mixed")
  assert_eq(parsed.budget, 8000)
  for
    body in [
      "{}",
      "[]",
      "{\"directory\":\".\",\"profile\":\"raw\",\"tokenBudget\":0,\"includePatterns\":[],\"keepFull\":[]}",
      valid.stringify().replace_all(old="8000", new="1.5"),
      valid.stringify().replace_all(old="8000", new="2147483648"),
      valid.stringify().replace_all(old="mixed", new="remote"),
      valid.stringify().replace_all(old="src/**", new="../outside"),
      valid.stringify().replace_all(old="src/**", new="x".repeat(1025)),
    ] {
    assert_true(
      try {
        ignore(pack_request(@json.parse(body)))
        false
      } catch {
        _ => true
      },
    )
  }
  guard valid is Object(values) else { fail("fixture") }
  values["securityCheck"] = false
  assert_true(
    try {
      ignore(pack_request(Json::object(values)))
      false
    } catch {
      _ => true
    },
  )
  values.remove("securityCheck")
  values["includePatterns"] = Json(Array::make(65, "x"))
  assert_true(
    try {
      ignore(pack_request(Json::object(values)))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "exact Host Origin and mandatory custom client header" {
  let headers : Map[String, String] = {
    "host": "127.0.0.1:8765",
    "x-moon-repomix": "webui",
  }
  let request : @http.Request = { meth: Get, path: "/api/session", headers, }
  authorize(request, 8765)
  headers["origin"] = "http://127.0.0.1:8765"
  authorize(request, 8765)
  for
    origin in [
      "null", "https://127.0.0.1:8765", "http://localhost:8765", "http://evil.invalid",
    ] {
    headers["origin"] = origin
    assert_true(
      try {
        authorize(request, 8765)
        false
      } catch {
        PublicError(403, _, _) => true
        _ => false
      },
    )
  }
  headers.remove("origin")
  for host in ["localhost:8765", "127.0.0.1", "127.0.0.1:8766", "evil.invalid"] {
    headers["host"] = host
    assert_true(
      try {
        authorize(request, 8765)
        false
      } catch {
        PublicError(403, _, _) => true
        _ => false
      },
    )
  }
  headers["host"] = "127.0.0.1:8765"
  headers.remove("x-moon-repomix")
  assert_true(
    try {
      authorize(request, 8765)
      false
    } catch {
      PublicError(403, _, _) => true
      _ => false
    },
  )
  assert_true(
    try {
      authorize({ ..request, meth: Options, }, 8765)
      false
    } catch {
      PublicError(403, _, _) => true
      _ => false
    },
  )
}

///|
#cfg(platform="windows")
async fn remove_fixture_directory_link(path : String) -> Unit {
  // Remove the Windows directory-link entry without traversing its target.
  @fs.rmdir(path)
}

///|
#cfg(not(platform="windows"))
async fn remove_fixture_directory_link(path : String) -> Unit {
  @fs.remove(path)
}

///|
async test "filesystem scope rejects linked components and roots" {
  let temp = @fs.tmpdir(prefix="moon-webui-test-")
  // Only synthetic temporary fixtures; never a user's repository.
  @fs.mkdir(temp + "/root")
  @fs.mkdir(temp + "/outside")
  @fs.mkdir(temp + "/root/child")
  @fs.symlink(target=temp + "/outside", temp + "/root/link")
  @fs.symlink(target=temp + "/root", temp + "/linked-root")
  let root = canonical_root(temp + "/root")
  assert_eq(canonical_root(temp + "/root/."), root)
  assert_eq(scoped_directory(root, "child"), root + "/child")
  assert_true(
    try {
      ignore(scoped_directory(root, "link"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(canonical_root(temp + "/linked-root/."))
      false
    } catch {
      _ => true
    },
  )
  remove_fixture_directory_link(temp + "/root/link")
  remove_fixture_directory_link(temp + "/linked-root")
  @fs.rmdir(temp + "/root/child")
  @fs.rmdir(temp + "/root")
  @fs.rmdir(temp + "/outside")
  @fs.rmdir(temp)
}

///|
async test "single pack gate returns 409 and cancellation releases it" {
  let resource = @env.current_dir().unwrap() +
    "/assets/tokenizer-o200k_base.tiktoken"
  let runtime = @repomix.Runtime::load(resource)
  let root = @fs.tmpdir(prefix="moon-webui-cancel-")
  @fs.write_file(
    root + "/sample.txt",
    "synthetic source\n".repeat(100),
    create_mode=CreateNew,
  )
  let options = @repomix.options(
    root,
    style=Json,
    max_files=2000,
    max_total_size=16777216L,
  )
  let state : State = { options, runtime, resource, port: 8765, busy: false, }
  let request : PackRequest = {
    directory: ".",
    profile: "raw",
    budget: 8000,
    includes: [],
    keep_full: [],
  }
  @async.with_task_group(group => {
    let running = group.spawn(() => build(state, request), allow_failure=true)
    @async.pause()
    assert_true(state.busy)
    assert_true(
      try {
        ignore(build(state, request))
        false
      } catch {
        PublicError(409, "pack_busy", _) => true
        _ => false
      },
    )
    running.cancel()
    let cancelled = try {
      ignore(running.wait())
      false
    } catch {
      err => @async.is_cancellation_error(err)
    }
    assert_true(cancelled)
    assert_false(state.busy)
  })
  ignore(build(state, request))
  assert_false(state.busy)
  @fs.remove(root + "/sample.txt")
  @fs.rmdir(root)
}
