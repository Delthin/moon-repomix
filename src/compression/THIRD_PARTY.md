# Vendored sources and ownership

All upstream resources are pinned, committed C sources/headers and license files.
No checkout, generator, Node, Python, parser installation or network access is
needed to build the package. These are build resources, not research artifacts.

| Local directory | Upstream repository | Tag | Full commit | License |
| --- | --- | --- | --- | --- |
| `vendor/runtime/` | https://github.com/tree-sitter/tree-sitter | `v0.25.3` | `2a835ee029dca1c325e6f1c01dbce40396f6123e` | MIT, `vendor/runtime/LICENSE` |
| `vendor/javascript/` | https://github.com/tree-sitter/tree-sitter-javascript | `v0.23.1` | `3a837b6f3658ca3618f2022f8707e29739c91364` | MIT, `vendor/javascript/LICENSE` |
| `vendor/python/` | https://github.com/tree-sitter/tree-sitter-python | `v0.23.6` | `bffb65a8cfe4e46290331dfef0dbf0ef3679de11` | MIT, `vendor/python/LICENSE` |
| `vendor/typescript/` | https://github.com/tree-sitter/tree-sitter-typescript | `v0.23.2` | `f975a621f4e7f532fe322e13c4f79495e0a7b2e7` | MIT, `vendor/typescript/LICENSE` |

The runtime's ICU subset (`vendor/runtime/lib/src/unicode/`) originates from
https://github.com/unicode-org/icu at
`552b01f61127d30d6589aa4bf99468224979b661`, pinned by the upstream `ICU_SHA` file
included alongside its full Unicode/ICU `LICENSE`. This includes `utf8.h`,
`utf16.h`, `umachine.h` and Tree-sitter's placeholder include headers.

`vendor/runtime/lib/src/portable/endian.h` additionally retains its upstream
public-domain notice, including its BSD/MIT/Apache fallback licensing statement.
Original copyright and license notices are retained verbatim.

## Copy layout and local changes

Only upstream `.c`/`.h` files, each repository's `LICENSE`, and the ICU subset's
`LICENSE` and `ICU_SHA` are included:

- Runtime: `lib/src/**` and `lib/include/**`. `lib/include/tree_sitter/**` is also
  copied to `lib/src/tree_sitter/**`, allowing the runtime's quoted API includes
  to resolve without compiler-specific `-I` configuration.
- JavaScript and Python: `src/**`.
- TypeScript/TSX: `typescript/src/**`, `tsx/src/**` and `common/**`.
  `typescript/src/tree_sitter/**` is also copied to `common/tree_sitter/**` so
  the shared scanner header can resolve its quoted includes.

**No vendored source text is modified.** The duplicate headers are byte-identical
to their pinned originals. A source audit compared every copied file against the
pinned checkouts, including both duplicate-header locations. Three upstream
trailing-whitespace lines are intentionally preserved (`lexer.c:207`,
`unicode/utf16.h:22,30`); package-authored files pass `git diff --check`.

The package's `runtime.c`, `*_parser.c`, and `*_scanner.c` files are local thin
translation-unit wrappers, keeping generated parsers/scanners separate to avoid
static symbol collisions. `compression_core.[ch]` implements AST selection and
owns/frees Tree-sitter objects and selection memory; `ffi.c` copies the selection
to a managed MoonBit byte array, then frees the mask. `compress.mbt` owns source
encoding, output assembly, line ranges, and fallback policy. These local adapters
are project code, not upstream patches.

The package uses a small native C boundary directly. Grammar resources are
compiled with the application rather than installed or generated at runtime.

## Resource size

Uncompressed vendored source/header/license sizes (including duplicate headers):

| Directory | Files | Bytes |
| --- | ---: | ---: |
| Runtime (including ICU notices) | 48 | 806,417 |
| JavaScript | 6 | 2,517,419 |
| Python | 6 | 3,464,497 |
| TypeScript + TSX | 15 | 17,583,384 |
| **Total** | **75** | **24,371,717** |

Approximately 23.24 MiB; generated TS/TSX parser tables dominate. Upstream tests,
package-manager metadata, grammar generators and repository history are not
shipped. Updating a dependency requires repinning its commit, copying its
resources/licenses and both applicable header locations, and rerunning the
package's genuine parse/compression tests and native memory validation.
