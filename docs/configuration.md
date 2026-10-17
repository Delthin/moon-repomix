# 配置与命令行

配置按“默认值 → 选定的 JSON 文件 → 显式 CLI 参数”合并。普通字段由后者覆盖；include 和自定义 ignore 列表按 JSON、CLI 的顺序追加，按原字符串去重并保留首次出现的位置。未出现的布尔参数不参与覆盖，因此 JSON 中的 `false` 会保留。

CLI 优先读取 `--config` 指定的文件，否则寻找输入根目录下的 `repomix.config.json`。显式配置路径、输出路径以启动时的工作目录为基准；include/ignore 以输入根目录为基准。默认配置文件不存在时使用默认值，显式指定的文件不存在则报错。

## 命令行参数

| 参数 | 行为 |
| --- | --- |
| `[directory]` | 单个输入目录，默认 `.` |
| `-o, --output PATH` | 输出文件路径 |
| `--stdout` | 正文写入 stdout，诊断写入 stderr |
| `--style xml\|markdown` | 默认 XML；默认文件名分别为 `repomix-output.xml`、`repomix-output.md` |
| `--include GLOBS` | 追加逗号分隔的正向选择模式 |
| `-i, --ignore GLOBS` | 追加逗号分隔的自定义排除模式 |
| `--no-gitignore` | 关闭 Git 规则 |
| `--no-dot-ignore` | 关闭 `.ignore`、`.repomixignore` |
| `--no-default-patterns` | 关闭内置忽略规则 |
| `--no-security-check` | 关闭扫描，记录关闭状态并显示警告 |
| `--token-count-encoding o200k_base` | 指定当前支持的编码 |
| `--token-budget N` | 正整数预算；等于预算通过，超限保留完整输出并返回 1 |
| `--tokenizer-path PATH` | 显式指定词表文件；加载时校验资源 |
| `-c, --config PATH` | 显式选择 JSON 配置 |
| `--init` | 创建配置文件；已有文件不覆盖 |
| `--parsable-style` | 兼容参数；两种格式始终按可解析规则生成 |
| `--quiet`, `--verbose` | 互斥的诊断模式 |
| `-h, --help` | 显示帮助 |
| `-v, --version` | 显示版本；`-v` 不是 verbose |

值参数支持 `--key=value` 和分开传值，`-o=PATH` 也可用。以 `-` 开头的值须使用等号形式。短选项不能合并，也不接受 `-oPATH`。`--` 结束参数解析，可用于输入名以 `-` 开头的目录。CSV 项会去除首尾空白，空项报错；重复的标量参数取最后一个值，列表参数继续追加。

`--stdout` 与显式 CLI `--output` 冲突，但与 JSON 中的输出文件名不冲突。stdout 模式不创建输出文件。文件名 `-` 表示普通文件，标准输出须使用 `--stdout`。

## JSON 配置

```json
{
  "output": {
    "filePath": "context.md",
    "style": "markdown",
    "tokenBudget": 200000
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
  "input": { "maxFileSize": 52428800 }
}
```

以上字段均可省略。所有层级都拒绝未知字段；根节点必须为对象，字段类型须与示例一致，`null` 不等于省略。列表元素必须是字符串。预算和单文件字节上限须为 `1..2147483647` 的整数；CLI 预算只接受十进制数字。路径必须非空且不含 NUL。默认输出文件名在样式合并完成后选择。

`tokenizer_path` 通过 CLI 或编程接口设置，不属于 JSON 字段。

include 和自定义 ignore 拒绝空模式、前导 `!`、绝对路径、反斜杠、冒号、花括号及 `..` 组件。支持 `*`、`?`、`**`、字符类和目录模式；完整语法由文件选择包校验。规则文件中的 `!` 反选另按 [文件选择规则](file-selection.md) 处理。

## 配置包接口

`delthin/moon_repomix/config` 负责纯解析与合并，返回的相对路径保持原样。调用者负责配置文件 I/O、路径解析、动作执行及资源加载。

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
| `style` | `Style`，`Xml`；另一值为 `Markdown` |
| `include_patterns`, `ignore` | `Array[String]`，空 |
| `use_gitignore`, `use_dot_ignore`, `use_default_patterns` | `Bool`，true |
| `security_check` | `Bool`，true |
| `encoding` | `String`，`o200k_base` |
| `token_budget` | `Int?`，`None`，不限 |
| `max_file_size` | `Int`，52,428,800 磁盘字节 |
| `tokenizer_path` | `String?`，`None` |
| `quiet`, `verbose` | `Bool`，false |

`ConfigError` 包含 `InvalidJson`、`UnknownField(String)`、`InvalidValue(String)`、`UnknownOption(String)`、`MissingValue(String)`、`Conflict(String)`、`MultipleDirectories`。字符串负载只标识字段或选项；JSON 解析异常统一为 `InvalidJson`。
