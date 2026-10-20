# 压缩、Git 与远程仓库

## 生成结构概览

```sh
moon-repomix ./project --compress --style json -o structure.json
```

`--compress` 在原始文件通过安全扫描后提取语法骨架。支持 `.js/.jsx/.mjs/.cjs`、`.ts/.mts/.cts/.tsx`、`.py/.pyi`，提取导入、类型、类及函数签名和从属结构，省略实现正文；解析器版本见 [第三方来源](../LICENSES/tree-sitter-sources.md)。运行时使用编译进程序的原生解析器。仅含实现的分支和循环整体省略，围住嵌套声明的控制结构保留；较短的初始化片段保留原文，避免替换成更长的省略标记。

每份压缩记录包含 `path`、`language`、`applied`、`reason`、`ranges`、`originalTokens` 和 `outputTokens`。`ranges` 是 `[startLine,endLine]` 数组，从 1 开始、包含两端，回指原文件而非输出行号。相邻或重叠的行区间合并，区间表示保留片段覆盖到的行，不表示整行均被保留；压缩包 API 仍提供逐片段范围。不支持、解析失败或正文 token 数没有减少时保留原文，并记录原因。骨架适合先了解结构；需要实现细节时可用 `--include` 选定路径，再关闭压缩。

终端的 `File-body tokens` 对比接受文件的原始正文与实际输出正文，文件排名和目录树使用后者。最终文档计数还包含目录树、格式包装、来源、压缩记录及 Git 章节，预算以这个完整计数为准。

## 导出变更和历史

```sh
moon-repomix ./project --include-diffs --include-logs --include-logs-count 20 -o review.xml
moon-repomix ./project/src --include-diffs --include 'api/**' --style markdown -o api-review.md
```

`--include-diffs` 分别导出 staged、unstaged 的逐文件补丁。`--include-logs` 先读取所选目录最近 N 个提交，再筛选其文件列表，因此接受的提交数可能小于 N。输出包含标识、日期、完整消息和文件列表；数量默认 50，可设为 `1..10000`。仅设置数量不会自动开启日志。

路径相对于所选目录，应用当前工作树的 include、ignore、父目录剪枝、链接和输出自身排除规则。已删除文件仍可导出；重命名任一端被排除时，整个补丁排除。历史提交只保留允许的文件列表，列表为空时排除该提交。这里使用当前 ignore 文件，不逐个恢复历史版本的规则。

提交消息保持原意，可能提及文件列表之外的名称，不会因此提取那些文件。原始补丁（包括删除行）和提交消息都扫描；命中时排除对应整个补丁或提交并记录诊断。XML 无法表示的章节也会排除。

Git 调用通过参数数组执行，禁用外部 diff、textconv、签名显示、fsmonitor、hooks 和交互凭据扩展，并限制输出与执行时间。`--max-git-bytes` 控制一次收集的 Git 文本总量，默认 8 MiB；超过上限会报错，而不是输出不完整的补丁。显式请求 Git 功能但目录不适用、Git 不存在或命令失败时，打包停止并保留旧输出。

## 从公开仓库获取

```sh
moon-repomix --remote https://github.com/octocat/Hello-World.git --include-logs --style json -o remote.json
moon-repomix --remote https://github.com/octocat/Hello-World.git --remote-branch master --include 'README*' -o readme.xml
```

首版接受公开 HTTPS URL，支持默认分支及显式 branch/tag/revision，拒绝嵌入凭据和其他协议。使用 `--include` 选择仓库内路径；远程输入与另一个本地目录参数互斥。

仓库进入独立临时目录，随后复用文件选择、扫描、压缩、格式与计数流程。成功、失败和取消均清理目录。开启日志时获取所选 ref 的完整祖先历史，再导出最近 N 条；大型历史可能受到每命令 30 秒限制。输出记录公开 URL 和实际 commit；干净 checkout 通常没有 staged/unstaged 差异。

远程模式只加载 `--config` 显式指定的本地配置，不自动采用启动目录或远程仓库中的 `repomix.config.json`。使用 JSON 的 `remote.url` 时同样需要显式 `--config`；自动发现的配置不能发起远程获取。仓库里的 ignore 文件仍作为路径规则读取。Git 子模块不递归获取，私有仓库与交互鉴权不在当前范围内。

## 结构化输出与库调用

`Document` 包含 `files`、`sections`、`metadata`；`PackResult.document` 暴露同一份模型。JSON 保留路径到输出正文的 `files` 对象，按需增加：

- `metadata.source`：`kind`、可选 URL 和实际 revision；普通本地压缩未请求 Git 时 revision 为 null。
- `metadata.compression`：逐文件骨架与回退记录。
- `metadata.git`：接受的 diff 路径、提交标识与文件列表。
- `sections`：`kind` 为 `git_diff` 或 `git_log`，并含 `title`、`text`。

XML 将来源和记录放在 `metadata`，Git 内容放在 `sections/section`；Markdown 与 plain 用对应章节展示，并以紧凑 JSON 写入元数据，减少缩进和换行占用的 token，字段与行区间完整保留。原有未开启这些功能的输出结构保持原样。

```moonbit
let options = @repomix.options(
  ".", style=@repomix.Style::Json, compress=true,
  remote=Some("https://github.com/octocat/Hello-World.git"),
  include_logs=true, include_logs_count=10,
)
let result = @repomix.pack(options, runtime)
```

库入口负责远程获取与清理，返回的文本和结构化文档均可独立使用，不依赖临时目录继续存在。`FileStats.original_tokens` 是扫描后原始正文的计数，`tokens` 是实际渲染正文的计数。`PackError` 增加 `GitError`、`RemoteError`；安全扫描与预算仍使用原有状态。
