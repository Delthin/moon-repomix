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
| `.go` | `go` |
| `.rs` | `rust` |
| `.java` | `java` |

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

### Go and Rust AST coverage

Go retains package/import declarations, comments/build tags, complete type
aliases, structs/tags, interfaces/type sets, generic constraints, receiver and
function signatures, full parameters and results. Only function/method/literal
body interiors are omitted at the actual block's brace tokens. Nested type
definitions and closure bindings survive, including below discarded control flow.

Rust retains use/mod declarations, attributes/docs, struct/enum/union/trait
shapes, impl headers, associated types/constants, visibility, generics, lifetimes,
where clauses and complete function signatures. Functions and default trait/impl
methods lose only their AST body interiors. Nested items and their attributes
survive. Macro definitions and invocations are opaque original fragments, even
inside bodies: they may generate public API. Extern blocks/declarations, constants,
types and unknown items are conservatively preserved, not guessed or expanded.
This can yield little or no compression for macro-heavy or interface-only files.
Neither language uses initializer folding or presentation compaction. As with
MoonBit, enclosing implementation conditions around nested definitions are omitted;
the outline is not an executable program.

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

## Reusable asynchronous planner

```moonbit
pub(all) struct Source {
  path : String
  text : String
}
pub fn Planner::new(workers? : Int) -> Planner raise PlannerError
pub fn Planner::submit(Self, Array[Source]) -> BatchTicket raise PlannerError
pub async fn BatchTicket::collect(Self) -> PlannedBatch
pub fn PlannedBatch::materialize(Self) -> Array[Outcome]
pub async fn BatchTicket::finish(Self) -> Array[Outcome]
pub async fn Planner::compress(Self, Array[Source]) -> Array[Outcome]
pub async fn Planner::close(Self) -> Unit
```

`submit` synchronously copies eligible UTF-8 into C-owned storage and starts the
batch before returning. The caller may then count original tokens on the main
thread before awaiting `ticket.finish()`. `compress` is `submit(...).finish()`.
Use `defer planner.close()` immediately after construction, including around work
between submit and collect/finish. Close after the final batch; reuse the pool
between batches. A ticket retains its planner and its own snapshot of the source
array. Results, ranges and fallback semantics match the single-source `compress`.
Neither API performs security scanning.

`collect` waits for all jobs, validates each returned wire, then releases the
native batch and clears the pool's active state **before** converting any wire
into output text/ranges. The existing main-thread bridge allocates fresh
`moonbit_make_bytes` storage and `memcpy`s each wire before native release; no
borrowed C buffer escapes. The opaque `PlannedBatch` holds only private managed
source/preparation data and owned wire bytes, with no planner/handle/C pointer.
`materialize` is synchronous, non-raising and repeatable: it reads that data,
returns fresh output arrays/ranges and performs no pool calls or I/O. It is safe
while the next batch runs, after close, and after the original owner is dropped.
`finish` remains `collect().materialize()`; `compress` remains `submit(...).finish()`.
For overlap, call `let planned = current.collect()`, then submit the next bounded
batch, then call `planned.materialize()` before awaiting that next ticket. Keep
`defer planner.close()` covering any ticket not yet collected. Retained detached
batches keep their managed text/UTF-8/wires alive until dropped; callers must
bound that retention. They hold no native task/input leases.

Planner, ticket and detached result state is opaque outside the package. Workers
default to 2 and must be 1..4 (otherwise `InvalidWorkers`); a batch contains at most four
sources and at most 16 MiB of eligible original UTF-8 (`BatchLimit`). Unsupported
and over-8-MiB sources return the existing exact fallback without copying into C.
Only one uncollected ticket per pool is allowed (`Busy`), even for empty batches;
a second collect or finish, in any combination, raises `Finished`. A concurrent
collector/finisher raises `Busy` without disturbing the first. Closing invalidates
pending tickets and future submissions (`Closed`). Thread creation, staging allocation or result allocation
failure raises `Unavailable`, not a retry or a synthetic timeout. Process-wide
atomic reservations additionally cap all open planners together at four workers,
four C-owned task inputs and 16 MiB raw UTF-8; exhausting another pool's budget
also raises `Unavailable`. Reservations are released on staging failure, batch
release and close (including partial thread-creation failure). Callers may
explicitly choose the original serial API if construction or staging is
unavailable; a failed submit has not started any tasks. Do not retry a failed
collect/finish or discard its timeout/cancellation.

Each OS worker performs the entire parse, AST walk, keep-mask and wire-plan
construction with its own input/parser/tree/scanner/selection/result. Workers
never access managed values or call MoonBit allocation. The main thread converts
wire plans to MoonBit bytes/text/ranges, preserving input order. Parser budgets
remain 200 ms, traversal depth 512, fragments 65,536 and source size 8 MiB.
Waiting polls with async sleep; it does not join on the event-loop thread while
workers are running. Cancellation of collect/finish stops queued work, atomically
notifies parsing (Tree-sitter 0.25.3 progress callback) and postprocessing, drains under
`async@0.19.2` cancellation protection, joins and frees the pool, then propagates
cancellation. Close is idempotent and also cancellation-protected. The external
object finalizer is an emergency stop/join, not a substitute for explicit close.

The eight generated grammars do not mutate shared tables (some generated
character-range arrays are not const-qualified but are only read). JS/TS/TSX
scanners are stateless; Python and Rust state is per scanner; MoonBit's scanner has no shared
mutation; Go and Java have no external scanner. Runtime parser/tree state is
per task. Runtime allocator function pointers and locale are process-global:
embedding callers must not change Tree-sitter allocators or the locale while
planning. No grammar/runtime dependency has been upgraded.

Complete child enumeration uses forward Tree-sitter cursors rather than repeated
indexed child lookup. In the pinned runtime, indexed lookup scans from the first
child; a forward cursor retains sibling position, including hidden grammar
nodes. Named-only walks filter visible cursor nodes with the alias-aware
`ts_node_is_named`, preserving anonymous-token handling, order and original node
identity. Each walk owns and closes its cursor on exhaustion, cancellation and
early return. Constant-index lookups, parent/field rules, selection depth and
all compression decisions are unchanged. This makes each child enumeration
linear; it does not cache or change repeated outline/binding queries.

## Build and verification

Package-local C translation units include vendored resources using relative
paths; `moon.pkg` needs no platform-specific include/link flags. The upstream
runtime includes Windows clock/endian support. The original nine compression
groups, including MoonBit, passed native CI on Windows, Linux and macOS for
v0.3.0. The subsequent four Go/Rust groups also passed current-source native
CI on all three platforms. The two Java groups have been verified on macOS
native with `moonc v0.10.15+943464bfa`; Java Windows/Linux execution has not
been verified yet.
The pool uses pthreads on POSIX and Win32 threads on Windows. macOS links
pthreads via the system library; POSIX toolchains that require it must link with
`-pthread`. Windows/Linux worker execution has not yet been verified.

With the project toolchain selected:

```
moon check src/compression --target native --frozen --deny-warn
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
Four Go/Rust groups cover complete type/signature preservation, nested definitions,
macro/extern conservatism, literal braces, original Unicode/CRLF fragments and
exact ranges, case-insensitive extensions, invalid syntax and honest non-smaller
fallbacks.

Two Java groups cover complete generic/constructor/native/throws signatures,
annotations, records/enums/interfaces, conservative fields, nested and anonymous
class APIs, original reference anchors, exact CRLF/Unicode ranges and unchanged
fallbacks. Java uses the fixed native parser described in `THIRD_PARTY.md`.

The worker lifecycle group checks 1/2/4-worker ordered serial equivalence across
all eight grammars, multi-batch reuse, source-array ownership, fallbacks, limits,
empty input, busy/finished/closed states and protected cancellation with zero live
workers afterward. Detached-result scenarios in `detached_wbtest.mbt` also check
collect-before-next-submit across all eight grammars and 1/2/4 workers, retained
results after reuse/close/owner scope exit, empty/all-fallback/mixed inputs,
mutable output isolation, once-only collection, partial missing-wire cleanup and
protected collect cancellation. The original 16 test groups remain; these
scenarios run sequentially inside the worker group because the async test driver
can otherwise run them concurrently against the process-wide hard budget.

Managed bridge ASan checks can use the white-box test driver's generated C plus
`ffi.c`, `worker_ffi.c` and locally compiled MoonBit runtime sources with
`-fsanitize=address -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM`. Omit the
mimalloc `libmoonbitrun.o` when linking this diagnostic executable; do not replace
or modify shared toolchain objects. This instruments managed allocation/copy and
post-release materialization, unlike the standalone C tests below. Reusing the
normal grammar/pool archives does not instrument their internal memory accesses.

`tests/traversal_test.c` is a standalone POSIX white-box traversal harness. It
checks complete named/all-child sequences against indexed runtime access,
including alias identity, anonymous tokens, extras and parents; all eight
grammars have wide and nested fixtures. It also checks exact depth guards,
early-return cursor ownership, deterministic mid-traversal cancellation and
four concurrent independent plans. To run it, use the grammar/runtime compiler
command below, replacing the worker harness with `tests/traversal_test.c` and
omitting both `compression_core.c` (included by the test) and the pool object.
For before/after full-mask differential checks, define `SC_TRAVERSAL_REFERENCE`
and link an independently captured original core compiled with
`-Dsc_plan=sc_reference_plan -Dsc_plan_cancelable=sc_reference_plan_cancelable`.
Only differential fixtures disable the parser clock, so scheduling cannot create
false mismatches; production and package tests retain the 200 ms parser budget.

`tests/worker_pool_test.c` is a standalone POSIX harness. It also checks copied
input ownership after the caller mutates/frees its input, independent original
line-range accounting, deterministic parser timeout/depth limits, allocation and
partial thread-creation failures, cross-pool quotas, and stop/drain/join. It does
not rely on sub-millisecond timing assertions. For example, with Clang:

```sh
mkdir -p _build/compression-sanitizers
clang -std=c11 -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer -pthread \
  -include src/compression/tests/worker_pool_faults.h \
  -Dmalloc=sc_test_malloc -Dcalloc=sc_test_calloc -Dpthread_create=sc_test_pthread_create \
  -c src/compression/worker_pool.c -o _build/compression-sanitizers/pool.o
clang -std=c11 -D_POSIX_C_SOURCE=200809L -g -O1 -fsanitize=address,undefined \
  -fno-omit-frame-pointer -pthread src/compression/tests/worker_pool_test.c \
  src/compression/compression_core.c src/compression/runtime.c \
  src/compression/*_parser.c src/compression/*_scanner.c \
  _build/compression-sanitizers/pool.o -o _build/compression-sanitizers/pool-test
_build/compression-sanitizers/pool-test
```

On macOS, ASan does not support LeakSanitizer: run with
`ASAN_OPTIONS=detect_leaks=0:halt_on_error=1` and check an unsanitized build with
`leaks --atExit -- <binary>` separately. Replace `address,undefined` by `thread`
for a separate TSan run. These focused C runs do not instrument MoonBit's managed
runtime/bridge and do not establish exhaustive thread safety. The new pool,
bridge and harness C sources are original project code under the project MIT
license; vendored grammar/runtime licenses remain unchanged.
