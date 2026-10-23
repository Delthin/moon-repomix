# 精确 Token 分卷

当前源码提供分卷库接口。已发布 v0.3.0 不包含本接口。CLI 仍输出单份文档；分卷调用返回可保存或作为资源提供的字符串，由调用者选择写入位置。

```moonbit
let runtime = @repomix.Runtime::load("assets/tokenizer-o200k_base.tiktoken")
let options = @repomix.options(
  ".",
  style=@repomix.Style::Markdown,
  compress=true,
  keep_full_patterns=["src/core/**"],
  header_text="请分析公开接口与错误处理。",
)
let result = @repomix.pack_volumes(options, runtime, max_tokens=32000)
for volume in result.partition.volumes {
  println("\{volume.id}: \{volume.tokens} tokens")
  // volume.text 是被精确计数的完整文档。
}
```

`pack_volumes` 复用普通 `pack` 的输入选择、原始内容扫描、压缩、全文例外、模板与 Git 过滤。每个文件只读取一次形成快照，远程目录在准备结束时清理，后续分卷使用已接受的内容。传入的 `max_tokens` 必须为正整数，它是每卷的硬限制；`Options.token_budget` 只用于普通 `pack` 的单文档预算，不替代分卷参数。

## 归属和预算

文件按规范相对路径的 UTF-8 字节序，随后是原顺序的附加章节。文件和章节都是不可拆的原子：包括空文件，每项恰好归属一卷。章节身份采用原下标，两个相同标题仍是两个独立章节。重复文件路径会报错。

每卷重复 header 和 instruction，目录树只含本卷文件。展示选项、路径前缀、文件行号及元数据详略仍参与该卷渲染。对每个候选卷先渲染，再精确计算完整 `o200k_base` token 数；返回的 `Volume.text` 就是这份被计数的文本，标签、转义和模板都在预算内。

超限候选按原子数量对半拆分，不逐项编码所有增长前缀，不使用单文件 token 求和或单调性假设。此策略保证成功卷都符合上限，卷数不保证最少。基础模板超限返回 `TemplateTooLarge(actual)`；单个原子仍超限返回 `UnitTooLarge(identity, actual)`，标识为文件规范路径或原章节下标。空输入返回一份模板卷。

## 索引

`result.partition` 包含：

- `volumes`：每项有 `id`、规范 `document`、完整 `text`、`tokens`、UTF-8 `bytes`，以及原始文件和章节下标。
- `index` / `index_text`：版本为 1 的 JSON 索引，ID 从 `part-0001` 起，提供规范路径及原章节下标到卷 ID 的映射；保留整次任务的完整元数据。
- `index_tokens`：索引字符串本身的精确计数，索引不受每卷上限约束。
- `total_tokens`：每个独立卷与独立索引计数之和，适用于分别提交这些文档，不是将它们拼接后的计数。

索引与文件路径映射可用于按需读取具体卷。展示为绝对路径或 cwd 相对路径时，索引和 `Volume.document` 仍使用规范的输入根相对路径。

## 元数据和 Git

库保留完整文档模型。各卷 `compression` 记录仅包含本卷文件；渲染器再根据 `full_metadata` 生成概览或完整记录。来源 `source` 描述整次快照，每卷保留。

Git 元数据按原始章节 kind 和出现次序绑定。diff/commit 随所属章节进入一卷，不按该卷文件重新过滤：一次跨文件差异可以涉及其他卷，提交也可以涉及已删除文件。未知自定义元数据不猜测归属，由底层调用者决定投影；原始全局值始终保存在索引中。

`VolumePackResult.files`、`skipped`、`findings`、`security` 描述整次输入处理。章节隐藏、文件隐藏或元数据隐藏都是渲染选择，不影响完整库模型和全局索引。

## 底层接口

`Delthin/moon_repomix/partition` 提供不依赖 Runtime 的纯分卷函数：

```text
partition(document, max_tokens,
  render~: (Document) -> String raise,
  count~: (String) -> Int raise,
  project_metadata~: (Array[Int], Array[Int]) -> Json raise
) -> Partition raise
```

回调必须确定，元数据投影收到原始输入下标，也会用于空模板和最终被拒绝的候选。回调错误原样传播；负计数、UTF-8 非法文本及整数溢出会报错。该接口可以复用其他格式和计数器；根 `pack_volumes` 已接好本工具的格式、安全流程、源图及 Git 投影。
