# 机器可读运行报告

当前源码的 `--report-json` 将诊断通道切换为一份紧凑 JSON 和末尾 LF，位置是 stderr。stdout 仍只承载文档；分卷写目录时 stdout 为空。该开关优先于 `--quiet`，不改变打包、扫描、退出码或正文格式。显式 `--no-report-json` 恢复人类诊断。帮助和版本查询保持各自的 stdout 格式。

每份报告带 `schemaVersion: 1`、`status`、`exitCode`。成功打包还包含 `operation`、`publication`、`style`、`security`、`counts`、`output`、`limits`、`tokens` 和 `bytes`。`counts.acceptedFiles` 是扫描后接受的文件数，`skippedEntries` 包括目录和非文件条目；它们不是输入资源限额的计数器。`limits.maxFiles` 与十进制字符串 `maxTotalSize` 表示配置上限，不冒充实际使用量。token 和字节计量使用十进制字符串，避免 JSON 消费者丢失 64 位精度。

单份文档示例：

```json
{"schemaVersion":1,"status":"ok","operation":"pack","publication":"committed","exitCode":0,"style":"markdown","security":{"status":"passed","enabled":true,"findings":0},"counts":{"acceptedFiles":2,"skippedEntries":0},"output":{"kind":"stdout","documents":1},"limits":{"maxFiles":20000,"maxTotalSize":"209715200"},"tokens":{"documents":"123","index":"0","total":"123","limit":null,"exceeded":false},"bytes":{"documents":"456","index":"0","total":"456"}}
```

`tokens.documents` 为最终完整文档计数；分卷时为各独立卷计数之和，`index` 单列最终索引计数，`total` 为两者之和。分卷报告另含 `volumes` 数组，每项给出 `id`、`fileName`、token/字节字符串及文件、章节数量。`output.indexFile` 为 `index.json`。

普通 `--token-budget` 超限时仍写出完整文档，报告 `status: "over_budget"`、`tokens.exceeded: true`、退出码 1。安全扫描主动关闭时 `security.status` 为 `disabled`，不会另外混入警告文本；`excluded` 表示已有命中被排除。报告不包含命中内容、模板、原文或主机绝对路径。

失败示例：

```json
{"schemaVersion":1,"status":"error","exitCode":1,"publication":"not_started","error":{"category":"ContextSecurityError","field":"output.headerText","limit":null}}
```

输入限额失败使用 `InputLimitError`，`field` 为 `input.maxFiles` 或 `input.maxTotalSize`，`limit` 为对应上限。`error.category` 是固定错误类别；`field` 只给出受影响的配置字段，`limit` 在适用时给出十进制限制。未知或不适用的值为 JSON null；失败报告不伪造未得到的处理计数。解析其他参数失败时，已出现的有效报告开关仍尽量保留 JSON 诊断。

## 入选原因操作

`--explain-path` 的 stdout 是独立的 requested-paths 决策 JSON，而不是上下文文档；同时使用 `--report-json` 时，stderr 返回同一操作的数量、来源配额和安全摘要，省略 `paths` 明细。`operation` 为 `explain_selection`，`scope` 为 `requested-paths`；没有未执行的 token 或文件发布计数。路径都完成查询即可退出 0，`excluded` 不是运行失败；非法查询、规则错误、候选/读取限额失败则退出非零，具体范围见 [查询说明](selection-explanation.md)。

## 提交点与失败处理

`publication` 是本次运行的输出状态：

- `not_started`：尚未尝试发布正文或目录。
- `unknown`：已经开始输出，异常使调用方不能确认提交状态；stdout 可能只有部分内容。
- `committed`：完整结果已写出；随后诊断通道失败也不会回滚结果。

分卷目录一旦原子发布就保留，不因后续取消或报告写入失败而删除。发布成功后的报告在取消保护内写入；诊断本身的 I/O 仍可能失败并导致非零退出。若 stderr 已不可写，无法保证还能收到失败 JSON。遇到 `unknown` 或非零退出应检查输出位置，不能假定可覆盖后安全重试。目录发布只接受不存在的目标，并要求已有父目录由调用方控制、执行期间保持稳定，具体边界见 [分卷](partition.md)。
