# 从 v0.3.0 升级到 v0.4.0

升级 CLI 时下载 [v0.4.0 安装包](https://github.com/Delthin/moon-repomix/releases/tag/v0.4.0)，使用 SDK 时将 `moon.mod` 中的 `Delthin/moon_repomix` 依赖更新到 `0.4.0`，再运行 `moon update`。

本页对照 v0.3.0 与 v0.4.0 的 [CLI help](../src/cmd/moon-repomix/help.mbt)、[配置类型及默认值](../src/config/types.mbt)、[JSON 解析](../src/config/json.mbt) 和 [SDK 接口](../src/pkg.generated.mbti)。问题报告请附 `--version` 输出；自行构建时另附 commit。

## 保留现有用法，先检查新默认限制

四种格式、默认 XML、显式 `--compress`、stdin 字面列表、include/ignore、安全扫描和普通单文档预算继续沿用。默认仍为全文，无模板、无显示行号、目标根相对路径，章节默认显示；单文件上限仍为 50 MiB。已有参数和 JSON 字段无须批量改名。

v0.4.0 的 CLI 推荐 `-f md`（兼容 `--style markdown`）、`--budget N`（兼容 `--token-budget`）、`--split N`（兼容 `--split-output`）；新旧拼法混写沿用后者覆盖。`md`、`txt` 是 CLI 简写，JSON 字段及 `markdown`、`plain` 值保持原样。`--help` 展示常用任务，完整参数使用 `--help-all`，见 [CLI 速查](cli.md)。

v0.4.0 新增：

| 项目 | CLI | JSON | SDK `Options` / 默认 |
| --- | --- | --- | --- |
| 普通候选数 | `--max-files N` | `input.maxFiles` | `max_files : Int`，20,000 |
| 累计原始读取 | `--max-total-size N` | `input.maxTotalSize` | `max_total_size : Int64`，209,715,200（200 MiB） |

两者允许 0，0 是零配额而非无限。候选数在过滤后、读取前计算；后续因密钥、二进制、无效 UTF-8 等被排除的候选仍占配额。累计字节包含 BOM、探测和之后被拒绝的源码读取；静态大小超单文件上限的跳过可消耗 0 字节。至多多探测 1 byte 就报 `InputLimitError`，停止整个处理。它不是模板、Git、词表、远程下载或进程内存的总配额。

`maxFiles` 范围为 `0..2147483647`；`maxTotalSize` 范围为 `0..9007199254740991`。JSON 输入填整数数字，SDK 填 `Int64`（例如 `209715200L`）。大型仓库升级后若触发新默认上限，先缩小 include 或显式核准更大的值。

## 新选项与字段

| 用途 | CLI | JSON `output` 字段 | SDK `options(...)` 命名参数 |
| --- | --- | --- | --- |
| 压缩时保留原文 | `--keep-full GLOBS` | `keepFull`（字符串数组） | `keep_full_patterns` |
| 头部与本地指令 | `--header-text TEXT`、`--instruction-file-path FILE` | `headerText`、`instructionFilePath` | `header_text`、`instruction_file_path : String?` |
| 章节显示 | `--[no-]file-summary`、`--[no-]directory-structure`、`--[no-]files`、`--[no-]git-sections`、`--[no-]metadata` | `fileSummary`、`directoryStructure`、`files`、`gitSections`、`metadata` | `file_summary`、`directory_structure`、`include_files`、`git_sections`、`metadata` |
| 显示行号 | `--output-show-line-numbers` / `--no-output-show-line-numbers` | `showLineNumbers` | `show_line_numbers` |
| 显示路径 | `--output-file-path-style STYLE` | `filePathStyle` | `output_file_path_style : PathStyle` |
| CLI 分卷 | `--split-output N` / `--no-split-output` | `splitOutput`（正整数或 `false`） | `split_output : SplitOutput`；实际分卷调用 `pack_volumes` |

路径值为 `target-relative`（默认）、`cwd-relative`、`absolute`，SDK 对应 `PathStyle::TargetRelative`、`CwdRelative`、`Absolute`。显示开关不改变规范文档正文、根相对路径或原始行映射；预算按实际渲染结果计算。

配置仍按默认 → JSON → 显式 CLI 合并；`include`、自定义 ignore 和 `keepFull` 追加去重，标量覆盖。正向章节参数可恢复 JSON 的 `false`。模板显式空字符串清除继承值；指令路径相对进程 cwd，每段最多 1 MiB，扫描失败停止本次打包。

可在已有配置上逐步加入这些字段，例如：

```json
{
  "output": {
    "style": "markdown",
    "compress": true,
    "keepFull": ["src/core/**"],
    "headerText": "请评审公开接口。",
    "showLineNumbers": true,
    "filePathStyle": "target-relative"
  },
  "input": { "maxFiles": 20000, "maxTotalSize": 209715200 }
}
```

所有层级仍拒绝未知字段，v0.3.0 不能读取新增字段。`--report-json`、`--explain-path`、`--mcp` 及 `--mcp-max-*` 是 CLI 入口参数，不是 JSON 配置键。完整参数见 [配置](configuration.md)。

## SDK 调整

已有 `options` 命名参数与 `pack(options, runtime) -> PackResult` 保留。用 `options(...)` 或 `Patch::empty()` 构造值，可获得新默认；直接写完整 `Options`、`Cli` 或 `Patch` 结构字面量的调用者需补齐新增字段，字段清单以 [config `.mbti`](../src/config/pkg.generated.mbti) 为准。`config.Action` 新增 `HelpAll`，直接匹配 CLI 动作的调用者需处理它。匹配 `PackError` 的代码需处理新增的 `ContextTextError(String)`、`ContextSecurityFinding(String)` 和 `InputLimitExceeded(kind~ : String, limit~ : Int64)`。

直接构造 `Document` 的调用者还需补充 `header_text`、`instruction_text` 两个字符串字段；使用 `document.create(...)` 时，新命名参数可省略并默认为空。直接调用四个 `output` 渲染器的旧调用保留，新可选 `display : Display` 控制展示，默认值通过 `Display::default()` 构造。详见 [document `.mbti`](../src/document/pkg.generated.mbti) 与 [output `.mbti`](../src/output/pkg.generated.mbti)。

本地联调可用 `moon.work` 将调用项目与本仓库列为 `members`。在已有 SDK 导入下，于 `async fn` 中调用：

```moonbit
let runtime = @repomix.Runtime::load("/absolute/share/moon-repomix/o200k_base.tiktoken")
let options = @repomix.options(
  "/absolute/project",
  style=@repomix.Style::Markdown,
  compress=true,
  keep_full_patterns=["src/core/**"],
  header_text="请评审公开接口。",
  max_files=20000,
  max_total_size=209715200L,
)
let result = @repomix.pack_volumes(options, runtime, max_tokens=12000)
// result.partition.volumes：完整文档字符串与各自精确计数。
// result.partition.index_text：最终索引；result.file_names：卷 ID 到文件名。
// result.partition.total_tokens : Int64，包含所有卷与独立索引。
```

`options.split_output` 不会改变 `pack` 的返回类型；SDK 分卷必须显式调用 `pack_volumes`，其 `max_tokens` 为每卷硬上限，`Options.token_budget` 不应用于分卷。SDK 返回字符串，不发布目录；捕获分卷失败时使用 `PartitionError`，例如 `TemplateTooLarge` 和 `UnitTooLarge`。每卷重复模板，文件/章节不拆开；索引不受每卷 cap 约束，`total_tokens` 是分别计数之和，并非拼接后计数。详见 [分卷接口](partition.md)。

新增 `explain_selection(options, paths) -> SelectionReport` 无需 `Runtime`；`SelectionReport::to_json()` 返回与 CLI 相同的安全投影。至多 256 个字面路径，只查询选择、读取、扫描与表示检查，不执行模板、Git、压缩或最终预算。`options.file_paths` 是独立白名单，查询不能扩大它。

## 自动化输出与 MCP

`--report-json` 将 stderr 切换成单份 schemaVersion 1 JSON；普通 stdout 仍为正文，CLI 分卷 stdout 为空。它优先于 quiet，不改变退出码。成功、超预算、失败分别为 `ok`、`over_budget`、`error`；普通预算超限仍提交完整输出并退出 1，分卷单项放不下则失败。

报告的 token/字节度量（含每卷值、`tokens.limit`）、`limits.maxTotalSize` 和错误 `error.limit` 使用十进制字符串；不适用的 limit 为 null。文件数、卷数、`schemaVersion` 和 `exitCode` 仍是 JSON 数字。解析为语言的精确整数类型，勿统一转成浮点数。SDK 中 `max_total_size`、`SelectionReport.read_bytes`、`Partition.total_tokens` 为 `Int64`，不意味着每个 SDK 计数都变为 Int64。报告字段与 `publication` 提交状态见 [机器报告](reports.md)。

CLI 分卷的 `-o` 是不存在的新目录，父目录必须已存在且稳定；与 stdout 和普通 `--token-budget` 冲突。失败后先检查报告和输出状态，详见 [错误指南](errors.md)。

MCP 是新增的固定本地根 stdio 入口：主机确定选择、扫描和输入上限，请求只在授权范围内选文件，不能提高主机每卷 cap。资源仅在内存中，失败或提交前取消保留上次成功结果。支持 `2026-07-28` 每请求版本协议，以及 `2025-11-25` / `2025-06-18` initialize 客户端；接入参数、资源限制和工具契约见 [MCP](mcp.md)。
