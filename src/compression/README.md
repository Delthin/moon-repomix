# Native structure compression

Independent native-only package `Delthin/moon_repomix/compression`. No root
module dependency changes, subprocesses, runtime parser installations, or build
downloads. Tree-sitter runtime and generated grammar C sources ship in `vendor/`;
see [THIRD_PARTY.md](THIRD_PARTY.md) for exact sources and licenses.

## Integration contract

```moonbit
pub(all) struct LineRange {
  start_line : Int32
  end_line : Int32
}
pub(all) struct Outcome {
  text : String
  language : String?
  applied : Bool
  reason : String?
  ranges : Array[LineRange]
}
pub fn compress(path : String, text : String) -> Outcome
```

`Int32` is MoonBit's `Int` alias (the generated `.mbti` uses `Int`). Supported
extensions, case-insensitively:

| Extensions | `language` |
| --- | --- |
| `.js`, `.jsx`, `.mjs`, `.cjs` | `javascript` |
| `.ts`, `.mts`, `.cts` | `typescript` |
| `.tsx` | `tsx` |
| `.py`, `.pyi` | `python` |

The function parses the complete UTF-8 input with its actual grammar. AST node
kinds and fields select original source fragments; no regular-expression body
stripping is involved. Imports, type declarations, class/function/method
signatures, decorators, nested declarations (including direct arrow/lambda
bindings), enclosing control-flow structure, comments, and Python docstrings are
retained in source order. Implementations and data initializers are omitted.
All AST comments are conservatively retained, not just a heuristic subset.
Omissions use synthetic `/* … */` or Python `...` markers, with indentation for
whole-line omissions. The result is context text, **not executable source**.

`ranges` has one entry per retained contiguous original fragment, in the same
order as the output. Bounds are **1-based inclusive original lines**, not output
lines. Inline fragments can share line numbers; a range need not contain the
entire boundary lines. Synthetic omission markers have no range. CRLF and UTF-8
source fragments are copied unchanged; synthetic marker line breaks use LF.

`applied = true` requires retained original content and a strictly smaller UTF-8
result. Otherwise `text` is the exact original input, `ranges = []`, and `reason`
is one of:

- `unsupported`: unknown extension (`language = None`).
- `parse-error`: any Tree-sitter error/missing syntax node.
- `not-smaller`: no useful selection or no byte-size reduction.
- `timeout`: parsing exceeded the per-call 200,000 microsecond budget.
- `resource-limit`: UTF-8 input exceeds 8 MiB, AST traversal exceeds depth 512,
  selection exceeds 65,536 fragments, or selection allocation failed.
- `parser-unavailable`: grammar unavailable or rejected by the pinned runtime.

Supported-language fallbacks keep their detected `language`. Raw-source safety
scanning is the caller's responsibility **before** compression. There is no
shared parser/cache or retained source pointer: each call owns its parser, tree
and byte mask, and frees them before returning a MoonBit-managed byte plan.

## Build and verification

Package-local C translation units include vendored resources using relative
paths; `moon.pkg` needs no platform-specific include/link flags. The upstream
runtime includes Windows clock/endian support. macOS native compilation and
functional tests were verified using `moonc v0.10.15+943464bfa`; Windows execution
and cross-compilation remain unverified (no Windows SDK/toolchain was available).
MoonBit grammar support is intentionally not included.

With the project toolchain selected:

```
moon check src/compression --target native
moon test src/compression --target native
moon fmt src/compression
moon info src/compression --target native
```

Four aggregate functional tests cover all four grammars, signature and Unicode
comment preservation, nested bindings, exact original-line ranges, genuinely
smaller output, unsupported paths, invalid syntax, and unchanged non-smaller
fallbacks. A separate development ASan/UBSan harness exercised the actual C FFI
adapter and grammars, repeated cleanup, parse errors, timeout and size-limit
paths using a byte-array allocator shim with `moonbit.h`'s layout. This checks
C-side lifetimes rather than MoonBit GC instrumentation.
