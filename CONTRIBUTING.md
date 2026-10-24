# 贡献指南

先阅读相关使用文档和目标包的 `.mbti`，在 issue 或变更说明中给出触发条件、预期与实际结果。复现使用合成仓库和脱敏数据；安全问题按 [SECURITY.md](SECURITY.md) 协调，不公开漏洞细节或真实秘密。

## 本地准备

项目使用 MoonBit native，清单为 `moon.mod` / `moon.pkg`，脚本为 `.mbtx`。固定工具链为 **0.10.15+943464bfa**，需要平台 C 工具链；安装和构建方法见 [工具链](docs/toolchain.md)。首次准备依赖与检查工具链：

```sh
moon run --target native scripts/check-toolchain.mbtx
moon update
```

`moon.mod` 的模块依赖与独立 `.mbtx` 的脚本依赖分别管理；不要把版本差异当成错误而全局替换。

## 按行为选择检查

修改一个包时，先运行该包的测试与类型检查。例如改动文件选择：

```sh
moon test src/selection --target native
moon check src/selection --target native
```

回归用例应独立表达输入、预期行为和失败条件。涉及取消、输出提交或输入限额时，检查相应错误路径，不用修改快照或放宽断言掩盖失败。

涉及 CLI 或跨模块契约时，选择对应脚本，避免为局部改动运行所有套件：

| 行为 | 定点入口 |
| --- | --- |
| stdin 文件列表与 stdout | `scripts/input-list-test.mbtx` |
| token 统计与机器报告 | `scripts/token-reports-test.mbtx` |
| 四格式与元数据 | `scripts/output-formats-test.mbtx` |
| 模板与全文例外 | `scripts/context-customization-test.mbtx` |
| 章节、行号和路径显示 | `scripts/display-controls-test.mbtx` |
| 分卷预算与目录发布 | `scripts/volume-cli-test.mbtx` |
| MCP 协议与缓存 | `scripts/mcp-test.mbtx` |

脚本需要当前 CLI、词表及各自参数；运行前阅读对应脚本的用法或 CI 中的调用，日志写入新的临时目录。只有相关行为需要时才运行跨模块、安装、分发或性能检查；文档改动核对 diff、链接与真实字段即可。

提交前格式化改动的 MoonBit 文件，并为改动的公开接口重新生成 `.mbti`，例如：

```sh
moon fmt src/selection
moon info src/selection --target native
```

复核生成接口是否正是预期变更；不要手改生成的 `.mbti`。对改动路径可再运行 `moon fmt src/selection --check`。完整跨平台检查入口见 [CI](.github/workflows/ci.yml)，本地只报告实际执行的命令、结果和未覆盖项。

## 资源、依赖与许可

解析器 C 源码、词表和 Unicode 数据随项目提供，运行不在线下载。变更这些文件时同步记录固定版本、提交或散列、来源、许可证及本地修改：

- [解析器来源](src/compression/THIRD_PARTY.md)、[来源与 ABI](LICENSES/tree-sitter-sources.md) 记录 runtime、各语言 grammar 和生成方式。MoonBit grammar 有本地修改，不能用上游文件直接覆盖。
- [分词说明](docs/tokenization.md) 记录词表、Unicode 版本与 SHA-256；资源变更须同步加载校验、安装和分发验证。
- [LICENSES](LICENSES/) 保留完整告知；运行依赖、分词资源和扫描器各有来源说明。分发产物需要携带这些许可证。

## 提交变更

保持改动围绕一个行为，更新受影响的使用说明和 [Unreleased](CHANGELOG.md#unreleased)。提交说明写明用途、行为差异与实际验证；提交前检查暂存 diff，确保没有真实秘密、临时日志或无关产物。推送、发布与仓库权限变更由维护者按相应授权处理。
