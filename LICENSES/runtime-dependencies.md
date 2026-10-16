# Native runtime dependencies

The distribution includes compiled code from these components, in addition to
the tokenizer and scanner sources documented in this directory.

| Component | Version / source | License |
| --- | --- | --- |
| MoonBit core | `0.10.15+943464bfa`, [moonbitlang/core](https://github.com/moonbitlang/core) | Apache-2.0 |
| MoonBit native runtime | Bundled with toolchain `0.10.15+943464bfa` | Apache-2.0 |
| moonbitlang/async | `0.19.2`, [moonbitlang/async](https://github.com/moonbitlang/async) | Apache-2.0 |
| moonbitlang/x | `0.5.5`, [moonbitlang/x](https://github.com/moonbitlang/x); path handling and SHA-256 | Apache-2.0 |
| simdutf | UTF conversion code bundled by the MoonBit toolchain, [simdutf](https://github.com/simdutf/simdutf) | MIT option of its dual license |

MoonBit components: Copyright 2025–2026 International Digital Economy Academy.
The Apache-2.0 text is retained in `MoonBit-Apache-2.0.txt`; compiled dependencies
are used without local source modifications. The simdutf notice is retained in
`simdutf-MIT.txt`, copied from the upstream `LICENSE-MIT`.

`install.mbtx` and `package.mbtx` copy this directory alongside the distribution.
