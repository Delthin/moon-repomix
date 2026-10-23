# 配置与命令行

本页描述当前源码的 CLI、JSON 配置和库接口。新增的混合原文/骨架、模板与展示控制需要源码构建；已发布 v0.3.0 的接口见 [该版本文档](https://github.com/Delthin/moon-repomix/blob/v0.3.0/docs/configuration.md)。

配置按“默认值 → 选定的 JSON 文件 → 显式 CLI 参数”合并。普通字段由后者覆盖；include 和自定义 ignore 列表按 JSON、CLI 的顺序追加，按原字符串去重并保留首次出现的位置。未出现的布尔参数不参与覆盖，因此 JSON 中的 `false` 会保留。

CLI 优先读取 `--config` 指定的文件，否则寻找输入根目录下的 `repomix.config.json`。远程模式仅加载显式指定的本地配置。显式配置路径、输出路径以启动时的工作目录为基准；include/ignore 以输入根目录为基准。默认配置文件不存在时使用默认值，显式指定的文件不存在则报错。

## 命令行参数

| 参数 | 行为 |
| --- | --- |
| `[directory]` | 单个输入目录，默认 `.` |
| `-o, --output PATH` | 输出文件路径；`-` 表示 stdout，`./-` 表示普通文件 |
| `--stdout` | 正文写入 stdout，诊断写入 stderr |
| `--stdin` | 显式读取 UTF-8 文件列表，每行一个路径，接受 CRLF |
| `--stdin0` | 显式读取 NUL 分隔的 UTF-8 文件列表，适配 Git `-z` |
| `--style xml\|markdown\|json\|plain` | 默认 XML；默认文件名为 `repomix-output` 加对应的 `.xml`、`.md`、`.json`、`.txt` 扩展名 |
| `--compress`, `--no-compress` | 开启或关闭语法树结构压缩，默认关闭 |
| `--keep-full GLOBS` | 压缩时保留匹配文件原文；与 include 使用相同的根相对 glob，可重复追加 |
| `--header-text TEXT` | 添加头部文字，最多 1 MiB UTF-8；空字符串清除 JSON 中的头部 |
| `--instruction-file-path FILE` | 添加显式本地指令文件，最多 1 MiB；相对进程 cwd，空字符串清除继承值 |
| `--full-metadata`, `--no-full-metadata` | 四种格式显示完整逐文件元数据，默认使用概览；库模型始终完整 |
| `--output-show-line-numbers`, `--no-output-show-line-numbers` | 给显示的文件正文加从 1 开始的行号；不改变库模型、模板或 Git 文本 |
| `--output-file-path-style STYLE` | `target-relative`（默认）、`cwd-relative` 或 `absolute`；控制四格式文件标签与目录树 |
| `--file-summary`, `--no-file-summary` | 显示或隐藏开头的说明，默认显示 |
| `--directory-structure`, `--no-directory-structure` | 显示或隐藏目录树，默认显示 |
| `--files`, `--no-files` | 显示或隐藏文件正文；选择、扫描与库模型仍完整 |
| `--git-sections`, `--no-git-sections` | 显示或隐藏 Git 章节正文；关闭采集使用 `--no-include-diffs/logs` |
| `--metadata`, `--no-metadata` | 显示或隐藏元数据段落；库模型仍完整 |
| `--include-diffs`, `--no-include-diffs` | 开启或关闭 staged/unstaged 差异，默认关闭 |
| `--include-logs`, `--no-include-logs` | 开启或关闭提交历史，默认关闭 |
| `--include-logs-count N` | 最近提交数量，默认 50，范围 `1..10000` |
| `--max-git-bytes N` | Git 文本收集上限，默认 8,388,608 字节 |
| `--remote URL` | 获取公开 HTTPS 仓库；与另一个输入目录互斥 |
| `--remote-branch REF` | 指定 branch/tag/full commit；需要远程 URL |
| `--include GLOBS` | 追加逗号分隔的正向选择模式 |
| `-i, --ignore GLOBS` | 追加逗号分隔的自定义排除模式 |
| `--no-gitignore` | 关闭 Git 规则 |
| `--no-dot-ignore` | 只关闭 `.ignore`；`.repomixignore` 继续生效 |
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

值参数支持 `--key=value` 和分开传值，`-o=PATH` 也可用。以 `-` 开头的值须使用等号形式，输出值单独的 `-` 也可直接传入。短选项不能合并，也不接受 `-oPATH`。`--` 结束参数解析，可用于输入名以 `-` 开头的目录。CSV 只在花括号和字符类之外按逗号分项；项首尾空白会去除，空项报错。重复的标量参数取最后一个值，列表参数继续追加。

`--token-count-tree` 会将紧随其后的非选项参数作为阈值。目录应放在该选项之前，或用 `--token-count-tree -- directory` 分隔；也可使用 `--token-count-tree=0 directory`。两项统计参数只影响 stderr，`--quiet` 会隐藏它们，打包正文与预算不受影响。详见 [Token 分布与排名](tokenization.md#token-分布与排名)。

`-o -`、`--output=-`、JSON 的 `output.filePath: "-"` 与 `--stdout` 都选择标准输出。`--stdout -o -` 可同时使用；`--stdout` 与显式 CLI 普通输出文件冲突，与 JSON 中的默认文件名不冲突。stdout 模式不创建文件；需要名为 `-` 的普通文件时使用 `-o ./-`。

### 文件列表输入

```sh
git ls-files -z | moon-repomix . --stdin0 --style markdown -o -
```

stdin 仅由这两个 CLI 参数显式开启，配置文件不会隐式读取终端。原始输入上限为 8 MiB，接受可选 UTF-8 BOM，非法 UTF-8 或超限时退出且保留旧输出。两种模式互斥，也不能和 `--init` 组合；help/version 仍优先返回。

换行模式接受 LF/CRLF；NUL 模式保留路径中的换行及 CR。协议忽略空记录，保留文件名的前后空格，文件列表本身不解释 glob。路径相对输入根，使用 `/` 分隔；绝对路径、盘符、反斜杠、冒号和空、`.`、`..` 组件整体报错。重复项去重，目录不递归；不存在的普通文件记录跳过。空列表选择零文件，而不是全仓。

文件列表与 include 取交集，仍应用所有 ignore、链接检查、输出自排除、原始内容扫描及大小限制；开启 Git 上下文时，diff 和提交路径也受同一集合限制。

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
    "keepFull": ["src/core/**"],
    "headerText": "请关注接口与错误处理。",
    "instructionFilePath": "review-instructions.md",
    "fullMetadata": false,
    "fileSummary": true,
    "directoryStructure": true,
    "files": true,
    "gitSections": true,
    "metadata": true,
    "showLineNumbers": false,
    "filePathStyle": "target-relative",
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

`output.keepFull` 是追加去重的字符串数组，CLI 的 `--keep-full` 在 JSON 列表之后合并。开启压缩时仅对最终已选且通过扫描的文件生效；`--no-compress` 时全部文件保留原文。它沿用 include 的根相对和目录后代语义，完整记录以 `reason: "kept-full"` 标识主动保留，概览用 `keptFull` 单独计数。

`output.headerText` 和 `output.instructionFilePath` 是可选字符串，CLI 标量覆盖 JSON，显式空字符串清除继承值。指令文件只读取一次，使用严格 UTF-8、去除开头 BOM、保留其余换行；读取非普通文件、最终符号链接或超过 1 MiB 时失败。扫描开启时，任一模板命中会使本次打包失败；错误仅含字段名，旧输出保持原样。`--no-security-check` 显式关闭同一套扫描。XML 还要求模板可表示为 XML 1.0 文本。

模板不改变文件选择；指令文件若同时在输入集合中，会分别作为文件和模板出现，可用 ignore 排除其文件副本。完整文档计数和预算包含模板文字及格式包装。

include、自定义 ignore 和 keep-full 拒绝空模式、前导 `!`、绝对路径、反斜杠、冒号、NUL 及 `..` 组件。支持 `*`、`?`、`**`、字符类、目录模式及有界的 `{a,b}` 嵌套备选；完整语法和展开上限由文件选择包校验。include 相对根匹配，`LICENSE` 只选根文件，`**/LICENSE` 选择各层文件。规则文件中的 `!` 反选另按 [文件选择规则](file-selection.md) 处理。

## 配置包接口

`Delthin/moon_repomix/config` 负责纯解析与合并，返回的相对路径保持原样。调用者负责配置文件 I/O、路径解析、动作执行及资源加载。

```moonbit
pub fn parse_cli(args : Array[String]) -> Cli raise ConfigError
pub fn parse_json(text : String) -> Patch raise ConfigError
pub fn resolve(cli : Cli, json : Patch?) -> Options raise ConfigError
pub fn parse_file_list(text : String, nul~ : Bool = false) -> Array[String] raise ConfigError
pub fn Patch::empty() -> Patch
```

传入 `parse_cli` 的参数不含 `argv[0]`。`Cli` 包含 `directory`、`config_path : String?`、`action : Action`、`stdout`、`stdin_mode : StdinMode`、`quiet`、`verbose` 和 `patch : Patch`。`StdinMode` 为 `Off | Lines | Nul`；解析和合并只记录模式，调用者读取后将列表传给 `Options.file_paths`。`Action` 为 `Pack | Init | Help | Version`；不同显式动作冲突，相同动作可重复。CLI 在读取配置和词表前处理 help/version/init。

没有选定配置文件时，向 `resolve` 传 `None`。`Patch` 的标量字段为可选值，列表为追加项；可从 `Patch::empty()` 修改字段构造。它不含 directory/stdout/quiet/verbose。`resolve` 校验两份 Patch 中的全部字段，包括随后被覆盖的值；合并不修改输入，结果数组独立分配。

| `Options` 字段 | 类型与默认值 |
| --- | --- |
| `directory` | `String`，`.` |
| `output` | `String`，由样式决定 |
| `stdout` | `Bool`，默认 false；`resolve` 在输出值为 `-` 时设为 true |
| `style` | `Style`，默认 `Xml`；可选 `Markdown`、`Json`、`Plain` |
| `include_patterns`, `ignore` | `Array[String]`，空 |
| `keep_full_patterns` | `Array[String]`，空；压缩时的原文例外，使用根相对 include 语义 |
| `header_text` | `String`，空；模板头部文字 |
| `instruction_file_path` | `String?`，None；相对进程 cwd 的显式本地文件路径 |
| `file_paths` | `Array[String]?`，默认 `None` 为遍历；`Some([])` 为零文件，仅库/显式 CLI 列表使用 |
| `use_gitignore`, `use_dot_ignore`, `use_default_patterns` | `Bool`，true |
| `security_check` | `Bool`，true |
| `encoding` | `String`，`o200k_base` |
| `token_budget` | `Int?`，`None`，不限 |
| `top_files_length` | `Int`，5；CLI 报告使用，0 关闭排名 |
| `token_count_tree` | `TokenCountTree`，`Disabled`；`Enabled(Int)` 指定非负阈值，供 CLI 报告使用 |
| `compress`, `include_diffs`, `include_logs` | `Bool`，false |
| `full_metadata` | `Bool`，false；控制四种格式的逐文件元数据展示 |
| `file_summary`, `directory_structure`, `include_files` | `Bool`，true；说明、目录与文件正文显示 |
| `git_sections`, `metadata` | `Bool`，true；Git 正文与元数据段落显示 |
| `show_line_numbers` | `Bool`，false；只装饰渲染的文件正文 |
| `output_file_path_style` | `PathStyle`，默认 `TargetRelative`；另有 `CwdRelative`、`Absolute` |
| `include_logs_count` | `Int`，50，范围 `1..10000` |
| `max_git_bytes` | `Int`，8,388,608 |
| `remote`, `remote_branch` | `String?`，`None` |
| `max_file_size` | `Int`，52,428,800 磁盘字节 |
| `tokenizer_path` | `String?`，`None` |
| `quiet`, `verbose` | `Bool`，false |

`ConfigError` 包含 `InvalidJson`、`UnknownField(String)`、`InvalidValue(String)`、`UnknownOption(String)`、`MissingValue(String)`、`Conflict(String)`、`MultipleDirectories`。字符串负载只标识字段或选项；JSON 解析异常统一为 `InvalidJson`。
