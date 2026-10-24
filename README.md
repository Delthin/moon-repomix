# moon-repomix

把本地目录或公开 HTTPS 仓库整理成 XML、Markdown、JSON 或纯文本，供 AI 阅读、代码评审和问题追踪。当前源码支持七类语言的 AST 骨架、全文/骨架混合、Git 差异与历史、精确预算分卷和固定本地根的只读 MCP。使用 MoonBit native 实现，提供 CLI、SDK 和本地浏览器工作台；解析器和分词资源随源码或安装包提供，运行时不需要 Node.js。

## 选择版本

| 版本 | 可用能力与获取方式 |
| --- | --- |
| 已发行 **v0.3.0** | 四格式、MoonBit/JavaScript/TypeScript/Python 骨架、Git 差异和历史、公开远程仓库、精确 `o200k_base` 计数、stdin 文件列表。使用 [Release](https://github.com/Delthin/moon-repomix/releases/tag/v0.3.0) 或 [Mooncakes 0.3.0](https://mooncakes.io/docs/Delthin/moon_repomix@0.3.0)，查阅 [固定版本文档](https://github.com/Delthin/moon-repomix/blob/v0.3.0/README.md)。 |
| **当前源码，尚未发行** | 新增本地浏览器工作台、混合全文/骨架、模板、展示控制、Go/Rust/Java 骨架、精确分卷、JSON stderr、输入总量限制、只读 MCP 和入选原因查询。需要从源码构建；见 [场景](docs/scenarios.md)、[0.3 → 0.4 接口迁移预览](docs/migration.md) 与 [Unreleased](CHANGELOG.md#unreleased)。 |

当前源码的版本标识为 `0.4.0`，表中的正式下载仍为 v0.3.0。以下新接口以当前源码为准，问题报告请附构建 commit。

v0.3.0 在固定三仓库、六场景的 macOS CLI 对照中耗时减少约 31%–76%。新增 35 MB TypeScript 大库中，Native CLI 耗时更高、RSS 更低；本次常驻 MCP 重复打包和完整读取更快。各场景的版本、选项、全部样本和平台范围见 [性能测量](docs/performance.md)。

## 浏览器工作台（当前源码）

工作台使用原生 HTML/CSS/JavaScript，通过本地 HTTP 接口调用 MoonBit native 引擎。目录浏览、源码读取、安全扫描、AST 压缩和最终 JSON 的精确 token 计数均由 Native 服务完成；浏览器负责配置、查看与下载。

![编辑器工作台：选择目录、生成上下文、切换原文与结构输出、检查预算](assets/demo/webui.gif)

在仓库根目录直接体验示例，需要 [固定版本 MoonBit 与 C 工具链](docs/toolchain.md)：

```sh
moon update
moon run src/cmd/moon-repomix --target native --release -- examples/demo --webui --tokenizer-path assets/tokenizer-o200k_base.tiktoken
```

从当前源码安装后，可运行 `moon-repomix ./project --webui`。打开 `http://127.0.0.1:8765`，在右侧选择授权目录、全文/骨架/混合策略及文件规则，点击“生成上下文”；左侧浏览结果文件，中间切换原文、处理后正文或完整 JSON，底部复制 CLI 或下载原始 JSON。

修改参数会将现有结果标为旧结果，下一次生成成功后才替换；预算超限仍保留完整输出。动图来自真实 Native 服务操作，三种模式的浏览器下载已与相同参数 CLI 输出逐字节核对。页面资源随当前源码安装提供，运行时不需要 Node.js；端口设置、输入限额与服务边界见 [工作台指南](docs/webui.md)。

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

[工作台](docs/webui.md) · [场景](docs/scenarios.md) · [配置](docs/configuration.md) · [输出格式](docs/output.md) · [分卷](docs/partition.md) · [机器报告](docs/reports.md) · [MCP](docs/mcp.md) · [入选原因](docs/selection-explanation.md) · [分词](docs/tokenization.md) · [错误处理](docs/errors.md)

[贡献指南](CONTRIBUTING.md) 说明定点测试、格式与接口更新、资源许可；[工具链](docs/toolchain.md) 说明本地构建和归档。[演示指南](docs/demo.md) 提供可保留产物的三步演示。[三平台 CI](https://github.com/Delthin/moon-repomix/actions/workflows/ci.yml) 覆盖 macOS arm64、Linux x64 和 Windows x64。

## 来源与许可

项目参考 [Repomix](https://github.com/yamadashy/repomix) 的仓库上下文生成行为，采用 [MIT](LICENSE) 许可。第三方代码及资源告知保存在 [LICENSES/](LICENSES/)，解析器固定版本和本地修改见 [来源清单](src/compression/THIRD_PARTY.md)。
