# CLI 任务规划与代码补读

当前源码支持从文件执行一次上下文请求，或在同一进程内通过 JSONL 连续读取。两种入口使用已有 Root 规格，不增加仓库权限。可复用格式及其他入口见[统一请求](context-requests.md)。

```sh
moon-repomix ./project --context-request request.json
moon-repomix ./project --context-request request.json -o response.json
moon-repomix ./project --context-stdio
```

默认响应写 stdout，即使仓库配置指定了普通打包输出文件。文件模式支持显式 `-o FILE` 原子替换或 `-o -`；stdio 模式不接受 `-o`，包括 `-o -`。请求文件、显式输出及配置路径相对启动目录，规格内路径相对授权仓库根。

## 请求

顶层仅接受 `schemaVersion`、`operation`、`spec` 和代码续读使用的 `continueFrom`。例如任务规划：

```json
{
  "schemaVersion": 1,
  "operation": "plan_task_context",
  "spec": {
    "maxTokens": 6000,
    "tasks": [{
      "id": "implementation",
      "required": [{"path": "src/main.mbt", "mode": "full"}],
      "optional": [{"path": "src/util.mbt", "mode": "either", "priority": 80}]
    }]
  }
}
```

首次代码读取：

```json
{
  "schemaVersion": 1,
  "operation": "read_code_context",
  "spec": {
    "maxTokens": 6000,
    "requests": [{"path": "src/main.mbt", "ranges": [{"startLine": 1, "endLine": 20}]}]
  }
}
```

`spec` 就是 `TaskContextSpec` 或 `CodeContextSpec`。代码请求的每个路径仅选 `symbols`、`ranges`、`full: true`、`outline: true` 之一；符号请求可加 `includeDependencies`。必选任务模式为 `full` / `skeleton`，可选另支持 `either`。具体限制、依赖、歧义及不可用原因见[代码读取](code-context.md)和[任务预算](task-context.md)。

输入须为严格 UTF-8 JSON，原始输入和规范化 JSON 均不得超过 65,536 字节。`schemaVersion` 必须为整数 1；未知字段、目录、词表路径及主机权限不属于便携请求。`ContextRequest::from_json` 校验并保存不可变快照，JSON 访问方法返回新副本。

## 响应与计数

每个请求产生一个以 LF 结尾的 JSON 响应。公共字段为 `schemaVersion`、`operation`、`ok`、`status`；计划结果另有 `tokens`、`bytes`、`security`、`audit`、`auditIncludedInText`。成功结果的 **`text` 是 Root 返回的完整原始正文字符串**，解析外层 JSON 即可还原；入口不二次渲染，也不以逐文件计数代替整文预算。

- 任务成功状态为 `complete` 或 `with_omissions`。审计独立：`auditIncludedInText: false`，另有 `auditText`、`auditTokens`、`auditBytes`。
- 代码成功状态为 `complete`，正文已经嵌入审计，`auditIncludedInText: true`；外层 `audit` 是审计投影，不重复收费。
- 不可用或超预算时没有 `text`，代码超预算可提供 `requiredTokens`。验证或传输错误使用 `status: "error"` 和安全的 `error.category`，不回显输入或源码。
- 外层封装不计入 `spec.maxTokens`；完整响应含末尾 LF 不得超过 16 MiB。

`--report-json` 将机器诊断写 stderr，每个已处理请求一条，报告操作、状态、退出码及 `publication`：`not_started`、`unknown` 或 `committed`。`resultStatus` 区分计划失败；失败响应已写出仍是失败操作。文件模式成功退出 0，失败退出 1；失败不替换旧响应文件，成功使用同级临时文件原子替换。链接或非普通输出目标被拒绝。

## 同进程补读

在 `--context-stdio` 中每行写一个请求，并等待对应响应。成功代码响应提供 `runId`、`round`、`sessionTokens`、`remainingTokens`、`maxTokens`、`canContinue`。续读只使用最近成功的 ID，`spec` 不带 `maxTokens`：

```json
{"schemaVersion":1,"operation":"read_code_context","continueFrom":"<最近成功的 runId>","spec":{"requests":[{"path":"src/util.mbt","full":true}]}}
```

首轮 cap 是最多三次成功读取的累计正文预算。失败读取、无效请求、旧 ID 或发布失败不扣额度，也不替换原 ID。每次成功更换 ID；新代码请求成功时开始新预算，任务成功时使旧代码会话失效。失败的新请求或任务保留原会话。

会话只在进程内保存，不写持久化文件。新进程不能恢复另一进程的 ID；单文件模式拒绝所有续读，并始终报告 `canContinue: false`。ID 不是文件路径或授权令牌。

stdio 串行处理请求并复用 Runtime。JSON、UTF-8 或规格错误产生安全失败，随后可处理下一行。过长行最多使用一个超限探测字节，返回失败后停止，不继续排空输入。正常 EOF 退出 0，包括此前出现可恢复失败的情况；过长输入或发布失败退出 1。stdout 没有启动横幅，客户端须持续读取响应，接受正常管道背压。

## 配置与权限

两种模式沿用 Root 的选择、ignore、完整原文扫描、文件与读取配额、模板和任务显示设置。配置不会使被排除或不安全的路径变得可读。模板照常扫描并计入正文预算；代码读取使用 Root 固定 JSON 正文。任务显示受主机输出选项影响；要与 JSON 工作台比较任务正文，应在 CLI 指定 `-f json`，并匹配其他主机设置。

与 MCP / WebUI、stdin 文件列表、`--explain-path`、`--init` 互斥。显式远程 / 分支、分卷、普通打包预算、Git 差异 / 历史、Git 专属配额、全局 `--compress` / `--no-compress`、普通摘要计数、服务专属参数、`--no-files` 和 `--parsable-style` 均被拒绝；模式通过规格指定。已选 JSON 配置含不适用设置也会失败。选择、扫描、资源与模板设置仍可用，普通打包的配置优先级不变。

## 定点功能检查

先独立构建并固定 Native 二进制，再运行：

```sh
moon run --target native scripts/context-entry-test.mbtx -- --ready /absolute/moon-repomix /absolute/o200k_base.tiktoken /absolute/new-log-directory
```

聚合脚本只使用合成夹具和所给二进制，记录参数、标准输入输出、stderr、退出码与清单，不构建或安装产品，也不调用 MCP / HTTP。
