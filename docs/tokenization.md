# o200k_base 分词

`Delthin/moon_repomix/metrics` 是 native 离线编码器，以 **tiktoken 0.14.0 的 `encode_ordinary`** 为兼容基线。`<|endoftext|>`、`<|endofprompt|>` 等特殊标记按普通文本编码；输入为 Unicode 字符串，保留原有形式。UTF-8 解码由调用者完成。

## 接口与资源

```moonbit
pub async fn Encoder::load(path : String) -> Encoder
pub fn Encoder::encode(self : Encoder, text : String) -> Array[Int]
pub fn Encoder::count(self : Encoder, text : String) -> Int
```

向 `load` 传入词表的绝对文件路径，词表同目录须有 `tokenizer-unicode-16.0.0.txt`。源码中的词表名为 `assets/tokenizer-o200k_base.tiktoken`；完整安装后的布局为：

```text
<prefix>/
  bin/moon-repomix                 # Windows 为 moon-repomix.exe
  share/moon-repomix/
    o200k_base.tiktoken
    tokenizer-unicode-16.0.0.txt
  LICENSES/
```

`load` 在解析前校验两份资源的 SHA-256。每份资源通过同一个打开的文件句柄按最多 1 MiB 的块读取，缓冲区上限为原资源字节数加一；短文件及超长文件仍由摘要校验拒绝，解析使用同一份字节快照。读取结束、失败或取消时关闭句柄。词表直接从 ASCII 字节解析 Base64 token 与十进制 rank，验证顺序、重复项、完整条目数和全部 256 个单字节 token。相对路径和校验失败抛出 `ResourceError(String)`；文件系统错误、解码错误和取消向调用者传播。加载后可重复使用同一编码器，`encode`/`count` 不执行 I/O，也不修改共享状态。

库由调用者提供资源路径；CLI 根据可执行文件位置定位资源。标准 `_build/native/{debug,release}/build/cmd/moon-repomix/` 构建使用源码根的 `assets/tokenizer-o200k_base.tiktoken`，安装布局使用 `../share/moon-repomix/o200k_base.tiktoken`。路径解析以实际可执行文件为准，与工作目录无关；自定义构建位置可用 `--tokenizer-path` 覆盖。`moon build` 只构建程序。完整安装使用 `scripts/install.mbtx`；只需复制分词资源和许可时，可运行：

```sh
moon run scripts/tokenizer-install-assets.mbtx --target native /absolute/repo /absolute/package/share/moon-repomix
```

该辅助脚本校验并复制两份运行资源及许可，重跑会覆盖对应文件，保留其他文件。`tokenizer-cases.json`、`tokenizer-golden.json` 是开发夹具。黄金 JSON 将 U+FFFE/U+FFFF 写为 `\ufffe`/`\uffff`，解析后的字符串及 token ID 不变，JSON 文件本身可作为 XML 正文。

最终 token 总数须对完整渲染文档一次编码。BPE 和预切分可能跨拼接边界变化，因此各片段计数相加不能代替总数。`count` 与 `encode` 共用预切分、合并顺序和 rank 规则，只累计合并后的符号数，省去完整 ID 数组及最终 rank 回查。

## Token 分布与排名

```sh
moon-repomix ./project --top-files-len 10 --token-count-tree 100
```

CLI 默认在 stderr 显示正文 token 数最多的 5 个文件，包含相对路径和磁盘字节数；`--top-files-len 0` 关闭排名。计数相同时按 UTF-8 相对路径字节排序。

`--token-count-tree` 开启统计树。省略阈值时显示全部节点，包含 token 数为 0 的空文件；指定 N 时，仅显示计数 ≥ N 的文件或目录。每层先列文件，再列目录，各自按 UTF-8 路径字节排序。名称以 JSON 字符串显示，转义换行和终端控制字符。

目录计数是所有已接受后代文件正文计数之和，筛选阈值不改变这个和。因此，一个目录可能达到阈值，而它的每个子节点都低于阈值，此时只显示目录及其总数。树根显示所有已接受文件的计数之和；空结果或没有节点达到阈值时附有提示。被忽略、扫描命中或因读取/格式问题被跳过的文件不参与排名和树统计。

报告复用打包时的 `FileStats`，不会重新读文件或分词；`--quiet` 隐藏报告，`--stdout` 的正文保持不变。**文件与目录计数用于定位上下文占用，预算仍以最终完整文档的一次编码为准。** 删除一个文件实际减少的 token 数还受包装和拼接边界影响。

库调用者可从 `PackResult.files` 读取逐文件计数：`original_tokens` 是原始正文，`tokens` 是加显示行号和格式转义之前的处理后正文。开启压缩时，排名和目录统计采用该计数；最终预算还包含实际路径、显示行号、来源、压缩记录和 Git 章节。`Options.top_files_length` 和 `Options.token_count_tree` 只控制 CLI 报告，`pack` 本身返回文档和统计，不向终端写入报告。

## BPE 与预切分

BPE 核心改编自 `howtomakeaname/tokenizers-moonbit@0.16.3`，保留链接符号、优先队列、过期合并失效及最左优先规则。原公开模型使用 HF pair-merges、字符串词表和字节映射；本项目的 `src/metrics/bpe.mbt` 改为原始 UTF-8 字节区间和 OpenAI `Map[Bytes, Int]` ranks，通过区间端点及链接判断堆记录是否失效。链接字段存放于连续整数数组，rank 查询借用同一 UTF-8 快照的区间，省去逐片段和候选合并的字节复制；词表加载按已知条目数预分配哈希表容量。较低 rank 优先，同 rank 时合并最左侧，返回原始 OpenAI rank ID。

`src/metrics/pretokenize.mbt` 在整文的一份 UTF-8 快照上直接扫描并返回字节边界，BPE 借用原快照切片；不再建立整文 `Array[Char]`，也不再逐片重遍历标量计算字节终点。ASCII 直接读取单字节，非 ASCII 按需解码当前标量，数字块及空白回退仍按完整标量推进。扫描实现参考 o200k 正则的有序分支，包括贪婪与回溯、缩写、Unicode 空白、CR/LF 和每组三个数字的限制。使用完整 Unicode 数据中的 Lu/Ll/Lt/Lm/Lo/M/N 类别及补充平面；M 包含 Mn/Mc/Me，N 包含 Nd/Nl/No。不区分大小写的缩写包含长 s（`ſ`），空白采用 Unicode White_Space 属性。

字节扫描器接收 `@utf8.encode` 生成的合法快照。`count` 的精确片段 memo 仅在一次调用内使用，最多保存 8,192 条、每条不超过 256 字节，键总量不超过 2 MiB；编码器本身保持不可变、可重入。

选择 **Unicode 16.0.0** 是为了匹配参考版本：tiktoken 0.14.0 声明 `fancy-regex 0.19.0` 与 `regex 1.13.1`，后者的[类别表](https://github.com/rust-lang/regex/blob/1.13.1/regex-syntax/src/unicode_tables/general_category.rs)和 [White_Space 表](https://github.com/rust-lang/regex/blob/1.13.1/regex-syntax/src/unicode_tables/perl_space.rs)采用该版本。发布 wheel 的完整 ID 对比也验证了这一选择。

原候选预切分将 `Привет мир` 按字符拆分；此反例及完整 Unicode 边界已进入回归。

## 来源、版本与许可

运行资源是提交到仓库的上游原始文件。

| 资源 | 来源 | SHA-256 | 许可告知 |
| --- | --- | --- | --- |
| `assets/tokenizer-o200k_base.tiktoken` | [OpenAI ranks](https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken)，由 [tiktoken 0.14.0](https://github.com/openai/tiktoken/blob/0.14.0/tiktoken_ext/openai_public.py) 固定 | `446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d` | `LICENSES/tokenizer-tiktoken-MIT.txt` |
| `assets/tokenizer-unicode-16.0.0.txt` | [Unicode 16.0.0 DerivedGeneralCategory](https://www.unicode.org/Public/16.0.0/ucd/extracted/DerivedGeneralCategory.txt) | `7676ab755a41ef82108460238569e60ad65c191ddafe61b36c6765ec1353f293` | Unicode License V3；`LICENSES/tokenizer-Unicode.txt` |
| `assets/tokenizer-golden.json` | tiktoken 0.14.0 `encode_ordinary` 生成的完整 ID | `2b61908c81205275034a1b5551b5a12a8babc80657bc1959db9a8cc9e1a312e8` | 项目夹具；保留参考 MIT 告知 |

内嵌 BPE 源码来自 [tokenizers-moonbit](https://github.com/howtomakeaname/tokenizers-moonbit) 的 Mooncakes **0.16.3** 发布版。原 `src/model/bpe.mbt` 的 SHA-256 为 `00d3af2b82559086cbdb2ab7a82e6634381df04fe481ee25eeb2cf5fd13c072a`。原告知保存在 `LICENSES/tokenizer-tokenizers-moonbit-Apache-2.0.txt`，完整许可在 `LICENSES/tokenizer-Apache-2.0.txt`；修改内容见上文及源码头部。

预切分遵循 MIT 许可下的 [tiktoken 0.14.0 定义](https://github.com/openai/tiktoken/blob/0.14.0/tiktoken_ext/openai_public.py)，Unicode 告知随数据保留。SHA-256 与路径操作使用 `moonbitlang/x@0.5.5`，文件 I/O 使用 `moonbitlang/async@0.19.2`，两者均为 Apache-2.0。

## 黄金数据与复现

两组聚合黑盒测试覆盖：

- 104 组完整 ID 序列，包括 Cyrillic、多语言与大小写交叠、组合字符、补充字符、Unicode 16 新字符、未分配码点、emoji/ZWJ、全部空白区间、数字、缩写、控制字符、特殊标记、源码和 XML/Markdown 拼接边界。
- 16,390 个类别区间内外边界探针，八组固定种子的 2,048 标量混合样例，以及 4,096 个空格、8,192 字节 BPE 片段和长换行序列。
- 编码器复用、片段计数不可相加、相对路径拒绝、两份资源校验失败、缺失文件、资源迁移及初始化取消。

白盒测试将完整 199,998 条词表逐条与原 UTF-8/split、core Base64 和 `parse_int` 参考路径核对，并检查字节解析器的格式拒绝及有界读取。UTF-8 预切分另以明确的正则分片边界检查可选前缀回退、类别交叠、多字节数字、`ſ` 缩写、Unicode 空白回退及标点后缀；显式 UTF-8 字节覆盖 1–4 字节宽度转换、BOM、非字符码点及最大标量，并检查合法与非法代理项构造。

黄金数据的期望值由已发布的 tiktoken wheel 生成。`scripts/tokenizer-golden.mbtx` 通过 Python Fire CLI 调用 `tiktoken.get_encoding("o200k_base").encode_ordinary`，先核对参考版本。复现时准备独立的开发工具目录：

```sh
uv pip install --python 3.12 --target /absolute/reference tiktoken==0.14.0 fire==0.7.1
mkdir -p /absolute/reference/cache
cp assets/tokenizer-o200k_base.tiktoken /absolute/reference/cache/fb374d419588a4632f3f557e76b4b70aebbca790
moon run scripts/tokenizer-golden.mbtx --target native /absolute/repo /absolute/python3.12 /absolute/reference
moon test src/metrics --target native
moon check src/metrics --target native
moon fmt src/metrics scripts/tokenizer-golden.mbtx scripts/tokenizer-install-assets.mbtx --check
moon info src/metrics --target native
```

缓存名是公开词表 URL 的 SHA-1；资源完整性由 tiktoken 和本库分别检查 SHA-256。工具准备完成后，缓存使黄金数据生成可离线执行。从其他工作目录启动测试时，将 `TOKENIZER_ASSETS` 设为夹具目录的绝对路径；运行时加载只需要词表绝对路径。

夹具对应 `moonc v0.10.15+943464bfa`。独立 `.mbtx` 脚本自行解析依赖，产品测试使用 `moon.mod` 中的固定依赖；native CI 还验证安装和归档解包后从其他工作目录加载资源。
