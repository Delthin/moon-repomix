# Changelog

记录面向使用者的版本差异。`Unreleased` 仅指当前源码，不表示已发行安装包或注册表版本。

## [Unreleased]

## [0.4.1] - 2026-10-27

### Changed

- 精确计数改用私有 C 内核和请求级有界缓存，减少 UTF-8 预切分、BPE 与分卷/索引的重复工作；既有编码路径作为差分参考和精确保守回退。
- 严格 UTF-8 快照复用验证结果；固定凭证规则通过必要字面条件预筛选，最终发现才计算字节/行坐标。完整原文扫描和命中排除策略保持一致。
- 原生 AST 使用有界滚动 lane、前向 cursor 与每次 Selection 的类型分类缓存；结果按原始顺序发布，取消时回收工作。原有 200 ms、8 MiB、深度和片段边界继续生效。
- 固定 35 MB TypeScript 的五轮对照中，macOS 原文/完整元数据压缩 wall 比 Node 降低 23.4% / 11.7%，Linux 降低 30.5% / 33.1%。完整样本、内存代价、小库回退和 Linux checker.ts 原文回退见 [性能文档](docs/performance.md)。

### Added

- 可复现的手动 Linux 大库工作流和 `run-verified` 身份校验入口，归档全部五轮、预热产物与正确性收据。

### Fixed

- Windows MSVC 使用兼容的原子操作封装，保留原子取消、CAS 和全进程 worker/job/源副本配额。
- 固定语料准备分别核对 annotated tag 对象、解引用提交与 HEAD，保持已有源码/许可散列。

## [0.4.0] - 2026-10-25

### Added

- 常用 CLI 简写 `-f` / `--format`、`--budget`、`--split`，格式接受 `md` / `txt`；默认帮助按常见任务组织，`--help-all` 展示完整参数。既有参数及 JSON 字段继续使用原语义。
- `--webui` 启动仅监听 loopback 的本地浏览器工作台，支持授权子目录选择、真实 Native 全文/骨架/混合生成、预算比较、代码对照与 JSON 下载；页面资源随安装包提供。
- `--keep-full` / `output.keepFull` 在骨架模式中保留指定文件全文；SDK 对应 `keep_full_patterns`。
- 扫描后的 header 与本地 instruction 模板，支持 CLI、JSON 配置和 SDK。
- 章节显示控制、输出行号、目标根/cwd/绝对三种显示路径；规范文档仍保留原始正文、根相对路径和行映射。
- Go、Rust、Java 的原生语法骨架；连同已有语言共七类。
- SDK `pack_volumes` 和 CLI `--split-output`：对每卷完整字符串精确计数、保持文件/章节完整，索引独立计数并纳入总开销。CLI 原子发布到不存在的新目录。
- `--report-json` 输出固定 schemaVersion 1 的 stderr 报告，包含精确计量、退出码与发布状态。
- 固定本地根的只读 MCP stdio 服务，提供上下文分卷、内存资源读取与释放；支持现代每请求协议和旧 initialize 客户端。
- CLI `--explain-path`、SDK `explain_selection` 及 MCP 同名工具，返回请求路径的入选/排除原因。

### Changed

- 标准 native 源码构建自动定位仓库内的词表和页面资源，`moon run` 启动 CLI 或工作台时可省略 `--tokenizer-path`。
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

[Unreleased]: https://github.com/Delthin/moon-repomix/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/Delthin/moon-repomix/releases/tag/v0.4.1
[0.4.0]: https://github.com/Delthin/moon-repomix/releases/tag/v0.4.0
[0.3.0]: https://github.com/Delthin/moon-repomix/releases/tag/v0.3.0
