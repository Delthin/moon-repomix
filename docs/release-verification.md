# 验证 Mooncakes 发行

`Publish and verify Mooncakes v0.6.0` 是手动触发的发行工作流，固定版本为 `0.6.0`，固定 MoonBit `0.10.17+d971670cd`。它核对当前提交与版本、生成待发布源码包，并先更新公共注册表索引。

- `publish-and-verify`：版本不存在时最多调用一次 `moon publish`；版本已存在时跳过上传，直接验证。
- `verify-only`：不接触发布凭证，只验证已经存在的版本。版本不存在即停止。

复核当前固定版本时，可在 `source_ref` 填入其原始 40 位提交 SHA；该参数只允许用于 `verify-only`，源码版本须与工作流和消费者一致。其他版本使用对应标签中的工作流和校验脚本。工作流从该提交生成预期源码包，同时使用当前提交的校验脚本；两份提交身份分别归档。这样可修正验证工具，而不修改或再次上传已发布版本。

上传步骤需要临时 Actions Secret `MOONCAKES_PUBLISH_CREDENTIALS`，内容为官方登录生成的凭证 JSON。只在凭证安装步骤传入，runner 文件权限为 `0600`；日志屏蔽 token，私有发布日志不进入 artifact。工作流总会清理自己创建的 runner 凭证文件。操作者还应在运行结束后删除这个仓库 Secret，包括失败的运行。

客户端上传失败不会自动重试。是否已发布由刷新后的公共索引、规范 ZIP 的 SHA-256、完整源码内容及真实 SDK 消费共同确认。若索引已有该版本但内容不一致，应停止并调查，不能覆盖原版本。

## 源码与 SDK 核验

工作流在独立目录解析 `scripts/release-sdk-smoke.mbtx`，只从注册表取得 `Delthin/moon_repomix@0.6.0`，不使用 checkout 覆盖库源码。随后：

1. 核对实际下载 ZIP 的 SHA-256 与公共索引一致。
2. `scripts/release-source-verify.mbtx` 流式读取两个 ZIP，比较文件集合和每个文件的全部字节；ZIP 条目顺序及压缩时间不作为源码差异，不把路径解压到文件系统。
3. 从规范注册表 ZIP 取得 tokenizer 资源，再编译、运行独立消费者。
4. 验证版本、混合与骨架结果、源行范围、精确计数及字节数、完整分卷与索引、入选解释、完整函数读取、读取预算边界及任务上下文的必选全文。

公开 artifact 包含注册表条目、源码身份比较、规范源码 ZIP 和消费验证结果。完整凭证、发布私有日志及整个 `MOON_HOME` 均不归档。正常的三平台 CI 和安装包验证仍由 `native` 工作流承担。

## GitHub 发行附件

`Release verified v0.6.0 assets` 手动工作流使用 CI 自带的短期 `GITHUB_TOKEN`，仅申请发行所需的 `contents: write` 和读取既有工件所需的 `actions: read`。它不读取 Mooncakes 发布凭证。

通过发行标签触发，传入 `source_sha`、`tag_object_sha`、`registry_sha256`、`native_run_id`、`registry_run_id`、`registry_attempt`。前两项分别是完整源码提交与 annotated tag 对象，不能混用；后两项 CI 均须成功且属于同一源码提交。`registry_attempt` 默认为 1。

工作流核对既有 v0.6.0 标签对象及其解引用提交、三平台检查、完整源码比较和注册表 SDK 验证，再取得对应原生归档与规范注册表源码。源码文件数从实际比较记录读取，不固定为旧版本数量。生成校验和后先创建草稿，核对上传文件的 SHA-256，最后设为正式最新版。版本或文件不一致即停止；已有 Release 时不自动覆盖。
