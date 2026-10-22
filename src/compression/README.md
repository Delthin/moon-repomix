# Native structure compression

Independent native-only package `Delthin/moon_repomix/compression`. No
subprocesses, runtime parser installations, or build downloads. Tree-sitter runtime and generated grammar C sources ship in `vendor/`;
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
| `.mbt`, `.mbti` | `moonbit` |

The function parses the complete UTF-8 input with its actual grammar. AST node
kinds and fields select original source fragments; no regular-expression body
stripping is involved. Imports, type declarations, class/function/method
signatures, decorators, nested declarations (including direct arrow/lambda
bindings), enclosing control-flow structure, comments, and Python docstrings are
retained in source order. Implementation-only branches and loops are omitted;
conditions enclosing nested declarations remain. CommonJS static `require`
bindings, export aliases, and member APIs installed inside callbacks are retained.
Private scalar/primitive-array tables with an explicit wide
`Record<string, ...>` or `Record<number, ...>` annotation can fold as one
initializer with at least two entries. Inferred scalar/array tables and explicitly
wide-key `Record` tables of constructor expressions require at least eight
entries. References must be indexed reads of the same lexical binding; parameter,
block, loop, catch and hoisted bindings can shadow it. Ambiguous type-only or
block declarations preserve the table, and parameter defaults do not inherit
body-local bindings. Exports, aliases, type queries, whole-table returns/serialization/arguments, key enumeration and table
mutations protect structure. Literal types/assertions, methods, computed keys
and spreads also protect it; constructor arguments containing object schemas,
inline callbacks or calls prevent folding. Other initializers are omitted when the
removed fragment is longer than the omission marker; short values stay unchanged.
Comments and their line terminators remain, except category comments inside a
table whose values were folded.
Omissions use synthetic `/* … */` or Python `...` markers, with indentation for
whole-line omissions. Adjacent deleted regions merge; presentation-only blank
lines between AST children compact, while literal and comment interiors stay
unchanged. The result is context text, **not executable source**.

### MoonBit AST coverage

MoonBit uses the official root grammar with documented current-syntax patches
for both source and interface files.
Functions (including `async`, `Type::method`, extern and local named functions),
`impl ... with` methods and tests retain their complete original signatures,
parameters/defaults, return/error annotations and body delimiters. Their
implementation interiors are omitted using AST block/token boundaries. Foreign
symbol/module linkage strings remain intact; only multiline inline extern bodies
are omitted. Local
struct/enum/type declarations and named functions survive even inside discarded
control flow; enclosing implementation conditions are not retained for MoonBit.
Matrix-function cases are implementations. Imports, attributes/`#cfg`, `///|`
comments, constants, structs, enums, traits, type aliases, derives and interface
impl declarations remain unchanged. Record-update and string braces are never
used as callable-body boundaries. Plain `#|` and interpolated `$|` multiline
strings, Unicode and CRLF are covered. A scanner-local CRLF adapter leaves
the input and vendored scanner bytes unchanged. MoonBit does not use the JS/TS/Python
initializer-folding or presentation-compaction passes. Interface-only `.mbti`
files normally return `not-smaller`, not `applied`.

The ABI 15 grammar supports tuple identifier bindings in `for` loops, inclusive
`..<=` range patterns and `errdefer`. The runtime remains v0.25.3; the local grammar
patch, generator version and generated-source hashes are in
[THIRD_PARTY.md](THIRD_PARTY.md). Invalid syntax returns the
exact original with `language = Some("moonbit")`, `reason = Some("parse-error")`
and no ranges. Error/missing nodes are never ignored or normalized away.

`ranges` has one entry per retained contiguous original fragment, in the same
order as the output. Bounds are **1-based inclusive original lines**, not output
lines. Inline fragments can share line numbers; a range need not contain the
entire boundary lines. Synthetic omission markers have no range. CRLF and UTF-8
source fragments are copied unchanged; synthetic marker line breaks follow the
removed fragment's CRLF or LF terminator.

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
runtime includes Windows clock/endian support. The original seven compression
groups have passed native CI on Windows, Linux and macOS. The MoonBit groups and
scanner adapter have been verified on macOS native with
`moonc v0.10.15+943464bfa`; MoonBit Windows/Linux execution is not yet claimed.
All adapters use portable C and need no platform-specific flags.

With the project toolchain selected:

```
moon check src/compression --target native --frozen
moon test src/compression --target native --frozen
moon fmt src/compression
moon info src/compression --target native --frozen
```

The original seven grouped tests remain unchanged and cover JS/TS/TSX/Python,
signature and Unicode comment
preservation, nested bindings, exact original-line ranges, genuinely smaller
output, unsupported paths, invalid syntax, unchanged non-smaller fallbacks,
private tables versus public types, CommonJS APIs, and whitespace/literal boundaries.
Two additional MoonBit groups cover declarations/literal boundaries, tuple loops,
range patterns, `errdefer`, complete default callback signatures, nested matrix
functions, invalid/`#~` fallbacks, case-insensitive extensions, `.mbti` interfaces
and exact Unicode/CRLF output and line ranges.
