# 文件选择

包：`Delthin/moon_repomix/selection`。仅发现候选与读取规则，不打开候选正文；读取快照、二进制判断、安全扫描与输出提交由后续阶段负责。

## 接口

```moonbit
pub(all) struct SelectionOptions {
  include_patterns : Array[String]
  ignore : Array[String]
  use_gitignore : Bool
  use_dot_ignore : Bool
  use_default_patterns : Bool
  output : String?
}
pub fn SelectionOptions::default() -> SelectionOptions
pub(all) struct Candidate { path : String; relative : String }
pub(all) struct Skipped { path : String; reason : String }
pub(all) struct Selection {
  root : String
  files : Array[Candidate]
  skipped : Array[Skipped]
}
pub async fn select(
  root : String, options : SelectionOptions,
  file_paths? : Array[String]? = None,
) -> Selection
pub async fn path_filter(
  root : String, options : SelectionOptions,
  file_paths? : Array[String]? = None,
) -> PathFilter
pub async fn PathFilter::allows(self : PathFilter, relative : String) -> Bool
```

MoonBit 异步函数隐式具有 `raise` 效果。默认 include_patterns/ignore 为空、三个开关均 true、output 为 None。下文的 include 指正向选择模式。

`root` 必须是绝对普通目录；最终根组件是链接/reparse point 时拒绝，包括尾随 `/`、`/.` 的写法。返回 root 为真实绝对路径。Windows 接受盘符绝对路径或 UNC share，输入反斜杠转为 `/`。候选 path 为绝对 I/O 路径，relative 为根相对路径；skipped.path 同样根相对。保留大小写、Unicode 原文，不折叠、不做 Unicode 归一化；Unix 文件名内的反斜杠是普通字符而非分隔符。

files 和 skipped 分别按相对路径的 **UTF-8 字节词典序** 排序，短前缀在前。

## 路径、文件类型与输出

- 只遍历普通目录，只返回普通文件。先用 async fs.kind(follow_symlink=false) 分类，再决定递归；目录/文件链接、断链记 Symlink，FIFO/socket/设备/未知类型记 UnsupportedFileType，均不打开。
- async **0.19.2** 的 `src/internal/event_loop/detect_file_kind.c` 先检查 `FILE_ATTRIBUTE_REPARSE_POINT`，将其判为 SymLink，覆盖 junction 等 reparse point。
- 相对路径从真实根加单个 readdir 名称构造，边界比较带 `/`，不会把 `/root-other` 误当 `/root` 子目录。include 无法指定绝对路径或 `..` 穿越根。
- output 必须绝对。输出已有时解析真实目标，尚不存在时解析最深已存在父目录再附加剩余组件；保留符号链接后 `..` 的实际解析顺序。解析后与候选路径相同的输出强制记 OutputFile，任何 include、反选或关闭默认忽略都不能恢复它。父目录别名、cwd 别名、文件链接别名均纳入比较；输出位于根外不会排除同名的根内文件。
- Windows 的 async 0.19.2 realpath 只调用 GetFullPathNameW，不解 junction，因此本包 `canonical.c` 对根和输出的已存在祖先用 metadata-only CreateFileW + GetFinalPathNameByHandleW 取得真实路径；不用于打开遍历候选。
- 不同硬链接路径分别保留。lstat 与读取/递归之间存在 TOCTOU 竞争窗口，读取阶段须重新检查类型；规则文件也先做 no-follow 分类。类型检查和打开分离，调用者应避免不可信进程在打包时替换路径。
- 输出临时文件在 pack 返回后创建；选择阶段不按临时文件名排除其他文件。

## 精确文件列表

- `file_paths=None` 保持目录遍历；`Some([])` 是零文件，绝不退回全仓。`SelectionOptions` 字段不变。PathFilter 的 root 使用 select 返回的 canonical root。
- `Some(paths)` 是 literal 根相对**文件**列表，`*`、`?`、方括号、花括号都不是模式。只检查列出的路径及祖先，不 readdir、不递归列出的目录，也不校验无关子树规则。保留空格、Unicode 和大小写；去重后按 UTF-8 字节排序，files/skipped 各自维持该顺序。
- 使用可移植 `/` 分隔写法。空路径、绝对路径、空组件、`.`、`..`、NUL、反斜杠及冒号均整体报 `InvalidPattern(source="file_paths", line=0, pattern=原始路径, ...)`，Windows 盘符、UNC、盘符相对路径也不能逃逸；**两接口都在规则 I/O 前校验完整列表**，不悄悄删除非法项。此限制不改变普通遍历或无精确列表的 Git 路径对 Unix 反斜杠/冒号文件名的支持。
- 显式列表不绕过 include/default/custom/Git/dot/output-self 规则。每个列出路径从根逐组件 no-follow 检查，链接祖先或末项均记 Symlink；祖先是普通文件记 NotDirectory；其他非普通类型记 UnsupportedFileType；末项是普通目录记 Directory，不展开内容。
- 完整路径语法校验后：继承的根剪枝 → 每层父目录规则加载 → 该组件 no-follow 类型（含 MissingFile）→ output-self → default → custom → Git/dot 规则 → 最终 include。普通文件/祖先缺失记 MissingFile；只有 ENOENT 是缺失，权限、规则解析、其他 I/O 和取消仍传播。一个列出路径只记一条 skip，path 保留列出项，祖先排除以 IgnoredDirectory 原因表示（不额外枚举祖先 skip）；空列表不读取根内规则。
- PathFilter 使用同一私有 reason 决策和 exact 集合：未列出的路径恒 false，不递归列出的目录；但允许不存在的文件/目录组件供 Git 删除记录过滤，其余规则照常适用。Git rename 两端是否都匹配由调用者现有逻辑决定，本包不改变该契约。列表与规则、候选文件均不会直接读取候选正文。

## 作用域与顺序

1. `use_gitignore` 开启时，从所选根向上找到最近包含 `.git` 目录或 `.git` 文件的工作树根；找不到则到文件系统根。只继承这段路径的 `.gitignore`，不读取全局 Git 配置或用户级 excludesFile。
2. 工作树 `.git/info/exclude` 最低优先级，匹配基准为工作树根。支持 `.git` 的 `gitdir: ...` 文件；linked worktree 再通过 `commondir` 定位公共 `info/exclude`。相对元数据路径按所在文件目录解释。元数据路径所有组件均 no-follow 检查，链接或不合法元数据 fatal。
3. 父层规则由浅到深加载。进入根及每个普通子目录后，依次加载该目录 `.gitignore` → `.ignore` → `.repomixignore`；更深目录覆盖较浅目录，同一文件后行覆盖前行。
4. `use_gitignore=false` 同时关闭 Git 发现、info/exclude 与所有 `.gitignore`；`use_dot_ignore=false` 仅关闭根及子目录 `.ignore`；`.repomixignore` 始终加载，不影响 Git 层。
5. 自定义 ignore 是最终只排除层，不能反选。内置规则是另一个独立只排除层，由 use_default_patterns 整体开关；集合依据 Repomix **1.18.1** `src/config/defaultIgnore.ts`，涵盖依赖、日志、缓存、构建产物、锁文件、编辑器及 OS 文件；另保留本项目 `.git`、`.hg`、`.svn`、`node_modules`、`_build`、`.DS_Store` 任意深度安全默认。编译列表由遍历与 Git 路径过滤共用。原版裸模式仅相对根生效（如 `.env`、`*.pid`、`vendor/**`、`dist/**`），显式 `**/` 模式才匹配任意深度（如 `**/package-lock.json`、`**/target/**`）。`dir/**` 可剪枝匹配的普通目录，不排除名为 dir 的普通文件；先检查类型，链接仍记 Symlink。
6. include 为空表示不限制，否则任一 include 匹配文件或其目录前缀即可入选；仍受所有排除约束。为不丢嵌套反选/规则错误，不根据 include 提前剪枝。

目录在完整适用规则集合计算完之后才剪枝。同层 `dir/` 后的 `!dir/` 可以恢复目录；只有 `!dir/file` 不能穿透已排除的 dir，目录内部规则也不能恢复已被父层剪枝的目录。每个剪枝目录仅记一条 IgnoredDirectory，不枚举其内容，不报告精确内部文件数。选择根本身被父规则剪枝时只记路径 `.`。

## glob 语法

共通：区分大小写，`/` 分隔组件；`*` 匹配组件内零或多个单位、`?` 一个单位、`[abc]`/`[a-z]`/`[!abc]`/`[^abc]` 字符类，支持类首字面 `]` 和反斜杠转义。完整组件 `**` 匹配零或多级目录，尾部 `a/**` 至少匹配一项内容，不匹配 a 本身。尾 `/` 仅匹配目录，目录匹配后覆盖后代。含 `/` 的模式相对其规则基准匹配；无 `/` 的模式是否匹配任意深度，由下面各层语义决定。

### include 与自定义 ignore

- 模式基准为选择根；`*`/`?`/类按 Unicode 标量匹配。include 始终根相对：`LICENSE` 仅选根文件，`src` 或 `src/` 包含根 src 目录后代，`**/LICENSE` 才选任意深度。自定义 ignore 的无 `/` 模式仍按任意深度 basename 匹配。
- 支持字符串花括号备选与嵌套，如 `{src,{lib,test}}/*.{mbt,md}`；每层 include/ignore 展开后总计最多 **256** 个模式，花括号嵌套最多 **8** 层（重复备选也计数）。未闭合、不成对、空备选、无逗号的花括号或超限报 InvalidPattern。转义的花括号与字符类内花括号、逗号按字面保留。
- 必须非空。拒绝前导 `/`、前导反斜杠、盘符/冒号、前导 `!`、空组件、`.`/`..`、未闭合/空/逆序字符类、无匹配的 `]`、悬空转义；每个展开结果均做相同检查，`**` 仅允许独占完整组件。错误保留原始未展开模式。
- 花括号不实现数字范围；不实现 extglob、tilde expansion 或环境变量展开；括号、`@`、`$`、`~` 等在此语法中只是字面字符。前导反斜杠统一拒绝以免混淆 Windows 绝对路径，不能用于转义模式首字符。

### Git / dot 规则文件

- 严格 UTF-8，可带 BOM。支持 LF/CRLF；前导空格有效，仅去除未转义尾随空格。空行与前导 `#` 注释忽略，`\#`、`\!` 为字面字符，前导 `!` 为反选，前导 `/` 在规则文件基准锚定。
- 使用 Git wildmatch 的 **UTF-8 字节** 单位：例如 `?.txt` 不匹配 `猫.txt`，`???.txt` 匹配。Unicode 字面名称正常匹配。Git/dot 字符类限 ASCII；不支持 POSIX 命名类（如 `[[:digit:]]`）、非 ASCII 类及 collating/equivalence 类，报 InvalidPattern，不悄悄降级。非完整组件的连续 `*` 按普通 `*` 处理。
- 空反选、空/`.`/`..` 组件、错误字符类和悬空转义视为规则错误。这是明确的严格子集：Git 对部分错误模式可能静默不匹配，本包 fatal；花括号在规则文件里是字面字符，不扩展。
- 无 `/` 的规则按任意深度 basename 匹配；前导 `/` 使其在规则基准锚定。
- 来源保存 source、1-based line、base。未访问的剪枝目录内的规则文件不会读取/校验。

## 错误与诊断

稳定 `pub(all) suberror SelectionError`：

- `InvalidRoot(String)`：相对根、缺失根或非普通目录（含链接）。
- `InvalidPattern(source~ : String, line~ : Int, pattern~ : String, detail~ : String)`：模式或精确列表路径错误；include/ignore/file_paths 的 source 为对应字段名、line 为 0；规则文件为绝对来源路径和 1-based 行号。
- `InvalidRuleFile(String)`：存在的规则文件不是普通文件，包括链接。
- `InvalidGitMetadata(String)`：Git marker/目录结构/commondir 不合法或含链接。
- `InvalidOutput(String)`：相对或无法建立绝对身份的输出参数。

ENOENT 表示规则或元数据不存在；权限、解码、遍历、其他 I/O 错误和取消均向调用者传播。

skipped.reason 当前形式：`Symlink`、`UnsupportedFileType`、`OutputFile`、`NotIncluded`、精确列表专用 `MissingFile`/`Directory`/`NotDirectory`、`Ignored:default`、`IgnoredDirectory:default`、`Ignored:custom`、`IgnoredDirectory:custom`、`Ignored:<source>:<line>`、`IgnoredDirectory:<source>:<line>`。冒号后的来源是诊断信息，不宜按冒号拆字段（Windows 盘符也含冒号）；目录统计应识别 IgnoredDirectory 前缀。

## 测试

在仓库根目录运行：

```text
moon fmt src/selection
moon test src/selection --target native
moon info src/selection --target native
moon check src/selection --target native
```

`selection_wbtest.mbt` 使用自动清理的临时合成树，覆盖：逐项比较真实 `git check-ignore --no-index`（屏蔽全局/系统配置）、父层/嵌套/目录反选与剪枝、dot/custom/默认独立开关、真实父路径输出别名与缺失输出、UTF-8 顺序、未读正文、链接/断链/FIFO、规则解码和类型错误、无 Git 父层与 worktree commondir。`compat_wbtest.mbt` 另覆盖固定原版默认集合具体文件、根/嵌套作用域、共享剪枝、root-relative include、嵌套花括号及 256/8 边界、Git 字面花括号；`exact_wbtest.mbt` 覆盖 literal 列表、空列表/重复/UTF-8 排序、所有忽略层及来源、非法路径整体失败、目录/缺失/链接祖先/FIFO、未读正文、output 别名与 Git 删除路径集合。测试需要现有 Git，Unix 类型夹具还需要现有 mkfifo。

CLI 功能测试还覆盖 Windows junction 排除；目标平台运行由 native CI 矩阵执行。
