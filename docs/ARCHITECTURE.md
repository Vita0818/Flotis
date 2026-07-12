# ARCHITECTURE

最近自查日期：2026-07-11

## 总体架构

Flotis 是一个 `LSUIElement` macOS app。用户通过 Carbon 全局热键或非激活浮窗触发命令/录音；转写完成后，app 在严格核验目标应用和剪贴板状态后用 `CGEvent` 发送 `⌘V`。

```text
HotkeyManager / FloatingPanelView
            │
            ├── PromptCommand ───────────────┐
            │                                │
            └── VoiceInputController         │
                    │                        │
                    └── Runtime plan         │
                         ├── ownedCapture    │
                         ├── pcmStream       │
                         └── recordedFile    │
                                  │          │
              TranscriptionAdapterRegistry  │
                                  │          │
                       adapter runtime ──────┤
                                             ▼
                                ClipboardPasteInjector
                                             │
                                             ▼
                                  verified target app
```

`AppDelegate` 装配 `AppState`、`CommandStore`、`SpeechProviderStore`、`VoiceInputController`、`FloatingPanelController` 与 `HotkeyManager`。应用退出时先停止热键并取消当前语音会话。

## Connection、Adapter 与 Preset

配置和运行时分成三层：

```text
用户 connection 实例 ──adapterID──▶ 版本化 adapter ──▶ 通用 runtime plan
          ▲
          └──── preset 只复制建议字段，不参与运行时判别
```

- `TranscriptionConnection` 是 canonical v3 数据，包含 ID、用户名称、adapter ID、endpoint、model、authentication reference、audio、options 与最近测试记录。同一 adapter 可有多个 endpoint/model/key 相互隔离的实例。
- `TranscriptionAdapterID` 有六个稳定 raw value；`TranscriptionAdapterRegistry` 是 adapter descriptor 与 runtime factory 的唯一注册点，拒绝重复 ID。
- `VoiceInputController` 只处理 `ownedCapture`、`pcmStream`、`recordedFile` 三类执行计划，不读取厂商名，也不按 adapter/wire protocol switch。
- `TranscriptionProviderPreset` 是独立 catalog。选择预设只为当前 draft 填入默认字段，不改变 connection identity，也不成为 runtime discriminator。

## 热键与命令链路

1. `HotkeyManager` 安装 Carbon `kEventHotKeyPressed` handler。
2. 固定热键 ID：panel `100`、voice `200`；命令从 `1000` 开始，并按 command UUID 保存稳定映射。
3. 命令变化只在 enabled/shortcut 改变时触发热键更新；标题、正文和排序不会导致全量 unregister/register。
4. 注册采用差异同步；失败消息保持在 UI，并每 2 秒重试。event handler 安装失败时不会注册孤立 hotkey。
5. 可打印键的全局快捷键必须包含 Command 与至少一个额外修饰键；固定 toggle、重复快捷键和危险的裸系统组合会被拒绝。
6. 命令编辑器使用本地 draft，只有 Save 才写 `commands.json`。

## 语音会话状态机

`VoiceInputState`：

```text
idle → requestingPermission → connecting → recording/streaming
     → stopping → transcribing → injecting → idle
                                      └─────→ failed
```

关键生命周期约束：

- 每次 `beginSession` / cancel / fail 都推进 `sessionGeneration`。所有异步 callback/task 回主线程前必须匹配 generation，旧会话不能清理或注入新会话。
- controller 保存 operation task、realtime writer task、recording limit task、streaming/file transcriber、capture/recorder；取消会统一终止这些资源。
- connection 配置与 API key 在会话开始时快照到 adapter runtime。录音期间切换/删除 connection 或清除 Keychain 不会让已开始会话在 stop 时重新查错配置。
- requesting/connecting/stopping/transcribing 状态都向 UI 暴露 Cancel；provider picker 在 active session 期间禁用。
- Apple Speech 收到真正 final 时会自动走 stop/inject，不会把 UI 留在 recording。

## 实时音频管线

`StreamingAudioCapture` 从 `AVAudioEngine` tap 深拷贝 buffer，在串行 conversion queue 输出 PCM16；只接受当前 schema 支持的 16 kHz 或 24 kHz、单声道参数。每个 tap callback 进入 dispatch group；graceful stop 先移除 tap/停止 engine，在 generation 仍有效时等待所有 in-flight conversion，再向 `AVAudioConverter` 发送 end-of-stream 并交付尾帧，最后才清状态。cancel 则先失效 generation，使待处理 chunk 安全丢弃。

controller 将 chunk 写入容量为 512 的有界 `AsyncStream`，由单一 writer 按序调用 transcriber。buffer drop 被视为会话失败；stop 先停止 capture 并 drain writer，再发送协议 terminal/commit，避免尾音与 finish 竞态。

## 六条 provider 路径

### Apple Speech

- `AppleSpeechTranscriber` 运行时请求麦克风与 Speech 权限。
- 必须满足 `supportsOnDeviceRecognition`，并设置 `requiresOnDeviceRecognition = true`。
- 等待真实 final/error；不再用固定 sleep 猜测尾句。

### OpenAI Realtime transcription

- WSS endpoint 默认 `wss://api.openai.com/v1/realtime?model=gpt-realtime-whisper`，Authorization Bearer；不再发送旧 `OpenAI-Beta` header。
- `session.update` 使用 GA 结构：`session.type = transcription`，配置位于 `session.audio.input`；音频为 PCM16 24 kHz mono。
- `turn_detection = null`，由 client 在 writer drain 后发送 `input_audio_buffer.commit`。
- sender 串行化；stop 等待 session ack、commit ack 与 item completion/终态或受控 timeout。
- `OpenAITranscriptAssembler` 用 `item_id`、`content_index` 与 previous item 关系合并 delta/final；跨 turn completion 乱序不会只保留最后一句。

### DashScope Paraformer Realtime

- 默认模型 `paraformer-realtime-v2`，PCM 16 kHz mono。
- 连接后等待 `task-started`；stop 发送 `finish-task` 后继续接收 `result-generated`，直到 `task-finished`。
- final segment 顺序追加，合法重复句不会被 suffix 去重吞掉。

### Volcengine BigASR Realtime

- WebSocket 使用火山二进制帧协议；资源 ID 与模型名分离。
- request 固定 `model_name = bigmodel`；`resourceID` 进入认证/资源边界。
- `enable_nonstream` 表示二遍识别选项，不作为 server VAD 名称展示。
- stop 等待显式 terminal event/packet，连接与解析状态由 actor/同步边界隔离。

### OpenAI HTTP transcription

- 通用 BYOK 默认生成 PCM16、16 kHz、单声道 `Flotis-Audio-*.wav`；从 v2 迁移或显式选择的兼容 connection 仍可使用 `.m4a`。`AudioRecorder` 检查 `prepareToRecord()`、`record()` 与最终文件存在/非空。
- multipart body 先流式写入 `Flotis-Multipart-*` 临时文件，再由 `URLSession` 上传；不把整个音频与 multipart 双份常驻内存。
- 仅接受 HTTPS/Bearer；Authorization-bearing upload 不跟随 redirect，transcriber 可取消。
- 响应必须是 2xx、`application/json` 且顶层存在字符串 `text`；不猜测 `data.text` 等未声明结构。默认不发送 prompt/temperature。

### GLM ASR HTTP Stream

- 录音为 WAV 16 kHz mono，模型固定 `glm-asr-2512`。
- controller 显示倒计时并在 schema 上限前自动 stop；上传前再次校验格式、时长路径和 `<= 25 MiB`。
- HTTP response 按 SSE 增量读取，`[DONE]` 结束；连接和 upload 都可取消。
- response 必须是 2xx 与 `text/event-stream`；`data:` 必须为有效 JSON，只接受明确的 delta/done/error 结构，并要求最终 `[DONE]`。

## Connection 配置模型

`TranscriptionAdapterID` 是运行时单一判别源。`SpeechProviderWireProtocol` 与 `SpeechProviderKind` 只保留为 v1/v2 decode 与源码兼容的计算层，不编码进 v3。

每个 adapter 的 `SpeechProviderProtocolSchema` 声明：

- endpoint 类型（none / WSS / HTTPS）与可信 host suffix；
- 是否需要 API key；
- 模型、音频格式、采样率、声道是固定还是可编辑；
- 支持的 language/prompt/temperature/Volc two-pass 字段；
- 录音时长和上传字节限制。

Connection 编辑器由 schema 驱动，只显示该 adapter 支持的字段，并使用 draft + Save/Cancel。Add 只创建内存 draft，Cancel 不落盘。URL 校验拒绝非 WSS/HTTPS、userinfo、query、fragment、反斜杠和歧义 path。自定义 host 需要用户显式确认，UI 显示凭据的精确目标 host。

adapter、scheme、host、effective port 或 auth type 改变会改变 `secretBoundaryIdentifier`：store 生成新 `apiKeyReference`，先保存新配置/可选新 key，成功后再删除旧 secret，防止旧服务凭据被发送到新目标。清理失败时事务回滚。

## Connection 持久化与恢复

- 主数据为 `TranscriptionConnectionStoreSnapshot` v3：`schemaVersion = 3`、`presetCatalogVersion`、connections、active ID；UserDefaults 主键为 `flotis.transcriptionConnections.v3`。
- `flotis.speechProviders.v2`、其 v2 last-known-good 与 `flotis.speechProviders.v1` 只作为只读迁移输入。迁移保留 UUID、用户名称、插入顺序、有效 active ID、自定义 endpoint/model/options，以及安全边界未变的 `apiKeyReference`，不会覆写旧 bytes。
- v3 decode/normalize 后保存 v3 last-known-good。坏数据另存 backup + metadata，不会用默认值覆写原 authoritative bytes；全新安装只创建 Apple connection。
- active connection 必须配置有效；需要 key 的 connection 还必须能从 Keychain 读到非空 key，否则不能激活或从 picker 选择。
- create/update/delete/clear credential 均为事务操作；持久化或旧 secret 清理失败时恢复原 snapshot，并清理本次新建 secret。

## Test Connection

`TranscriptionConnectionTester` 使用与真实会话相同的 registry/runtime factory：

- Apple 路径只做 locale、recognizer availability 与设备端能力检查，不请求麦克风。
- HTTP/file 与 Realtime 路径使用程序生成的 0.8 秒无隐私 PCM/WAV 或 M4A 合成音；不读取用户录音或历史转写。
- HTTP 验证实际 multipart、状态码、Content-Type 与顶层 `text` 结构；Realtime 验证 start、append、manual commit 和协议终态。合成音不是语音质量样本，因此合法空 `text` 也可证明 transport/响应结构可用。
- 成功只保存时间、adapter version、固定安全摘要与配置 fingerprint，不保存 transcript。失败摘要限制长度，并先按本次内存中的完整 API key 精确脱敏，再做通用凭据模式脱敏。
- fingerprint 覆盖 endpoint/model/options 与 credential revision，但不含用户显示名称；相关配置或凭据变化会自动使旧测试记录失效。

## Keychain 边界

- generic-password service 固定为 `com.flotis.Flotis.speech-provider-api-key`，account 为 provider 的 `apiKeyReference`。
- 新 item 使用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`；输入会 trim，空值拒绝保存。
- v1 无 service item 只按 account 枚举，确认 service 为空后先写 scoped item，再通过 exact persistent reference 删除旧 item；不会用宽泛 class+account 删除新 item。
- 删除 connection、切换到无需 key 的 adapter、改变 secret boundary 或 UI Clear 都会清理对应旧 item。

## 剪贴板注入链路

1. 非提示式检查 AX 权限；无权限立即失败，绝不发 `CGEvent`。
2. 捕获当前或最近的非 Flotis target application、PID、入队时间与文本；队列最多 4 个 in-flight，burst 最多 8 个，operation 5 秒过期。
3. 仅当剪贴板全部 item/type 可同步复制且 `changeCount` 未在快照期间改变时开始 burst；无法完整快照则拒绝注入。
4. 写入文本后记录 app 管理的 `changeCount`，激活目标并轮询确认它确实 frontmost；用户切到第三方 app、进程退出或激活超时均 abort。
5. 等修饰键完全释放；超时返回 false。发事件前再次核验 AX、目标 PID/frontmost、operation 时效与 pasteboard `changeCount`。
6. post `⌘V` 后等待目标读取窗口。只有 pasteboard 仍是 app 写入的版本才恢复原 snapshot；若用户或 clipboard manager 已写新内容，则保留新内容。
7. completion=true 表示安全前置条件成立、事件已 post、剪贴板恢复/保留成功；不宣称任意目标控件一定消费了事件。

浮窗的红色关闭按钮通过 `NSWindowDelegate` 同步 `AppState.isPanelVisible`；toggle 以真实 `window.isVisible` 为准。

## 线程与安全约束

- UI 与 controller 状态在 MainActor。
- WebSocket sender 串行；协议解析/connection/transcript 状态使用 actor 或锁隔离。
- 网络仅允许 HTTPS/WSS；HTTP 与 WebSocket session 共用 no-redirect delegate，携带凭据的请求不跟随重定向。
- API key 不进入 UserDefaults、JSON、文档或日志；配置只保存引用。
- temp cleanup 仅匹配 Flotis 自有前缀、普通文件且超过 24 小时，避免清理无关文件。
