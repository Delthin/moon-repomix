///|
test "cwd labels keep filesystem spelling and respect Windows volumes" {
  for
    (root, cwd, windows, expected) in [
      ("/repo/src", "/repo", false, "src"),
      ("/repo", "/repo/src", false, ".."),
      ("/repo", "/repo", false, ""),
      ("/", "/repo/src", false, "../.."),
      ("/repo/with\\backslash", "/repo", false, "with\\backslash"),
      ("C:\\Work\\Repo", "c:/work/other", true, "../Repo"),
      ("D:/Repo", "C:/work", true, "D:/Repo"),
      ("//server/share/repo", "//SERVER/share/work", true, "../repo"),
      (
        "//server/other/repo", "//server/share/work", true, "//server/other/repo",
      ),
    ] {
    assert_eq(relative_label_root(root, cwd, windows), expected)
  }
}
