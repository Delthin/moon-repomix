# Changelog

记录面向使用者的版本差异。`Unreleased` 仅指当前源码，不表示已发行安装包或注册表版本。

## [Unreleased]

### Added

- `--keep-full` / `output.keepFull` 在骨架模式中保留指定文件全文；SDK 对应 `keep_full_patterns`。
- 扫描后的 header 与本地 instruction 模板，支持 CLI、JSON 配置和 SDK。
- 章节显示控制、输出行号、目标根/cwd/绝对三种显示路径；规范文档仍保留原始正文、根相对路径和行映射。
- Go、Rust、Java 的原生语法骨架；连同已有语言共七类。
- SDK `pack_volumes` 和 CLI `--split-output`：对每卷完整字符串精确计数、保持文件/章节完整，索引独立计数并纳入总开销。CLI 原子发布到不存在的新目录。
- `--report-json` 输出固定 schemaVersion 1 的 stderr 报告，包含精确计量、退出码与发布状态。
- 固定本地根的只读 MCP stdio 服务，提供上下文分卷、内存资源读取与释放；支持现代每请求协议和旧 initialize 客户端。
- CLI `--explain-path`、SDK `explain_selection` 及 MCP 同名工具，返回请求路径的入选/排除原因。

### Changed

- 默认限制过滤后的普通候选为 20,000 个、源码原始读取为 200 MiB，可通过 `--max-files` / `--max-total-size`、JSON 和 SDK 显式调整。超过任一限额停止打包；0 表示零配额。
- SDK 增加模板和输入限额错误、新选项及分卷/查询结果类型。机器 JSON 的 token/字节度量使用十进制字符串，详见 [迁移说明](docs/migration.md)。

## [0.3.0] - 2026-10-23

### Added

- MoonBit `.mbt` 和 `.mbti` 原生骨架，接入 CLI、规范文档及源码行映射；已有 JavaScript/TypeScript/Python 骨架继续可用。
- CLI `--stdin` / `--stdin0` 字面文件列表和 `--stdout` / `-o -` 正文输出；输入列表有边界校验，并继续受选择规则和扫描约束。
- SDK `file_paths` 白名单，统一普通发现与 Git 差异/历史的路径过滤。
- 固定输入的原生性能测量、Linux 测量和真实 MoonBit 自打包回归。

### Changed

- 对齐默认排除、ignore 开关、自定义 glob 与精确磁盘拼写行为，修正跨平台字面路径选择。
- 优化精确 tokenizer 的初始化、分词计数、文件选择和安全命中定位，减少文件处理中的定时器分配。

[Unreleased]: https://github.com/Delthin/moon-repomix/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Delthin/moon-repomix/releases/tag/v0.3.0
