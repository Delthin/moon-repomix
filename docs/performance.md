# 性能与测量方法

2026-10-27 的架构优化在固定 35 MB TypeScript 大库中，使 macOS 和 Linux 两批的原文及完整元数据压缩 CLI 耗时中位数均低于原版。各批结果对应固定输入、选项和平台，CLI 与常驻 MCP 分开测量；历史不利结果保留在下文。

## 2026-10-27：Linux 大库复验

测量源码为 `4bf0d990ceb656c2dddf267315bd914ea5888d71`，[完整工作流与原始材料](https://github.com/Delthin/moon-repomix/actions/runs/40432025882) 保留了全部样本。环境是 GitHub-hosted `ubuntu-latest` x64（实际 Ubuntu 26.04 image），MoonBit `0.10.15+943464bfa` native release，Repomix `1.18.1` / Node `25.9.0`，使用 GNU `/usr/bin/time`；没有单独记录 CPU 型号。

输入与下文相同：TypeScript v5.9.3 的 736 份源码/许可、35,182,011 bytes，另有 chi 8 份和 itoa 4 份。三源 × 原文/完整元数据压缩 × Native/Node，每端每场景预热一次后交替运行五轮，共 **12 预热、60 正式、72 份完整 JSON**，全部退出 0。所有构建、依赖安装和准备在预热前完成；正常 Node workers 与预热后缓存保留。源码、407 份 tracked 文件散列、二进制、词表/Unicode、配置和参考安装身份在批前后相同。离线复核 36 份 Native stderr 报告及已有正文/API/ranges/fallback/stability，不再调用产品。

以下为五轮中位数，wall 单位秒，RSS 为被测进程峰值 MiB（不是全部 worker 合计）。

| 场景 | Native wall | Node wall | Native RSS | Node RSS |
| --- | ---: | ---: | ---: | ---: |
| TypeScript 原文 | 1.82 | 2.62 | 353.8 | 995.7 |
| TypeScript 完整元数据压缩 | 2.40 | 3.59 | 322.2 | 934.3 |
| chi 原文 | 0.09 | 0.27 | 36.8 | 158.7 |
| chi 完整元数据压缩 | 0.09 | 0.34 | 38.1 | 188.6 |
| itoa 原文 | 0.08 | 0.28 | 36.2 | 158.0 |
| itoa 完整元数据压缩 | 0.08 | 0.32 | 38.1 | 191.8 |

六场景 wall/RSS 均较低；TypeScript 原文/压缩 wall 分别降低 **30.5% / 33.1%**，RSS 降低 64.5% / 65.5%。全部慢样本保留，例如 Node TypeScript 压缩最大 4.24 s、Native chi 原文最大 0.19 s。速度不决定工作流退出码，绿灯表示执行和正确性守卫通过；本批没有同机旧 Native 基线，也不据两台机器的绝对秒数判断平台优劣。

Linux 的压缩结果有一项平台差异：六轮均为 **534 applied、1 timeout**（另有 116 `not-fewer-tokens`、45 `not-smaller`、35 `unsupported`、4 `parse-error`）。`src/compiler/checker.ts` 触及原有 200 ms 边界，完整原文回退、ranges 为空；其余 734 份正文与 macOS 同配置输出相同。Linux 压缩整文为 **8,087,099 tokens / 30,210,970 bytes**，不能沿用 macOS 的 7,739,936 / 28,488,489。已下载的 36 份 Native 产物中，另五场景的 30 份完整文档与 macOS 逐字节相同；TypeScript 压缩的六份差异均来自这一回退及对应元数据，没有为取得相同输出放宽限额或重测。

Native 仍因凭证规则接受 735 份 TypeScript、Node 接受 736；Node 大文分块计数、压缩保留策略和 API 差异沿用下文说明。这是固定端到端工作负载比较，不是相同计算工作的证明。冻结 Linux binary SHA-256 为 `e86035443cee84044c97bff3aac5de8da81aa4da775c9cb0dbf332134314f81b`。对应源码的[三平台常规 CI](https://github.com/Delthin/moon-repomix/actions/runs/40432024550) 也完整通过：macOS/Linux 各 106/106，Windows 103/103；Windows 大库性能和新的常驻 MCP/WebUI 性能尚未测量。

## 2026-10-27：精确计数内核与滚动 AST 流水线

测量源码为 `c168b83336566c2bd42f690e2d8086b768530aca`，对照旧 Native 为 `0a44c422319624440602cc583d7199c4496a6ccc`。两端均使用 MoonBit `0.10.15+943464bfa` native release；原版为 Repomix `1.18.1` / Node `25.9.0`。环境为 Apple M4、10 核、16 GiB、macOS 26.2，使用 `/usr/bin/time -lp`。

这次调整了计算和调度方式：

- 私有 C 内核直接在整文 UTF-8 上执行原有预切分和精确 BPE，使用不可变词表索引和平坦 scratch/heap。每次 pack 独立的 `CountSession` 在原文、候选、最终文档、分卷及最终索引之间复用有界 clock 缓存；`Encoder` 的独立调用与其他请求保持隔离。原 MoonBit 编码路径继续用于差分和精确保守回退，资源与合并规则保持原样。
- 严格 UTF-8 解码产生不可伪造的快照证明，输入扫描复用该证明；公开 String 扫描入口继续验证完整文本。固定凭证检测器先检查必要字面条件，仅为最终保留的发现计算字节与行坐标，规则和整文件排除策略保持原样。
- 读取、扫描和源配额仍串行执行。最多三条各一 worker 的纯 C AST lane 处理已筛选快照；任一源完成即可释放其槽并接收下一源，不再等待四文件批中的慢源。主线程随后物化、计数已完成源，按原始序号发布所有正文、统计和元数据。C 线程不操作 MoonBit 托管对象。
- AST 子节点改用前向 cursor；每次 Selection 的类型分类缓存不超过 16 KiB，按实际 alias-aware 类型名称匹配，碰撞重分类、分配失败回原谓词。parser 的 200 ms、8 MiB、512 层和 65,536 片段边界保持原样。

原生工作状态仍受全进程 4 workers / 4 jobs / 16 MiB 源副本限制。Root 的三个活跃快照权重合计不超过 16 MiB，另有一个当前快照；超 8 MiB 单源先排空再走原串行路径。取消和错误均停止工作并等待全部 lane 关闭。缓存上限及 C 所有权见 [tokenization](tokenization.md) 和 [compression](../src/compression/README.md)。

输入沿用下文固定 TypeScript v5.9.3、chi、itoa：736 / 8 / 4 份源码与许可，TypeScript 为 35,182,011 bytes。原文与 `--compress --full-metadata` 均输出完整 JSON。先完成三轮三方诊断，再从同一冻结候选做一次五轮正式比较：每场景每端一次预热，轮换旧 Native、新 Native、Node 的顺序；18 预热、90 正式，共 108 workload 全部退出 0，无重试、丢样或挑选重测。正常 Node workers 与预热后的独立缓存保留，计时期间源码和编译停止。

下表为五轮中位数；wall 单位秒，RSS 为被测进程峰值的 MiB（1,048,576 bytes），不是所有 worker 合计。

| 场景 | 旧 Native wall | 新 Native wall | Node wall | 旧 → 新 Native RSS | Node RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| TypeScript 原文 | 2.33 | 1.05 | 1.37 | 364.2 → 367.4 | 1,248.5 |
| TypeScript 完整元数据压缩 | 3.83 | 1.43 | 1.62 | 302.3 → 328.0 | 1,128.1 |
| chi 原文 | 0.03 | 0.04 | 0.19 | 25.3 → 31.8 | 153.2 |
| chi 完整元数据压缩 | 0.04 | 0.05 | 0.20 | 26.5 → 33.2 | 180.3 |
| itoa 原文 | 0.03 | 0.04 | 0.19 | 25.3 → 31.6 | 152.4 |
| itoa 完整元数据压缩 | 0.03 | 0.04 | 0.20 | 26.9 → 33.3 | 189.1 |

TypeScript 相对同批 Node，原文 wall 降低 **23.4%**、压缩降低 **11.7%**；相对旧 Native 降低 54.9% / 62.7%。新版原文五轮为 `[1.06,1.03,1.05,1.02,1.05]`，压缩为 `[1.41,1.41,1.43,1.43,1.43]`；Node 分别为 `[1.40,1.37,1.35,1.40,1.35]`、`[1.47,1.46,1.65,1.62,1.97]`，全部样本保留。

代价同样保留：TypeScript RSS 相对旧 Native 增加 0.9% / 8.5%；四个小场景各增加约 0.01 s，RSS 增加约 24%–26%，仍低于本批 Node。五轮本机结果不代表统计显著性或跨平台保证；这批仅测 macOS，后续 Linux 复验见上节，常驻 MCP 和 WebUI 不在此批范围。

36 对旧/新 Native 完整 JSON 逐字节相同，schema-1 的精确 tokens、bytes、安全发现、集合、配额、metadata/ranges/fallback 均核对通过。TypeScript 原文仍为 9,709,413 tokens / 37,206,811 bytes，完整元数据压缩为 7,739,936 / 28,488,489。metrics 16/16、compression 16/16、security 7/7、Root 五个定点组及取消/配额清理检查通过；新 C 内核、选择器与所有权有独立差分和 ASan/UBSan 证据，线程池未变层复用既有 TSan，不能据此声称全部 managed 桥或跨平台验证完成。

两端工作差异仍存在：Native 因凭证规则排除一份测试文件，接受 735 份，Node 接受 736 份；Node 大文 token 按 200,000 UTF-16 单位切片后求和，本批原文/压缩推得 184/131 块，Native 精确计数整份文档。各端压缩保留策略和输出也不同。该结果是固定端到端工作负载对比，不是计算工作完全等价的结论。

冻结新二进制 SHA-256 为 `070b1b0a7a8b70bf96075bc5c1ff4f6b84e0868d1cdc05f5607da5ece27392a9`，旧 Native 为 `2313e5ca94370ef08699860a27f48467f29e45c5226db4b06a85077f394dfa60`。固定语料和契约准备见 [大库复现方法](#复现与离线检查)；该历史入口绑定其自己的 binary 身份，复测新版须显式更新冻结身份并另建批次。

## 2026-10-26：UTF-8 预切分与 PEM 预筛选

基线源码为 `94e618c769b5febe7d1f4810b2eeeae9bd49dfee`，优化源码为 `0a44c422319624440602cc583d7199c4496a6ccc`。两端均使用 MoonBit `0.10.15+943464bfa` native release；对照为 Repomix `1.18.1`、Node `25.9.0`。环境为 Apple M4、10 核、16 GiB、macOS 26.2，使用 `/usr/bin/time -lp`。

改动集中在两个 CPU 热点：

- 预切分直接扫描整文唯一的 UTF-8 快照，BPE 借用其字节切片，移除整文 `Array[Char]` 及逐片重算字节终点；ASCII 走直接读取路径，Unicode 类别、正则分支顺序、回退和 BPE 合并规则保持原样。
- PEM 检测先检查固定 moon_scrub 0.5.2 七种私钥头共有的必要前缀，存在时运行完整匹配；其他凭证规则继续扫描完整快照。详见 [密钥扫描](security.md)。

输入复用下文的固定 TypeScript v5.9.3、chi 和 itoa，包含相同源码、许可及配置：736 / 8 / 4 份文件，TypeScript 原始输入 35,182,011 bytes。原文和完整元数据压缩均输出 JSON，Native 压缩启用 `--compress --full-metadata`。每场景、每端预热一次，再轮换旧 Native、新 Native、Node 的先后顺序运行五轮；共 18 次预热、90 次正式计时，108 次 workload 全部退出 0。常规线程池与预热后的缓存保留，测量期间停止源码修改和编译。

耗时是五轮 wall 中位数，单位秒；RSS 是被测进程峰值中位数，单位 MiB（1,048,576 bytes），不是所有 worker 的合计。

| 场景 | Native 耗时：旧 → 新 | 原版耗时 | Native RSS：旧 → 新 | 原版 RSS |
| --- | ---: | ---: | ---: | ---: |
| TypeScript 原文 | 2.97 → 2.67（−10.1%） | 1.61 | 393.0 → 364.3（−7.3%） | 1,179.3 |
| TypeScript 完整元数据压缩 | 4.52 → 4.27（−5.5%） | 2.13 | 366.1 → 302.5（−17.4%） | 1,055.0 |
| chi 原文 | 0.04 → 0.04 | 0.24 | 25.2 → 25.3 | 153.0 |
| chi 完整元数据压缩 | 0.05 → 0.05 | 0.23 | 26.3 → 26.5 | 179.5 |
| itoa 原文 | 0.04 → 0.04 | 0.21 | 25.2 → 25.3 | 152.3 |
| itoa 完整元数据压缩 | 0.04 → 0.04 | 0.22 | 26.8 → 26.9 | 183.9 |

Go/Rust 四项耗时中位数在 0.01 s 显示分辨率内持平，RSS 中位数增加 64–144 KiB（约 0.2%–0.5%）。TypeScript 新版原文耗时范围为 2.62–2.73 s（旧版 2.90–3.08），压缩为 4.20–4.44 s（旧版 4.49–4.56）。五轮结果是本机描述性测量，不作为统计显著性或其他平台保证。

36 对新旧 Native 完整产物逐字节相同；schema-1 报告的精确 tokens、bytes、安全发现、接受集合与配额字段相同，源正文/BOM、预定 API、完整压缩记录、有界有序 ranges 和回退正文检查均通过。metrics 10/10、security 5/5 定点测试通过，包含既有独立 token ID 黄金数据、UTF-8 边界及七种 PEM 头与未优化引擎的结果对照。

原版与 Native 的工作差异仍存在：TypeScript 原版接受 736 份，Native 排除一份命中凭证规则的测试文件、接受 735 份；原版大文计数按 200,000 UTF-16 单位分块后求和（本批原文 184 块、压缩 131 块，由输出长度和固定源码规则推得），Native 精确计数整份文档。各端输出和压缩保留策略也不同，不能将其视为完全等价的计算任务。本批未新增 Linux/Windows 或常驻 MCP 测量。

冻结二进制 SHA-256：

- 旧 Native：`390ccc169c07d586cb5c2679b0cea0dc86e1164151471ae52ef58dba63885e75`。
- 新 Native：`2313e5ca94370ef08699860a27f48467f29e45c5226db4b06a85077f394dfa60`。

完整固定输入与大库测量入口见 [大库复现方法](#复现与离线检查)；该入口绑定历史 binary 身份，复测新版时需显式使用上述新身份并另建批次。

## 先前六个小场景：测量环境

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

## Linux CI 复验

[CI 39874664420](https://github.com/Delthin/moon-repomix/actions/runs/39874664420) 在源码 `d5de18c67f27c37920134f00ae01ac865966ecf1` 上运行相同三源、两模式，使用 GNU time、Node 25.9.0 和 Repomix 1.18.1。每端每场景预热一次，再交替执行五轮；全部 60 次计时、12 次预热和 3 次计时外源映射检查完成，输入与程序散列在批内不变。

| 场景 | 本工具 wall 中位数 | 原版 wall 中位数 | 原版 / 本工具 |
| --- | ---: | ---: | ---: |
| Repomix 原文 | 0.24 s | 0.62 s | 2.58× |
| Repomix 结构压缩 | 0.36 s | 0.76 s | 2.11× |
| Express 原文 | 0.09 s | 0.40 s | 4.44× |
| Express 结构压缩 | 0.12 s | 0.53 s | 4.42× |
| Requests 原文 | 0.11 s | 0.43 s | 3.91× |
| Requests 结构压缩 | 0.15 s | 0.54 s | 3.60× |

六场景的 wall 与 RSS 中位数均更低，RSS 约为原版的 11.6%–16.5%，不利场景为零。`performance-linux-x64` artifact 保留所有样本、命令/退出码、配置与文件 SHA、API/ranges 检查和代表输出；共享 runner 的噪声仍需随每轮样本一起判断，CI 成功只表示执行及内容契约通过，胜负以报告为准。

同次三平台 CI 还压缩本项目真实 MoonBit 代码：75 个接受文件中 60 个应用压缩，12 个接口保持原文；含完整源映射的 JSON 从 87,133 降到 28,186 tokens。三端结果一致，`moonbit-self-pack-*` artifacts 可直接下载原文、骨架及诊断。

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

常规 CI 不运行性能比较，也不安装 Node 或下载对照语料。需要复测这组六场景时，手动执行上面的 `prepare/run/verify`；大源码工作负载另有文末的手动 workflow。历史 `performance-linux-x64` artifact 保存代表文档、样本和散列，但离线 `verify` 仍需恢复固定源文件。常规 CI 只在 Linux 执行一次真实 MoonBit 自打包，保留原文/骨架的接受集合、签名、接口和源行范围检查，上传 `moonbit-self-pack-linux-x64`。

### 开发依赖与数据许可

工具独立导入 [moonbitlang/async 0.22.5](https://github.com/moonbitlang/async)（Apache-2.0），不修改产品运行时依赖；对照使用 [Node.js 25.9.0](https://nodejs.org/)（MIT，含第三方声明）和 [Repomix 1.18.1](https://www.npmjs.com/package/repomix/v/1.18.1)（MIT，其 npm 依赖另有各自许可）。三个语料来自前述固定公共 Git commit：Repomix、Express 为 MIT，Requests 为 Apache-2.0；准备阶段保留各仓库 `LICENSE`。它们只作开发测试输入，不打进产品发行包；再分发语料或 npm 依赖时应同时遵守各自许可/声明。

原版 parsable-style 也计数完整文档；其大于 1,000,000 UTF-16 单位的输出会分块处理。上述先前六个小场景都低于该阈值。本工具始终计数完整输出，不用分块或逐文件求和代替预算计数。

## MoonBit 压缩是单独能力

原版未提供 MoonBit grammar，不能把其未执行 MoonBit 压缩算作同功能性能胜利。本工具当前 76 份源码/接口都能通过 AST 解析；默认安全流程排除含合成测试凭据的一份文件，实际导出其余 75 份。

在同一接受集合上，完整 JSON 从 87,133 降至 19,389 tokens，减少 77.7%；60 份应用压缩，15 份保持原文，包括完整保留的 12 份 `.mbti`。另核对了 235 个完整声明 header 与原始行范围。完整元数据模式为 28,186 tokens，按需选择；两种模式文件正文相同。

## 2026-10-24 大库、Go/Rust 与常驻 MCP

这批使用冻结的 native release：源码 `4a8c3e3c8f9ef89e14d624e9586b19799eded96e`，二进制 SHA-256 `67da22e745ca556a0e37bb9ea86d1813371d4951c7f504a431e016f3d07327b9`。工具链为 MoonBit `0.10.15+943464bfa`、脚本复用 async `0.22.5` 与 moonbitlang/x `0.5.5` crypto（均 Apache-2.0）；对照复用已隔离安装、带 package-lock 的 Repomix `1.18.1` 和 Node `v25.9.0`。o200k_base 产品资源 SHA-256 为 `446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d`。本次只执行 Apple M4 / macOS 26.2；下列数据没有新增 Linux 或 Windows 复验。

### 固定输入与新进程 CLI

| 来源 | 固定版本 / commit | 预先选定范围 | 源文件数 | 原始 bytes |
| --- | --- | --- | ---: | ---: |
| Microsoft TypeScript | v5.9.3 / `c63de15a992d37f0d6cec03ac7631872838602cb` | `src/**,LICENSE.txt` | 736 | 35,182,011 |
| go-chi/chi | `71307f9b7e4e9527638bc951c42b782cd1560331` | 7 份根目录 Go 源码与 LICENSE | 8 | 50,684 |
| dtolnay/itoa | `e2766b868e4ac1ae2bf5bea1ac43d4c0da23b899` | `src/**,LICENSE-MIT,LICENSE-APACHE` | 4 | 23,718 |

公开准备入口默认从三个公共 HTTPS Git URL 按上述固定 commit 稀疏检出，并验证 HEAD；TypeScript 还核对 v5.9.3 tag。itoa 的固定获取对象 `8ee97f64bf3cbfa42d357a2c39955fd062492e7d` 是 1.0.15 的带注释标签，脚本分别验证对象类型、解引用后的 `e2766b8…` 提交和检出 HEAD；原有源码/许可 SHA 保持相同。本表使用的 Go/Rust 源副本逐一符合内置的 12 份源码/许可 SHA-256；原定的全部声明/导入锚点也内置在脚本中，在线和离线准备均核对相同常量。TypeScript 为 Apache-2.0，chi 为 MIT，itoa 为 MIT/Apache-2.0 双许可；许可文件随语料保留，语料只作开发输入。独立输入只含选定文件、空 `.git` 边界及安全 JSON 配置，不执行仓库代码、JS 配置或 processors。TypeScript 不是从大库挑出的性能小样本。

每来源、模式、端点预热一次，接着交替先后顺序运行五个新进程：共 **60 次正式计时、12 次预热**。白名单环境中的独立 HOME/XDG/TMP/token cache 批内保留，普通线程池和安全扫描开启。这里的“新进程”不表示冷磁盘、冷 OS 页缓存或每轮清空 token cache。本表的压缩行是 Native **完整元数据压缩**（`--compress --full-metadata`）对照原版自身压缩，和前面六个小场景的 Native 默认轻量压缩不是同一工作。保留原有 72 份产物；18 份 Native 完整元数据压缩输出在计时外检查 ranges。

| CLI 场景 | Native wall 中位数 s | 原版 wall 中位数 s | Native RSS 中位数 bytes | 原版 RSS 中位数 bytes |
| --- | ---: | ---: | ---: | ---: |
| TypeScript 原文 | 2.89 | **1.61** | 412,352,512 | 1,426,980,864 |
| TypeScript 完整元数据压缩 | 4.45 | **1.97** | 384,057,344 | 1,152,647,168 |
| chi 原文 | 0.04 | 0.21 | 26,116,096 | 160,448,512 |
| chi 完整元数据压缩 | 0.04 | 0.23 | 27,590,656 | 188,940,288 |
| itoa 原文 | 0.04 | 0.21 | 26,083,328 | 159,514,624 |
| itoa 完整元数据压缩 | 0.04 | 0.24 | 27,688,960 | 190,693,376 |

TypeScript 两项都是 Native 更慢；Go/Rust 四项 wall 和 RSS 中位数较低。macOS `/usr/bin/time -lp` 的 RSS 本来就是 bytes，表示被测进程峰值而非子进程之和，wall 分辨率为 0.01 s。每批 `report/summary.json` 保存全部五轮 wall、user、sys、RSS 样本及 median/min/max/MAD；`logs/` 保存命令、退出码和原始 time 输出。统计包含全部慢样本、回退和输出差异。

Native 的 `--quiet --report-json` 在 **stderr** 输出 schema-1 JSON，time 行另行解析。36 份保留报告均为 `status=ok`、`operation=pack`、`publication=committed`、`exitCode=0`、`style=json`，单文件输出，安全检查开启；`maxFiles=20000`、`maxTotalSize=209715200` bytes，token limit 为 null、exceeded=false，index tokens/bytes 均为 0。接受集合、声明 bytes 与实际输出、documents/index/total 算术、精确计数字符串、相同输出 SHA 的计数稳定性和 time 指标均离线核对。

| Native CLI 场景 | 接受 / 跳过 | 安全状态 / findings | 完整文档精确 tokens | 输出 bytes |
| --- | ---: | --- | ---: | ---: |
| TypeScript 原文 | 735 / 2 | excluded / 1 | 9,709,413 | 37,206,811 |
| TypeScript 完整元数据压缩 | 735 / 2 | excluded / 1 | 7,739,936 | 28,488,489 |
| chi 原文 | 8 / 1 | passed / 0 | 16,410 | 55,329 |
| chi 完整元数据压缩 | 8 / 1 | passed / 0 | 11,007 | 44,274 |
| itoa 原文 | 4 / 1 | passed / 0 | 6,214 | 24,648 |
| itoa 完整元数据压缩 | 4 / 1 | passed / 0 | 6,199 | 25,112 |

这里的 tokens 来自保留的 Native 完整文档精确计数报告；离线复核不再次编码或启动 CLI。itoa 的完整元数据压缩产物 bytes 比原文更大，不能把正文压缩等同完整输出变小。

内容与工作差异直接影响解读：

- Native 实际接受 TypeScript **735/736** 份；`src/testRunner/unittests/services/colorization.ts` 的合成 `token: string` 测试命中 `credential-assignment`，被安全扫描排除。原版接受 736 份。只读路径解释保留了 `SecurityFinding`、规则和 19,156 readBytes；输入与扫描器保持原样。这不是相同接受集合的对比。Go/Rust 两端接受集合相同。
- Native 每份 TypeScript 压缩输出都为 535 applied、116 `not-fewer-tokens`、45 `not-smaller`、35 `unsupported`、4 `parse-error`；六轮一致，没有观察到 timeout。四份解析回退为 `src/compiler/transformers/utilities.ts`、`src/compiler/types.ts`、`src/lib/es2015.symbol.wellknown.d.ts`、`src/services/exportInfoMap.ts`，全部保留原文、空 ranges，而不是关闭保护。chi 为 7 applied + 1 许可原文，itoa 为 2 applied + 2 许可原文。
- 原文检查遵循各自输入契约：Native 仅去掉一个初始 UTF-8 BOM，原版 trim；原始 bytes/SHA 始终对磁盘文件统计。Native 的接受集合、回退正文、完整记录、有序有界 ranges 和抽样声明源行覆盖均严格检查。
- TypeScript 的 7 个声明/导入锚点在 Native 全部保留。原版压缩保留抽样声明，但省去 program 的 performance 导入和 session 的 protocol 导入。Go/Rust 的 42 个预定 API/图锚点在 Native 全部保留；原版 itoa 压缩缺少 `#![no_std]`、关联 `Buffer` 类型、`write` trait 方法和 no-panic 属性四项。它们是内容策略差异，不包装成同功能速度收益。另在源文件上核对了两条 TypeScript import 的目标以及 Rust `mod udiv128` 的目标文件与散列。
- 原版对大于 1,000,000 UTF-16 单位的文档，按 200,000 单位切片独立计数再求和。TypeScript 原版原文为 36,661,647 单位 / **184 块**，压缩为 26,099,066 单位 / **131 块**；Native 仍精确计数完整文档。因此不能称为同一种完整文档计数工作。Go/Rust 未超过阈值。

### 真正常驻 MCP：同一 PID 的重复 pack/read

固定在同一 TypeScript commit，测量前将范围限定为 **`src/server/**,LICENSE.txt`，18 份、817,532 原始 bytes**。这与上述 35 MB 单库 CLI 是不同工作负载。先通过原版真实 `tools/list` 检查 schema，确认安装版本的 `pack_codebase` 支持 `style:"json"`，`read_repomix_output` 支持完整读取；未替换或修改 SDK。

两端协商 **2025-06-18**。每模式每端各启动一个真实常驻服务器，在同一进程中执行 1 次预热 + 5 次重复事务：pack 后读完所有产物。共 **4 个正式服务器、4 次预热、20 次正式事务**，另有 1 个只读 schema 探测进程。Native 使用 `pack_repository` + 逐资源 `resources/read`，原版使用 `pack_codebase` + 无行范围的 `read_repomix_output`，校验 `linesRead == totalLines`。每轮 PID 和 wrapper/PPID/RSS 收据证明没有在轮间重启。

Native host 为每卷 96,000 tokens、总输出上限 16,777,216 bytes、最多 32 卷，单资源 4 MiB 保护保持开启。原文读 4 卷 + index，共 862,593 bytes；压缩读 2 卷 + index，共 462,422 bytes（index 包含压缩 ranges）。原版分别读 1 份 862,303 / 408,088 bytes 的 JSON，工具的 `topFilesLength` schema 最小值为 1。两端都接受全部 18 份，原文与三项声明/导入锚点核对通过；原版压缩依然省去 protocol 导入，Native 保留。

| 模式 / 端点 | spawn 至 initialize ms | pack 中位数 ms | 读全中位数 ms | pack+读全中位数 ms | 生命周期 peak RSS bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 原文 Native | 38 | 86 | 350 | 436 | 40,878,080 |
| 原文 原版 | 227 | 112 | 3,703 | 3,815 | 251,002,880 |
| 压缩 Native | 39 | 130 | 170 | 300 | 40,271,872 |
| 压缩 原版 | 224 | 201 | 875 | 1,078 | 287,621,120 |

这些是此本地客户端的实际事务时间：包含 RPC 传输、MoonBit 客户端 JSON 解码、完整 NDJSON 归档和官方 read 工具的包装，不是纯服务器计算时间。原版响应中的正文包装/重复、Native 的资源分卷与压缩索引、产物字节数也不同；不据此给出算法速度倍数。pack 时间不含后续读全，initialize 单列、不摊入五轮。全部五轮分别保留 pack/read/e2e 的样本与 median/min/max/MAD；例如 Native 原文 e2e 为 `[436,435,455,435,818]` ms，818 ms 慢轮同样纳入，压缩读全 431 ms 的慢轮也保留。

RSS 的两种测量分别保留：`time -lp` 覆盖整个服务器生命周期；`ps` 在 initialize 和每轮响应/计时外校验后采样实际子进程，KiB 乘 1024 转为 bytes。初始化 → 第五轮 idle RSS，原文 Native 为 25,640,960 → 40,861,696，原版为 83,296,256 → 224,198,656；压缩 Native 为 25,657,344 → 40,255,488，原版为 83,165,184 → 255,279,104。没有强制 GC；idle 不是最小稳态内存。

Native 每次 pack 后旧 URI 返回 `-32002`，`release_context` 后资源列表为空、最后 URI 也失效；释放后 RSS 未立即下降，不能把资源失效等同 allocator 归还。原版没有相同释放工具，旧 outputId 仍可真实读出，临时文件在本批 owned TMP 下保留。旧 ID 检查在计时外完成，生命周期 RSS 也包括这些检查。Native stdin EOF 正常退出 0；两次原版会话在全部六次事务完成后对核验的自有 PID 发送 SIGTERM，实际退出 **-15，并非干净退出 0**，原始收据为准。

### 复现与离线检查

从产品根运行这两个聚焦 `.mbtx`。`CLI_WORK`、`MCP_WORK` 为尚不存在的绝对路径；`REFERENCE_CLI` 为已有隔离 npm 项目中 Repomix 1.18.1 的 `bin/repomix.cjs` 绝对路径，项目根须保留 `package-lock.json` 以便归档（脚本不安装依赖）。默认 `prepare` 仅需这两个参数，不需要外部 hash/anchor 文件或私有源码目录：它按公开 URL 和固定 SHA 安全检出 TypeScript、chi、itoa，只复制选定源码与许可，不执行这些仓库的代码或 JS 配置。

`FROZEN_NATIVE` 是上述固定 SHA256 二进制的绝对路径，`VOCAB_ABSOLUTE` 是仓库 `assets/tokenizer-o200k_base.tiktoken` 的绝对路径。本组 `run` 明确校验冻结产品/词表/原版身份；不同的自建 binary 需要维护者显式更新固定身份、另建批次，不可冒用本表。

```sh
moon run --target native scripts/benchmark-workloads.mbtx -- prepare "$CLI_WORK" "$REFERENCE_CLI"
moon run --target native scripts/benchmark-workloads.mbtx -- run "$CLI_WORK" \
  "$FROZEN_NATIVE" assets/tokenizer-o200k_base.tiktoken
moon run --target native scripts/benchmark-workloads.mbtx -- verify "$CLI_WORK"

moon run --target native scripts/benchmark-resident.mbtx -- prepare "$MCP_WORK" "$CLI_WORK"
moon run --target native scripts/benchmark-resident.mbtx -- probe "$MCP_WORK" \
  "$FROZEN_NATIVE" "$VOCAB_ABSOLUTE" "$REFERENCE_CLI"
moon run --target native scripts/benchmark-resident.mbtx -- run "$MCP_WORK" \
  "$FROZEN_NATIVE" "$VOCAB_ABSOLUTE" "$REFERENCE_CLI"
moon run --target native scripts/benchmark-resident.mbtx -- verify "$MCP_WORK" "$CLI_WORK"
```

若已有同范围源副本，可选 `benchmark-workloads.mbtx -- local NEW_CLI_WORK REFERENCE_CLI SOURCE_ROOT`；`SOURCE_ROOT` 下是 `typescript/`、`chi/`、`itoa/`。该入口不联网，仍核对内置 12 SHA、文件数/bytes 和全部锚点，但不把本地 TypeScript 声称为已验证远端 HEAD。`verify-prepared NEW_CLI_WORK PRIOR_CLI_WORK` 可逐文件比较已验证源批的全部 748 个 SHA，确认准备逻辑没有换语料。

每批自带 `manifest/`（固定来源、逐文件 SHA、配置及运行身份）、`logs/`（完整 argv、退出码、stdout/stderr/time）、`documents/` 和 `report/`。CLI `verify` 同时产出 `report/native-stderr-audit.json`；`audit-reports CLI_WORK` 可仅复核原生 stderr 报告。常驻各 session 保存真实工具 schema、NDJSON、pack/read 正文、固定 PID/PPID/RSS、退出码及全部五轮统计；`verify` 的末尾可选新收据路径，避免覆盖旧证据。关闭结果以 `exit.json` / `shutdown-result.json` 的实际状态为准，`/bin/kill` 返回 0 只证明信号发送成功。

脚本不安装原版依赖、不清理用户缓存，已有目录拒绝覆盖；没有盲重试。可用 `--target-dir` 将编译产物放到独立目录。上述历史批仅实测 macOS，未测 Linux/Windows、冷页缓存、付费模型；协议、内容与性能结果不能外推。

### 当前源码的 Linux 大库复验入口

`.github/workflows/benchmark-large.yml` 仅由 **workflow_dispatch** 手动运行，不随 push 自动测量。它检出 dispatch 所选 ref，以 `github.sha` 冻结源码身份，使用 [moon-toolchain](../moon-toolchain) 固定的 MoonBit（当前 `0.10.17+d971670cd`）和 Node `25.9.0`，只构建 native release CLI；上方历史样本仍对应各自记录的旧工具链，未来运行单独记录源码与编译器身份；参考 Repomix `1.18.1` 在 runner 临时目录独立安装，禁止生命周期脚本并归档 package-lock。语料与上文相同，所有编译、安装和准备均在预热前完成。此入口已完成上节 Linux 五轮实测；未来运行仍保留有利与不利结果，速度不作为通过条件。

也可在 Linux 的干净产品 Git 根目录直接复现；先准备指定工具链、Node、npm、Git 和 GNU `/usr/bin/time`，再使用各自尚不存在的绝对临时路径：

```sh
moon update
moon run --target native scripts/check-toolchain.mbtx
moon build --target native --release src/cmd/moon-repomix
REFERENCE_INSTALL="${TMPDIR:-/tmp}/moon-repomix-large-reference-unique"
CLI_WORK="${TMPDIR:-/tmp}/moon-repomix-large-workload-unique"
mkdir "$REFERENCE_INSTALL"
(cd "$REFERENCE_INSTALL" && npm install --ignore-scripts --no-audit --no-fund --save-exact repomix@1.18.1)
REFERENCE_CLI="$REFERENCE_INSTALL/node_modules/repomix/bin/repomix.cjs"
NATIVE_CLI="$PWD/_build/native/release/build/cmd/moon-repomix/moon-repomix.exe"
SOURCE_REVISION="$(git rev-parse HEAD)"
NATIVE_SHA256="$(sha256sum "$NATIVE_CLI")"
NATIVE_SHA256="${NATIVE_SHA256%% *}"
moon run --target native scripts/benchmark-workloads.mbtx -- prepare "$CLI_WORK" "$REFERENCE_CLI"
moon run --target native scripts/benchmark-workloads.mbtx -- run-verified "$CLI_WORK" \
  "$NATIVE_CLI" "$PWD/assets/tokenizer-o200k_base.tiktoken" "$SOURCE_REVISION" "$NATIVE_SHA256"
moon run --target native scripts/benchmark-workloads.mbtx -- verify "$CLI_WORK"
```

`run-verified WORKSPACE NATIVE VOCABULARY FULL_SOURCE_REVISION EXPECTED_BINARY_SHA256` 要求显式的 40/64 位小写十六进制身份，校验 binary 实际散列、Git HEAD 和干净状态（允许 ignored 构建产物）。预热前与全批后核对全部 tracked 源文件 SHA、源码身份、binary、词表/Unicode、配置、参考 CLI/package/原始与归档 lock；`manifest/verified-before.json`、`verified-after.json` 保存调用者期望、实际 revision、binary bytes/SHA 和各项散列，`run.json` 继续记录计时协议与运行散列。历史 `run/resume` 仍绑定 `67da22e7…`，身份要求不变；新 `run-verified` 不复用历史收据。纯参数/身份回归可运行 `moon run --target native scripts/benchmark-workloads.mbtx -- selftest-identity`，不调用产品或公网。

仍为三源 × 两模式 × 两端 ×（一次预热 + 五轮），共 **72 次 workload / 72 份完整 JSON**；计时参数、顺序和正文/schema-1/API/ranges/fallback/stability 守卫不变，正常 Node workers 与预热后缓存保留。`verify` 离线复核已保存产物，不再启动产品；需恢复同一固定输入，不能仅凭 artifact 重验。workflow 无论测量成功或失败都尝试上传 `performance-large-linux-x64-*`：包含 `report/`、`logs/`、`manifest/`、配置、构建/安装日志及 **全部 documents/**（不只预热），保留 14 天；不上传语料、node_modules、Git 目录、HOME/TMP 或 token cache。所有慢样本保留，速度不决定退出码；执行或正确性失败仍使 job 失败，不伪装成性能落后或成功。
