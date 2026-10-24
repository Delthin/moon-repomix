# 工具链与本地构建

运行已发行归档只需解压并保留 `bin/`、`share/`、`LICENSES/` 布局；无需 MoonBit。以下面向从源码构建和维护的使用者。

## 固定版本

[moon-toolchain](../moon-toolchain) 和 [CI](../.github/workflows/ci.yml) 固定 MoonBit **0.10.15+943464bfa**；版本检查核对 `moonc` 版本和提交前缀。使用 MoonBit 官方工具链安装方式选择该版本，然后在仓库根目录运行：

```sh
moon version --all
moon run --target native scripts/check-toolchain.mbtx
moon update
```

构建 native 需要平台 C 工具链，macOS 可用 Command Line Tools，Linux 需要 C 编译环境，Windows 按 MoonBit native 要求配置 C 工具链。核心 CLI、分词和 vendored 解析器不需要 Node.js，也不需要 Go、Rust 或 Java 编译器。差异、历史和远程输入需要系统 Git。首次获取依赖需要网络，安装后的普通本地打包离线运行。

模块依赖以 [moon.mod](../moon.mod) 为准：`moonbitlang/async@0.19.2`、`123123213weqw/moon_scrub@0.5.2`、`moonbitlang/x@0.5.5`。独立 `.mbtx` 声明自己的依赖，例如工具链检查使用不同的 async 版本；这些版本分别固定。

## 构建、运行与安装

```sh
moon build src/cmd/moon-repomix --target native --release
moon run src/cmd/moon-repomix --target native --release -- --help
moon run src/cmd/moon-repomix --target native --release -- examples/demo --stdout --tokenizer-path assets/tokenizer-o200k_base.tiktoken
```

直接运行构建产物时，显式传入 `--tokenizer-path`，或使用安装脚本布局资源：

```sh
moon run --target native scripts/install.mbtx "$HOME/.local"
```

PowerShell 使用 `moon run --target native scripts/install.mbtx "$env:LOCALAPPDATA\moon-repomix"`。将该前缀的 `bin` 加入 `PATH`。安装布局为 `bin/moon-repomix`（Windows 为 `.exe`）、`share/moon-repomix/o200k_base.tiktoken`、同目录 Unicode 数据和 `LICENSES/`。加载时校验词表及 Unicode 数据散列，缺失或修改会返回 `ResourceError`。

源码当前接口与已发行版本的区别见 [README](../README.md#选择版本)。本地安装源码不代表发布新版本。

## 平台与分发验证

CI 在 macOS arm64、Linux x64、Windows x64 上验证固定工具链、native 构建、定点功能及归档。macOS x64 虽有打包选项，不等于已有同等运行证据。归档与源码包入口分别为 `scripts/package.mbtx` 和 `scripts/source-package-test.mbtx`；运行前核对脚本用法、输出位置和平台。

按改动选择最小检查见 [贡献指南](../CONTRIBUTING.md)。性能检查需要独立准备参考环境，不是日常文档或局部逻辑改动的前置步骤，方法见 [性能测量](performance.md)。
