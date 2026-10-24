# 错误与恢复

当前源码 CLI 正常完成退出 **0**；查询路径被排除也可正常退出 0。捕获的配置、读取、资源、分卷、输出和取消错误退出 **1**。普通 `--token-budget` 超限同样退出 1，但完整文档已经输出，这与打包失败不同。

自动化使用 `--report-json`，先检查退出码、`status` 和 `publication`。报告格式见 [机器报告](reports.md)。以下是固定 CLI 类别；SDK 错误名不总与 CLI 相同，例如 SDK 的 `ContextSecurityFinding`、`InputLimitExceeded` 对应 CLI 的 `ContextSecurityError`、`InputLimitError`。

| CLI 类别 | 用户可采取的操作 |
| --- | --- |
| `ConfigurationError` | 核对参数拼写、JSON 字段和互斥项；配置拒绝未知字段。确认运行版本支持新增选项。 |
| `InputError` | 检查 stdin 列表编码、长度和字面相对路径；使用 `git ls-files -z` 配合 `--stdin0` 处理特殊文件名。 |
| `SelectionError` | 检查输入根、字面路径、glob 和 ignore 文件；当前源码可用 `--explain-path` 定点查询。 |
| `ScanError` | 检查输入目录与普通文件是否可读，确认执行期间文件未移走；缩小输入以定位失败文件。 |
| `InputLimitError` | 根据 `error.field` 缩小候选或读取量；核准资源后显式调整 `--max-files` 或 `--max-total-size`。0 不是无限。 |
| `ContextTextError` | 根据 `error.field` 检查 header/instruction：有效 UTF-8、无 NUL、每段最多 1 MiB；检查指令是可读普通文件及 XML 可表示性。 |
| `ContextSecurityError` | 清除模板中的敏感内容或改用合成值；模板命中停止整个打包，不只是隐藏模板。 |
| `GitError` | 确认系统 Git 可用、目标为可读仓库；检查所需历史及 Git 文本上限。仅需文件时移除 diff/log 参数。 |
| `RemoteError` | 核对公开 HTTPS 仓库 URL、引用、网络与 Git；需要认证的仓库改为自行检出后本地输入。 |
| `ResourceError` | 恢复词表及配套 Unicode 数据，保留安装布局；用 `--tokenizer-path` 指向校验通过的词表。 |
| `SplitError` | 检查 cap 为正整数；`TemplateTooLarge` 减少模板，`UnitTooLarge` 缩小输入、使用骨架或核准更大 cap。不会截断文件凑预算。 |
| `OutputError` | 检查输出权限和空间；分卷目标必须不存在，父目录已存在且稳定。先检查是否已提交输出。 |
| `Cancelled` | 检查 `publication` 与目标，确认是否已完成发布；使用新目标重新执行，而非假定取消已回滚。 |
| `OperationError` | 保存版本、commit、OS、脱敏命令和固定类别，以合成数据缩小复现后提交 issue。 |

模板类别在 JSON 中把受影响配置键放入 `error.field`；限额放入十进制字符串 `error.limit`。人类诊断可能带字段和细节，机器解析应使用固定 JSON 类别，不匹配动态错误文本。

## 跳过与失败的区别

单文件过大、二进制、无效 UTF-8、链接或密钥命中等可作为跳过记录，而不停止整个打包；命中安全规则的 Git 补丁或提交也整项排除。检查 `skipped`、扫描摘要和查询结果，不能仅凭退出 0 推断所有输入都已包含。候选数和累计原始读取超限则停止整个操作，不能返回看似完整的部分结果。

不支持的压缩语言或没有精确 token 收益时保留全文，不属于运行错误。当前源码的排除原因与查询范围见 [入选原因](selection-explanation.md)。

## 输出是否已经存在

- `not_started`：尚未尝试发布。普通文件旧输出保留，分卷不会发布部分目录。
- `unknown`：已开始输出但提交状态不能确认；stdout 可能只有部分内容。检查目标后再决定重跑。
- `committed`：完整输出已提交，后续取消或诊断失败不会删除已发布分卷目录。

普通文件通过同父临时文件原子替换；分卷通过同父 staging 原子、不覆盖地发布新目录。目标父目录需稳定且受调用方控制。stderr 写入本身失败时，报告可能无法送达；非零退出且没有报告也应先检查输出。发布细节与安全范围见 [分卷](partition.md) 和 [SECURITY](../SECURITY.md)。
