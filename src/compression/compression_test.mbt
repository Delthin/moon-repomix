///|
test "TypeScript outline retains source fragments, signatures and original lines" {
  let source =
    #|import { dep } from "./dep";
    #|/** API 文档 😀 */
    #|export function greet(name: string): string {
    #|  const message = dep(name);
    #|  return message + " very long implementation";
    #|}
    #|
  let out = @compression.compress("src/greet.ts", source)
  assert_true(out.applied)
  assert_eq(out.language, Some("typescript"))
  assert_eq(out.reason, None)
  let expected =
    #|import { dep } from "./dep";
    #|/** API 文档 😀 */
    #|export function greet(name: string): string {
    #|  /* … */
    #|}
    #|
  assert_eq(out.text, expected)
  assert_eq(out.ranges, [
    { start_line: 1, end_line: 3, },
    { start_line: 6, end_line: 6, },
  ])
}

///|
test "Python decorators, docstrings, imports, nested declarations and class methods" {
  let source =
    #|from typing import Optional, Union
    #|UserId = int
    #|Result = Union[Success, Error]
    #|
    #|@decorate
    #|class Service(Base):
    #|    """Public service documentation."""
    #|    def fetch(self, key: str) -> Optional[str]:
    #|        """Look up a key."""
    #|        # important: caller owns the result
    #|        def normalize(value: str) -> str:
    #|            return value.strip().lower() + "implementation details"
    #|        payload = self.storage.fetch(normalize(key))
    #|        return payload if payload is not None else "fallback details"
    #|
  let out = @compression.compress("service.py", source)
  assert_true(out.applied)
  assert_eq(out.language, Some("python"))
  for
    signature in [
      "from typing import Optional", "UserId = int", "Result = Union[Success, Error]",
      "@decorate", "class Service(Base):", "def fetch(self, key: str) -> Optional[str]:",
      "def normalize(value: str) -> str:", "\"\"\"Look up a key.\"\"\"", "# important: caller owns the result",
    ] {
    assert_true(out.text.contains(signature))
  }
  assert_false(out.text.contains("value.strip()"))
  assert_false(out.text.contains("self.storage.fetch"))
  assert_eq(out.ranges, [{ start_line: 1, end_line: 11, }])
}

///|
test "JS, JSX, TSX and inline implementations use AST byte spans" {
  let control_source =
    #|const choices = { code: 'js', yes: true, count: 1 };
    #|export function outer(plain, keep, items) {
    #|  if (plain) work('long implementation without a block');
    #|  if (plain) { work('long implementation inside a block'); }
    #|  if (keep) {
    #|    function helper(value) { return value.repeat(100) + 'long implementation'; }
    #|  }
    #|  for (let i = 0; i < items.length; i++) {
    #|    function step(value) { return value.repeat(100) + 'long implementation'; }
    #|  }
    #|  work('long implementation with first comment'); // first note
    #|  work('long implementation with second comment'); // second note
    #|}
    #|
  let python_control =
    #|def outer(plain, keep):
    #|    if plain: work('long implementation without a block')
    #|    if keep:
    #|        def normalize(value: str) -> str:
    #|            return value.strip().lower() + 'long implementation'
    #|
  let fixtures = [
    (
      "outline-control.js",
      control_source.replace_all(old="\n", new="\r\n"),
      "function helper(value)",
      "javascript",
    ),
    (
      "outline-control.py", python_control, "def normalize(value: str) -> str:",
      "python",
    ),
    (
      "a.mjs", "export class Greeter { greet(name) { return name.repeat(100) + 'long implementation'; } }",
      "greet(name)", "javascript",
    ),
    (
      "nested.js", "export function outer() { const helper = (value) => value.toLowerCase() + 'long implementation'; return helper('long caller details'); }",
      "const helper = (value) =>", "javascript",
    ),
    (
      "nested.py", "def outer():\n    helper = lambda value: value.lower() + 'long implementation'\n    return helper('long caller details')\n",
      "helper = lambda value:", "python",
    ),
    (
      "a.jsx", "export const View = (props) => <div>{props.items.map(x => <p>{x.name}</p>)}</div>;",
      "(props) =>", "javascript",
    ),
    (
      "a.tsx", "export const View = (props: Props): Element => <section>{props.items.map(x => <p>{x.name}</p>)}</section>;",
      "(props: Props): Element =>", "tsx",
    ),
    (
      "a.ts", "interface User { name: string }\nexport class API { value: string = 'long initializer details'; run(x: User): string { return x.name.repeat(1000); } }",
      "run(x: User): string", "typescript",
    ),
  ]
  for (path, source, signature, language) in fixtures {
    let out = @compression.compress(path, source)
    assert_true(out.applied)
    assert_eq(out.language, Some(language))
    assert_true(out.text.contains(signature))
    assert_true(out.text.length() < source.length())
    assert_false(out.text.contains("repeat(100"))
    assert_false(out.text.contains("items.map"))
    assert_false(out.text.contains("long caller details"))
    assert_false(out.text.contains("long implementation"))
    assert_false(out.text.contains("long initializer details"))
    if path == "outline-control.js" {
      assert_false(out.text.contains("work("))
      assert_false(out.text.contains("if (plain)"))
      assert_true(out.text.contains("if (keep)"))
      assert_true(out.text.contains("function step(value)"))
      assert_true(out.text.contains("let i = 0; i < items.length; i++"))
      assert_true(out.text.contains("code: 'js'"))
      assert_true(out.text.contains("yes: true"))
      assert_true(out.text.contains("count: 1"))
      assert_true(out.text.contains("// first note\r\n"))
      assert_true(out.text.contains("// second note\r\n"))
    } else if path == "outline-control.py" {
      assert_false(out.text.contains("work("))
      assert_false(out.text.contains("if plain:"))
      assert_true(out.text.contains("if keep:"))
    }
    assert_false(out.ranges.is_empty())
    for range in out.ranges {
      assert_true(range.start_line >= 1)
      assert_true(range.end_line >= range.start_line)
    }
  }
}

///|
test "unsupported, invalid syntax and non-smaller outlines return original text" {
  let fixtures = [
    ("unknown.rb", "def f\n  puts 'hello'\nend\n", "unsupported"),
    ("bad.js", "export function broken( {", "parse-error"),
    ("bad.py", "def broken(:\n    return 1\n", "parse-error"),
    (
      "imports.ts", "import type { A } from './a';\ninterface B { value: A }\n",
      "not-smaller",
    ),
    ("empty.py", "", "not-smaller"),
  ]
  for (path, source, reason) in fixtures {
    let out = @compression.compress(path, source)
    assert_false(out.applied)
    assert_eq(out.text, source)
    assert_eq(out.reason, Some(reason))
    assert_eq(out.ranges, [])
  }
}
