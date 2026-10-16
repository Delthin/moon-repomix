# moon-repomix

把本地代码目录整理成一份 XML 或 Markdown，方便交给 AI 阅读或留作代码上下文。使用 MoonBit native 实现，提供 CLI 和库 API；运行时不需要 Node.js，也不上传代码或下载分词资源。

## 最快上手

源码构建需要 MoonBit **0.10.15+943464bfa**（见 [`moon-toolchain`](moon-toolchain)）和平台 C 工具链。在仓库根目录先更新依赖，再运行：

```sh
moon update
moon run src/cmd/moon-repomix --target native --release -- examples/demo --style markdown --stdout --tokenizer-path assets/tokenizer-o200k_base.tiktoken
```

终端会显示包含 MoonBit、TypeScript 源码和目录结构的 Markdown；`debug.log` 和 `src/scratch.txt` 被忽略。文档写到标准输出，统计和跳过原因写到标准错误。

想一起看看密钥排除和预算超限的行为，运行这个三步演示：

```sh
moon run --target native scripts/demo.mbtx
```

它会自动构建 CLI，将输入副本、XML、Markdown 和诊断日志保留在新建的 `dist/demo/`；目录已存在就报错，不覆盖。也可传入另一个尚不存在的输出目录。步骤和观察点见 [演示指南](docs/demo.md)。

## 安装

在完成 `moon update` 后，把程序与分词资源一起安装到指定前缀：

```sh
moon run --target native scripts/install.mbtx "$HOME/.local"
```

Windows PowerShell：

```powershell
moon run --target native scripts/install.mbtx "$env:LOCALAPPDATA\moon-repomix"
```

将前缀下的 `bin` 加入 `PATH`。安装版从程序所在位置寻找 `../share/moon-repomix/`，不依赖当前工作目录。移动安装目录时，请一起保留 `bin`、`share` 及其相对位置；仅复制可执行文件不构成完整安装。

源码运行需要像上面的命令一样显式指定词表。项目面向 macOS、Linux 和 Windows；各平台构建须使用相应的 native C 工具链。

## CLI 用法

```sh
moon-repomix ./project
moon-repomix ./project --style markdown -o context.md
moon-repomix ./project --include 'src/**,README.md' --ignore '**/*_test.mbt'
moon-repomix ./project --stdout > context.xml
moon-repomix ./project --token-budget 100000
moon-repomix ./project --init
```

默认输出 `repomix-output.xml`；Markdown 默认输出 `repomix-output.md`。`-o` 会替换已有同名输出，使用时请选好路径。相对输出路径和显式配置路径以当前工作目录为准；自动发现的 `repomix.config.json` 位于所选目录内。`--init` 创建配置，不覆盖已有配置。全部选项见 `--help` 和 [配置文档](docs/configuration.md)。

当前功能：

- 读取 `.gitignore`、`.ignore`、`.repomixignore`（含嵌套规则），支持 include/ignore glob；按相对路径稳定排序。include 不会绕过忽略规则。
- 打包有效 UTF-8 普通文件；去掉 UTF-8 BOM，保留原始换行。默认单文件上限为 **50 MiB**；链接、二进制、不可读或超限文件跳过。
- 默认扫描密钥，排除命中的**整个文件**。诊断给出规则、路径、行号和磁盘字节区间，不打印匹配值。
- 用完整 `o200k_base` 词表计算最终文档的 token 数，同时报告逐文件统计。超预算不截断：仍输出完整文档，CLI 返回 **1**；正常完成且未超预算返回 **0**。配置、资源、扫描或写入错误也返回 **1**，需结合诊断区分。
- 文件输出先写同目录临时文件，再原子替换；打包失败时保留已有输出。`--stdout` 将文档写到标准输出，统计和诊断写到标准错误。

更多细节：[文件选择](docs/file-selection.md) · [输出格式](docs/output.md) · [扫描规则](docs/security.md) · [分词](docs/tokenization.md)。

## 安全与使用边界

密钥扫描是启发式检测，不能保证发现所有凭证；分享前仍应检查最终文档。`--no-security-check` 会关闭扫描并显示警告。忽略规则控制文件选择，不是安全隔离；不要在打包时允许不可信进程并发修改输入目录。

打包和计数在内存中完成，内存占用随输入和输出大小增长。token 预算用于告警，不是内存限制，也不自动挑选或裁剪文件。

## 库 API

在调用项目中添加 `delthin/moon_repomix` 依赖，并在 `moon.pkg` 导入：

```moonbit
import {
  "delthin/moon_repomix" @repomix,
}
```

在 `async fn` 中先加载资源，再打包：

```moonbit
let options = @repomix.options("/absolute/project")
let runtime = @repomix.Runtime::load("/absolute/share/moon-repomix/o200k_base.tiktoken")
let result = @repomix.pack(options, runtime)
// result.text 是完整文档；result.tokens 是完整文档的 token 数。
// result.files / skipped / findings / security / budget 提供统计及状态。
```

`pack` 返回结果，不写文件；由调用者决定如何处理输出和预算超限。词表同目录还须有 `tokenizer-unicode-16.0.0.txt`，两份资源均校验 SHA-256。一个 `Runtime` 可复用于多次顺序打包。接口见 [`src/pkg.generated.mbti`](src/pkg.generated.mbti)。

## 开发与打包

```sh
moon update
moon check --target native --deny-warn
moon test --target native
moon build --target native --release
moon run --target native scripts/package.mbtx dist macos-arm64
```

打包标签为 `macos-arm64`、`macos-x64`、`linux-x64`、`windows-x64`，在对应平台和架构上构建。归档包含程序、词表、Unicode 数据及许可证。

## 来源与许可

项目参考 [Repomix](https://github.com/yamadashy/repomix) 的本地仓库打包行为，采用 [MIT](LICENSE) 许可。第三方代码及资源的许可保存在 [`LICENSES/`](LICENSES/)；分词实现、词表与 Unicode 数据的来源、版本及兼容范围见 [分词文档](docs/tokenization.md)，扫描依据见 [扫描规则](docs/security.md)。
