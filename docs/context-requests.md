# 在各入口复用上下文请求

当前源码为任务规划和代码补读提供相同的版本化请求，供 SDK、CLI、MCP 和浏览器工作台复用。这些新增入口需从当前源码构建；v0.6.0 安装包已有任务与补读工作台，尚不包含请求配置导入导出和新的 CLI 入口。

## 请求格式

将下面内容保存为 `request.json`：

```json
{
  "schemaVersion": 1,
  "operation": "read_code_context",
  "spec": {
    "maxTokens": 8000,
    "requests": [
      { "path": "src/lib.mbt", "symbols": ["greet"], "includeDependencies": true }
    ]
  }
}
```

`operation` 接受 `read_code_context` 或 `plan_task_context`；`spec` 分别使用完整的[代码读取规格](code-context.md)或[任务规格](task-context.md)。必选、可选、优先级、依赖、范围和审计的含义保持一致。顶层字段严格校验，规范化 JSON 最多 64 KiB。

请求不携带工作区、远程地址、源代码或主机权限。路径相对各入口的授权根解释；迁移请求配置不会授权另一个目录。不同主机可以施加更小的文件、读取、输出或 token 上限。

## CLI

```sh
# 在授权目录执行一次，响应 JSON 写到 stdout
moon-repomix ./project --context-request request.json

# 响应原子写入文件
moon-repomix ./project --context-request request.json -o response.json

# 同一 Native 进程内按 JSONL 串行处理请求，支持有界续读
moon-repomix ./project --context-stdio
```

响应包含完整正文字符串、精确计量和审计；`response.json` 是响应封装，不是仅含源码的正文。详细输出、互斥参数和流式会话用法见 [CLI 上下文读取](context-cli.md)。普通目录打包继续使用原有 CLI 参数。

## SDK

`ContextRequest::from_json` 校验请求并保存不可变副本；`spec_json()` 和 `to_json()` 返回新副本。按 `request.operation` 取得 `Task` 或 `Code`，将 `spec_json()` 交给已有的 `TaskContextSpec::from_json` 或 `CodeContextSpec::from_json`，再调用 `plan_task_context` 或 `read_code_context`。SDK 不自动执行请求或授予文件访问权限。

`CodeContextSession` 统一累计预算和轮数：首轮通过 `new(max_tokens)` 建立状态，后续通过 `request(spec)` 注入剩余预算。用 `advance(plan)` 取得候选状态；失败计划不扣额度。调用方完成自己的输出大小检查及提交后，再保存候选状态。会话 ID、资源地址和目录绑定由入口管理，不由预算对象管理。

## MCP

将相同的请求 JSON 直接作为 `execute_context_request` 工具的 `arguments`。返回结果、资源 URI、主机 cap 和失败保留规则与已有 `plan_task_context`、`read_code_context` 工具一致；旧工具继续可用。取得资源的正文后再续读。

`context_capabilities` 工具接受空对象，返回共享能力及当前主机限额。SDK 的 `context_capabilities()` 和 HTTP 的 `GET /api/session` 中的 `context` 提供相同的共享能力信息，包括符号索引实际支持的后缀。

## 浏览器工作台与 HTTP

工作方式选择任务预算或代码补读，点击“保存配置”下载新请求。配置保留完整规格，不含目录、正文和会话 ID。“导入配置”先由 Native 校验，沿用页面当前的授权目录；点击生成后才读取仓库。高级规格会进入高级 JSON 编辑器。

工作台复制的请求 JSON 也使用上述格式。HTTP 执行时在外层绑定目录：

```json
{
  "directory": ".",
  "request": {
    "schemaVersion": 1,
    "operation": "read_code_context",
    "spec": { "maxTokens": 8000, "requests": [{ "path": "src/lib.mbt", "outline": true }] }
  }
}
```

向 `POST /api/context-request` 发送此对象；认证头、Host、Origin、Content-Type、请求体和输出限额与既有工作台接口相同。`POST /api/context-request/validate` 只接受内层请求，返回校验后的配置，不读取仓库或修改会话。原有 `/api/task-context` 和 `/api/code-context` 保持兼容。

## 预算与续读

新代码会话的 `spec.maxTokens` 固定累计正文 cap。续读在顶层传入最近一次成功响应的 ID：

```json
{
  "schemaVersion": 1,
  "operation": "read_code_context",
  "continueFrom": "最近成功的会话 ID",
  "spec": { "requests": [{ "path": "src/lib.mbt", "full": true }] }
}
```

续读不能带 `maxTokens`，最多成功三轮；失败不扣额度。每次成功使用新 ID，旧 ID 失效。CLI JSONL、MCP 和 HTTP 的会话相互独立，不能跨进程或入口迁移 ID。工作台保存配置时始终生成不含 ID 的新请求，导入不接受续读 ID。

所有入口先扫描完整原文件，再生成所请求的内容。代码读取审计嵌入正文，已计入正文预算；任务审计独立计数。最终 cap 依据完整交付正文，不把逐文件 token 数相加，也不把传输封装、模型消息计入正文 cap。
