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
pub async fn select(root : String, options : SelectionOptions) -> Selection
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

## 作用域与顺序

1. `use_gitignore` 开启时，从所选根向上找到最近包含 `.git` 目录或 `.git` 文件的工作树根；找不到则到文件系统根。只继承这段路径的 `.gitignore`，不读取全局 Git 配置或用户级 excludesFile。
2. 工作树 `.git/info/exclude` 最低优先级，匹配基准为工作树根。支持 `.git` 的 `gitdir: ...` 文件；linked worktree 再通过 `commondir` 定位公共 `info/exclude`。相对元数据路径按所在文件目录解释。元数据路径所有组件均 no-follow 检查，链接或不合法元数据 fatal。
3. 父层规则由浅到深加载。进入根及每个普通子目录后，依次加载该目录 `.gitignore` → `.ignore` → `.repomixignore`；更深目录覆盖较浅目录，同一文件后行覆盖前行。
4. `use_gitignore=false` 同时关闭 Git 发现、info/exclude 与所有 `.gitignore`；`use_dot_ignore=false` 关闭根及子目录 `.ignore`/`.repomixignore`，不影响 Git 层。
5. 自定义 ignore 是最终只排除层，不能反选。内置规则是另一个独立只排除层，由 use_default_patterns 整体开关；当前集合为 `.git`、`.hg`、`.svn`、`node_modules`、`_build`、`.DS_Store`，均按 basename 生效。
6. include 为空表示不限制，否则任一 include 匹配文件或其目录前缀即可入选；仍受所有排除约束。为不丢嵌套反选/规则错误，不根据 include 提前剪枝。

目录在完整适用规则集合计算完之后才剪枝。同层 `dir/` 后的 `!dir/` 可以恢复目录；只有 `!dir/file` 不能穿透已排除的 dir，目录内部规则也不能恢复已被父层剪枝的目录。每个剪枝目录仅记一条 IgnoredDirectory，不枚举其内容，不报告精确内部文件数。选择根本身被父规则剪枝时只记路径 `.`。

## glob 语法

共通：区分大小写，`/` 分隔组件；`*` 匹配组件内零或多个单位、`?` 一个单位、`[abc]`/`[a-z]`/`[!abc]`/`[^abc]` 字符类，支持类首字面 `]` 和反斜杠转义。完整组件 `**` 匹配零或多级目录，尾部 `a/**` 至少匹配一项内容，不匹配 a 本身。尾 `/` 仅匹配目录，目录匹配后覆盖后代。无 `/` 的模式按任意深度 basename 匹配；含 `/` 的模式相对其规则基准匹配。

### include 与自定义 ignore

- 模式基准为选择根；`*`/`?`/类按 Unicode 标量匹配。目录 include（如 `src/`）包含该目录后代。
- 必须非空。拒绝前导 `/`、前导反斜杠、盘符/冒号、前导 `!`、花括号、空组件、`.`/`..`、未闭合/空/逆序字符类、无匹配的 `]`、悬空转义；`**` 仅允许独占完整组件。
- 不实现 brace expansion、extglob、tilde expansion 或环境变量展开；括号、`@`、`$`、`~` 等在此语法中只是字面字符。前导反斜杠统一拒绝以免混淆 Windows 绝对路径，不能用于转义模式首字符。

### Git / dot 规则文件

- 严格 UTF-8，可带 BOM。支持 LF/CRLF；前导空格有效，仅去除未转义尾随空格。空行与前导 `#` 注释忽略，`\#`、`\!` 为字面字符，前导 `!` 为反选，前导 `/` 在规则文件基准锚定。
- 使用 Git wildmatch 的 **UTF-8 字节** 单位：例如 `?.txt` 不匹配 `猫.txt`，`???.txt` 匹配。Unicode 字面名称正常匹配。Git/dot 字符类限 ASCII；不支持 POSIX 命名类（如 `[[:digit:]]`）、非 ASCII 类及 collating/equivalence 类，报 InvalidPattern，不悄悄降级。非完整组件的连续 `*` 按普通 `*` 处理。
- 空反选、空/`.`/`..` 组件、错误字符类和悬空转义视为规则错误。这是明确的严格子集：Git 对部分错误模式可能静默不匹配，本包 fatal；花括号在规则文件里是字面字符，不扩展。
- 来源保存 source、1-based line、base。未访问的剪枝目录内的规则文件不会读取/校验。

## 错误与诊断

稳定 `pub(all) suberror SelectionError`：

- `InvalidRoot(String)`：相对根、缺失根或非普通目录（含链接）。
- `InvalidPattern(source~ : String, line~ : Int, pattern~ : String, detail~ : String)`：模式错误；include/ignore 的 source 为对应字段名、line 为 0；规则文件为绝对来源路径和 1-based 行号。
- `InvalidRuleFile(String)`：存在的规则文件不是普通文件，包括链接。
- `InvalidGitMetadata(String)`：Git marker/目录结构/commondir 不合法或含链接。
- `InvalidOutput(String)`：相对或无法建立绝对身份的输出参数。

ENOENT 表示规则或元数据不存在；权限、解码、遍历、其他 I/O 错误和取消均向调用者传播。

skipped.reason 当前形式：`Symlink`、`UnsupportedFileType`、`OutputFile`、`NotIncluded`、`Ignored:default`、`IgnoredDirectory:default`、`Ignored:custom`、`IgnoredDirectory:custom`、`Ignored:<source>:<line>`、`IgnoredDirectory:<source>:<line>`。冒号后的来源是诊断信息，不宜按冒号拆字段（Windows 盘符也含冒号）；目录统计应识别 IgnoredDirectory 前缀。

## 测试

在仓库根目录运行：

```text
moon fmt src/selection
moon test src/selection --target native
moon info src/selection --target native
moon check src/selection --target native
```

`selection_wbtest.mbt` 使用自动清理的临时合成树，覆盖：逐项比较真实 `git check-ignore --no-index`（屏蔽全局/系统配置）、父层/嵌套/目录反选与剪枝、dot/custom/默认独立开关、真实父路径输出别名与缺失输出、UTF-8 顺序、未读正文、链接/断链/FIFO、规则解码和类型错误、无 Git 父层与 worktree commondir。测试需要现有 Git，Unix 类型夹具还需要现有 mkfifo。

CLI 功能测试还覆盖 Windows junction 排除；目标平台运行由 native CI 矩阵执行。
