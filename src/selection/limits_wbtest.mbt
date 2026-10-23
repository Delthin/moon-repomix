///|
async test "candidate limits apply before append after exclusions for recursive and exact selection" {
  fixture() <| root => {
    put(root, "a.txt", "one")
    put(root, "b.txt", "two")
    put(root, "ignored.txt", "ignored")
    put(root, "ignored/tree.txt", "ignored descendant")
    let options = { ..SelectionOptions::default(), ignore: ["ignored*"], }
    for
      paths in [
        None,
        Some(["b.txt", "ignored.txt", "a.txt", "a.txt", "ignored/tree.txt"]),
      ] {
      let equal = select(root, options, file_paths=paths, max_files=2)
      assert_eq(equal.files.map(f => f.relative), ["a.txt", "b.txt"])
      for limit in [0, 1] {
        try select(root, options, file_paths=paths, max_files=limit) catch {
          SelectionError::FileLimitExceeded(limit=actual) =>
            assert_eq(actual, limit)
          _ => fail("unexpected selection limit error")
        } noraise {
          _ => fail("candidate excess must fail before reading")
        }
      }
    }
    let empty = select(
      root,
      options,
      file_paths=Some(["ignored.txt"]),
      max_files=0,
    )
    assert_eq(empty.files.length(), 0)
    let no_candidates = { ..options, include_patterns: ["absent.txt"], }
    assert_eq(select(root, no_candidates, max_files=0).files.length(), 0)
  }
}
