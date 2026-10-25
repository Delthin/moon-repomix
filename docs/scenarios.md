# 三个使用场景

以下新增选项需要当前源码构建，尚未包含在已发行 v0.3.0 中。先按 [README](../README.md#最快上手) 安装当前源码，命令中的 `moon-repomix` 指这份本地安装。命令从包含 `project/` 的目录运行，输出放在输入根以外。

## 1. 评审关键实现，其余保留骨架

把评审要求写到 UTF-8 文件 `review-instructions.md`，再运行：

```sh
moon-repomix ./project --compress --keep-full 'src/core/**,README.md' \
  --header-text '请关注公开接口与错误处理。' \
  --instruction-file-path review-instructions.md \
  --include-diffs -f md -o review.md
```

`review.md` 中关键文件保留全文，其他受支持语言提取骨架，并附经过路径筛选的 Git 差异。`--keep-full` 只作用于已选且通过扫描的文件。头部和指令各最多 1 MiB，进入文档前扫描，最终 token 数包含模板和包装；指令路径相对启动 cwd。

需要定位原始源码时加 `--full-metadata`；显示正文行号用 `--output-show-line-numbers`，它是输出行号，压缩后的原始行映射仍在元数据中。选择原因不明时，单独运行 `moon-repomix ./project --explain-path src/core/main.mbt`；查询通过不代表模板、Git 或预算也会通过。详见 [配置](configuration.md) 与 [入选原因](selection-explanation.md)。

## 2. 把仓库分成每卷不超过预算的材料

```sh
moon-repomix ./project --compress --split 12000 \
  -f md -o review-parts --report-json 2> review-report.json
```

`review-parts` 必须不存在，父目录已存在且由调用方控制。成功后读取 `index.json` 选择对应的 `part-0001.md` 等卷；每卷对最终字符串精确计数，文件和 Git 章节各自完整归属一卷，模板按卷重复。索引独立计数，不受 12,000 的每卷 cap 约束，总开销是所有卷与索引计数之和。

单个文件、章节或基础模板放不下时，运行失败而不是截断；可减少输入、开启骨架或在实际允许范围内提高 cap。`--budget` 则是单文档告警：超限仍写全文、退出 1，不能和 CLI 分卷同时使用。发布与预算规则见 [分卷](partition.md)，报告字段见 [机器报告](reports.md)。

## 3. 接入 MCP 客户端或自动化任务

由主机启动固定本地根的只读服务：

```sh
moon-repomix ./project --mcp --compress --include 'src/**,README.md' \
  --mcp-max-tokens 12000 --max-files 20000 --max-total-size 209715200
```

客户端通过 `pack_repository` 请求上下文，再用返回的 URI 读取卷和索引；请求只能在启动授权范围内选文件，不能改根、关闭扫描或提高 cap。`explain_selection` 查询字面路径，`release_context` 释放内存缓存。当前协议与旧 initialize 客户端的配置见 [MCP stdio](mcp.md)。

不使用 MCP 的自动化可分别保存正文与运行报告：

```sh
moon-repomix ./project --compress -f md -o - --report-json \
  > context.md 2> report.json
```

检查退出码与 JSON `status`，再使用正文；`over_budget` 表示全文已生成但超出单文档预算。报告中的 token/字节度量是十进制字符串，勿当作浮点数累计。遇到失败先检查 `publication`，不要直接覆盖重试，见 [错误指南](errors.md)。
