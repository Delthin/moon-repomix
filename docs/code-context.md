# 按实现读取与补读代码

`read_code_context` 用于需要理解具体行为的任务：先读取完整函数实现，遇到缺失的函数、常量或文件再补读。它按调用者给出的路径和符号工作，不解释自然语言任务，也不自动证明材料足以回答问题。

v0.5.0 起提供 SDK 与 MCP 入口。

## 选择读取内容

每个请求包含 1 至 32 个不同文件。每个文件在以下方式中选择一种：

```json
{
  "maxTokens": 4000,
  "requests": [
    {"path": "lib/response.js", "symbols": ["res.render"]},
    {"path": "lib/application.js", "outline": true}
  ]
}
```

| 字段 | 行为 |
| --- | --- |
| `symbols` | 1 至 16 个不同名称，读取完整定义所在行。优先匹配限定名，例如 `res.render`、`Session.prepare_request`；简单名称必须唯一 |
| `ranges` | 1 至 16 个 `{startLine,endLine}`，从 1 开始、两端包含。合并重叠及相邻范围，保留原始 Unicode、CRLF 与行尾；越界失败 |
| `full: true` | 读取完整文件，可用于不支持的语言或无法解析的源文件 |
| `outline: true` | 只返回名称、限定名与行范围，用于定位，不返回实现 |
| `includeDependencies: true` | 仅用于符号读取，递归添加同文件中唯一匹配的词法引用定义及常量，最多 64 个定义；默认关闭 |

符号和 outline 支持 JavaScript（含 JSX）、TypeScript、TSX、Python。索引单文件上限为 8 MiB，解析超时为 200 ms，最多 4,096 个定义、每个定义 256 个词法引用；遍历另有节点、深度和总引用配额。超过索引限额返回 `resource-limit`，不会返回部分目录。完整限额及原生内存边界见 [索引说明](../src/compression/README.md#complete-definition-symbol-index)。名称重复时返回 `ambiguous-symbol` 和最多八个候选，不擅自选第一个。找不到名称返回 `symbol-not-found`。解析、资源或语言限制会明确报出；需要时调用者可另行选择 ranges 或 full。

词法依赖不是语义调用图。动态调用、别名、跨文件导入和局部遮蔽都可能影响解析；自动展开可能多带代码，也可能缺少行为依据。审计会列出同文件有多个候选的依赖，最多 32 个名称，并标记提示是否截短；源代码本身不会因此被截断。需要进一步判断时，指定正确文件及限定名补读。

符号读取会比较当前文件的完整正文与范围对象的精确 token 成本；全文对象更小时直接返回全文。显式 ranges 不扩大读取结果。多文件最终预算始终以整份 JSON 再计数，不假定各片段成本可加，也不承诺求出全局最小上下文。

## SDK

```mbt
let spec = @repomix.CodeContextSpec::from_json({
  "maxTokens": 4000,
  "requests": [
    { "path": "src/session.py", "symbols": ["Session.prepare_request"] },
  ],
})
let plan = @repomix.read_code_context(options, runtime, spec)
match plan.text {
  Some(text) => /* 把精确计数的 JSON 交给模型 */ ignore(text)
  None => /* 查看不含源码正文的审计 */ ignore(plan.audit)
}
```

以上代码在已导入根 SDK 为 `@repomix`、已有 `options` 和 `runtime` 的异步函数中运行。

`CodeContextSpec::from_json` 校验严格字段、路径、数量、类型和最多 64 KiB 的规范化请求 JSON。非法描述抛出 `InvalidCodeSpec`，不读文件。路径必须是规范根相对字面路径，最多 4,096 UTF-8 bytes；符号最多 256 UTF-8 bytes。禁止绝对路径、空段、`.`、`..`、反斜杠、冒号和 NUL。

`CodeContextPlan` 返回：

- `status`：`complete`、`unavailable` 或 `over_budget`。
- `text`：成功时为完整 JSON；任一要求不可提供或整份超预算时为 `None`，不交付部分源码。
- `tokens`、`bytes`：实际交付 JSON 的精确计量；失败为 0。
- `required_tokens`：仅超预算时提供所需 token 数。
- `audit`：请求结果、读入字节、尝试次数、安全状态、匹配定义及依赖歧义。成功时同一审计已嵌入 `text`，不需要再送一份给模型。
- `security`：沿用完整文件扫描的 `Passed` / `Excluded` / `Disabled`。

JSON 使用固定 `schemaVersion: 1`，包含 `files`、`audit`、模板及不可信数据标识。`maxTokens` 限制完整 JSON，包括定位元数据和审计；不包括调用参数、协议包装、失败诊断或模型已有消息。SDK 的每次调用独立计量，累计额度由 SDK 调用方管理。

`maxReadBytes` 默认且最高 16 MiB，与主机实际源码读取限额取较小值；EOF/超额探测最多额外读一个字节。读取按请求顺序进行，已知有被排除的路径时不打开任何源码；执行中一项失败后不再读取后续文件。

## MCP 的有界补读会话

启动已有只读服务，例如：

```sh
moon-repomix /path/to/repository --mcp --mcp-max-tokens 8000
```

调用工具 `read_code_context`，首次参数：

```json
{
  "maxTokens": 6000,
  "requests": [{"path": "lib/response.js", "symbols": ["res.render"]}]
}
```

成功摘要返回 `runId`、本次 `tokens`、`sessionTokens`、`remainingTokens`、轮次和一个 `code.json` 资源 URI。先用 `resources/read` 读取实际 URI。若发现 `app.render` 的实现缺失，再调用同一个工具：

```json
{
  "continueFrom": "上次成功返回的 runId",
  "requests": [
    {"path": "lib/application.js", "symbols": ["app.render"], "includeDependencies": true}
  ]
}
```

- 新会话的 `maxTokens` 默认使用主机 cap，只能降低。续读必须省略 `maxTokens`，沿用剩余额度。
- 一次会话最多三次成功读取，即首次读取加两次补读；每轮按完整 JSON 精确计费，重复返回的正文也再次计费。
- 成功生成一个资源，原子替换旧资源并更新累计用量。旧 URI 失效，客户端需要在补读前取得上一轮材料。
- 失败、超预算或提交前取消不替换资源、不消耗成功轮次及会话额度。失败诊断不在累计正文 cap 内，客户端需为它和协议消息另留额度。
- 用旧 `runId`、已释放资源，或已被其他成功任务/打包替换的会话续读，返回 `StaleCodeSession`。额度用尽返回 `CodeBudgetExhausted`；三轮后返回 `CodeRoundLimit`。
- 请求更大的新会话是显式重新开始，不会让旧会话自动扩容。此限制约束一次读取会话，不是进程终身 token 配额。
- 资源最多 4 MiB，并受主机 `--mcp-max-output-bytes` 限制。忙时返回 `Busy`。

## 授权与错误

选择、include/ignore、白名单、符号链接与安全扫描沿用主机授权。文件必须先通过**完整正文**扫描，才生成片段或符号目录；不能用“只读安全函数”绕过文件别处的敏感内容。请求中的路径和名称、主机模板也经过扫描。

该入口固定返回 JSON，由请求选择内容，与 pack 的 style、压缩、全文例外和行号展示设置独立；header 和 instruction 文本仍按主机配置处理。远程源、Git diff/log、分卷配置、单份 token 预算、关闭文件正文输出和非 `o200k_base` 编码与此入口冲突，返回配置错误。

文件仍可能在不同读取轮次间改变；每轮重新检查和读取，不是仓库事务快照。客户端应结合返回的实现与行范围判断是否需要重新获取相关内容。

已有 `plan_task_context` 适合调用者已知必选文件和候选优先级的共享文件预算；本工具适合具体实现与依赖补读。两者都不以“预算内交付”承诺语义充分性。
