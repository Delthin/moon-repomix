# 密钥扫描

默认采用 `123123213weqw/moon_scrub@0.5.2` 的 `ScanConfig::secrets_only()` 凭证规则扫描压缩前的原始文本快照。发现密钥时排除整个文件；Git 补丁（含删除行）和提交消息另行扫描，命中时排除对应整个补丁或提交。诊断只保留规则、路径和位置。

头部文字和显式本地指令也使用同一扫描器，在远程获取、压缩和渲染前检查。模板命中时停止整个打包，错误只标明 `output.headerText` 或 `output.instructionFilePath`；文件输出尚未提交，stdout 尚未开始。显式 `--no-security-check` 同时关闭文件、Git 与模板扫描，CLI 仍按关闭状态显示警告。

## 检测范围

以下规则已用合成数据验证：

| 规则 ID | 识别形状与适配策略 |
| --- | --- |
| `github-token` | `ghp_`、`gho_`、`ghu_`、`ghs_`、`ghr_`：总长 40；`github_pat_`：总长 93 |
| `aws-access-key` | `AKIA` / `ASIA`：总长 20，使用大写 ASCII 字母和数字 |
| `openai-key` | 旧式 `sk-`：总长 51；`sk-proj-` / `sk-svcacct-`：总长 48–256 |
| `pem-private-key` | 从引擎识别的私钥 BEGIN 标记到结尾标记或文本末尾；证书和公钥不属于此项 |
| `credential-assignment` | 引擎识别的敏感字段赋值；值至少 8 个 UTF-16 单位，含字母及数字或凭证标点 |
| `access-token`、`bearer-token`、`jwt`、`url-credential` | 保留引擎 secrets-only 的对应规则 |

适配层收紧 GitHub/AWS/OpenAI 长度条件，并过滤常见占位符与代码表达式。占位符包括 example/placeholder、changeme、your_/your-、replace_me、redacted、dummy 和重复字符值。通用赋值过滤裸标识符、类型、process/env/config 取值、插值及表达式括号。同一行中的字符串拼接（如 `"token=" + value + "\n"`）会结合引号状态识别为代码；带 `+` 的密码字面量仍参与检测。普通代码和联系方式作为负例；邮箱、IP、电话号码不在此扫描范围。

这是启发式检测：短密码、新凭证格式及含占位词的字面值可能漏报，分享前仍应审阅最终文档。引擎在适配过滤前合并重叠发现，因此返回结果不枚举同一位置的全部规则。当前覆盖表来自合成样例，尚未与 Secretlint 做独立差分。

## 接口与位置

包：`Delthin/moon_repomix/security`。

```text
pub(all) struct Finding { rule:String, path:String, start:Int, end:Int, line:Int }
pub fn scan(path:String, text:String, bom_bytes:Int) -> Array[Finding] raise ScanError
pub fn scan_validated(path:String, text:@validated_text.Text) -> Array[Finding] raise ScanError
```

调用者传入与渲染相同的已解码快照。读取时去掉 UTF-8 BOM，传 `bom_bytes=3`；否则传 `0`。`start`、`end` 是以磁盘文件首字节为 0 的 UTF-8 字节半开区间；`line` 从 1 开始，CRLF 计一次换行，裸 CR、LF 也各计一次。

有界读取器也提供 `read_validated_metered`：严格 UTF-8 解码后保留文本、原始字节数和 BOM 长度的验证值，打包和入选查询将其交给 `scan_validated`，复用已完成的验证。`Delthin/moon_repomix/validated_text` 的 `Text` 字段私有，只能通过严格解码获得；复制并更新普通 `Snapshot` 不会改变验证值。直接调用 `scan(String, bom_bytes)` 时仍先验证文本和 BOM 参数。

Git 诊断使用 `git:diff:N` 或 `git:commit:ID` 标签，偏移和行号相对于补丁正文或提交章节，而非磁盘文件。补丁行标记不作为源代码参与边界判断，位置仍与原补丁一致。

引擎返回 UTF-16 单位索引，适配层逐项检查范围上下界和代理对边界，再应用过滤策略。只有保留的发现需要计算 UTF-8 字节偏移和行号；转换遍历在最后一个所需边界处结束，BOM 长度计入磁盘偏移。坐标存储随返回发现的数量增长。回归覆盖中文、emoji、组合字符、CRLF 和 BOM。

## 错误与调用约束

`ScanError` 包含 `InvalidBomOffset`、`InvalidText`、`InvalidEngineRange`、`InputTooLarge`，不携带原文或引擎消息。扫描函数同步执行，无 I/O 和日志；调用者处理失败时也不得记录快照正文。内存耗尽等原生运行时终止不属于可恢复的 MoonBit 错误。

入选原因查询与打包共用源码读取、扫描和 XML 表示检查；只返回固定阶段、原因、检测器标签和安全规则位置，不返回正文、规则内容或绝对祖先路径。查询不处理模板、Git、压缩与最终预算，见 [查询范围](selection-explanation.md)。

依赖原码保持原样。原生适配器先做一次保守的字面前缀预筛选，覆盖固定 0.5.2 的 40 种 token 前缀、Bearer、JWT、七种 PEM 私钥头及认证 URL。必要条件成立时，对应引擎检测器仍接收完整原文；字段赋值和 Basic Auth 检测照常执行。此优化绑定该版本的规则清单，升级依赖时需重新核对。显式关闭扫描时，CLI 显示警告，结果记录 `SecurityStatus.Disabled`。
