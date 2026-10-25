# 演示

## 浏览器工作台

安装 v0.4.0 后运行 `moon-repomix --webui`，打开终端显示的 loopback 地址。选择授权目录、生成混合上下文，在同一页面对照源码与骨架、查看完整文档预算并下载 JSON。[README 动图](../README.md#浏览器工作台) 记录了真实 Native 请求；[工作台指南](webui.md) 说明启动和资源限制。

## 三步 CLI 演示

以下示例用一个微型 MoonBit / TypeScript 目录，展示忽略规则、密钥排除、两种输出格式，以及预算超限时的行为。只在本地运行，不需要 AI 服务或 Node.js。

### 运行

准备好 [README](../README.md#安装与第一次运行) 中的 MoonBit 与 native C 工具链，在仓库根目录运行：

```sh
moon update
moon run --target native scripts/demo.mbtx
```

脚本构建 release CLI，将 [`examples/demo/`](../examples/demo/) 复制到 `dist/demo/input/`，并在副本中生成一份用于扫描的合成凭证。

默认输出目录为 `dist/demo/`。也可以指定一个**尚不存在、父目录已存在**的目录，含空格时加引号：

```sh
moon run --target native scripts/demo.mbtx "dist/my demo"
```

输出路径已存在时脚本报错，再次演示请换一个新目录。演示输入、输出及失败时已生成的文件都保留在该目录；CLI 构建产物位于 `_build/`。

### 演示步骤与输出

脚本依次运行以下三步并核对结果；任意一步不符合预期都会失败：

| 步骤 | 产物 | 观察点 |
| --- | --- | --- |
| 1. XML 打包 | `context.xml`、`xml.log` | 两种语言源码入选；`debug.log` 受根 `.gitignore` 排除，`src/scratch.txt` 受嵌套 `.gitignore` 排除；生成的 `credentials.txt` 因扫描命中而整文件排除。日志列出跳过原因和逐文件统计，不打印密钥值。 |
| 2. Markdown 打包 | `context.md`、`markdown.log` | 同一输入以目录结构和代码围栏呈现，适合直接阅读。 |
| 3. 预算设为 1 token | `budget.xml`、`budget.log` | CLI 返回 **1**，日志含 `complete output retained`；`budget.xml` 与第一步 XML 逐字节一致，没有裁剪内容。 |

预算超限是这次演示的预期结果，因此第三步的 CLI 返回 1，而脚本确认完整输出保留后正常结束。

分享前检查 `context.xml` 或 `context.md`；`input/` 中仍保留合成凭证。扫描的覆盖范围见 [扫描规则](security.md)。

### 手动调整

安装版可对同一份输入直接运行（以下路径以默认输出目录为例）：

```sh
moon-repomix dist/demo/input --style markdown --include 'src/**' -o dist/demo/src-only.md
```

输出中只留下 `src/` 下未被忽略的文件；include 不会重新引入 `src/scratch.txt`。`-o` 会替换同名文件，手动运行时请选择新的输出名。

未安装时，在仓库根目录使用源码入口，并显式传入词表：

```sh
moon run src/cmd/moon-repomix --target native --release -- dist/demo/input --style markdown --include 'src/**' -o dist/demo/src-only.md --tokenizer-path assets/tokenizer-o200k_base.tiktoken
```

更换输入、调整 glob 或设置实际 token 预算，参见 [配置与 CLI](configuration.md)。
