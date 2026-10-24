# moon-repomix

把本地目录或公开 HTTPS 仓库整理成 XML、Markdown、JSON 或纯文本，供 AI 阅读、代码评审和问题追踪。当前源码支持七类语言的 AST 骨架、全文/骨架混合、Git 差异与历史、精确预算分卷和固定本地根的只读 MCP。使用 MoonBit native 实现，提供 CLI 与 SDK；解析器和分词资源随源码或安装包提供，运行时不需要 Node.js。

## 选择版本

| 版本 | 可用能力与获取方式 |
| --- | --- |
| 已发行 **v0.3.0** | 四格式、MoonBit/JavaScript/TypeScript/Python 骨架、Git 差异和历史、公开远程仓库、精确 `o200k_base` 计数、stdin 文件列表。使用 [Release](https://github.com/Delthin/moon-repomix/releases/tag/v0.3.0) 或 [Mooncakes 0.3.0](https://mooncakes.io/docs/Delthin/moon_repomix@0.3.0)，查阅 [固定版本文档](https://github.com/Delthin/moon-repomix/blob/v0.3.0/README.md)。 |
| **当前源码，尚未发行** | 新增混合全文/骨架、模板、展示控制、Go/Rust/Java 骨架、精确分卷、JSON stderr、输入总量限制、只读 MCP 和入选原因查询。需要从源码构建；见 [场景](docs/scenarios.md)、[0.3 → 0.4 接口迁移预览](docs/migration.md) 与 [Unreleased](CHANGELOG.md#unreleased)。 |

本分支的使用文档描述当前源码接口。版本号尚未调整时，源码构建的 `--version` 也可能显示 `0.3.0`；排查问题请同时记录构建 commit。

v0.3.0 在固定三仓库、六场景中已有 macOS 与 Linux 的 CLI 对照：macOS 耗时减少约 31%–76%，该轮 Linux 原版耗时约为本工具的 2.1–4.4 倍。测量版本、完整样本、内存和适用范围见 [性能测量](docs/performance.md)；新进程 CLI 与常驻 MCP 分别记录。

## 安装与第一次运行

从 [v0.3.0 Release](https://github.com/Delthin/moon-repomix/releases/tag/v0.3.0) 下载平台归档，用附带的 `SHA256SUMS` 校验。解压后保留 `bin`、`share` 和 `LICENSES` 的相对位置，在解压目录运行：

```sh
./bin/moon-repomix /path/to/project --style markdown -o context.md
```

Windows PowerShell：

```powershell
.\bin\moon-repomix.exe "C:\path\to\project" --style markdown -o context.md
```

也可将 `bin` 加入 `PATH`。归档运行不需要 MoonBit；普通本地打包和骨架压缩不需要 Git，差异、历史和远程获取需要系统 Git。

### 最快上手

运行当前源码需要固定的 MoonBit **0.10.15+943464bfa** 和平台 C 工具链，见 [工具链](docs/toolchain.md)。在仓库根目录运行：

```sh
moon update
moon run src/cmd/moon-repomix --target native --release -- examples/demo --style markdown --stdout --tokenizer-path assets/tokenizer-o200k_base.tiktoken
```

终端显示示例源码和目录结构；正文写 stdout，统计与诊断写 stderr。通过 `moon run` 执行 CLI 时显式传入词表。要将当前源码与资源一起安装到本地前缀：

```sh
moon run --target native scripts/install.mbtx "$HOME/.local"
```

Windows PowerShell 使用 `moon run --target native scripts/install.mbtx "$env:LOCALAPPDATA\moon-repomix"`。将前缀的 `bin` 加入 `PATH`；程序从 `../share/moon-repomix/` 寻找词表与 Unicode 数据，移动时一并保留。

## 常用操作

以下命令可用于 v0.3.0 和当前源码：

```sh
moon-repomix ./project --compress --style markdown -o structure.md
moon-repomix ./project --include-diffs --include-logs --include-logs-count 20 -o review.xml
moon-repomix ./project --include 'src/**/*.{mbt,ts,py}' --ignore '**/*_test.mbt' -o context.json --style json
git ls-files -z | moon-repomix . --stdin0 --style markdown -o -
moon-repomix ./project --token-budget 100000
moon-repomix ./project --token-count-tree 100 --top-files-len 10
moon-repomix --remote https://github.com/octocat/Hello-World.git --remote-branch master --style markdown -o remote.md
```

默认格式是 XML；四格式默认文件名为 `repomix-output.xml`、`.md`、`.json`、`.txt`。`-o -` 和 `--stdout` 将正文写 stdout；重定向时选输入根以外的路径，或显式忽略目标。`-o` 普通文件会原子替换已有同名文件，打包失败时保留旧输出；`--init` 创建配置且拒绝覆盖。

`--stdin` 每行一个相对路径，`--stdin0` 使用 NUL 分隔，适合 Git `-z`。列表是字面文件名，空输入选零文件，仍受 include、ignore 和安全检查约束。配置合并顺序为默认值 → JSON → 显式 CLI；配置和输出路径相对进程 cwd，自动配置位于输入根。详见 [配置](docs/configuration.md) 与 [文件选择](docs/file-selection.md)。

当前源码的三个完整用法见 [使用场景](docs/scenarios.md)：关键文件保留全文并加入评审模板、按精确预算分卷、通过 MCP 或 JSON 报告接入自动化。

## 输出、计数与安全

- 默认保留完整正文；`--compress` 提取语法骨架，保留声明、类型、注释与结构。当前源码支持 MoonBit（含 `.mbti`）、JavaScript/TypeScript（含 JSX/TSX）、Python、Go、Rust、Java；其他语言或无精确 token 收益时保留原文。范围见 [仓库上下文](docs/context.md)。
- 读取有效 UTF-8 普通文件，去除 UTF-8 BOM 并保留换行。默认单文件上限 50 MiB；当前源码另有 20,000 个过滤后普通候选、200 MiB 原始读取的总量限制。链接、二进制、无效 UTF-8 等跳过原因见 [错误指南](docs/errors.md)。
- 默认扫描压缩前原文，命中时排除整个文件、Git 补丁或提交；模板命中则停止整个打包。扫描是启发式检测，分享前仍应审阅结果，详见 [安全边界](SECURITY.md) 和 [检测规则](docs/security.md)。
- 对完整渲染字符串精确计算 `o200k_base` tokens，包含格式包装、模板与显示装饰。普通 `--token-budget` 超限仍输出全文，退出 **1**；正常完成退出 **0**。文件排名和目录统计不能代替最终预算。分卷的每卷硬上限与独立索引开销见 [分卷](docs/partition.md)。

打包与计数在内存中完成，token 预算不是内存配额。固定输入的测量方法、结果及平台范围见 [性能测量](docs/performance.md)。

## SDK

已发行模块为 [`Delthin/moon_repomix@0.3.0`](https://mooncakes.io/docs/Delthin/moon_repomix@0.3.0)。在调用项目的 `moon.mod` 中声明依赖，在 `moon.pkg` 导入：

```moonbit
import {
  "Delthin/moon_repomix" @repomix,
}
```

在 `async fn` 中加载资源并打包，以下接口两版均可用：

```moonbit
let runtime = @repomix.Runtime::load("/absolute/share/moon-repomix/o200k_base.tiktoken")
let options = @repomix.options("/absolute/project", style=@repomix.Style::Json, compress=true)
let result = @repomix.pack(options, runtime)
// result.text 是完整文档，result.tokens 是最终 token 数。
// result.document 提供规范模型；files / skipped / findings / security / budget 提供处理结果。
```

词表同目录须有 `tokenizer-unicode-16.0.0.txt`，加载时校验两份资源的 SHA-256。`Runtime` 可复用于多次顺序打包；SDK 返回结果，不写输出文件。当前源码的 `pack_volumes`、`explain_selection`、新增选项与结构字段见 [迁移](docs/migration.md) 和 [生成接口](src/pkg.generated.mbti)。

## 文档与贡献

[场景](docs/scenarios.md) · [配置](docs/configuration.md) · [输出格式](docs/output.md) · [分卷](docs/partition.md) · [机器报告](docs/reports.md) · [MCP](docs/mcp.md) · [入选原因](docs/selection-explanation.md) · [分词](docs/tokenization.md) · [错误处理](docs/errors.md)

[贡献指南](CONTRIBUTING.md) 说明定点测试、格式与接口更新、资源许可；[工具链](docs/toolchain.md) 说明本地构建和归档。[演示指南](docs/demo.md) 提供可保留产物的三步演示。[三平台 CI](https://github.com/Delthin/moon-repomix/actions/workflows/ci.yml) 覆盖 macOS arm64、Linux x64 和 Windows x64。

## 来源与许可

项目参考 [Repomix](https://github.com/yamadashy/repomix) 的仓库上下文生成行为，采用 [MIT](LICENSE) 许可。第三方代码及资源告知保存在 [LICENSES/](LICENSES/)，解析器固定版本和本地修改见 [来源清单](src/compression/THIRD_PARTY.md)。
