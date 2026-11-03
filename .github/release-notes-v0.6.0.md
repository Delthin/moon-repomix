# v0.6.0

本地浏览器工作台接入任务预算和代码补读，继续使用原生 HTML/CSS/JavaScript 与 MoonBit native 服务。

- **任务预算**：配置多个任务、必选和可选文件、表示与优先级；在完整文档硬上限内生成共享上下文，单独查看、下载选择审计。
- **代码补读**：按符号、精确行范围、全文或符号目录读取；首轮固定累计预算，最多成功三轮，失败不扣额度。分离范围保留实际来源行号，审计计入完整 JSON。
- **结果保留**：任务必选超限或补读失败保留上次成功正文；任务与补读不额外读取或传输原文对照。

既有 CLI、SDK、MCP、混合全文/骨架与精确分卷用法保持兼容。源码构建与 SDK 使用 MoonBit `0.10.17+d971670cd`；平台归档包含运行资源，运行不需要 MoonBit 或 Node.js。

下载平台归档，用 `SHA256SUMS` 校验，解压后保留 `bin/`、`share/` 和 `LICENSES/` 的相对位置：

```sh
./bin/moon-repomix /path/to/project --webui
```

打开终端显示的本地地址，在右侧选择工作方式。详细步骤见 [工作台指南](https://github.com/Delthin/moon-repomix/blob/v0.6.0/docs/webui.md)，升级说明见 [迁移指南](https://github.com/Delthin/moon-repomix/blob/v0.6.0/docs/migration.md)。SDK 包为 `Delthin/moon_repomix@0.6.0`。

发行源码 ZIP 使用 Mooncakes 已发布并经独立 SDK 消费验证的源包；三平台原生归档来自同一源码的成功 CI。`PERFORMANCE.md` 保留标明工具链、平台和固定输入的既有测量。
