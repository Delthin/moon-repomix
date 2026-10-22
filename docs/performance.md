# 性能与测量方法

当前源码在三个固定仓库的原文、结构压缩场景中，与 Repomix 1.18.1 比较端到端耗时。下面是 macOS 单机结果；它说明这些工作负载的性能，不代表任意仓库、选项或平台都必然更快。

## 测量环境

- 本工具源码：`b0d1bbbb54c2ea7486b03ae5b9bed817cb9a06a1`，MoonBit `0.10.15+943464bfa`，native release。
- 本工具二进制 SHA-256：`5f1e7d8016ca3f8142709eac9747ee73b7b93f12c34dab4411d742e4fa1ee43f`。
- 对照：npm `repomix@1.18.1`，Node.js `v25.9.0`。npm 包没有 gitHead，不将其与同名源码归档当作字节相同的发布物。
- Apple M4、10 核、16 GiB RAM，macOS 26.2。采用 `/usr/bin/time -lp`；wall 单位为秒，进程峰值 RSS 单位为 bytes。

每组预热一次，然后以新进程交替执行五轮；预热不计入统计。原版的常规线程池保留，独立 HOME/XDG/TMPDIR 和 token 缓存目录在预热后继续使用，既不删除用户缓存，也不在每轮清空原版内容缓存。

## 相同输入的端到端结果

原文和压缩均输出 JSON，开启安全扫描与 parsable-style，使用 o200k_base。配置文件显式指定，原版 processors 为空、Git 变更频率排序关闭；执行过程中不运行仓库配置代码或脚本。

| 仓库与模式 | 文件数 | 原版耗时中位数 | 本工具耗时中位数 | 原版耗时 / 本工具耗时 |
| --- | ---: | ---: | ---: | ---: |
| Repomix 原文 | 144 | 0.26 s | 0.14 s | 1.86× |
| Repomix 结构压缩 | 144 | 0.29 s | 0.20 s | 1.45× |
| Express 原文 | 12 | 0.19 s | 0.05 s | 3.80× |
| Express 结构压缩 | 12 | 0.21 s | 0.06 s | 3.50× |
| Requests 原文 | 19 | 0.21 s | 0.05 s | 4.20× |
| Requests 结构压缩 | 19 | 0.22 s | 0.07 s | 3.14× |

这六个场景中，耗时减少约 31%–76%，进程峰值 RSS 中位数为原版的 12.8%–16.6%。本工具的峰值 RSS 中位数为 25.1–31.8 MiB，原版为 154.3–239.0 MiB。RSS 是进程统计，不是所有子进程峰值的求和；wall 显示分辨率为 0.01 s，不能把显示相同的多轮结果解释为没有抖动。

固定输入版本与范围：

- [Repomix](https://github.com/yamadashy/repomix)：`80b4280a9196feace092fc672dfe2b5fac62ef08`，`src/**,LICENSE`。
- [Express](https://github.com/expressjs/express)：`1faf228935aa0a13111f92c28ee795be64ce3f0f`，`lib/**,LICENSE`。
- [Requests](https://github.com/psf/requests)：`0e322af87745eff34caffe4df68456ebc20d9068`，`src/requests/**,LICENSE`。

两端接受的文件集合相同。原版会 trim 正文，输出结构和 AST 保留策略也不同，因此不声称执行了逐字节相同的工作。优化前后的本工具则保持六个场景的文件正文和完整产物逐字节相同；计时外使用旧版 `encode().length()` 与新版 `count()` 复核完整文档，18 份输出计数全部相同。104 组独立 token ID 黄金数据以及完整 199,998 条词表的参考解码检查仍通过。

## 优化内容

- 资源通过同一句柄以最多 1 MiB 块有界读取；直接解析 ASCII/Base64/rank，保留两份 SHA-256、顺序、重复与单字节 token 覆盖检查。
- 精确计数复用 BPE 合并规则，减少 ID 数组、临时字节及重复片段分配；缓存局限于单次调用，编码器保持不可变。
- 安全扫描仍验证原文；无命中时不建立逐字符坐标表，命中时只计算实际边界的磁盘字节和行位置。
- glob 复用路径分段与动态规划行，literal 直接比较；规则顺序、否定、Unicode、Git 字节匹配、目录剪枝及原始输出保持不变。
- 批量任务定期让出执行机会，替代逐文件的固定 1 ms 定时等待，保留取消检查。

这些改动没有关闭扫描、缩减输入、使用近似 token 计数或引入跨进程结果缓存。当前也未使用文件处理线程池。

## 可复现的性能入口

`scripts/benchmark.mbtx` 是维护者工具，支持 Linux（GNU `/usr/bin/time`）和 macOS（`/usr/bin/time -lp`）。需要项目指定的 MoonBit 工具链、Node **25.9.0**、npm、Git，以及 Linux 的 `sha256sum` 或 macOS 的 `shasum`。Node 只用于开发对照，不是本工具运行依赖。运行目录为产品仓库根目录。

```sh
moon build --target native --release
# WORKSPACE 必须是尚不存在的绝对路径，位于源码 checkout 之外，例如临时目录下。
WORKSPACE="${TMPDIR:-/tmp}/moon-repomix-benchmark-unique"
moon run --target native scripts/benchmark.mbtx prepare "$WORKSPACE"
moon run --target native scripts/benchmark.mbtx run "$WORKSPACE" \
  _build/native/release/build/cmd/moon-repomix/moon-repomix.exe \
  assets/tokenizer-o200k_base.tiktoken
```

`prepare` 从上述三个公共 HTTPS Git 源按精确 commit 浅取，验证 HEAD，稀疏检出指定目录及 `LICENSE`，再核对 144/12/19 个文件。Git 禁用 hooks、凭据 helpers、fsmonitor、全局配置和子模块递归。参考 CLI 安装命令固定为 `npm install --ignore-scripts --no-audit --no-fund --save-exact repomix@1.18.1`；安装目录、锁文件和缓存均位于 workspace，不改项目依赖。不会执行语料的脚本、JS 配置或 processors。下载仅访问公共源；不会上传本地源码。下载/安装失败属于 **setup failure**，不是性能落后；不自动重试。

已有固定源码和参考 CLI 时，可以离线复用，免去重新下载、安装：

```sh
moon run --target native scripts/benchmark.mbtx local "$WORKSPACE" \
  "$REFERENCE_CLI" "$REPOMIX_SOURCE" "$EXPRESS_SOURCE" "$REQUESTS_SOURCE"
# 再执行上述 run 命令。
```

`local` 仅复制指定范围的普通文件，拒绝符号链接，核对文件数和复制前后 SHA-256；不改原目录，也不运行其中的代码。此模式将固定 revision 标为维护者声明，**不冒充远程 HEAD 验证**；实际文件清单与散列始终保存。两种准备方式都会拒绝已有 workspace；同一 workspace 只允许一次 `run`，失败证据不覆盖、不删除。要重新运行须明确选择新的 workspace，而不是择优重试。

### 契约、统计与产物

- 两端使用显式 JSON 配置、安全扫描、o200k_base、parsable JSON、`--top-files-len 0`；Node 的 `input.processors=[]`、`output.git.sortByChanges=false`，不改变正常线程池。
- 子进程只继承白名单环境。每批新建 HOME/XDG/TMP 和 `REPOMIX_TOKEN_CACHE_PATH`，预热后保留常规缓存；每个场景每端预热一次，再以新进程交替先后运行五轮。预热不纳入统计。
- 保存每次命令参数、exit、stdout、stderr、wall、user/sys CPU、RSS、输出大小/散列、接受集合和 API 检查。非零退出、已知计数失败警告、集合/源正文/API/ranges 不完整或批内输入/程序资源变化均 hard fail。原文 Native 逐字节对源文件，Node 允许自身 trim 行为；各端产物必须逐轮稳定。
- 压缩额外执行一次**计时外** Native `--full-metadata`：正文须与计时输出一致，记录须覆盖全部接受文件，ranges 有序且在原始行界内，检查独立抽样 API 的源行覆盖，fallback 正文逐字节完整；拒绝解析失败等异常 fallback。它不是对整个语法树的等价证明。Node 压缩的 API 缺失只记录策略差异，不作为 Native 等价守卫。
- GNU time 的 `%M` 从 KiB 换算为 bytes，macOS RSS 已是 bytes；报告 wall 来自 elapsed/real，绝不把 user+sys 当 wall。RSS 不代表所有进程峰值之和。
- `report/REPORT.md` 给出每个 case 的 wall/RSS `better` 或 `not-better` 及所有不利 case；`summary.json` 保存全部五轮样本、median/min/max/MAD，`rounds.json` 保存逐轮记录。没有共享 runner 的性能硬阈值，不丢慢样本、不按胜负决定退出码。CI 绿不代表任意平台都更快。

`report/complete.json` 仅在全批校验结束后生成；`setup-started.json` / `setup-complete.json` 区分准备进度。失败时查相应命令的 `logs/*.exit.json`、stdout/stderr 和 CI step 日志；进程启动失败可能只有 command 记录。所有 workspace 内容保留，工具不执行 cleanup。计时外检查可独立重验已保存的 documents，不重跑计时：

```sh
moon run --target native scripts/benchmark.mbtx verify "$WORKSPACE"
```

Linux CI 复用已有 release CLI，运行同样六场景；macOS/Windows 功能测试不增加性能矩阵。`performance-linux-x64` artifact 在成功或失败时都尝试上传，**仅含 `report/`、`logs/`、`manifest/`**，不含语料、documents、node_modules、cache 或完整环境。离线 `verify` 需要本机保留的 documents，不能只靠精简 CI artifact 重跑。三 OS 另外上传 `moonbit-self-pack-*`，范围仅为 `dist/self-pack/moonbit-*` 的真实 MoonBit 自打包证据。

### 开发依赖与数据许可

工具独立导入 [moonbitlang/async 0.22.5](https://github.com/moonbitlang/async)（Apache-2.0），不修改产品运行时依赖；对照使用 [Node.js 25.9.0](https://nodejs.org/)（MIT，含第三方声明）和 [Repomix 1.18.1](https://www.npmjs.com/package/repomix/v/1.18.1)（MIT，其 npm 依赖另有各自许可）。三个语料来自前述固定公共 Git commit：Repomix、Express 为 MIT，Requests 为 Apache-2.0；准备阶段保留各仓库 `LICENSE`。它们只作开发测试输入，不打进产品发行包；再分发语料或 npm 依赖时应同时遵守各自许可/声明。

原版 parsable-style 也计数完整文档；其大于 1,000,000 UTF-16 单位的输出会分块处理。本批都低于该阈值。本工具始终计数完整输出，不用分块或逐文件求和代替预算计数。

## MoonBit 压缩是单独能力

原版未提供 MoonBit grammar，不能把其未执行 MoonBit 压缩算作同功能性能胜利。本工具当前 76 份源码/接口都能通过 AST 解析；默认安全流程排除含合成测试凭据的一份文件，实际导出其余 75 份。

在同一接受集合上，完整 JSON 从 87,133 降至 19,389 tokens，减少 77.7%；60 份应用压缩，15 份保持原文，包括完整保留的 12 份 `.mbti`。另核对了 235 个完整声明 header 与原始行范围。完整元数据模式为 28,186 tokens，按需选择；两种模式文件正文相同。
