# o200k_base 分词

`Delthin/moon_repomix/metrics` 是 native 离线编码器，以 **tiktoken 0.14.0 的 `encode_ordinary`** 为兼容基线。`<|endoftext|>`、`<|endofprompt|>` 等特殊标记按普通文本编码；输入为 Unicode 字符串，保留原有形式。UTF-8 解码由调用者完成。

## 接口与资源

```moonbit
pub async fn Encoder::load(path : String) -> Encoder
pub fn Encoder::encode(self : Encoder, text : String) -> Array[Int]
pub fn Encoder::count(self : Encoder, text : String) -> Int
pub fn Encoder::session(self : Encoder) -> CountSession
pub fn CountSession::count(self : CountSession, text : String) -> Int
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

最终 token 总数须对完整渲染文档一次编码。BPE 和预切分可能跨拼接边界变化，因此各片段计数相加不能代替总数。`encode` 保留 MoonBit 完整 ID 路径；`count` 使用私有单线程 C 内核，以同样的预切分、合并顺序和 rank 规则只累计符号数，省去完整 ID 数组及最终 rank 回查。旧 MoonBit count 保留为精确参考与保守回退路径，原有 `Encoder.load`/`encode`/`count` 行为不变。

`CountSession` 是 opaque、同步、单线程的请求级计数会话，可在一次 pack 内复用 piece memo 和 BPE scratch。每次 `encoder.session()` 都创建独立存储；会话强持有原 Encoder，即使调用者的局部 Encoder 已离开作用域，词表仍存活。Encoder 本身仍不可变、可重入，不保存会话缓存，也不承担额外的旧 `count` 调用分配成本。会话不应放入跨请求共享的不可变 runtime，也不应并发使用同一会话。

可用同一会话依次计数原始正文、处理后正文、最终完整文档以及各个完整 partition 候选。**每次调用仍从头完整预切分并精确 BPE**；跨调用只复用拥有完整字节键的片段结果，不缓存文件总数，不假设候选单调，也不能用逐文件之和替代最终 whole count。会话释放时由 external-object finalizer 释放其缓存和工作区，无需另加关闭 API。

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

两条路径的字节扫描器均接收 `@utf8.encode` 生成的合法快照。不会把非法 UTF-16 代理项替换成近似文本：合法代理对正常编码，孤立或错位代理项保留原 panic 行为。

### 私有 native count 内核

`src/metrics/native_counter.c`、`src/metrics/native_pretokenize.h` 覆盖整个 count 热路径，而非只替换词表 lookup：

- `load` 先完成原有摘要和 MoonBit 格式校验，再把**同一份原始字节快照**借用给 C。C 复制出 token arena、连续 rank 偏移表、524,288 槽开放寻址索引及每码点 4 bit 的 Unicode 16 类别表；不借用 MoonBit Map 的内部表示，不保留资源 bytes 指针。rank 0 和含 NUL 的键都按长度精确比较。
- UTF-8 扫描保持有序分支、完整标量推进和原有回溯。BPE 使用连续链接节点和索引数组最小堆；每个存活左符号至多一个候选，更新相邻项而不积累过期记录。比较顺序为 rank、左字节位置；较低 rank、最左合并优先。
- scratch 按需增长，每个容量槽 24 字节（五个 32-bit 节点字段加一个堆位置），容量向上取 2 的幂。单个片段上限 1 MiB，因此 scratch 上限 24 MiB，包括先释放旧 buffer 再增长时的瞬时 C-owned 存储。超过该界限的非直接命中片段请求完整 MoonBit count 回退，不返回部分结果。
- 平坦精确 memo 最多 8,192 键、16,384 索引槽、每键 256 字节、键 payload 总量不超过 2 MiB。hash 冲突后仍比较长度和全部字节；饱和或超长键停止插入，未命中片段仍精确 BPE。`Encoder::count` 延迟按本次输入大小分配，返回（含失败）时释放全部 memo/scratch，原有资源成本不变。
- `src/metrics/count_session.mbt` 的会话把 memo/scratch 保留到会话释放。第一次可缓存片段延迟分配上述有界完整 memo，不会因首个文档短而缩小后续容量；empty/仅单字节片段不分配 memo。键完整复制到 C-owned payload，绝不借用前次输入；scratch 没有指向前次输入的字段。所有 limits 按每个会话独立约束，不跨请求累积。
- 每次会话 count 的堆长度、局部总数和错误状态重新开始并在返回时清理；此前正确的 memo entries 可保留，包括某个后续片段失败的调用。C-owned session 构建失败使该会话一直使用完整 MoonBit fallback；memo 分配失败使该会话禁用缓存且不重试，计数仍精确；scratch 分配失败或片段超限只让当前文档回退，后续 count 仍可使用会话（必要时重新分配 scratch）。所有 C-owned 分配检查失败与乘法溢出，不把失败当作部分计数、0 或近似结果。
- `src/metrics/native_counter_ffi.c` 分别以 external-object finalizer 释放 C-owned 词表和会话存储，不释放运行时容器。`NativeCountSession` 不保留词表 owner 或 Moon 托管 pointer，finalizer 不访问 owner。MoonBit CountSession 强持有 Encoder，每次 FFI 显式 borrow 会话、owner 和本次 bytes；只改变独立 C 会话状态，不对 readonly MoonBit 对象隐藏写入。编码器共享表保持不可变、无跨调用可变缓存。

MoonBit Map 与类别表仍供 `encode`、旧 count 和强差分使用；C count 热路径不经过通用 Map 或逐合并的 RC 对象操作。

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

新增五组 native 白盒测试直接检查 C 返回值，不能由公开 fallback 掩盖失败：全部 104 组独立 ID goldens 同时核对 C count、旧 encode/count 与逐片字节边界；覆盖固定种子混合文本、补充标量、NUL、正则优先级、长空白/标点/BPE、256 字节键边界、8,400 个不同片段及重复、handle 复用、超限与不可用 handle 的精确 fallback、原生路径非法代理项 panic。原有十组测试保持原断言。这些 native 组同时使用持久 CountSession 多轮、逆序计数 goldens，与独立会话交错调用；核对完整拼接非可加性、8,400-key 饱和后的新文档、超限 fallback 后再次计数、无 native 的精确 fallback、owner 离开局部作用域后的会话使用。另以一组 panic 检查复用会话后非法代理项仍被拒绝，共 16 组 metrics 测试。

`src/metrics/native_counter_sanitize_test.c` 是独立 C 单元驱动，不链接进产品。它对真实内核和 FFI 执行 ASan/UBSan：穷举构建和调用内各个 C-owned 分配失败点；与独立的逐轮全候选重算算法比较 4,096 个固定样例；专门构造 rank 0/左侧 tie、强制 memo hash 冲突、8,192 个 256 字节键填满 2 MiB payload；检查 scratch 增长/边界、不可变表指纹，以及 16 次真实 external object 的资源提前释放、重复 borrow、最终 finalizer。会话验证另覆盖构建失败和每个 lazy memo/scratch 分配失败后的重复调用、输入释放后的完整键、独立会话不共享状态、8,192 个完整 256-byte 跨文档键填满 payload、增长时 24 MiB scratch 瞬时上限、16 次真实会话 FFI 生命周期与两种 owner/session finalizer 顺序。所有 C-owned 分配跟踪（块数和字节数）最终必须为 0。可在源码根执行（`MOON_HOME` 指向匹配版本的工具链）：

```sh
mkdir -p _build/native-counter-evidence
clang -std=c11 -O1 -g -fno-omit-frame-pointer \
  -fsanitize=address,undefined -fno-sanitize-recover=all -Wall -Wextra -Werror \
  -I"$MOON_HOME/include" src/metrics/native_counter_sanitize_test.c \
  "$MOON_HOME/lib/runtime/runtime.c" -o _build/native-counter-evidence/sanitize-counter
ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 \
  UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
  _build/native-counter-evidence/sanitize-counter
```

驱动单独编译使用系统分配器的运行时，不改写工具链或共享 runtime object。macOS 此命令不启用 LeakSanitizer；C-owned 泄漏通过分配跟踪与实际 finalizer 验证，不把它报告为全进程 LSan 检查。本单元不包含性能测量。

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
