///|
test "tokenizer resources follow source-build and installed executable layouts" {
  let cases : Array[(String, Bool, String)] = [
    (
      "/work/moon-repomix/_build/native/release/build/cmd/moon-repomix/moon-repomix.exe",
      false, "/work/moon-repomix/assets/tokenizer-o200k_base.tiktoken",
    ),
    (
      "/work/仓库/_build/native/debug/build/cmd/moon-repomix/moon-repomix.exe",
      false, "/work/仓库/assets/tokenizer-o200k_base.tiktoken",
    ),
    (
      "D:/工具/_BUILD/NATIVE/DEBUG/BUILD/CMD/MOON-REPOMIX/MOON-REPOMIX.EXE", true,
      "D:/工具/assets/tokenizer-o200k_base.tiktoken",
    ),
    (
      "//server/share/project/_build/native/release/build/cmd/moon-repomix/moon-repomix.exe",
      true, "//server/share/project/assets/tokenizer-o200k_base.tiktoken",
    ),
    (
      "/tmp/repo\\name/_build/native/debug/build/cmd/moon-repomix/moon-repomix.exe",
      false, "/tmp/repo\\name/assets/tokenizer-o200k_base.tiktoken",
    ),
    (
      "/opt/moon-repomix/bin/moon-repomix", false, "/opt/moon-repomix/share/moon-repomix/o200k_base.tiktoken",
    ),
    (
      "C:/Program Files/moon-repomix/bin/moon-repomix.exe", true, "C:/Program Files/moon-repomix/share/moon-repomix/o200k_base.tiktoken",
    ),
    (
      "/work/repo/_build/native/release/build/cmd/moon-repomix/other.exe", false,
      "/work/repo/_build/native/release/build/cmd/share/moon-repomix/o200k_base.tiktoken",
    ),
    (
      "/work/repo/_BUILD/NATIVE/DEBUG/BUILD/CMD/MOON-REPOMIX/MOON-REPOMIX.EXE", false,
      "/work/repo/_BUILD/NATIVE/DEBUG/BUILD/CMD/share/moon-repomix/o200k_base.tiktoken",
    ),
  ]
  for (executable, windows, expected) in cases {
    assert_eq(tokenizer_path_for_executable(executable, windows), expected)
  }
}
