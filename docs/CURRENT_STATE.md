# CURRENT_STATE

最近一次自查日期：2026-07-11

## 当前真实状态总览

- Flotis 是 macOS 浮动面板语音输入 + prompt 命令注入工具，当前 Git 历史已有 v0.4 tag。
- XcodeGen 工程包含 `Flotis` app 与 `FlotisTests` unit-test 两个 target；app 有 26 个 Swift 源文件，测试有 4 个 Swift 文件，无第三方依赖。
- app 为 `LSUIElement=YES`，无 Dock 图标；deployment target 为 macOS 13.0。
- 六个版本化转写 adapter 已注册：Apple on-device、OpenAI-compatible HTTP、OpenAI Realtime GA、DashScope Paraformer、Volcengine BigASR、GLM ASR HTTP/SSE。用户管理的是统一 connection 实例，preset 只负责填充建议值；全新安装只创建 Apple connection。
- 命令注入、全局热键、connection 配置 v3、Keychain 凭据隔离、v1/v2 只读迁移、统一新增/编辑 UI、Test Connection 和可取消语音会话均已实现。
- 2026-07-11 已运行 `xcodegen generate`、完整 Debug build 和 unit tests：构建成功，39 tests、0 failures。
- 真实麦克风、辅助功能、跨 Space 激活、剪贴板管理器竞争及六个 provider 的真实账号端到端仍需 macOS 真机验证。

## 已有能力

| 能力 | 入口 / 关键类型 | 自动化覆盖 | 当前验证 |
|---|---|---|---|
| 浮动面板与关闭状态同步 | `FloatingPanelController` / `FloatingPanelView` | 构建覆盖 | 真机待验 |
| Carbon 全局热键 | `HotkeyManager` | 快捷键策略单测；注册逻辑构建覆盖 | 真机待验 |
| 命令 CRUD 与草稿保存 | `CommandStore` / `CommandEditorView` | 快捷键策略单测 | 构建通过 |
| 安全剪贴板注入 | `ClipboardPasteInjector` | 队列容量、过期策略单测 | 真机待验 |
| Apple Speech 设备端转写 | `AppleSpeechTranscriber` | 构建覆盖 | 权限/设备支持待验 |
| OpenAI Realtime GA 转写 | `OpenAIRealtimeTranscriber` | 多 item 乱序、partial/final 组装及 scripted session/append/commit/terminal | 真实 key 待验 |
| DashScope Realtime | `DashScopeParaformerRealtimeTranscriber` | 重复句与文本边界单测 | 真实 key 待验 |
| Volcengine BigASR Realtime | `VolcengineBigASRRealtimeTranscriber` | schema、registry/runtime plan 单测 | 真实 key 待验 |
| OpenAI-compatible HTTP multipart | `OpenAIHTTPTranscriber` | 自定义 endpoint/model、WAV/M4A multipart、严格响应、取消边界 | mock 通过；真实 key 待验 |
| GLM HTTP SSE | `GLMASRHTTPTranscriber` | Content-Type、JSON event、delta/done/`[DONE]` 与错误脱敏 | mock 通过；真实 key 待验 |
| 统一 connection / adapter registry | `TranscriptionConnection` / `TranscriptionAdapterRegistry` | 6 个唯一 adapter 与 3 类通用 runtime plan | 通过 |
| Connection Test | `TranscriptionConnectionTester` | 合成音频、HTTP 与 Realtime mock、空文本合法、任意形态 Key 回显脱敏 | 通过 |
| Provider v1/v2→v3 迁移 | `SpeechProviderSnapshotMigration` / `SpeechProviderStore` | 六类、自定义实例、排序、active、引用、v2 LKG | 通过 |
| Keychain 命名空间/迁移/清除 | `KeychainSecretStore` | 内存 secret store 覆盖 reference 轮换、清理失败与回滚 | 真实 Keychain 待验 |

## 已解决的 2026-07-10 审计问题

- 注入前确认目标 PID 存活且仍为 frontmost；激活失败、用户中途切换 app、修饰键超时或 AX 权限丢失都会终止，不再发送 `⌘V`。
- 注入队列和 burst 有容量/时效上限；剪贴板仅在 `changeCount` 未变化时恢复，复杂类型无法完整快照时拒绝注入。
- 可打印全局快捷键必须包含 Command 和至少一个额外修饰键，避免 `⌘V`、`⌘C`、`⌘Q` 等系统级冲突；热键按差异增量注册并自动重试失败项。
- `VoiceInputController` 用 session generation、可取消 task 和会话内 connection/key 快照隔离旧回调；实时音频使用有界串行队列并在 terminal commit 前 drain。
- Realtime stop 改为等待协议终态/ack；OpenAI 按 `item_id` / `content_index` / previous item 关系组装，Dash 等待 `task-finished`，Volc 等待终端事件/包。
- `StreamingAudioCapture.stop()` 会先移除 tap/停 engine，保持 generation 有效地排空所有 in-flight conversion，并以 end-of-stream flush `AVAudioConverter` 尾帧；`cancel()` 才立即失效 generation 并丢弃待处理音频。
- 运行时改为 `TranscriptionAdapterID → TranscriptionAdapterRegistry → ownedCapture/pcmStream/recordedFile`；`VoiceInputController` 不再按厂商或 wire protocol 分支。协议专属参数、HTTPS/WSS 校验、可信 host 提示、凭据边界和草稿 Save/Cancel 保持不变。
- UserDefaults 主数据升级为 canonical v3 connection；v2/v1 只作为只读迁移输入，保留 UUID、名称、排序、active ID 与安全边界不变的 Keychain reference，并继续使用 last-known-good、坏数据备份和事务回滚。
- 设置页使用一个 Add Connection 入口和同一 editor 管理所有协议；同 adapter 可创建多个 endpoint/model/key 相互隔离的实例，preset 不参与 runtime 判断。
- Test Connection 使用程序内生成的无隐私短音频验证实际 transport、音频上传与响应结构；合成音不要求产生非空转写。错误摘要有长度上限并按本次实际 Key 精确脱敏，不保存响应正文或转写内容。
- 最终复核补齐了 Keychain 清理失败回滚、坏 v3/v2 的对应 LKG 恢复与 legacy v1 fallback、Volc resource ID 的 schema/runtime 同源校验，并移除了 Volc 无效 language 配置。

## 尚未完成 / 需要人工确认

- **真机端到端**：Carbon、`CGEvent`、AX 权限、非激活面板焦点、跨 Space、目标 app 慢激活以及剪贴板管理器竞争无法由当前 unit tests 证明。
- **真实供应商联调**：OpenAI、DashScope、Volcengine、GLM 的认证、服务端事件顺序、错误包和限流行为需分别使用有效账号验证；按本轮用户要求未创建、读取或使用真实 API key，也未发出真实供应商请求。
- **签名/分发**：无 entitlements、Developer Team、notarization 或正式发布流水线。
- **`VoiceInputMode` 疑似 vestigial**：`AppState.voiceMode` 仍存在，但真实分派依据是 adapter registry 返回的通用 runtime plan。
- **部分 UI 状态不持久化**：`isPanelVisible`、`selectedSpeechLocale`、`voiceMode` 重启后重置；是否应持久化仍为产品决策。
- **无 README/CHANGELOG**：项目入口文档仍以 `AGENTS.md` 与 `docs/` 为主。

## 当前风险边界

- `ClipboardPasteInjector` 的 success 表示目标在发事件瞬间已核验、事件已 post 且剪贴板结局安全；macOS 没有通用 API 能证明任意目标控件已消费该粘贴事件。
- 为支持 Carbon 全局热键与 `CGEvent`，app 当前未沙箱化。正式分发前必须单独评估 hardened runtime、签名和 notarization。
- 第三方协议已有静态 schema、mock transport、超时/终态保护与严格响应解析，但公开服务端协议可能演进；升级 API 前必须重跑自动化与真实 provider 矩阵。
- `run.sh` 会删除 DerivedData 并重置该 bundle 的 Accessibility TCC，适合冷启动调试，不适合日常增量构建。

## 工作区状态

当前工作树包含用户原有改动、本次全量修复、自动化测试、生成工程和文档更新，尚未 add/commit/push。`.DS_Store`、`CLAUDE.md`、`GEMINI.md` 等非本任务文件均未被本轮覆盖或清理。判断当前实际状态时以 `git status --short` 为准。

## 文档与源码冲突

2026-07-10 审计发现的“22 个 Swift / 3 provider / v1 配置 / 无测试 target / OpenAI Beta payload / HTTP 统一 m4a”等旧描述，以及本轮实现前的“v2 provider + vendor switch”描述，均已按当前源码修正。后续若文档再次与源码、`project.yml` 或测试冲突，仍以可构建的当前源码与工程配置为准，并在报告中指出差异。
