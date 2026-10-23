# Vendored sources and ownership

Pinned runtime/grammar C sources, headers and full licenses are committed in
`vendor/`. MoonBit additionally includes its patched grammar and generation
metadata. No checkout, generator, Node, parser installation or network access is
needed to build or run the package.

| Local directory | Upstream repository | Tag | Full commit | License |
| --- | --- | --- | --- | --- |
| `vendor/runtime/` | https://github.com/tree-sitter/tree-sitter | `v0.25.3` | `2a835ee029dca1c325e6f1c01dbce40396f6123e` | MIT, `vendor/runtime/LICENSE` |
| `vendor/javascript/` | https://github.com/tree-sitter/tree-sitter-javascript | `v0.23.1` | `3a837b6f3658ca3618f2022f8707e29739c91364` | MIT, `vendor/javascript/LICENSE` |
| `vendor/python/` | https://github.com/tree-sitter/tree-sitter-python | `v0.23.6` | `bffb65a8cfe4e46290331dfef0dbf0ef3679de11` | MIT, `vendor/python/LICENSE` |
| `vendor/typescript/` | https://github.com/tree-sitter/tree-sitter-typescript | `v0.23.2` | `f975a621f4e7f532fe322e13c4f79495e0a7b2e7` | MIT, `vendor/typescript/LICENSE` |
| `vendor/moonbit/` | https://github.com/moonbitlang/tree-sitter-moonbit | untagged (2026-07-22), locally patched | `5435c307c6cf2ef0d508a99047b06f35a4308444` | Apache-2.0, `vendor/moonbit/LICENSE` |
| `vendor/go/` | https://github.com/tree-sitter/tree-sitter-go | `v0.23.4` | `3c3775faa968158a8b4ac190a7fda867fd5fb748` | MIT, `vendor/go/LICENSE` |
| `vendor/rust/` | https://github.com/tree-sitter/tree-sitter-rust | `v0.23.2` | `cad8a206f2e4194676b9699f26f6560d07130d3f` | MIT, `vendor/rust/LICENSE` |

The runtime's ICU subset (`vendor/runtime/lib/src/unicode/`) originates from
https://github.com/unicode-org/icu at
`552b01f61127d30d6589aa4bf99468224979b661`, pinned by the upstream `ICU_SHA` file
included alongside its full Unicode/ICU `LICENSE`. This includes `utf8.h`,
`utf16.h`, `umachine.h` and Tree-sitter's placeholder include headers.

`vendor/runtime/lib/src/portable/endian.h` additionally retains its upstream
public-domain notice, including its BSD/MIT/Apache fallback licensing statement.
Original copyright and license notices are retained verbatim.

## Copy layout and local adapters

- Runtime: `lib/src/**`, `lib/include/**`, full license and ICU notices.
  `lib/include/tree_sitter/**` is also copied to `lib/src/tree_sitter/**`, allowing
  quoted API includes to resolve without compiler-specific `-I` configuration.
- JavaScript and Python: `src/**` C/H files and full licenses.
- Go and Rust: `src/**` C/H files and full licenses. Both upstream parsers use
  ABI 14, compatible with the unchanged runtime's ABI 13–15 range. Go has no
  external scanner; Rust includes its original `src/scanner.c`. No regeneration,
  patching, upstream lifecycle script or additional runtime is needed. Flat
  `LICENSES/tree-sitter-go-MIT.txt` and `LICENSES/tree-sitter-rust-MIT.txt` copies
  retain their full respective licenses and are included by the existing package
  and install scripts.
- TypeScript/TSX: `typescript/src/**`, `tsx/src/**`, `common/**` and full license.
  `typescript/src/tree_sitter/**` is also copied to `common/tree_sitter/**` for
  the shared scanner header's quoted includes.
- MoonBit: root `src/**` C/H files, full license, `grammar.js`, `grammar.patch`
  and original `tree-sitter.json`. The root grammar serves both `.mbt` and
  `.mbti`; upstream's `grammars/quotation` and `grammars/mbtp` are not built or
  shipped.

Except for the explicitly patched/regenerated MoonBit grammar/parser below,
vendored source text and duplicate headers remain byte-identical to their pinned
originals. Upstream trailing whitespace is preserved in `lexer.c:207` and
`unicode/utf16.h:22,30`.

The package's `runtime.c`, `*_parser.c`, and `*_scanner.c` files are local thin
translation-unit wrappers, keeping parsers/scanners separate to avoid static
symbol collisions. `compression_core.[ch]` owns/frees Tree-sitter objects and
selection memory; `ffi.c` copies the selection to a managed MoonBit byte array,
then frees the mask. `compress.mbt` owns source encoding, assembly, line ranges,
and fallback policy. These adapters are project code.

`moonbit_scanner.c` includes `<wctype.h>` and scopes an `iswblank` macro around
the original scanner include, additionally accepting CR for automatic semicolon
insertion with CRLF. The macro is undefined immediately afterwards. No input
normalization or runtime upgrade is performed. The original scanner and all
three headers are unmodified. MoonBit's generated `LANGUAGE_VERSION` is 15,
within runtime v0.25.3's supported ABI range 13–15.

## MoonBit grammar patch and regeneration

`vendor/moonbit/grammar.patch` is the exact zero-context unified diff from the fixed upstream
`grammar.js` to the shipped `grammar.js`. Its local changes are:

- Tuple identifier binders in `for_in_expression`, retaining the original
  comma-separated binders.
- `..<=` alongside existing range operators in `range_pattern` and
  `lexmatch_range_pattern` (range expressions already supported it).
- `errdefer_expression` alongside `defer_expression` in statement expressions.

The modified grammar and generated parser carry prominent local-change notices.
Parser tables are generated, not hand-edited. Generation uses **Tree-sitter CLI
0.25.10**, commit `da6fe9beb4f7f67beb75914ca8e0d48ae48d6406`, with **ABI 15**.
The development-only official release asset is
https://github.com/tree-sitter/tree-sitter/releases/download/v0.25.10/tree-sitter-macos-arm64.gz
(SHA-256 `a6295d469669f6e901b6029ae6c129bd094df582d278c237fada413505cb9c42`;
uncompressed binary SHA-256
`374f6f9733a3f3e2dff72fcc1640b35c7d75ab60f531c8dc5865af3a12a28411`).
Neither this tool nor a JavaScript runtime is a user build/runtime dependency.

To regenerate, place the shipped `grammar.js` and `tree-sitter.json` together in
an isolated directory and run the verified CLI there:

```
tree-sitter generate --abi 15 grammar.js
```

The original metadata is required: without `tree-sitter.json`, this CLI warns
and downgrades to ABI 14 even with `--abi 15`. Only the root grammar is generated;
no upstream lifecycle or build script is needed. Retain only the emitted
`src/parser.c`, prepending this exact Apache local-change notice:

```c
/* Locally regenerated from MoonBit grammar 5435c307 with tuple-for, ..<=
 * range-pattern and errdefer patches, using tree-sitter 0.25.10 (ABI 15).
 * See src/compression/THIRD_PARTY.md and vendor/moonbit/grammar.patch.
 * Original grammar/source license: Apache-2.0, see ../LICENSE. */
```

Keep the pinned original scanner/headers, rather than replacing them with CLI
outputs. Refresh the `moonbit_parser.c` native-stub dependency or clear native
build outputs after changing included C sources, so incremental builds do not
reuse an older parser. Recheck hashes, package tests and native memory handling.

Original upstream SHA-256 hashes:

| File | SHA-256 |
| --- | --- |
| `grammar.js` | `ccf346ad0bd35dc46340c65750b2e8c44d3b75217dbe4e0f5ada67f904803b3f` |
| `src/parser.c` | `4786ee6b1bbc825eac64cfa05cb42ec5a31311304ded7da6df6aec8c045f28e5` |

Shipped MoonBit resource SHA-256 hashes (relative to `vendor/moonbit/`):

| File | SHA-256 |
| --- | --- |
| `LICENSE` | `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4` |
| `grammar.js` (patched) | `0fe13aa39b633bd49b649e0479f0e99ece814d5daf349f6536c9bae964e15300` |
| `grammar.patch` | `84e657f90ddc94ca6c805858ed3d190103b5f5d26e3faa6526281d71e697dc4d` |
| `tree-sitter.json` (unchanged) | `ec4fb39f511de1714bb7aff59d9b3162df1165eccfd46660844a7e07a04abcd6` |
| `src/parser.c` (regenerated, including local-change notice) | `14b917661aeace3e4cfb0ee69f0f5f94fd5a284eac76676490dba62a843915f8` |
| `src/scanner.c` | `4b6f1eff38807f71902993ac35fb926712cb9e8faf85a817362c5f45c36889c4` |
| `src/tree_sitter/parser.h` | `180b893c8734778fd32f372dfbc27bd6ad1cd2221f26150b31256ff6716320d2` |
| `src/tree_sitter/array.h` | `31e60a1bff6f715afacce03b5b70efe42b58371b4f9595dd4af52a577ff9608c` |
| `src/tree_sitter/alloc.h` | `b29c1c9fb7cc82f58c84b376df1297d6e2737a1d655fd356db0859e3c29c2fea` |

The raw regenerated `src/parser.c`, before the notice is prepended, has SHA-256
`f596c6715144f40045fcaf50044b34aafee76c82b446aab353ea522832cf15d5`.
Scanner, headers, metadata, license and the distribution license copy in
`LICENSES/tree-sitter-moonbit-Apache-2.0.txt` are byte-identical to the fixed
upstream archive. There is no upstream `NOTICE` file. Distributions must carry
full licenses and attribution, not only URLs or SPDX identifiers, together with
the C source/header resources and MoonBit grammar/patch provenance.

## Go/Rust resource manifest

All Go/Rust entries below are byte-identical to their pinned upstream archives.
Paths are relative to `vendor/`. The two `src/tree_sitter/` header sets have
identical contents; they are kept in each grammar's original include location.
Neither upstream archive has a `NOTICE` file. The flat distribution license
copies have the same SHA-256 as the corresponding `LICENSE` below.

| File | SHA-256 |
| --- | --- |
| `go/LICENSE` | `2e0110e07abef7c2548b26ec9d6969775617ca539a0dc8dbeeb14d6452c711d1` |
| `go/src/parser.c` | `3e412fb341a5ccb20455b34a8e3c1068cc064bd044146255fd47442458f5d575` |
| `rust/LICENSE` | `31d5b6f4243d5c7c6e1c4ebbbb9f6407bd1457a08bcc4f706521710341acba36` |
| `rust/src/parser.c` | `bd34b47f9cce5b4f85153e1180bdb4aa3d2b12fd0c33bb22bcbd9ffc1c3f80d5` |
| `rust/src/scanner.c` | `77faa4943da96dcb17d9c2a735bdbf7702287b52a1d2971117b167e47e318620` |
| `{go,rust}/src/tree_sitter/parser.h` | `a1f6ef161fbaf48a0e10fca90ef5290a062462b307b3898aa562993853b9f80a` |
| `{go,rust}/src/tree_sitter/array.h` | `4ff743903dc46f5db6aa54f31c6b4d160a8a9779e5b2ab1ee59ae7ebcd850ea1` |
| `{go,rust}/src/tree_sitter/alloc.h` | `b29c1c9fb7cc82f58c84b376df1297d6e2737a1d655fd356db0859e3c29c2fea` |

## Resource size

Uncompressed vendored sources/provenance/licenses (including duplicate headers):

| Directory | Files | Bytes |
| --- | ---: | ---: |
| Runtime (including ICU notices) | 48 | 806,417 |
| JavaScript | 6 | 2,517,419 |
| Python | 6 | 3,464,497 |
| TypeScript + TSX | 15 | 17,583,384 |
| MoonBit | 9 | 6,200,870 |
| Go | 5 | 1,557,034 |
| Rust | 6 | 6,212,241 |
| **Total** | **95** | **38,341,862** |

Approximately 36.57 MiB; generated parser tables dominate. Upstream tests,
package-manager files, generator binaries and repository history are not shipped.
Updating a dependency requires repinning its commit, copying resources/licenses
and both applicable header locations, preserving or reviewing local patches, and
rerunning genuine parse/compression tests and native memory validation.
