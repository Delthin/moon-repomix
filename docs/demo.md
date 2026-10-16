# 三步演示

这个示例用一个微型 MoonBit / TypeScript 目录，展示忽略规则、密钥排除、两种输出格式，以及预算超限时的行为。只在本地运行，不需要 AI 服务或 Node.js。

## 运行

准备好 [README](../README.md#最快上手) 中的 MoonBit 与 native C 工具链，在仓库根目录运行：

```sh
moon update
moon run --target native scripts/demo.mbtx
```

脚本会构建 release CLI，复制 [`examples/demo/`](../examples/demo/) 到 `dist/demo/input/`，并生成一份仅用于扫描的合成凭证。凭证由脚本运行时拼接，不访问真实账号；示例源码没有完整 token。输入副本还会创建一个空的 `.git/` 目录作为规则边界，避免父目录的 `dist/` 忽略规则遮蔽整个示例；不调用 Git，也不创建提交。

默认输出目录为 `dist/demo/`。也可以指定一个**尚不存在、父目录已存在**的目录，含空格时加引号：

```sh
moon run --target native scripts/demo.mbtx "dist/my demo"
```

输出目录只允许新建，已有目录、文件或链接都会使脚本失败；再次演示请换一个新目录。失败时已生成的文件也会保留，便于查看原因。演示数据和输出均写入该新目录，CLI 构建产物仍按项目约定写入 `_build/`。

## 看什么

脚本依次运行以下三步并核对结果；任意一步不符合预期都会失败：

| 步骤 | 产物 | 观察点 |
| --- | --- | --- |
| 1. XML 打包 | `context.xml`、`xml.log` | 两种语言源码入选；`debug.log` 受根 `.gitignore` 排除，`src/scratch.txt` 受嵌套 `.gitignore` 排除；生成的 `credentials.txt` 因扫描命中而整文件排除。日志列出跳过原因和逐文件统计，不打印密钥值。 |
| 2. Markdown 打包 | `context.md`、`markdown.log` | 同一输入以目录结构和代码围栏呈现，适合直接阅读。 |
| 3. 预算设为 1 token | `budget.xml`、`budget.log` | CLI 返回 **1**，日志含 `complete output retained`；`budget.xml` 与第一步 XML 逐字节一致，没有裁剪内容。 |

预算超限是这次演示的预期结果，因此第三步的 CLI 返回 1，而脚本确认完整输出保留后正常结束。其他退出码或不符合预期的输出不会被忽略。

`input/` 也会保留，包括那份合成凭证。需要分享的是检查过的 `context.xml` 或 `context.md`，而不是整个输入目录。扫描只是启发式检测，不能代替分享前审阅；详见 [安全边界](security.md)。

## 手动调整

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
