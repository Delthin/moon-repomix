# 原生运行依赖

分发包包含下列组件的编译代码。分词与扫描来源另见本目录的对应说明。

| 组件 | 版本与来源 | 许可 |
| --- | --- | --- |
| MoonBit core | `0.10.15+943464bfa`，[moonbitlang/core](https://github.com/moonbitlang/core) | Apache-2.0 |
| MoonBit native runtime | 随工具链 `0.10.15+943464bfa` 提供 | Apache-2.0 |
| moonbitlang/async | `0.19.2`，[源码](https://github.com/moonbitlang/async) | Apache-2.0 |
| moonbitlang/x | `0.5.5`，[源码](https://github.com/moonbitlang/x)；用于路径处理与 SHA-256 | Apache-2.0 |
| simdutf | MoonBit 工具链内的 UTF 转换代码，[源码](https://github.com/simdutf/simdutf) | 采用双重许可中的 MIT |

MoonBit components: Copyright 2025–2026 International Digital Economy Academy.

MoonBit 组件的 Apache-2.0 全文保留在 `MoonBit-Apache-2.0.txt`，这些编译依赖未经本地源码修改。simdutf 告知保留在 `simdutf-MIT.txt`，来自上游 `LICENSE-MIT`。

`install.mbtx` 与 `package.mbtx` 将本目录随产品分发。
