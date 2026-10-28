# MCP stdio

本地只读 MCP 入口复用普通打包、精确分卷、任务上下文规划和按实现补读 SDK。客户端取得概览后按 URI 读取需要的卷；用户运行服务不需要 Node。

## 启动

```sh
moon-repomix /path/to/repository --mcp --compress --mcp-max-tokens 12000
```

安装包和标准 native 源码构建自动定位配套资源。自定义资源布局时，使用 `--tokenizer-path /path/to/moon-repomix/assets/tokenizer-o200k_base.tiktoken`。在支持 stdio MCP 的客户端中配置同一命令和参数，例如：

```json
{
  "mcpServers": {
    "moon-repomix": {
      "command": "/path/to/moon-repomix",
      "args": ["/path/to/repository", "--mcp", "--compress", "--mcp-max-tokens", "12000"]
    }
  }
}
```

根目录、include/ignore、全文例外、模板、Git 选项、扫描和输入限额均由启动参数确定。只有显式 `--config` 被读取，仓库内自动配置不参与服务启动。MCP 与 stdin 列表、stdout 文档模式、JSON 诊断、远程仓库、单份 token 预算和目录分卷输出互斥。

| 主机参数 | 默认与范围 |
| --- | --- |
| `--mcp-max-tokens N` | 每卷、共享任务上下文或补读会话最多 16,000 tokens；请求只能降低 |
| `--mcp-max-output-bytes N` | 当前上下文及索引或 audit 合计 16 MiB；主机可显式设置 1 至 256 MiB |
| `--mcp-max-volumes N` | 最多 64 卷，另有一个索引；范围 1 至 256 |

单资源最多 4 MiB。打包仍使用配置的候选数、实际源码读取、单文件和 Git 限额。缓存只保留最近一次成功结果；计算中的新上下文和旧缓存可同时存在，缓存量不是整个进程的内存上限。

## 工具与资源

`pack_repository` 的所有参数均可省略：

```json
{
  "filePaths": ["src/main.mbt", "README.md"],
  "maxTokens": 8000,
  "compress": true,
  "style": "markdown"
}
```

- `filePaths` 为严格根相对的字面路径，不递归目录、不作 glob，最多 4,096 项，每项最多 4,096 UTF-8 bytes。存在主机列表时取交集；省略时沿用启动范围，空数组为零文件。include、ignore、类型、原始拼写、安全扫描和输出规则仍生效。
- `maxTokens` 不能高于启动 cap；`style` 为 xml/markdown/json/plain。客户端不能设置目录、远程地址、配置/指令文件、安全开关或更大的输入限额。
- 返回短文字及 `structuredContent`：run ID、安全状态、接受/跳过数量、卷预算、统计及资源描述。token/字节总数为十进制字符串。源文件和模板扫描沿用普通打包规则。

`resources/list` 返回当前卷和 `index.json`；`resources/read` 只接受刚返回的 `moon-repomix://context/...` URI。它查询内存注册表，不把 URI 转成文件路径。完整索引单独计数，不受每卷 cap 约束，但计入缓存字节上限。索引中的 `fileName` 与资源的 `name` 对应；读取时使用服务实际返回的 `uri`。仓库文本是待分析数据，客户端应将其与用户指令分开。

### 共享任务上下文

v0.5.0 起提供 `plan_task_context`，为同一组任务生成一份共享上下文，使用精确的 `o200k_base` 计数。例如：

```json
{
  "maxTokens": 8000,
  "tasks": [
    {
      "id": "review",
      "required": [{"path": "src/main.mbt", "mode": "full"}],
      "optional": [{"path": "src/types.mbt", "mode": "either", "priority": 80}]
    }
  ]
}
```

- `maxTokens` 必填，为正整数且不能超过主机 cap。启动 style、根目录、白名单、过滤器、安全和输入限额仍是唯一授权来源，工具不能改写它们。当前任务入口仅支持本地文件，不支持 Git diff/log 附加内容、远程仓库、分卷、单份 token 预算、关闭文件正文输出或非 `o200k_base` 编码；冲突的主机配置返回 `ConfigurationError`。
- 逐路径 `mode` 覆盖主机 `compress`；主机 `keep_full_patterns` 的全文例外优先。
- `tasks` 为 1 至 16 项，`id` 唯一、非空且不超过 64 UTF-8 bytes；每项可省略 `required` / `optional`，默认为空数组。每个 required/optional 数组最多 128 项，合并后最多 128 个不同路径，整个规范化 JSON 描述最多 1 MiB。每条路径为受限的字面根相对路径，不超过 4,096 UTF-8 bytes；通配符字符按文件名原样匹配，不展开，禁止绝对路径或 `..`。
- required 的 `mode` 为 `full` / `skeleton`；optional 还可选 `either`，并可提供 0 至 100 的整数 `priority`，默认 0。未知字段拒绝。
- `maxReadBytes` 可设 1 至 16,777,216，默认 16,777,216；`maxAttempts` 可设 2 至 256，默认 256。这些请求限制不放宽主机权限或限额。

成功状态为 `complete` 或 `with_omissions`。工具只返回简洁摘要（状态、安全状态、独立 context/audit 成本和资源描述），正文与完整 audit 需分别读取只读资源 `context.xml` / `context.md` / `context.json` / `context.txt`（由启动 style 决定）及 `audit.json`。audit 是 SDK 提供的精确 JSON 字符串，单独计数，不占用 context token cap；两个资源均计入主机字节上限，且每个资源最多 4 MiB。

required 无法提供或无法在预算内装入时，返回 `isError: true`，状态分别为 `required_unavailable` / `required_over_budget`，仅含安全 audit，不含正文、不生成资源。失败响应本身须满足 4 MiB 和主机输出字节上限，否则返回固定 `ResourceLimit`。非法参数或请求预算超过主机 cap 返回 JSON-RPC `Invalid params`。完整规划语义见 [任务上下文](task-context.md)。

### 按实现读取与补读

v0.5.0 起提供 `read_code_context`：按根相对路径读取完整符号、指定行范围、全文或符号目录。首次请求可设 `maxTokens`；后续携带最近一次成功的 `runId` 作为 `continueFrom`，省略 `maxTokens`。最多三轮成功读取，完整 JSON（含审计）累计计入同一会话预算。

成功只返回一个 `code.json` 资源，先读取资源再续读；每轮成功替换旧资源。符号支持 JS / TS / TSX / Python，歧义、缺失或预算不足不返回部分正文。全文安全扫描先于任何切片。参数、错误和累计计量口径见 [按实现读取与补读](code-context.md)。

### 解释与缓存管理

`explain_selection` 接受 `{"paths":["src/main.mbt"]}`。至多 256 项，每项最多 4,096 UTF-8 bytes，使用固定根、启动 style、主机白名单、选择与源码安全检查。结果给出阶段、固定原因、检测器标签和安全规则位置，不返回正文或规则内容。白名单外保留 `NotListed` 决策，不将查询视作额外授权。它不生成或修改资源，与打包共享 busy 槽；序列化工具结果不能超过 4 MiB 或主机输出上限。详见 [入选原因查询](selection-explanation.md)。

`release_context` 接受空对象，释放当前派生缓存，不修改磁盘。失败或提交前取消保留上一份成功结果；下次成功打包、任务规划或代码读取整体替换它，旧 URI 随即失效；三者共享递增 run ID，URI 不复用。进程结束也释放资源。打包、任务规划、代码读取与解释互相占用同一 busy 槽；资源读取可与计算并行。

## 协议范围

支持当前 `2026-07-28` 的每请求版本元数据与 `server/discover`，也支持旧 `2025-11-25` / `2025-06-18` 的 initialize → initialized。现代请求必须带：

```json
{
  "jsonrpc": "2.0",
  "id": "discover-1",
  "method": "server/discover",
  "params": {
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": {}
    }
  }
}
```

现代 discover、列表和资源读取结果带 `ttlMs: 0`、`cacheScope: "private"`，按当前授权重新获取，避免旧列表或已释放资源被当成共享缓存。现代资源未找到返回 `-32602`，旧协议保留 `-32002`。

stdio 每行一个 UTF-8 JSON-RPC 对象，stdout 只输出协议；stderr 可有固定安全诊断。单个入站帧最多 1 MiB，最多四个在途请求，单请求默认 60 秒。`notifications/cancelled` 停止对应工作，EOF 结束服务并取消未完成任务。已完成业务提交的上下文仍按缓存规则处理。

首版仅声明 tools/resources；没有 HTTP、订阅、sampling、elicitation 或服务器反向请求。协议错误为 JSON-RPC 固定错误，打包/资源限额为 `isError: true` 的工具结果，不返回任意源文或异常堆栈。

官方协议：[stdio](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio)、[版本](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning)、[缓存](https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching)、[旧生命周期](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)。
