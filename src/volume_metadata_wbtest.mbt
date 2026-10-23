///|
test "volume metadata follows canonical files and original Git section identities" {
  let source : Json = {
    "kind": "remote",
    "url": "https://example.com/repo",
    "revision": "fixed",
  }
  let first : Json = { "path": "a.ts", "applied": true }
  let second : Json = { "path": "b.ts", "applied": false }
  let diff : Json = {
    "kind": "staged",
    "paths": ["a.ts", "b.ts", "deleted.ts"],
  }
  let commit : Json = { "id": "commit", "files": ["b.ts", "deleted.ts"] }
  let metadata : Json = {
    "source": source,
    "compression": [first, second],
    "git": { "diffs": [diff], "commits": [commit] },
    "custom": { "scope": "global" },
  }
  let document = @document.create(
    [{ path: "b.ts", text: "b", }, { path: "a.ts", text: "a", }],
    sections=[
      { kind: "git_diff", title: "same", text: "diff", },
      { kind: "note", title: "same", text: "custom", },
      { kind: "git_log", title: "same", text: "log", },
    ],
    metadata~,
  )
  let projection = volume_metadata(document)
  assert_eq(projection.project([0], [2]), {
    "source": source,
    "compression": [first],
    "git": { "diffs": [], "commits": [commit] },
  })
  assert_eq(projection.project([1], [0, 1]), {
    "source": source,
    "compression": [second],
    "git": { "diffs": [diff], "commits": [] },
  })
  assert_eq(projection.project([], []), {
    "source": source,
    "compression": [],
    "git": { "diffs": [], "commits": [] },
  })
  assert_eq(document.metadata, metadata)
  assert_eq(volume_metadata(@document.create([])).project([], []), Json::null())
  try projection.project([-1], []) catch {
    ConfigurationError => ()
    _ => fail("Wrong projection error")
  } noraise {
    _ => fail("Invalid file index was accepted")
  }
  let mismatched = @document.create([], metadata={
    "git": { "diffs": [diff], "commits": [] },
  })
  try volume_metadata(mismatched) catch {
    ConfigurationError => ()
    _ => fail("Wrong metadata association error")
  } noraise {
    _ => fail("Unbound Git record was accepted")
  }
}
