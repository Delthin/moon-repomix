# 查询文件入选原因

可以单独解释至多 256 个本地根相对字面路径。查询执行真实选择、源码读取、扫描及当前 style 的表示检查，返回阶段和安全原因；不加载词表、不生成上下文，也不修改已有输出。

```sh
moon-repomix ./project --explain-path src/main.mbt --explain-path dist/app.js
```

stdout 为一份 schemaVersion 1 JSON 和末尾 LF；`--report-json` 另外在 stderr 给出不含路径明细的数量摘要。路径重复时去重，按 UTF-8 字节排序，每项最多 4,096 UTF-8 bytes。参数不是 glob，目录不递归；原始名称、include/ignore、输出自身、链接、输入限额和安全开关与打包共用。规则来源来自同一结构化判定，不另建匹配器。

## 返回内容

顶层 `operation` 为 `explain_selection`，`scope` 为 `requested-paths`，`style` 标明本次表示检查的格式。`paths` 中每项包含：

- `path`：已验证的根相对路径。
- `eligible`：是否成为普通候选文件；它与后续是否接受分开。
- `status`：`accepted` 或 `excluded`。
- `stage`：`selection`、`input`、`security`、`format` 或 `complete`。
- `reason`：固定原因，例如 `NotListed`、`IgnoredDirectory`、`Ignored`、`NotIncluded`、`MissingFile`、`NonLiteralPath`、`Symlink`、`Directory`、`OutputFile`、`TooLarge`、`Binary`、`InvalidUtf8`、`SecurityFinding`、`UnrepresentableText`、`Accepted`。
- `origin`：适用时给出 `kind`、根相对 `source`、一基行号 `line`，或零基编译后 matcher `index`；不返回规则正文。祖先和外部规则的 `source` 为 null，仍保留安全的种类和行号。
- `findingCount` / `findingRules`：只给出命中数及检测器标签，不含内容或坐标。

`counts` 是去重后的查询、候选、接受与排除数量。`readBytes` 为本次查询实际读取的原始源码字节十进制字符串，包含 BOM 与之后被拒绝的数据；`limits` 给出主机源码上限。候选数量或读取总量超过上限时整次查询失败，不返回伪造的部分结论。

## 与完整打包的关系

接受表示本次请求通过上述筛查。模板、Git 导出、AST、渲染、最终 token 预算及输出发布由打包操作继续处理；本次查询的配额不代表整个仓库的配额。被父目录规则剪枝的文件按父目录决定，不读取其内部规则。

CLI 查询与 `--stdin` / `--stdin0`、`--stdout`、显式 `--output`、`--mcp` 和 `--init` 互斥；解析后的远程、分卷、stdout 或 token-budget 模式也会被拒绝。帮助和版本仍可直接查询。若只需要源码决策，可使用一份独立的显式配置。

静态 no-follow 与原始名称检查拒绝链接和拼写别名；调用方负责执行期间的文件系统稳定性。该操作没有建立抵御恶意并发替换父目录的文件系统沙箱。

## 库与 MCP

库入口为 `explain_selection(options, paths) -> SelectionReport`，无需 `Runtime`；使用 `SelectionReport::to_json()` 取得同一安全结构。`options.file_paths` 始终是独立主机白名单：查询列表不能扩权，白名单外返回 `NotListed`，`Some([])` 允许零文件。读取只使用本次选择返回的候选，不再扫描一次仓库。

底层 `selection.explain` 只判结构资格。它的 `decisions` 提供安全来源；`selection.skipped` 为兼容保留旧诊断，可能包含绝对规则路径，面向远程客户端应使用 Root 投影。

MCP 工具 `explain_selection` 仅接受 `{"paths":["src/main.mbt"]}`，使用启动时的根目录、style、白名单和配额。它与打包共享单个 busy 槽，结果大小受 4 MiB 与主机输出上限的较小值限制；不创建、替换或释放上下文资源。错误、超限和取消保持已有缓存，资源读取仍可并行。
