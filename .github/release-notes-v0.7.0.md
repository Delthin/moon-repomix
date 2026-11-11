# v0.7.0

任务预算与代码补读使用统一的版本化请求，可在 SDK、CLI、MCP 和浏览器工作台之间复用。

- **共享请求**：`ContextRequest` 校验任务与代码规格；CLI 提供 `--context-request` 单次执行和 `--context-stdio` 有界 JSONL 会话，MCP 与 HTTP 提供通用请求执行与能力查询。
- **工作台配置**：保存、导入完整请求规格，沿用当前授权目录和主机限额；配置只包含请求参数。
- **MoonBit 完整定义索引**：`.mbt` / `.mbti` 支持符号读取、符号目录和同文件依赖补读，识别新版 `#derive`、限定派生名与 `nocancel` 语法。
- **工具链维护**：最低支持 MoonBit `0.10.20`，接受后续稳定版本；CI 跟随官方当前稳定版，异步依赖升级至 `0.22.5`，更新取消清理与脚本导入。

既有 CLI、SDK、MCP 和工作台用法保持兼容。代码补读保持最多三轮成功、累计正文硬上限和失败不扣额度；任务审计单独计量。平台归档包含原生程序与运行资源，运行时无需 MoonBit 或 Node.js。

下载 macOS arm64、Linux x64 或 Windows x64 归档，用 `SHA256SUMS` 校验，解压后保留 `bin/`、`share/` 和 `LICENSES/` 的相对位置。SDK 包为 `Delthin/moon_repomix@0.7.0`，源码构建与 SDK 消费使用 MoonBit `>=0.10.20`。

[共享请求协议](https://github.com/Delthin/moon-repomix/blob/v0.7.0/docs/context-requests.md) · [CLI 上下文读取](https://github.com/Delthin/moon-repomix/blob/v0.7.0/docs/context-cli.md) · [迁移指南](https://github.com/Delthin/moon-repomix/blob/v0.7.0/docs/migration.md)

发行源码 ZIP 经注册表源码逐项比较与独立 SDK 消费验证；三平台原生归档来自同一源码的成功 CI。`PERFORMANCE.md` 保留各表注明工具链和固定输入的既有测量。
