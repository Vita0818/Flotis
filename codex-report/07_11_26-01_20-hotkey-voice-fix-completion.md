# Flotis 快捷键注入与语音输入全量修复完成报告

## MODEL_CHECK_RESULT

当前执行模型：Codex / GPT-5。

## PATH_CHECK_RESULT

- `pwd`：`/Users/vita/Vitemis/Flotis`
- Git root：`/Users/vita/Vitemis/Flotis`
- 结果：路径一致，匹配预期仓库根目录。

## OUTCOME

`codex-report/07_10_26-23_04-hotkey-voice-audit.md` 中的快捷键/剪贴板注入、语音会话生命周期、六类 provider runtime、配置持久化、Keychain 生命周期和文档冲突已完成静态修复。

最终复核还发现并修复了五个未在首轮实现中闭环的点：Keychain cleanup 失败回滚、Volc resource ID 的 schema/runtime 一致性、坏 v2 向有效 v1 fallback、实时音频 graceful stop 的 conversion drain/尾帧 flush，以及上述持久化路径的隔离单测。

当前自动化结论：完整 Debug build 成功，20 tests、0 failures。剩余项仅是必须依赖真实 macOS 权限/窗口系统、麦克风、Keychain 或供应商账号的真机端到端验证。

## ORIGINAL_AUDIT_RESOLUTION

### 快捷键与剪贴板注入

| 原问题 | 状态 | 修复结果 |
|---|---|---|
| 可能粘贴到错误 app | 已修复 | activation 返回值受检；轮询目标 PID 成为 frontmost；发事件前再次核验；用户切到第三 app/进程退出即 abort |
| 恢复覆盖用户新 clipboard | 已修复 | 记录 managed `changeCount`；外部写入后保留新 clipboard，不恢复旧 snapshot |
| 危险全局快捷键 | 已修复 | 可打印键必须 Command + 至少一个额外修饰键；`⌘V`、`⌘C`、`⌘Q`、`⇧A` 等被拒绝 |
| `simulateCmdV` 成功语义过度 | 已修复/明确边界 | true 只表示安全核验、event post 与 clipboard outcome；UI 不再声称任意目标控件已消费文本 |
| 注入队列无上限/旧 operation | 已修复 | max in-flight 4、burst 8、operation 5 秒过期，使用 monotonic uptime |
| 编辑正文导致全量热键抖动 | 已修复 | 命令 draft + Save/Cancel；独立 hotkey-change callback；manager 差异注册 |
| 修饰键超时仍粘贴 | 已修复 | 超时明确返回 false，不发送 `⌘V` |
| 注册失败短暂且不重试 | 已修复 | 持久错误状态、逐项信息、2 秒自动重试；handler 安装失败时不注册 hotkey |
| panel close 状态漂移 | 已修复 | `NSWindowDelegate` 同步，toggle 读取真实 `window.isVisible` |
| 复杂 clipboard best effort 丢数据 | 已修复为保守策略 | 任一 item/type 无法完整复制或 snapshot 期间变化即拒绝注入；恢复结果受检 |

### 语音 runtime 与 provider 配置

| 原问题 | 状态 | 修复结果 |
|---|---|---|
| OpenAI Realtime 多 turn 丢句/乱序 | 已修复 | `OpenAITranscriptAssembler` 按 `item_id`、`content_index`、previous item 组装；有乱序单测 |
| stop/fail/retry 旧任务覆盖新会话 | 已修复 | controller session generation + 所有 callback/task identity guard |
| HTTP/GLM 无法取消 | 已修复 | file transcriber 增加 `cancel()`；URLSession/SSE task 与 UI busy 状态均可取消 |
| 用户可配置任意不兼容音频 | 已修复 | schema 固定协议音频；capture 只接受 16/24 kHz mono PCM16；UI 只读展示 |
| `kind`/`wireProtocol` 分离与 key 泄漏 | 已修复 | `resolvedWireProtocol` 为运行时判别源；kind 由 protocol 推导；protocol/host 跨 secret boundary 时轮换 reference |
| UserDefaults decode 失败覆盖原配置 | 已修复 | v2 schema/catalog、corrupt backup、last-known-good；原坏 bytes 不覆写；无 LKG 时优先恢复有效 v1 |
| GLM 30 秒/25 MiB 未限制 | 已修复 | 倒计时自动 stop + 上传前 size/format 检查；schema 声明上限 |
| 切 Apple 遗留旧 Keychain item | 已修复 | 配置成功后删除旧 secret；删除失败则回滚配置并提示 |
| URL/TLS 无校验 | 已修复 | 仅 WSS/HTTPS；拒绝 userinfo/query/fragment/歧义 path；自定义 host 需显式批准；HTTP redirect 拒绝 |
| 通用 union UI 暴露错误字段 | 已修复 | protocol schema 驱动字段显示；Volc 独立 resource ID/two-pass，固定 `model_name=bigmodel`，不再暴露无效 language |
| OpenAI Realtime Beta 漂移 | 已修复 | GA nested transcription session；`gpt-realtime-whisper`；移除 Beta header；24 kHz mono PCM16；manual commit |
| Provider 缺少完整迁移策略 | 已修复 | v1→v2 migration、preset catalog、D/E/F 补入、精确旧模型升级、用户自定义值保留 |
| stop 用固定 sleep 猜 final | 已修复 | OpenAI 等 ack/item final；Dash 等 `task-finished`；Volc 等 terminal packet；Apple 等真实 final/error |
| realtime writer 无 backpressure/drain | 已修复 | 512-chunk 有界 `AsyncStream` + 单 writer；overflow 失败；stop 先 drain 后 terminal |
| `AVAudioRecorder` bool 被忽略 | 已修复 | 检查 `prepareToRecord()`、`record()`、最终文件存在且非空 |
| Dash 合法重复句被吞 | 已修复 | final segment 顺序追加；“好的。好的。”回归单测 |
| transcriber 共享状态数据竞争 | 已修复 | serialized sender、actor/lock state、connection identity 与 session generation |
| Apple final 后 controller 仍 recording | 已修复 | Apple final 自动进入 stop/inject，且 generation/state 受检 |
| 录音期间删 provider/key 导致 stop 失败 | 已修复 | 会话开始时快照 provider 与 key 到内存；UI session 期间禁用 picker |
| HTTP multipart 内存峰值 | 已修复 | 音频和 multipart 通过自有临时文件/streamed upload，不构造完整双份 `Data` |
| Apple “设备端”未强制 | 已修复 | 检查 `supportsOnDeviceRecognition` 并设置 `requiresOnDeviceRecognition=true` |
| Keychain 命名空间/生命周期弱 | 已修复 | 稳定 service、ThisDeviceOnly 可访问级别、trim/空值拒绝、Clear UI、精确 legacy migration |
| Provider editor 即时写半配置 | 已修复 | 本地 draft + Save/Cancel + schema validation；未保存草稿不能被激活 |

### 最终复核新增闭环

| 复核问题 | 修复 |
|---|---|
| legacy Keychain migration 忽略旧 item 删除失败 | 旧 item 删除失败时移除刚写的 scoped 副本，保留 legacy 为权威来源供下次重试，并保留错误 status |
| protocol/host 更新或 provider 删除忽略 secret cleanup 失败 | store 使用可注入 secret backend；cleanup 失败时回滚 provider/UserDefaults/新 secret，UI 显示失败 |
| Volc schema 比 runtime 宽、language 无效 | schema 与 runtime 共用 `isValidVolcengineResourceID`；只接受 `volc.*.sauc.*`；`supportsLanguage=false` |
| v2 损坏但有效 v1 被忽略 | 恢复顺序为 LKG → 有效 v1 migration → fresh，且坏 v2 bytes 保留 |
| graceful stop 提前失效 generation、丢 conversion 尾部 | stop/cancel 分流；stop 先移除 tap/停 engine，等待 callback group 和 conversion queue，在 generation 有效时 end-of-stream flush converter，之后再清状态 |

## IMPLEMENTATION_SUMMARY

### 主要源码

- 热键/注入：`ClipboardPasteInjector.swift`、`HotkeyManager.swift`、`CommandStore.swift`、`FlotisApp.swift`、`FloatingPanelController.swift`。
- 会话控制/UI：`VoiceInputController.swift`、`SpeechTranscribing.swift`、`FloatingPanelView.swift`、`VoiceSettingsView.swift`、`UIStrings.swift`。
- Provider/config/security：`TranscriptionProviderConfig.swift`、`TranscriptionProviderStore.swift`、`KeychainSecretStore.swift`。
- Runtime：`AppleSpeechTranscriber.swift`、`AudioRecorder.swift`、`StreamingAudioCapture.swift`、`OpenAIRealtimeTranscriber.swift`、`OpenAICompatibleTranscriber.swift`、`DashScopeParaformerRealtimeTranscriber.swift`、`VolcengineBigASRRealtimeTranscriber.swift`。

### 工程与测试

- `project.yml` 新增 `FlotisTests` unit-test target；`Flotis.xcodeproj` 已由 XcodeGen 重建。
- `HotkeyAndInjectionPolicyTests.swift`：5 tests。
- `TranscriptAssemblyTests.swift`：4 tests。
- `SpeechProviderConfigurationTests.swift`：11 tests，包括 v2/v1 recovery、credential boundary success/rollback、provider delete rollback 和 Volc schema/runtime 一致性。

### 文档

- `AGENTS.md` 已更新到 24 app Swift、3 test Swift、2 targets、6 provider、v2/Keychain/session/injection 真实边界。
- `docs/CURRENT_STATE.md`、`PROJECT_MAP.md`、`ARCHITECTURE.md`、`DO_NOT_BREAK.md`、`TESTING.md` 已按当前源码重写。
- 临时目标完成后删除 `docs/NEXT_TARGET.md`。

## VALIDATION_RESULT

已运行并通过：

```text
pwd
git rev-parse --show-toplevel
git status --short
xcrun swiftc -frontend -parse <本轮补丁涉及源码与测试>
xcodegen generate
xcodebuild -project Flotis.xcodeproj -scheme Flotis -configuration Debug -derivedDataPath /tmp/FlotisDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Flotis.xcodeproj -scheme Flotis -configuration Debug -derivedDataPath /tmp/FlotisDerivedData CODE_SIGNING_ALLOWED=NO test
git diff --check
```

结果：

- `BUILD SUCCEEDED`。
- `TEST SUCCEEDED`：20 tests、0 failures。
- 24 个 app Swift 文件、3 个 test Swift 文件。
- `git diff --check` 无 whitespace error。
- 未 add、未 commit、未 push、未创建 PR；用户原有工作树改动未回退或清理。

非致命测试环境警告：当前 Xcode 的 XCTest dylib 构建目标为 macOS 14，而 test target deployment target 为 13；test host 还会输出 App Intents `linkd` 连接日志。两者均未造成 build/test failure。

## REAL_DEVICE_VALIDATION_REMAINING

以下无法由静态分析/unit tests 证明，不视为仍未修复的代码问题：

- Carbon 热键注册与冲突自动恢复、AX 授权/撤权、`CGEvent` 事件是否被具体目标控件消费。
- 跨 Space、目标 app 慢激活/退出、用户中途切 app、clipboard manager 与复杂延迟 pasteboard provider。
- 真实麦克风/Speech 权限、Apple 设备端模型可用性。
- OpenAI、DashScope、Volcengine、GLM 的真实 key、认证、限流、服务端错误、协议事件时序和慢网络。
- macOS Keychain 锁定/权限错误下的 legacy migration、删除失败和 UI 反馈。

真机矩阵已写入 `docs/TESTING.md`。仓库中未写入、读取或调用任何真实 API key。

## UNCERTAINTIES

- macOS 没有通用回执能证明任意目标 app 的任意控件已经消费合成的粘贴事件；当前 success 语义已收窄并明确文档化。
- 公开云端协议可能继续演进；本轮按 2026-07-10/11 核对到的官方协议形态实现，升级前仍需重新核对并做真实账号回归。
- `VoiceInputMode` 与部分 UI 状态持久化仍是产品层待决事项，不属于本审计问题。

## NEXT_RECOMMENDED_ACTION

只需按 `docs/TESTING.md` 跑真机矩阵，优先顺序：注入目标/clipboard 竞争 → Apple 权限与设备端 final → OpenAI Realtime 多 turn → Dash/Volc terminal → HTTP cancel/GLM 30 秒边界 → Keychain migration/cleanup failure UI。静态实现无需继续扩展 provider。
