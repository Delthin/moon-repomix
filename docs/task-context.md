# 按任务选择预算内上下文

v0.5.0 起提供 `plan_task_context` SDK 与同名 MCP 工具。调用方列出必选文件和带优先级的候选文件，获得一份不超过 `maxTokens` 的完整上下文，以及独立的选择审计。

多个任务共享同一份上下文，相同路径只读取、纳入一次。调用方应先为 system 消息、工具定义、会话历史、审计和预计模型输出预留空间，再设置上下文预算。计数器固定为 `o200k_base`；其他模型的实际计数可能不同。

## SDK 调用

在 `async fn` 中使用已有 `Options` 和可复用的 `Runtime`：

```moonbit
let spec = @repomix.TaskContextSpec::from_json({
  "maxTokens": 12000,
  "tasks": [{
    "id": "review-config",
    "required": [{ "path": "src/config/types.mbt", "mode": "full" }],
    "optional": [
      { "path": "src/config/cli.mbt", "mode": "either", "priority": 90 },
      { "path": "src/config/config_test.mbt", "mode": "full", "priority": 70 },
    ],
  }],
})
let result = @repomix.plan_task_context(options, runtime, spec)
// result.text 仅在 complete / with_omissions 时包含可交付正文。
// result.tokens / bytes 是该完整字符串的精确成本。
// result.audit_text 单独返回；audit_tokens / audit_bytes 单独计数。
```

SDK 返回内存结果，不写文件。现有 `pack` 的输出后预算检查及 `pack_volumes` 的逐卷预算行为保持不变。MCP 的资源读取、主机上限与缓存规则见 [MCP 指南](mcp.md)。

## 参数与选择顺序

| 字段 | 规则 |
| --- | --- |
| `maxTokens` | 必填，1–2,147,483,647 的整数；MCP 还受启动时的 `max_tokens` 限制 |
| `tasks` | 1–16 个任务；`id` 唯一、非空、不含 NUL，最多 64 UTF-8 bytes |
| `required` | 可省略；条目为 `path` 与 `mode: full / skeleton` |
| `optional` | 可省略；另支持 `mode: either` 和 `priority: 0–100`，默认优先级 0 |
| `maxReadBytes` | 1–16,777,216，默认 16 MiB；与 host 总读取上限取较小值 |
| `maxAttempts` | 2–256，默认 256；包含必选文档计数和最后一次核对 |

所有层级拒绝未知字段。单个 required/optional 数组最多 128 项，所有任务合并后最多 128 个不同路径；每路径最多 4,096 UTF-8 bytes，整个规范化 JSON 描述最多 1 MiB。

路径使用根目录相对的 `/` 拼写，禁止绝对路径、空组件、`.`、`..`、反斜线、冒号与 NUL；通配符字符按文件名原样匹配，不展开。host 的 include、ignore、`file_paths`、输出排除、单文件及总读取限制继续生效。

1. 合并相同路径：任一任务将其设为必选，它就成为全局必选；表示强度为 `full > skeleton > either`；可选优先级取最高值。host `keep_full_patterns` 始终优先。
2. 读取并扫描所有必选内容，再渲染完整文档。必选内容不可用或整文超限时立即返回失败。
3. 按优先级从高到低、相同优先级按路径 UTF-8 字节序尝试可选文件。`either` 先试全文，超限后再试骨架；单个已读快照不会因换表示重新读取或扫描。
4. 每次尝试都计数完整渲染字符串，包含任务引用、目录、模板、行号和启用的元数据。拒绝本次候选后继续尝试后续候选；不依赖单文件 token 相加或 BPE 单调性。
5. 返回前再计数最终字符串。候选选择是确定性的有界贪心，不保证全局最优覆盖。

`skeleton` 复用已有 AST 压缩；不支持的语言、解析失败或没有单文件 token 收益时保留全文，并在审计中记录实际表示与回退原因。全文回退仍须满足完整文档预算。任务 mode 决定逐文件表示，不依赖 host `compress` 开关。

当前入口只处理本地文件，不接受远程来源、Git 附加段、自动分卷、原 `token_budget` 或关闭文件正文展示的 host 配置。这些配置产生 `ConfigurationError`。host 模板和四种现有输出格式均可使用。

## 结果与安全边界

| `status` | 含义 |
| --- | --- |
| `complete` | 全部候选已纳入，所有必选要求满足 |
| `with_omissions` | 必选要求满足，可选内容因过滤、安全、预算或工作上限而省略 |
| `required_unavailable` | 必选文件被排除、缺失、无法读取，或必选阶段触及读取上限；无正文 |
| `required_over_budget` | 必选内容连同模板和包装超限；无正文，审计保留该次整文 token 数 |

空的必选集合仍有模板与任务概览成本，也可能 `required_over_budget`。失败结果的 `tokens` 和 `bytes` 为 0；过预算的测量值在 `audit.requiredDocumentTokens` 中。

审计逐路径列出是否选择、原因、是否完成安全扫描、实际表示和回退原因，逐任务列出必选满足情况；还记录实际原始读取 bytes、尝试读取数和整文计数次数。它不包含源码正文、密钥匹配文本或绝对根目录。审计中的路径与任务 ID 来自请求，调用方也应按自身隐私要求处理。

正文扫描先于压缩。默认命中秘密的必选文件使整个计划失败，可选文件则被排除；任务描述或模板命中秘密时抛出安全错误。主机显式关闭扫描时，结果标为 `security: disabled`。扫描是启发式检测，见 [安全边界](../SECURITY.md)。

读取器为判断是否超过限额最多额外探测一个字节，因此 `readBytes` 可能等于有效上限加 1。可选阶段触及读取/尝试上限后停止扩展；尚未评估的候选标为 `not_evaluated_read_limit` 或 `not_evaluated_attempt_limit`，不会标为已扫描。安全的已选文档经最后核对后仍可返回。

取消在读取和规划步骤之间传播；单次同步扫描、AST 与整文编码不能被步骤间轮询抢占。工作上限不是 RSS 配额，也不计调用方的模型消息或 MCP 外层包装。
