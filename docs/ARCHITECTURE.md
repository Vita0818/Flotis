# ARCHITECTURE

最近自查日期：2026-07-30

## 总体架构

Flotis V0.8 是一个 `LSUIElement` macOS app。用户通过 Carbon 全局热键控制非激活悬浮语音胶囊；最终转写先进入可编辑审阅态，用户再次确认后，app 才在严格核验目标应用和剪贴板状态后用 `CGEvent` 发送 `⌘V`。

```text
HotkeyManager / FloatingPanelView
            │
            ▼
VoiceInputController
            │
            └── Runtime plan
                 ├── ownedCapture
                 ├── pcmStream
                 └── recordedFile
                          │
      TranscriptionAdapterRegistry
                          │
               adapter runtime
                          ▼
                 editable review
                          │ confirm
                          ▼
                                ClipboardPasteInjector
                                             │
                                             ▼
                                  verified target app
```

`AppDelegate` 装配 `AppState`、`SpeechProviderStore`、`VoiceInputController`、`FloatingPanelController`、可复用的 `FlotisSettingsWindowController` 与 `HotkeyManager`。胶囊齿轮直接调用持有的独立 `760×560` 设置窗口，不依赖字符串 selector，也不再挂接会推动父 panel 的 sheet。Settings 页头的一键退出使用 `NSApplication.shared.terminate(nil)`，因此应用退出仍统一进入 `applicationWillTerminate`，先停止热键并取消当前语音会话；注入进行中退出按钮暂时禁用，`applicationShouldTerminate` 也统一拒绝菜单、`⌘Q` 或其他终止请求，避免在剪贴板恢复窗口内终止。旧 `CommandStore`/`PromptCommand` 源码和数据格式仍保留，但 V0.8 主入口不实例化或展示它们。

## Presentation / Design System

`FlotisDesign.swift` 是胶囊与 Settings 共用的 Presentation / Design System 层。`FloatingPanelView` 和 `VoiceSettingsView` 只从该层取得 palette、字体、内容表面、glass button 与设置页组合组件；视觉层不持有语音或 provider 状态，也不改变 `VoiceInputController`、connection schema、`LocalSecretStore` 或 `ClipboardPasteInjector` 的边界。

- **动态系统白黑**：`FlotisTheme` 使用随 Light/Dark appearance 动态解析的 `.primary`、`.secondary`、透明度派生 tertiary 与系统 `separatorColor`。主要操作为系统白/黑单色；红、橙、绿只保留给录音、警告、成功和失败等有限语义状态，不维护固定品牌色板。
- **窗口 canvas**：Settings 在 macOS 14+ 使用 SwiftUI `windowBackground`；macOS 13 通过 `.windowBackground` `NSVisualEffectView` fallback。胶囊仍由透明 borderless `NSPanel` 承载 `.popover` material；AppKit visual-effect view 使用可拉伸圆角 `maskImage` 同时限定 material 与窗口服务器阴影，CALayer mask 仅裁切 hosted subviews，并在显示或静态尺寸切换后刷新原生阴影。SwiftUI 不再绘制整圈 separator，从源头避免 material、窗口阴影与外描边叠成浅色模式的矩形高光或双边毛躁。
- **内容表面**：结构化内容使用 `regularMaterial`、1 pt separator 和 continuous rounded rectangle；长文本与表单内容保持在系统 canvas / Material 层，不用 glass 覆盖全部正文。
- **Liquid Glass 与兼容路径**：在编译器支持且运行于 macOS 26+ 时，交互表面可使用 `glassEffect`，按钮使用 `.glass` / `.glassProminent`；macOS 13–15 分别回退到 `regularMaterial` 与原生 `.bordered` / `.borderedProminent`，因此 deployment target 仍为 macOS 13。
- **字体与图标**：中文页面大标题和标题使用系统默认字体，英文品牌与标题使用 Serif；正文使用系统默认字体，快捷键和技术信息使用 Monospaced。功能图标继续使用 SF Symbols。
- **共享组合**：胶囊与 Settings 沿用同一套 palette、字体、圆角和系统控件，但去掉重复 page header、section card、状态标题和提示。idle 胶囊为 `120×56`，只显示录音、设置与下方 11 pt 系统次级灰快捷键符号；普通工作态为 `188×56`，错误/提示态为 `280×56`，reviewing 为 `420×160`。所有非审阅态固定 56 pt 高；尺寸请求只保留最后一次，panel 固定在启动屏幕底部中央且不允许整窗背景拖动。缺少 AX 权限不会在用户尚未尝试注入时主动扩张 idle；权限持续显示在 Settings，实际注入失败后再显示单行提示和系统设置入口。

## 界面语言与本地化

`AppLanguage` 与 `UIStrings` 构成独立的 Presentation 文案层。启动时只读取 `Locale.preferredLanguages.first`：明确的简体中文标识（`zh-Hans` 或中国大陆、新加坡、马来西亚地区标识）选择简中；繁体中文、英文和其他语言都选择英文。语言改变后通过重新启动 App 生效，不提供手动切换入口。

- 胶囊、Settings、热键注册、音频捕获、连接测试和各 adapter 的 App 自定义错误都通过同一双语入口生成；英文标题继续进入 Serif 字体路径，中文标题继续使用系统默认字体。
- 日期显示显式使用当前 App 中/英文 locale，避免其他系统 locale 把英文界面中的日期格式化成第三种语言。
- `project.yml` 以英文为 development language 和权限说明基值；`InfoPlist.xcstrings` 为麦克风与 Speech Recognition 权限提示提供英文、简中资源。
- UI 语言不参与 `TranscriptionConnection.language`、模型、endpoint、协议事件或 schema 编码。现有用户 connection 名称和历史测试摘要不做持久化迁移；仅对仍匹配内建默认名称的稳定 UUID 做显示层本地化。
- 服务端返回的原始错误和 Apple/AVFoundation 的系统错误保留真实内容；App 自己添加的 wrapper/fallback 保证中英双语。

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
- Settings 另有独立的 Presentation visibility 层：当前 allowlist 只包含 OpenAI Compatible HTTP。它只过滤 SwiftUI 展示，不参与 connection 编码、active 选择的持久化、adapter registry 或 runtime 判别。

## V0.8 热键链路与旧命令兼容

1. `HotkeyManager` 安装 Carbon `kEventHotKeyPressed` 与 `kEventHotKeyReleased` handler；press gate 保证一次物理按下只分派一次，release 后才允许下一次。
2. V0.8 App 只传入空 command 列表，因此只注册 panel `100`（`⌘⌥⇧0`）和 voice `200`（`⌘⌥⇧R`）。底层从 `1000` 开始的命令 ID 映射仍为旧数据兼容实现，但当前不可达。
3. 注册使用 Carbon `kEventHotKeyExclusive` 并保持差异同步；生成的 Info.plist 以 `LSMultipleInstancesProhibited=true` 阻止两个 Flotis 进程同时竞争。失败消息保持在胶囊，并每 2 秒重试；event handler 安装失败时不会注册孤立 hotkey。
4. `VoiceInputState.hotkeyAction` 是纯策略映射：idle/failed→start，recording/streaming→stop，reviewing→inject，requesting/connecting→cancel，stopping/transcribing/injecting→none。
5. 固定语音热键触发时会先确保胶囊可见。注入器等待 `⌘⌥⇧R` 的修饰键和主键 R 全部释放，并确认 Flotis 自身 key window 已让出键盘焦点后，才允许发 `⌘V`。
6. 旧 `commands.json` 不被 V0.8 主入口加载、修改或删除；恢复命令产品能力必须另行做显式产品与迁移决策。

## 语音会话状态机

`VoiceInputState`：

```text
idle → requestingPermission → connecting → recording/streaming
     → stopping → transcribing → reviewing → injecting → idle
                                │       ▲         │
                                │       └─ retry ─┘
                                └──────────────→ failed
```

关键生命周期约束：

- 每次 `beginSession` / cancel / fail 都推进 `sessionGeneration`。所有异步 callback/task 回主线程前必须匹配 generation，旧会话不能清理或注入新会话。
- controller 保存 operation task、realtime writer task、recording limit task、streaming/file transcriber、capture/recorder；取消会统一终止这些资源。
- connection 配置与 API key 在会话开始时快照到 adapter runtime。录音期间切换/删除 connection 或清除本地 secret 不会让已开始会话在 stop 时重新查错配置。
- requesting/connecting 状态向 UI 暴露 Cancel；stopping/transcribing 正在完成终态处理时忽略额外热键，避免误清空即将进入审阅的文本。provider 只在 Settings 中切换。
- adapter 完成后先释放 capture/transcriber/runtime，再将 trim 后的最终文本写入 `transcriptPreview` 并进入 reviewing；reviewing 不持有录音或网络资源。
- reviewing 使用原生 `NSTextView`，可编辑、鼠标选择、右键或 `⌘C` 复制；工具栏另有复制全部按钮。确认后才调用 `ClipboardPasteInjector`。注入失败回到 reviewing 并保留文本，成功才清空并回 idle。
- Apple Speech 收到真正 final 时会自动走 graceful stop/review，不会把 UI 留在 recording，也不会自动注入。

## 实时音频管线

`StreamingAudioCapture` 从 `AVAudioEngine` tap 深拷贝 buffer，在串行 conversion queue 输出 PCM16；只接受当前 schema 支持的 16 kHz 或 24 kHz、单声道参数。每个 tap callback 进入 dispatch group；graceful stop 先移除 tap/停止 engine，在 generation 仍有效时等待所有 in-flight conversion，再向 `AVAudioConverter` 发送 end-of-stream 并交付尾帧，最后才清状态。cancel 则先失效 generation，使待处理 chunk 安全丢弃。

controller 将 chunk 写入容量为 512 的有界 `AsyncStream`，由单一 writer 按序调用 transcriber。buffer drop 被视为会话失败；stop 先停止 capture 并 drain writer，再发送协议 terminal/commit，避免尾音与 finish 竞态。

## 六条 provider 路径

### Apple Speech

- `AppleSpeechTranscriber` 运行时请求麦克风与 Speech 权限。
- 必须满足 `supportsOnDeviceRecognition`，并设置 `requiresOnDeviceRecognition = true`。
- `AppleTranscriptAccumulator` 使用 `SFTranscriptionSegment` 的 timestamp/duration 保存时间片段；重叠片段替换旧假设，非重叠片段追加。空 final 保留最后一个有效 partial，handler 始终发布完整累积文本。
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

- Settings 可见主表单只显示 Endpoint（同一标签下内部仍保持 `baseURL + path` 两个输入）、API Key 与 Model；Connection Name 和多 connection 管理当前隐藏但底层值不删除。Language、Prompt、Temperature 是折叠的可选高级字段；成功保存后该 OpenAI Compatible connection 自动设为当前项。
- WAV/M4A 兼容选择、16 kHz 单声道音频参数与 JSON response mode 继续由已有 connection/schema 管理，不在精简主表单中展示；保存旧 M4A connection 时不得静默改写为 WAV。
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

当前 Settings 只会为 OpenAI Compatible HTTP 实例化 editor：协议、preset、connection name 与多 connection 侧栏不可见；没有现有 OpenAI connection 时只显示加号，创建内存 draft 后 Cancel 不落盘。底层六套 schema 与多 connection 数据仍用于迁移、normalize、校验、连接测试和 runtime；可见性不是新的 runtime discriminator。URL 校验继续拒绝非 HTTPS、userinfo、query、fragment、反斜杠和歧义 path。自定义 host 仍需用户显式确认，UI 仍显示凭据的精确目标 host。

adapter、scheme、host、effective port 或 auth type 改变会改变 `secretBoundaryIdentifier`：store 生成新 `apiKeyReference`，先保存新配置/可选新 key，成功后再删除旧 secret，防止旧服务凭据被发送到新目标。清理失败时事务回滚。

## Connection 持久化与恢复

- 主数据为 `TranscriptionConnectionStoreSnapshot` v3：`schemaVersion = 3`、`presetCatalogVersion`、connections、active ID；UserDefaults 主键为 `flotis.transcriptionConnections.v3`。
- Settings 从完整 `providers` 计算可见数组，但绝不把过滤结果写回 store。隐藏 connection、隐藏 active ID 及其 `apiKeyReference` 不会因打开、编辑或关闭 Settings 而删除或改写。
- `flotis.speechProviders.v2`、其 v2 last-known-good 与 `flotis.speechProviders.v1` 只作为只读迁移输入。迁移保留 UUID、用户名称、插入顺序、有效 active ID、自定义 endpoint/model/options，以及安全边界未变的 `apiKeyReference`，不会覆写旧 bytes。
- v3 decode/normalize 后保存 v3 last-known-good。坏数据另存 backup + metadata，不会用默认值覆写原 authoritative bytes；全新安装只创建 Apple connection。
- active connection 必须配置有效；需要 key 的 connection 还必须能从 `LocalSecretStore` 读到非空 key，否则不能激活或从 picker 选择。
- create/update/delete/clear credential 均为事务操作；持久化或旧 secret 清理失败时恢复原 snapshot，并清理本次新建 secret。

## Test Connection

`TranscriptionConnectionTester` 使用与真实会话相同的 registry/runtime factory：

- Apple 路径只做 locale、recognizer availability 与设备端能力检查，不请求麦克风。
- HTTP/file 与 Realtime 路径使用程序生成的 0.8 秒无隐私 PCM/WAV 或 M4A 合成音；不读取用户录音或历史转写。
- HTTP 验证实际 multipart、状态码、Content-Type 与顶层 `text` 结构；Realtime 验证 start、append、manual commit 和协议终态。合成音不是语音质量样本，因此合法空 `text` 也可证明 transport/响应结构可用。
- 成功只保存时间、adapter version、固定安全摘要与配置 fingerprint，不保存 transcript。失败摘要限制长度，并先按本次内存中的完整 API key 精确脱敏，再做通用凭据模式脱敏。
- fingerprint 覆盖 endpoint/model/options 与 credential revision，但不含用户显示名称；相关配置或凭据变化会自动使旧测试记录失效。

## 应用自管 Secret Store 边界

- `LocalSecretStore` 是唯一生产凭据后端，路径固定为 `~/Library/Application Support/Flotis/secrets.json`。版本化 JSON envelope 使用 `schemaVersion = 1`，`secrets` 字典以 provider 的 `apiKeyReference` 为键；reference 从不参与文件路径拼接。
- Flotis 目录强制为 `0700`，`secrets.json` 与 `.secrets.lock` 为 `0600`。读写先打开不跟随符号链接的目录描述符；同一进程由共享 `NSLock` 串行化，多进程通过 `.secrets.lock` 的 POSIX advisory write lock 覆盖完整 read-modify-write。锁竞争使用单调时钟短间隔重试并在 500 ms 后失败，不会因另一个暂停或卡死的进程永久等待。数据写入同目录 `0600` 随机临时文件并 `fsync`，再用 `renameat` 原子替换并同步目录。
- 输入会 trim，空值、超长 reference/secret、超过 256 条记录或超过 1 MiB 的 payload 拒绝保存。读取只接受普通文件、当前 schema、合法 JSON 与合法内容；符号链接、目录、其他文件类型、损坏或异常大的文件均返回失败，保存不得覆盖损坏数据。
- 删除 connection、切换到无需 key 的 adapter、改变 secret boundary 或 UI Clear 都会清理对应本地记录；最后一条记录删除后移除 `secrets.json`。文件系统删除不承诺物理介质上的安全擦除。
- Flotis 不再导入 `Security`、调用 `SecItem*`，也不读取、迁移或删除旧系统钥匙串条目。旧 connection 的 `apiKeyReference` 继续有效，但升级用户必须在新构建中重新输入一次 API key；旧条目只能由用户自行处理。
- 该文件不做独立加密，安全性依赖 macOS 登录用户权限和可选的 FileVault；同一登录用户权限下的进程仍可能读取，不得把 `0600` 描述成钥匙串级保护。

## 剪贴板注入链路

1. 非提示式检查 AX 权限；无权限立即失败，绝不发 `CGEvent`。
2. 捕获当前或最近的非 Flotis target application、PID、入队时间与文本；队列最多 4 个 in-flight，burst 最多 8 个，operation 5 秒过期。
3. 仅当剪贴板全部 item/type 可同步复制且 `changeCount` 未在快照期间改变时开始 burst；无法完整快照则拒绝注入。
4. 写入文本后记录 app 管理的 `changeCount`，让 Flotis 自身 key window 辞去键盘焦点，激活目标并轮询确认它确实 frontmost 且本 app 不再持有 key window；用户切到第三方 app、进程退出或激活超时均 abort。
5. 等 `⌘⌥⇧R` 的修饰键与主键 R 全部释放；Carbon hotkey 可使用当前 5 秒 operation 有效期内的剩余时间，operation 过期仍返回 false。发事件前再次核验 AX、目标 PID/frontmost、Flotis key window、operation 时效与 pasteboard `changeCount`。
6. post `⌘V` 后等待目标读取窗口。只有 pasteboard 仍是 app 写入的版本才恢复原 snapshot；若用户或 clipboard manager 已写新内容，则保留新内容。
7. completion=true 表示安全前置条件成立、事件已 post、剪贴板恢复/保留成功；不宣称任意目标控件一定消费了事件。

V0.8 胶囊为 borderless panel，不提供红色关闭按钮；panel toggle 仍以真实 `window.isVisible` 为准，voice hotkey 在 panel 隐藏时会先恢复可见性。

## 线程与安全约束

- UI 与 controller 状态在 MainActor。
- WebSocket sender 串行；协议解析/connection/transcript 状态使用 actor 或锁隔离。
- 网络仅允许 HTTPS/WSS；HTTP 与 WebSocket session 共用 no-redirect delegate，携带凭据的请求不跟随重定向。
- API key 不进入 UserDefaults、connection snapshot、文档或日志；明文只存在当前会话内存与应用自管 `secrets.json`，connection 配置只保存引用。
- temp cleanup 仅匹配 Flotis 自有前缀、普通文件且超过 24 小时，避免清理无关文件。
