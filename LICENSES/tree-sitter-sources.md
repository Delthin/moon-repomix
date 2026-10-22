# Native parser sources

These components are compiled into the application. Original license files accompany this notice.

| Component | Version / pinned commit | License file |
| --- | --- | --- |
| [Tree-sitter](https://github.com/tree-sitter/tree-sitter) | `v0.25.3`, `2a835ee029dca1c325e6f1c01dbce40396f6123e` | `tree-sitter-runtime-MIT.txt` |
| [JavaScript grammar](https://github.com/tree-sitter/tree-sitter-javascript) | `v0.23.1`, `3a837b6f3658ca3618f2022f8707e29739c91364` | `tree-sitter-javascript-MIT.txt` |
| [TypeScript/TSX grammars](https://github.com/tree-sitter/tree-sitter-typescript) | `v0.23.2`, `f975a621f4e7f532fe322e13c4f79495e0a7b2e7` | `tree-sitter-typescript-MIT.txt` |
| [Python grammar](https://github.com/tree-sitter/tree-sitter-python) | `v0.23.6`, `bffb65a8cfe4e46290331dfef0dbf0ef3679de11` | `tree-sitter-python-MIT.txt` |
| [MoonBit grammar (.mbt/.mbti)](https://github.com/moonbitlang/tree-sitter-moonbit) | `5435c307c6cf2ef0d508a99047b06f35a4308444` (2026-07-22), locally patched, ABI 15 | `tree-sitter-moonbit-Apache-2.0.txt` |
| [ICU/Unicode subset](https://github.com/unicode-org/icu) | `552b01f61127d30d6589aa4bf99468224979b661` | `tree-sitter-ICU.txt` |

MoonBit's root grammar serves both file extensions. Its local `grammar.patch`
adds tuple `for` identifier binders, inclusive `..<=` range patterns and `errdefer`;
the parser is regenerated with Tree-sitter CLI 0.25.10, ABI 15. Modified grammar
and parser files carry local-change notices. The patched grammar, exact patch,
original generation metadata, generated C, original scanner, all three original
headers and full Apache-2.0 license ship in `src/compression/vendor/moonbit/`.
The CRLF wrapper treats CR as blank during automatic semicolon insertion without
changing scanner bytes. Original pins/hashes, generator provenance and shipped
hashes are documented in `src/compression/THIRD_PARTY.md`; the parser is not
byte-identical to upstream. Include this notice and the full license in binary
distributions as well as the source resources/provenance in source distributions.

The runtime's `portable/endian.h` retains this original notice:

```text
// "License": Public Domain
// I, Mathias Panzenböck, place this file hereby into the public domain. Use it at your own risk for whatever you like.
// In case there are jurisdictions that don't support putting things in the public domain you can also consider it to
// be "dual licensed" under the BSD, MIT and Apache licenses, if you want to. This code is trivial anyway. Consider it
// an example on how to get the endian conversion functions on different platforms.
```
