# moon-repomix

把本地目录或公开远程仓库整理成一份 XML、Markdown、JSON 或纯文本，供 AI 阅读、代码评审和问题追踪。支持语法树结构压缩、Git 差异与提交历史。使用 MoonBit native 实现，提供 CLI 和库 API；代码处理在本地完成，解析器与分词资源随源码或安装包提供，运行时不需要 Node.js。

## 核心功能

- **代码结构压缩**：`--compress` 支持 MoonBit 源码与接口（`.mbt/.mbti`）、JavaScript/TypeScript（含 JSX/TSX）和 Python，保留声明、类型、注释与嵌套结构，省略实现细节；其他语言保留原文。
- **远程与 Git 上下文**：获取公开 HTTPS 仓库的指定版本，或把本地源码、暂存/未暂存差异和近期提交组合成评审材料。
- **四格式导出**：XML、Markdown、JSON 和纯文本均含目录结构，默认展示轻量概览；`--full-metadata` 提供逐文件记录与原始行区间。
- **筛选与密钥扫描**：组合忽略规则和 glob；源码版还支持 stdin 精确文件列表、NUL 协议和花括号备选。先扫描原始内容，再压缩，命中的文件、补丁或提交整体排除。
- **计数与预算**：精确计算完整输出的 `o200k_base` token 数，提供文件排名、目录统计与预算检查；同一处理流程也可通过库 API 复用。

当前源码在 Apple M4/macOS 的六组固定同输入基准中，端到端耗时比 Repomix 1.18.1 减少约 31%–76%，进程峰值 RSS 也更低。测试方法、输入版本及平台范围见 [性能测量](docs/performance.md)。MoonBit 项目自身的完整 JSON 上下文从 87,133 降至 19,389 tokens，保留完整声明与原行映射。

## 最快上手

源码构建需要 MoonBit **0.10.15+943464bfa**（见 [`moon-toolchain`](moon-toolchain)）和平台 C 工具链。在仓库根目录先更新依赖，再运行：

```sh
moon update
moon run src/cmd/moon-repomix --target native --release -- examples/demo --style markdown --stdout --tokenizer-path assets/tokenizer-o200k_base.tiktoken
```

终端会显示包含 MoonBit、TypeScript 源码和目录结构的 Markdown；`debug.log` 和 `src/scratch.txt` 被忽略。文档写到标准输出，统计和跳过原因写到标准错误。

想一起看看密钥排除和预算超限的行为，运行这个三步演示：

```sh
moon run --target native scripts/demo.mbtx
```

它会自动构建 CLI，将输入副本、XML、Markdown 和诊断日志保留在新建的 `dist/demo/`；目录已存在就报错，不覆盖。也可传入另一个尚不存在的输出目录。步骤和观察点见 [演示指南](docs/demo.md)。

## 源码版的文件列表与兼容行为

当前主线在 v0.2.0 之后增加了 MoonBit 结构压缩、文件列表及筛选兼容能力，并优化精确分词与任务调度；安装版用法见 [v0.2.0 文档](https://github.com/Delthin/moon-repomix/tree/v0.2.0)。下列命令用于从当前源码构建并安装的 CLI：

```sh
# 只处理 Git 列出的文件，NUL 协议保留文件名中的空格和换行
git ls-files -z | moon-repomix . --stdin0 --style markdown -o -
# 多种后缀；引号让 CLI 而非 shell 展开备选
moon-repomix ./project --include 'src/**/*.{mbt,ts,py}' -o -
```

`--stdin` 每行一个相对路径，`--stdin0` 使用 NUL 分隔；空输入选零文件，重复项去重，列表仍受 ignore、原始内容扫描和 Git 路径筛选约束。`-o -`、`--output=-` 和配置中的 `output.filePath: "-"` 均输出到 stdout；`-o ./-` 写入普通文件。`--no-dot-ignore` 仅关闭 `.ignore`，`.repomixignore` 始终生效。详细规则见 [配置文档](docs/configuration.md)。

## 安装

### 使用平台归档

从 [v0.2.0 Release](https://github.com/Delthin/moon-repomix/releases/tag/v0.2.0) 下载对应平台归档，并用附带的 `SHA256SUMS` 校验。解压后保留 `bin`、`share` 和 `LICENSES` 目录。在解压目录中直接运行：

```sh
./bin/moon-repomix /path/to/project -o context.xml
```

Windows PowerShell：

```powershell
.\bin\moon-repomix.exe "C:\path\to\project" -o context.xml
```

运行归档中的程序不需要安装 MoonBit；也可将 `bin` 加入 `PATH`。差异、历史和远程获取需要系统 Git，普通本地打包与结构压缩可直接运行。

### 从源码安装

在完成 `moon update` 后，把程序与分词资源一起安装到指定前缀：

```sh
moon run --target native scripts/install.mbtx "$HOME/.local"
```

Windows PowerShell：

```powershell
moon run --target native scripts/install.mbtx "$env:LOCALAPPDATA\moon-repomix"
```

将前缀下的 `bin` 加入 `PATH`。安装版从程序所在位置寻找 `../share/moon-repomix/`，不依赖当前工作目录。移动安装目录时，请一起保留 `bin`、`share` 及其相对位置；仅复制可执行文件不构成完整安装。

通过 `moon run` 执行 CLI 时须显式指定词表。[三平台 CI](https://github.com/Delthin/moon-repomix/actions/workflows/ci.yml) 覆盖 macOS arm64、Linux x64 和 Windows x64 的检查、构建、功能测试、安装及归档。各平台构建须使用相应的 native C 工具链。

## CLI 用法

```sh
moon-repomix ./project
moon-repomix ./project --style markdown -o context.md
moon-repomix ./project --style json -o context.json
moon-repomix ./project --style plain --stdout
moon-repomix ./project --compress --style json -o structure.json
moon-repomix ./project --include-diffs --include-logs --include-logs-count 20 -o review.xml
moon-repomix --remote https://github.com/octocat/Hello-World.git --remote-branch master --include-logs --style markdown -o remote.md
moon-repomix ./project --include 'src/**,README.md' --ignore '**/*_test.mbt'
moon-repomix ./project --stdout > context.xml
moon-repomix ./project --token-budget 100000
moon-repomix ./project --token-count-tree 100 --top-files-len 10
moon-repomix ./project --init
```

四种格式的默认输出分别为 `repomix-output.xml`、`repomix-output.md`、`repomix-output.json`、`repomix-output.txt`，默认格式为 XML。JSON 的 `files` 是相对路径到输出正文的对象映射；默认保留完整正文，`--compress` 显式选择语法骨架。plain 使用章节和文件分隔线，适合直接阅读或粘贴。`-o` 会替换已有同名输出，使用时请选好路径。相对输出路径和显式配置路径以当前工作目录为准；自动发现的 `repomix.config.json` 位于所选目录内。`--init` 创建配置，不覆盖已有配置。全部选项见 `--help` 和 [配置文档](docs/configuration.md)。

本仓库的 `repomix.config.json` 默认忽略 `assets/**` 和压缩包内的第三方解析器源码，让自打包文档聚焦项目代码、脚本和说明。需要打包这些资源时，使用 `--config` 指向内容为 `{}` 的配置文件，再用 `--include` 选择目标文件。

## 打包行为

- 读取 `.gitignore`、`.ignore`、`.repomixignore`（含嵌套规则），支持 include/ignore glob；按相对路径稳定排序。include 不会绕过忽略规则。
- 打包有效 UTF-8 普通文件；去掉 UTF-8 BOM，保留原始换行。默认单文件上限为 **50 MiB**；链接、二进制、不可读或超限文件跳过。
- `--compress` 支持 MoonBit（含 `.mbti`）、JavaScript/TypeScript（含 JSX/TSX）和 Python，在原始快照扫描通过后提取语法骨架；其他语言或压缩无收益时保留原文。四种格式默认只带来源和压缩概览，`--full-metadata` 展示逐文件状态与原始行区间；库模型始终保留完整记录。正文排名统计实际输出正文，同时记录原始正文计数。
- `--include-diffs`、`--include-logs` 导出经过路径筛选的 Git 章节；提交消息和包含删除行的补丁也扫描，命中时排除对应整个补丁或提交。远程输入支持公开 HTTPS 仓库的默认分支及指定 branch/tag/full commit，获取后复用同一处理流程，并清理临时目录。
- 默认扫描密钥，排除命中的**整个文件**。诊断给出规则、路径、行号和磁盘字节区间，不打印匹配值。
- 用完整 `o200k_base` 词表计算最终文档的 token 数，默认显示正文 token 数最多的 5 个文件。`--top-files-len` 调整排名数量，`--token-count-tree [N]` 显示带阈值的文件/目录统计；目录值为文件正文计数之和。超预算不截断：仍输出完整文档，CLI 返回 **1**；正常完成且未超预算返回 **0**。配置、资源、扫描或写入错误也返回 **1**，需结合诊断区分。
- 文件输出先写同目录临时文件，再原子替换；打包失败时保留已有输出。`--stdout` 将文档写到标准输出，统计和诊断写到标准错误。

压缩、Git 与远程仓库的范围、回退和调用约束见 [仓库上下文](docs/context.md)。更多细节：[文件选择](docs/file-selection.md) · [输出格式](docs/output.md) · [扫描规则](docs/security.md) · [分词](docs/tokenization.md)。

## 安全与使用边界

密钥扫描是启发式检测，不能保证发现所有凭证；分享前仍应检查最终文档。`--no-security-check` 会关闭扫描并显示警告。忽略规则控制文件选择，不是安全隔离；不要在打包时允许不可信进程并发修改输入目录。

打包和计数在内存中完成，内存占用随输入和输出大小增长。token 预算用于告警，不是内存限制，也不自动挑选或裁剪文件。

## 库 API

Mooncakes 模块为 [`Delthin/moon_repomix@0.2.0`](https://mooncakes.io/docs/Delthin/moon_repomix@0.2.0)，在调用项目的 `moon.mod` 依赖表声明该版本。本地联调可用 `moon.work` 将调用项目与本仓库列为 `members`。在 `moon.pkg` 导入：

```moonbit
import {
  "Delthin/moon_repomix" @repomix,
}
```

在 `async fn` 中先加载资源，再打包：

```moonbit
let options = @repomix.options(
  "/absolute/project", style=@repomix.Style::Json,
  compress=true, include_diffs=true, include_logs=true,
)
let runtime = @repomix.Runtime::load("/absolute/share/moon-repomix/o200k_base.tiktoken")
let result = @repomix.pack(options, runtime)
// result.text 是完整文档；result.tokens 是完整文档的 token 数。
// result.document.sections / metadata 提供 Git 内容及来源、压缩记录。
// result.files / skipped / findings / security / budget 提供统计及状态。
```

`options` 默认使用 XML；可通过 `style` 选择 `Xml`、`Markdown`、`Json`、`Plain`，同时选择对应的默认文件名。`options` 还接受 `compress`、`full_metadata`、`include_diffs`、`include_logs`、`include_logs_count`、`remote : String?` 和 `remote_branch : String?`。当前源码另支持 `file_paths : Array[String]?`：`None` 表示遍历，`Some(paths)` 只选择列表中的文件，`Some([])` 为零文件；此参数尚不属于 v0.2.0 的库接口。远程调用使用目录 `"."`，例如 `options(".", remote=Some("https://github.com/octocat/Hello-World.git"))`。`pack` 返回结果，不写文件，并负责远程目录的获取与清理；由调用者决定如何处理输出和预算超限。词表同目录还须有 `tokenizer-unicode-16.0.0.txt`，两份资源均校验 SHA-256。一个 `Runtime` 可复用于多次顺序打包。接口见 [`src/pkg.generated.mbti`](src/pkg.generated.mbti)。

## 开发与打包

CI 通过官方安装脚本安装固定版本，再从 `moon-toolchain` 读取要求并核对实际编译器。升级时同步修改该文件与工作流中的 `MOONBIT_INSTALL_VERSION`，并重新运行黄金夹具和功能测试。

```sh
moon update
moon check --target native --deny-warn
moon test --target native
moon build --target native --release
moon run --target native scripts/package.mbtx dist macos-arm64
```

打包标签为 `macos-arm64`、`macos-x64`、`linux-x64`、`windows-x64`，在对应平台和架构上构建；macOS x64 尚无 CI 运行证据。归档包含程序、词表、Unicode 数据及许可证。

构建后可运行常见场景及真实 CLI 功能测试：

```sh
moon run --target native scripts/scenarios.mbtx _build/native/release/build/cmd/moon-repomix/moon-repomix.exe assets/tokenizer-o200k_base.tiktoken
moon run --target native scripts/functional.mbtx _build/native/release/build/cmd/moon-repomix/moon-repomix.exe assets/tokenizer-o200k_base.tiktoken
moon run --target native scripts/token-reports-test.mbtx _build/native/release/build/cmd/moon-repomix/moon-repomix.exe assets/tokenizer-o200k_base.tiktoken
moon run --target native scripts/output-formats-test.mbtx _build/native/release/build/cmd/moon-repomix/moon-repomix.exe assets/tokenizer-o200k_base.tiktoken
moon run --target native scripts/advanced-context-test.mbtx _build/native/release/build/cmd/moon-repomix/moon-repomix.exe assets/tokenizer-o200k_base.tiktoken
moon run --target native scripts/input-list-test.mbtx
moon run --target native scripts/self-pack-test.mbtx ../moon-repomix-self-check
```

格式功能测试覆盖四种格式的文件输出、stdout、预算边界和失败保留；安装了 `jq` 时可追加 `--json-oracle`，独立解析 JSON 并还原每个文件的正文。

自打包检查会新建输出目录，保留 XML、Markdown 和日志；已有目录会报错。安装了 `xmllint` 时可追加 `--xml-oracle`，独立核对黄金数据从 XML 还原后的正文。

测试覆盖编码和大小边界、配置合并、密钥排除、输出格式、预算、错误保护及路径处理；Linux CI 包含独立 XML/JSON 解析与正文还原检查，并验证 `moon package` 生成的源码包解压后能运行 demo。源码包位于 `_build/publish/Delthin-moon_repomix-0.2.0.zip`。

## 来源与许可

项目参考 [Repomix](https://github.com/yamadashy/repomix) 的仓库上下文生成行为，采用 [MIT](LICENSE) 许可。第三方代码及资源的许可保存在 [`LICENSES/`](LICENSES/)；分词实现、词表与 Unicode 数据的来源、版本及兼容范围见 [分词文档](docs/tokenization.md)，扫描依据见 [扫描规则](docs/security.md)。
