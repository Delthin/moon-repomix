# 原生运行依赖

分发包包含下列组件的编译代码。分词与扫描来源另见本目录的对应说明。

| 组件 | 版本与来源 | 许可 |
| --- | --- | --- |
| MoonBit core | `0.10.17+d971670cd`，[moonbitlang/core](https://github.com/moonbitlang/core) | Apache-2.0 |
| MoonBit native runtime | 随工具链 `0.10.17+d971670cd` 提供 | Apache-2.0 |
| moonbitlang/async | `0.19.2`，[源码](https://github.com/moonbitlang/async) | Apache-2.0 |
| moonbitlang/x | `0.5.5`，[源码](https://github.com/moonbitlang/x)；用于路径处理与 SHA-256 | Apache-2.0 |
| Tree-sitter runtime | `0.25.3` | MIT，`tree-sitter-runtime-MIT.txt` |
| Tree-sitter JavaScript | `0.23.1` | MIT，`tree-sitter-javascript-MIT.txt` |
| Tree-sitter TypeScript/TSX | `0.23.2` | MIT，`tree-sitter-typescript-MIT.txt` |
| Tree-sitter Python | `0.23.6` | MIT，`tree-sitter-python-MIT.txt` |
| ICU/Unicode subset | 由固定 Tree-sitter runtime 引入 | `tree-sitter-ICU.txt` |
| simdutf | MoonBit 工具链内的 UTF 转换代码，[源码](https://github.com/simdutf/simdutf) | 采用双重许可中的 MIT |

MoonBit components: Copyright 2025–2026 International Digital Economy Academy.

MoonBit 组件的 Apache-2.0 全文保留在 `MoonBit-Apache-2.0.txt`，这些编译依赖未经本地源码修改。simdutf 告知保留在 `simdutf-MIT.txt`，来自上游 `LICENSE-MIT`。

Tree-sitter 的固定提交、Unicode 来源及 endian 告知见 [解析器来源](tree-sitter-sources.md)。

`install.mbtx` 与 `package.mbtx` 将本目录随产品分发。
