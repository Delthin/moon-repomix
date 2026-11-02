# v0.5.1

固定使用 MoonBit `0.10.17+d971670cd`，提供 macOS arm64、Linux x64、Windows x64 原生安装包和 `Delthin/moon_repomix@0.5.1` SDK。原有 CLI、配置及 Root SDK 用法保持兼容。

- 支持完整实现/源行补读、累计预算补读、必需/可选文件的任务上下文规划，以及原有工作台、混合全文/骨架和精确分卷。
- 计数资源、原生解析器、页面和许可证随包提供，CLI 运行不需要 Node.js 或 MoonBit。
- 三平台 CI 完成检查、构建、核心测试、CLI/MCP/WebUI、安装与源码归档验证：macOS/Linux 各 121/121，Windows 118/118。
- 从 Mooncakes 独立下载、编译和运行 SDK，核对规范源码 ZIP 的全部 423 个文件与发行提交一致；完整实现、任务全文、分卷/索引精确计数及预算边界通过。

## 安装与校验

下载对应平台 `.tar.gz`，按 `SHA256SUMS` 校验。解压后保留 `bin`、`share`、`LICENSES` 的相对位置：

```sh
./bin/moon-repomix ./project -f md --compress
./bin/moon-repomix ./project --webui
```

Windows 使用 `bin/moon-repomix.exe`。SDK 依赖版本为 `0.5.1`，用法见仓库 README。源码附件采用 Mooncakes 的规范发布 ZIP；性能资料见 `PERFORMANCE.md` 中各平台与测量范围。

发行源码：`2a6e0afee16f7342a89fd242ec29b0fe06e19a86`。

[三平台 CI](https://github.com/Delthin/moon-repomix/actions/runs/41415234158) · [注册表 SDK 验证](https://github.com/Delthin/moon-repomix/actions/runs/41416936880) · [Mooncakes](https://mooncakes.io/docs/Delthin/moon_repomix)
