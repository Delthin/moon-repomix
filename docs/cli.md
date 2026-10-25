# CLI 按任务速查

[安装 v0.4.0](../README.md#安装与第一次运行) 后，日常使用 `moon-repomix`，程序自动定位配套资源。需要从旧版本升级时，查看 [迁移指南](migration.md)。

## 打包与选择格式

在要处理的项目目录直接运行：

```sh
moon-repomix
```

默认处理当前目录，结果写到启动目录的 `repomix-output.xml`；输入根已有 `repomix.config.json` 时，沿用其中设置。指定别的项目、格式和文件名：

```sh
moon-repomix ./project -f md -o context.md
moon-repomix ./project -f json -o context.json
```

`-f` 接受 `xml`、`md`、`json`、`txt`，也接受完整名称 `markdown`、`plain`。格式由 CLI、JSON 配置、默认 XML 依次决定；输出文件名只决定路径。`-o -` 将正文写 stdout，诊断与统计写 stderr。

## 缩小输入与提取骨架

```sh
moon-repomix ./project --include 'src/**,README.md' --compress -f md -o structure.md
```

需要阅读关键实现时，用 `--keep-full 'src/core/**'` 保留其全文；其他已选文件提取骨架。include、ignore、扫描与输入限额始终先应用。更多规则见[文件选择](file-selection.md)，模板和混合示例见[使用场景](scenarios.md)。

## 检查预算或分卷

```sh
moon-repomix ./project --budget 12000 -f md -o context.md
moon-repomix ./project --compress --split 12000 -f md -o context-parts
```

普通预算超限仍写入完整 `context.md`，退出 1；它只检查预算。分卷则保证每卷最终文档不超过上限，`context-parts` 必须不存在，父目录必须已存在且稳定。单个文件或章节放不下时失败，索引单独计数；`--split` 与普通预算、stdout 互斥。见[分卷](partition.md)。

## 带上 Git 差异与历史

```sh
moon-repomix ./project --include-diffs --include-logs --include-logs-count 20 -f md -o review.md
```

差异包括 staged/unstaged；历史包含消息和路径。日志开关与数量独立，单独设置数量不会启用历史。需要系统 Git。

## 远程仓库与字面文件列表

```sh
moon-repomix --remote https://github.com/octocat/Hello-World.git -f md -o remote.md

git ls-files -z | moon-repomix --stdin0 -f md -o -
```

远程输入限公开 HTTPS 仓库；指定 branch、tag 或 revision 时加 `--remote-branch REF`。stdin 示例从项目目录执行，每项是输入根相对的字面路径；空输入选零文件。stdout 重定向应放在输入根以外，或显式忽略目标。

## 将常用设置留在配置里

`moon-repomix ./project --init` 创建配置并拒绝覆盖；以后处理该根目录时自动读取。可将配置整理为自己需要的字段，例如：

```json
{
  "include": ["src/**", "README.md"],
  "output": {
    "style": "markdown",
    "compress": true,
    "tokenBudget": 12000
  }
}
```

保存后运行 `moon-repomix ./project -o context.md` 即可。标量由显式 CLI 覆盖；include、ignore、keepFull 追加去重。显式配置路径和输出路径相对启动目录，规则相对输入根。JSON 使用完整名称 `markdown`、`plain` 和既有字段名。

## 帮助与兼容写法

`--help` 展示常见任务，`--help-all` 列出全部参数，包括 MCP、机器报告、展示和资源控制。两个帮助入口及 `--version` 都在加载词表或启动服务前返回。

| 常用写法 | 既有写法 | JSON `output` 字段 |
| --- | --- | --- |
| `-f md` / `--format md` | `--style markdown` | `style: "markdown"` |
| `--budget N` | `--token-budget N` | `tokenBudget` |
| `--split N` | `--split-output N` | `splitOutput` |

新旧拼法使用同一解析和校验路径；同一标量混写时后者生效。完整配置见[配置参考](configuration.md)，浏览器和客户端入口分别见[工作台](webui.md)与[MCP](mcp.md)。
