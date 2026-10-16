# moon-repomix

将本地代码目录打包为一个 XML 或 Markdown 文档，供 AI 阅读。使用 MoonBit native 实现，提供命令行和可复用的库 API。

文件选择支持 `.gitignore`、`.ignore`、`.repomixignore` 和自定义 glob；按相对路径稳定排序。默认扫描密钥并排除命中的整个文件，使用完整 `o200k_base` 词表计算最终文档的 token 数。输出采用同目录临时文件加原子替换，打包失败时保留已有文件。

## 安装

源码构建需要 MoonBit **0.10.15+943464bfa** 和平台 C 工具链。项目目标是 macOS、Linux 和 Windows；CI 对三个平台运行 native 检查及功能测试。官方安装 action 使用 `latest` 通道，随后由版本检查阻止未经验证的编译器升级。

在仓库根目录运行以下命令，将程序和分词资源一起安装到指定前缀：

```sh
moon run --target native scripts/install.mbtx "$HOME/.local"
```

Windows PowerShell：

```powershell
moon run --target native scripts/install.mbtx "$env:LOCALAPPDATA\moon-repomix"
```

将前缀下的 `bin` 加入 `PATH`。安装后的程序从自身所在位置寻找 `../share/moon-repomix/`，因此可以在任意工作目录运行。移动安装目录时，保留 `bin` 与 `share` 的相对位置。

也可直接构建运行；开发目录内需显式指定词表：

```sh
moon build --target native --release
moon run src/cmd/moon-repomix --target native --release -- . --tokenizer-path assets/tokenizer-o200k_base.tiktoken
```

## 使用

```sh
moon-repomix ./project
moon-repomix ./project --style markdown -o context.md
moon-repomix ./project --include 'src/**,README.md' --ignore '**/*_test.mbt'
moon-repomix ./project --stdout > context.xml
moon-repomix ./project --token-budget 100000
moon-repomix ./project --init
```

默认输出 `repomix-output.xml`；Markdown 默认输出 `repomix-output.md`。相对输出路径与显式配置路径相对于当前工作目录，自动发现的 `repomix.config.json` 位于所选目录内。`--help` 列出全部选项。

- 文件必须是有效 UTF-8 普通文件。读取时去掉 UTF-8 BOM，保留原始换行；默认最大文件大小为 **50 MiB**。链接、二进制、不可读文件与超限文件会跳过。
- 默认进行密钥扫描。诊断只列规则、路径、行号和磁盘字节区间。`--no-security-check` 关闭扫描并始终显示警告；扫描不等于安全保证，请在分享前检查输出。
- token 预算比较的是完整输出。超限仍写出完整文档，退出码为 **1**；成功且未超限为 **0**。配置、资源、扫描和写入错误也返回 **1**。
- `--stdout` 只把文档写到标准输出，统计和诊断写到标准错误。`--quiet` 隐藏日常统计，保留预算超限、关闭扫描和空结果警告。

配置及细节见：[配置与 CLI](docs/configuration.md) · [文件选择](docs/file-selection.md) · [输出格式](docs/output.md) · [扫描规则](docs/security.md) · [分词与来源](docs/tokenization.md)。

## 库 API

导入 `delthin/moon_repomix`，先加载资源，再打包。`pack` 返回文档与统计，由调用者决定写入位置：

```moonbit
let options = @repomix.options("/absolute/project")
let runtime = @repomix.Runtime::load("/absolute/share/moon-repomix/o200k_base.tiktoken")
let result = @repomix.pack(options, runtime)
// result.text / tokens / bytes / files / skipped / findings / security / budget
```

上述代码位于 `async fn` 中。词表同目录还需有 `tokenizer-unicode-16.0.0.txt`；两份资源都校验 SHA-256。一个 `Runtime` 可以复用于多次顺序打包。接口定义见 [`src/pkg.generated.mbti`](src/pkg.generated.mbti)。

## 开发与打包

```sh
moon check --target native --deny-warn
moon test --target native
moon build --target native --release
moon run --target native scripts/functional.mbtx _build/native/release/build/cmd/moon-repomix/moon-repomix.exe assets/tokenizer-o200k_base.tiktoken
moon run --target native scripts/distribution-test.mbtx macos-arm64
moon run --target native scripts/package.mbtx dist macos-arm64
```

功能测试覆盖真实 CLI、扫描、输出、预算、配置、链接和失败保留行为。安装测试从不同工作目录运行安装版、移动后的目录和解包后的归档。macOS/Linux 安装 `xmllint` 后可在功能测试命令末尾加入 `--xml-oracle`，独立解析并核对 XML 正文和路径。

打包平台标签为 `macos-arm64`、`macos-x64`、`linux-x64`、`windows-x64`，应在相应架构的机器上构建。归档包含程序、词表、Unicode 数据及许可证。运行时无需 Node.js，也不下载分词资源。全文构建和计数在内存中完成，内存占用随所选文件与输出大小增长。

## 来源与许可

项目参考 [Repomix](https://github.com/yamadashy/repomix) 的本地仓库打包行为，许可证为 [MIT](LICENSE)。上游及资源许可集中保存在 [`LICENSES/`](LICENSES/)。分词、扫描与文件选择的兼容范围和来源分别记录在对应文档中。
