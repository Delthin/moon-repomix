# 配置与命令行

配置按“默认值 → 选定的 JSON 文件 → 显式 CLI 参数”合并。普通字段由后者覆盖；include 和自定义 ignore 列表按 JSON、CLI 的顺序追加，按原字符串去重并保留首次出现的位置。未出现的布尔参数不参与覆盖，因此 JSON 中的 `false` 会保留。

CLI 优先读取 `--config` 指定的文件，否则寻找输入根目录下的 `repomix.config.json`。远程模式仅加载显式指定的本地配置。显式配置路径、输出路径以启动时的工作目录为基准；include/ignore 以输入根目录为基准。默认配置文件不存在时使用默认值，显式指定的文件不存在则报错。

## 命令行参数

| 参数 | 行为 |
| --- | --- |
| `[directory]` | 单个输入目录，默认 `.` |
| `-o, --output PATH` | 输出文件路径 |
| `--stdout` | 正文写入 stdout，诊断写入 stderr |
| `--style xml\|markdown\|json\|plain` | 默认 XML；默认文件名为 `repomix-output` 加对应的 `.xml`、`.md`、`.json`、`.txt` 扩展名 |
| `--compress`, `--no-compress` | 开启或关闭语法树结构压缩，默认关闭 |
| `--include-diffs`, `--no-include-diffs` | 开启或关闭 staged/unstaged 差异，默认关闭 |
| `--include-logs`, `--no-include-logs` | 开启或关闭提交历史，默认关闭 |
| `--include-logs-count N` | 最近提交数量，默认 50，范围 `1..10000` |
| `--max-git-bytes N` | Git 文本收集上限，默认 8,388,608 字节 |
| `--remote URL` | 获取公开 HTTPS 仓库；与另一个输入目录互斥 |
| `--remote-branch REF` | 指定 branch/tag/full commit；需要远程 URL |
| `--include GLOBS` | 追加逗号分隔的正向选择模式 |
| `-i, --ignore GLOBS` | 追加逗号分隔的自定义排除模式 |
| `--no-gitignore` | 关闭 Git 规则 |
| `--no-dot-ignore` | 关闭 `.ignore`、`.repomixignore` |
| `--no-default-patterns` | 关闭内置忽略规则 |
| `--no-security-check` | 关闭扫描，记录关闭状态并显示警告 |
| `--token-count-encoding o200k_base` | 指定当前支持的编码 |
| `--token-budget N` | 正整数预算；等于预算通过，超限保留完整输出并返回 1 |
| `--top-files-len N` | 按文件正文 token 数降序显示前 N 个文件，默认 5；0 关闭 |
| `--token-count-tree [N]` | 显示文件和目录的 token 树；省略 N 时为 0，只显示计数 ≥ N 的节点 |
| `--tokenizer-path PATH` | 显式指定词表文件；加载时校验资源 |
| `-c, --config PATH` | 显式选择 JSON 配置 |
| `--init` | 创建配置文件；已有文件不覆盖 |
| `--parsable-style` | 兼容参数，不改变输出；JSON 始终生成合法 JSON，XML 始终遵循 XML 1.0 字符和转义规则 |
| `--quiet`, `--verbose` | 互斥的诊断模式 |
| `-h, --help` | 显示帮助 |
| `-v, --version` | 显示版本；`-v` 不是 verbose |

值参数支持 `--key=value` 和分开传值，`-o=PATH` 也可用。以 `-` 开头的值须使用等号形式。短选项不能合并，也不接受 `-oPATH`。`--` 结束参数解析，可用于输入名以 `-` 开头的目录。CSV 项会去除首尾空白，空项报错；重复的标量参数取最后一个值，列表参数继续追加。

`--token-count-tree` 会将紧随其后的非选项参数作为阈值。目录应放在该选项之前，或用 `--token-count-tree -- directory` 分隔；也可使用 `--token-count-tree=0 directory`。两项统计参数只影响 stderr，`--quiet` 会隐藏它们，打包正文与预算不受影响。详见 [Token 分布与排名](tokenization.md#token-分布与排名)。

`--stdout` 与显式 CLI `--output` 冲突，但与 JSON 中的输出文件名不冲突。stdout 模式不创建输出文件。文件名 `-` 表示普通文件，标准输出须使用 `--stdout`。

## JSON 配置

```json
{
  "output": {
    "filePath": "context.md",
    "style": "markdown",
    "tokenBudget": 200000,
    "topFilesLength": 5,
    "tokenCountTree": 100,
    "compress": true,
    "git": { "includeDiffs": true, "includeLogs": true, "includeLogsCount": 20 }
  },
  "include": ["src/**", "docs/*.md"],
  "ignore": {
    "customPatterns": ["tmp/**"],
    "useGitignore": true,
    "useDotIgnore": true,
    "useDefaultPatterns": true
  },
  "security": { "enableSecurityCheck": true },
  "tokenCount": { "encoding": "o200k_base" },
  "input": { "maxFileSize": 52428800, "maxGitBytes": 8388608 }
}
```

以上字段均可省略。所有层级都拒绝未知字段；根节点必须为对象，字段类型须与示例一致，`null` 不等于省略。列表元素必须是字符串。预算和单文件字节上限须为 `1..2147483647` 的整数；CLI 预算只接受十进制数字。路径必须非空且不含 NUL。默认输出文件名在样式合并完成后选择；显式 `output.filePath` 或 CLI `--output` 保持用户指定名称。格式结构见 [文件读取与输出](output.md)。

`output.topFilesLength` 为 `0..2147483647` 的整数，默认 5。`output.tokenCountTree` 默认为 `false`；`true` 开启完整树，非负整数或只含十进制数字的字符串表示阈值。阈值范围为 `0..2147483647`，0 也会显示空文件。CLI 的排名数量和阈值均只接受十进制数字。

远程来源可在 `--config` 显式指定的文件中配置为 `"remote": {"url":"https://github.com/octocat/Hello-World.git", "branch":"master"}`。`branch` 可省略，URL 必填；配置中的远程 URL 同样要求目录为 `.`。语法压缩、Git 章节、回退和安全规则详见 [仓库上下文](context.md)。

`tokenizer_path` 通过 CLI 或编程接口设置，不属于 JSON 字段。

include 和自定义 ignore 拒绝空模式、前导 `!`、绝对路径、反斜杠、冒号、花括号及 `..` 组件。支持 `*`、`?`、`**`、字符类和目录模式；完整语法由文件选择包校验。规则文件中的 `!` 反选另按 [文件选择规则](file-selection.md) 处理。

## 配置包接口

`Delthin/moon_repomix/config` 负责纯解析与合并，返回的相对路径保持原样。调用者负责配置文件 I/O、路径解析、动作执行及资源加载。

```moonbit
pub fn parse_cli(args : Array[String]) -> Cli raise ConfigError
pub fn parse_json(text : String) -> Patch raise ConfigError
pub fn resolve(cli : Cli, json : Patch?) -> Options raise ConfigError
pub fn Patch::empty() -> Patch
```

传入 `parse_cli` 的参数不含 `argv[0]`。`Cli` 包含 `directory`、`config_path : String?`、`action : Action`、`stdout`、`quiet`、`verbose` 和 `patch : Patch`。`Action` 为 `Pack | Init | Help | Version`；不同显式动作冲突，相同动作可重复。CLI 在读取配置和词表前处理 help/version/init。

没有选定配置文件时，向 `resolve` 传 `None`。`Patch` 的标量字段为可选值，列表为追加项；可从 `Patch::empty()` 修改字段构造。它不含 directory/stdout/quiet/verbose。`resolve` 校验两份 Patch 中的全部字段，包括随后被覆盖的值；合并不修改输入，结果数组独立分配。

| `Options` 字段 | 类型与默认值 |
| --- | --- |
| `directory` | `String`，`.` |
| `output` | `String`，由样式决定 |
| `stdout` | `Bool`，false |
| `style` | `Style`，默认 `Xml`；可选 `Markdown`、`Json`、`Plain` |
| `include_patterns`, `ignore` | `Array[String]`，空 |
| `use_gitignore`, `use_dot_ignore`, `use_default_patterns` | `Bool`，true |
| `security_check` | `Bool`，true |
| `encoding` | `String`，`o200k_base` |
| `token_budget` | `Int?`，`None`，不限 |
| `top_files_length` | `Int`，5；CLI 报告使用，0 关闭排名 |
| `token_count_tree` | `TokenCountTree`，`Disabled`；`Enabled(Int)` 指定非负阈值，供 CLI 报告使用 |
| `compress`, `include_diffs`, `include_logs` | `Bool`，false |
| `include_logs_count` | `Int`，50，范围 `1..10000` |
| `max_git_bytes` | `Int`，8,388,608 |
| `remote`, `remote_branch` | `String?`，`None` |
| `max_file_size` | `Int`，52,428,800 磁盘字节 |
| `tokenizer_path` | `String?`，`None` |
| `quiet`, `verbose` | `Bool`，false |

`ConfigError` 包含 `InvalidJson`、`UnknownField(String)`、`InvalidValue(String)`、`UnknownOption(String)`、`MissingValue(String)`、`Conflict(String)`、`MultipleDirectories`。字符串负载只标识字段或选项；JSON 解析异常统一为 `InvalidJson`。
