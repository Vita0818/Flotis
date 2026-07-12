# Flotis 快捷键注入与语音输入配置审计报告

## MODEL_CHECK_RESULT

当前执行模型：Codex / GPT-5。

## PATH_CHECK_RESULT

- `pwd`: `/Users/vita/Vitemis/Flotis`
- Git root: `/Users/vita/Vitemis/Flotis`
- 结果：路径匹配预期仓库根目录。

## FILES_WRITTEN

- 新增：`codex-report/07_10_26-23_04-hotkey-voice-audit.md`

## SUMMARY

本轮按只读审计结论整理报告，仅把问题写入 Markdown。审计重点是：

- 快捷键到剪贴板粘贴注入链路的稳定性、目标 app 选择、剪贴板恢复和热键配置风险。
- 语音输入 provider 配置方案、协议切换、凭据生命周期、实时/HTTP 转写运行时状态机风险。

外部协议核对来源：

- OpenAI Realtime transcription 当前文档：`session.update` 使用 `session.type = "transcription"` 和嵌套 `audio.input` 配置；当前低延迟实时转写推荐 `gpt-realtime-whisper`，并要求用 `item_id` 对齐多 speech turn 的 final transcript，因为不同 turn 的 completion 顺序不保证。参考：https://developers.openai.com/api/docs/guides/realtime-transcription
- 阿里云 Paraformer WebSocket 文档：发送 `finish-task` 后仍应继续接收 `result-generated`，直到收到 `task-finished` 再关闭连接。参考：https://help.aliyun.com/en/model-studio/websocket-for-paraformer-real-time-service
- 智谱 GLM-ASR 文档：上传文件支持 `.wav / .mp3`，文件大小限制 `<= 25 MB`，音频时长限制 `<= 30 秒`；`stream=true` 是 Event Stream 返回，不是实时上传流。参考：https://docs.bigmodel.cn/api-reference/%E6%A8%A1%E5%9E%8B-api/%E8%AF%AD%E9%9F%B3%E8%BD%AC%E6%96%87%E6%9C%AC
- Apple `requiresOnDeviceRecognition` 官方属性页：用于约束 Speech recognition request 是否必须设备端识别。参考：https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition

## PROJECT_AUDIT_SUMMARY

当前源码实际是 24 个 Swift 文件，包含 Apple Speech、OpenAI Realtime、OpenAI HTTP、DashScope Paraformer Realtime、Volcengine BigASR Realtime、GLM ASR HTTP Stream 六类默认/预设 provider。核心链路为：

`HotkeyManager` -> `VoiceInputController` -> provider-specific transcriber/capture/recorder -> `ClipboardPasteInjector`。

快捷键注入通过 Carbon 全局热键触发，最终用系统级 `CGEventTapLocation.cghidEventTap` 发送 `⌘V`。语音配置通过 `SpeechProviderConfig` 的 `kind + wireProtocol + flat fields` 表达，provider 数据写入 UserDefaults `flotis.speechProviders.v1`，API key 只保存 Keychain 引用 `apiKeyReference`。

## ISSUES

### 快捷键注入稳定性

#### P1 - 可能粘贴到错误 app，且代码会报告成功

`ClipboardPasteInjector` 在写入剪贴板后只调用 `activateTargetApplicationIfNeeded`，随后固定等 100ms 再发系统级 `⌘V`。代码没有检查 `application.activate(...)` 的返回值，也没有在发事件前确认当前 frontmost PID 是否仍是目标 app。

证据：

- `Flotis/ClipboardPasteInjector.swift:86` 激活目标后直接进入延迟粘贴。
- `Flotis/ClipboardPasteInjector.swift:149-153` 未检查激活结果和前台 PID。
- `Flotis/ClipboardPasteInjector.swift:201-202` 使用 `.cghidEventTap` 发系统级事件。
- `Flotis/ClipboardPasteInjector.swift:140-146` 目标 app 可以回退到 `lastTargetApplication`。

触发条件包括目标在其他 Space、激活慢、目标进程已退出、用户在 100ms 等待期间切换 app。结果是文本可能被粘贴到当前前台 app，形成错误窗口注入或信息泄漏。

#### P1 - 剪贴板恢复会覆盖用户在注入窗口期间的新剪贴板内容

注入开始时只保存一次 `burstOriginalClipboard`，恢复时只校验内部 `generation`、队列和 `isProcessingPaste`，没有记录/比较 `NSPasteboard.changeCount`。如果用户或剪贴板管理器在注入到恢复的窗口内复制了新内容，恢复逻辑会把旧快照写回，覆盖用户新剪贴板。

证据：

- `Flotis/ClipboardPasteInjector.swift:54-60` 创建 burst 原始剪贴板快照。
- `Flotis/ClipboardPasteInjector.swift:110-126` 恢复条件只看内部 generation 和队列状态。

#### P1 - 快捷键校验允许危险系统级组合，且与注入用 `⌘V` 有反馈风险

命令快捷键只要求至少一个修饰键，并排除固定 toggle/重复项。它会允许 `⇧A`、`⌘C`、`⌘Q`、`⌘V` 这类高冲突组合。注入本身合成的也是 `⌘V`，如果用户把某个命令注册成 `⌘V`，普通粘贴会被全局热键截获；合成事件是否会再次触发 Carbon hotkey 需要真机验证，但这是高风险配置缺口。

证据：

- `Flotis/CommandStore.swift:133-152` 只校验有修饰键、固定快捷键和命令间重复。
- `Flotis/ClipboardPasteInjector.swift:189-203` 注入事件固定发送 `⌘V`。

#### P2 - `simulateCmdV()` 的成功语义不代表真的粘贴成功

`simulateCmdV()` 只要创建并 post 了两个 `CGEvent` 就返回 true；没有确认目标 app 收到事件、剪贴板内容被消费或焦点正确。`VoiceInputController` 把 true 当成注入成功，false 文案则提示“可能没有权限”，会误导用户和状态机。

证据：

- `Flotis/ClipboardPasteInjector.swift:189-203` post 后直接返回 true。
- `Flotis/VoiceInputController.swift:276-288` 按 success 切换 idle/failed。

#### P2 - 注入队列无上限，可能积压并向旧目标 app 粘贴过期内容

`pendingOperations` 没有容量上限、去重、合并或超时。每个 operation 固定包含 100ms 激活等待、最多 800ms 修饰键等待、500ms 粘贴后等待和 250ms 恢复窗口。快速连按命令或热键可能产生 backlog，后面的旧 operation 仍按捕获时的 targetApplication 注入。

证据：

- `Flotis/ClipboardPasteInjector.swift:21-25` 队列和状态字段。
- `Flotis/ClipboardPasteInjector.swift:62-70` 无上限 append。
- `Flotis/ClipboardPasteInjector.swift:73-97` 串行处理每个 operation。

#### P2 - 命令编辑每输入一个字符都会触发全量热键 unregister/register

设置页命令编辑绑定直接调用 `commandStore.updateCommand`。标题、内容、启用状态等任何字符变化都会保存并 `publishChange`，AppDelegate 收到后调用 `HotkeyManager.updateCommands`，而 update 内部会 stop/start 全部热键。编辑文本时会产生热键抖动和短暂空窗。

证据：

- `Flotis/VoiceSettingsView.swift:237-242` command binding setter 直接更新 store。
- `Flotis/CommandStore.swift:92-97` update 后 persist/publish。
- `Flotis/CommandStore.swift:171-189` publishChange 通知。
- `Flotis/FlotisApp.swift:63-66` 每次 commands changed 都更新热键。
- `Flotis/HotkeyManager.swift:33-35` updateCommands 走全量 start。

#### P2 - 修饰键等待超时后仍会粘贴

等待逻辑在修饰键释放或到达 deadline 时都会调用 completion。也就是说用户一直按住 `⌘/⌥/⇧/⌃`，0.8s 后仍会发 `⌘V`，此时实际组合可能不是单纯 `⌘V`。

证据：

- `Flotis/ClipboardPasteInjector.swift:155-166`

#### P2 - 热键注册失败只显示 2 秒临时错误，没有持久状态和重试

Carbon 注册失败会通过 `onRegistrationError` 传给 UI，但 AppDelegate 只显示 2 秒后清除，没有记录哪个命令未注册、没有禁用该命令、也没有自动重试。

证据：

- `Flotis/HotkeyManager.swift:124-130`
- `Flotis/FlotisApp.swift:91-97`

#### P3 - 浮窗红色关闭按钮会导致 `isPanelVisible` 状态不同步

`NSPanel` 允许 `.closable`。用户点红色关闭时，`AppState.isPanelVisible` 不会同步更新。之后第一次 toggle hotkey 可能只是把状态从 true 切到 false，但窗口本来已经关了，用户感知是热键无反应。

证据：

- `Flotis/FloatingPanelController.swift:12-16`
- `Flotis/FlotisApp.swift:45-52`

#### P3 - 剪贴板快照/恢复是 best effort，复杂类型可能丢失

快照仅遍历 `NSPasteboardItem.types` 并同步读取 data。延迟提供者、文件承诺、非 data 表示或 `writeObjects` 失败都没有显式处理。恢复时也忽略 `pasteboard.writeObjects` 返回值。

证据：

- `Flotis/ClipboardPasteInjector.swift:169-187`

### 语音运行时与配置方案

#### P1 - OpenAI Realtime 多 turn 会丢文本或顺序错乱

代码把所有 delta 拼到全局 `partialTranscript`，每个 completed 事件又覆盖全局 `finalTranscript`。stop 时优先返回最后一个 `finalTranscript`。OpenAI 当前文档说明不同 speech turn 的 completion 顺序不保证，应使用 `item_id` 对齐和排序；代码没有读取 `item_id`，因此默认 server VAD 多 turn 场景下会丢前文、错序或只注入最后一句。

证据：

- `Flotis/OpenAIRealtimeTranscriber.swift:102-118`
- `Flotis/OpenAIRealtimeTranscriber.swift:50-59`
- `Flotis/TranscriptionProviderConfig.swift:117-135` 默认 Realtime 开启 `enableServerVAD`。

#### P1 - stop/fail/retry 存在旧任务覆盖新会话的竞态

`VoiceInputController` 启动的 stop Task 没有保存 task handle，也没有 session generation 或 identity check。若 stop 期间 transcriber error 触发 `fail()`，用户马上重试创建新会话，旧 stop Task 稍后恢复时会无条件清空 `activeStreamingTranscriber/realtimeAudioCapture/activeProvider` 并注入旧文本，可能破坏新录音。

证据：

- `Flotis/VoiceInputController.swift:180-190` stop Task 无身份校验。
- `Flotis/VoiceInputController.swift:305-327` handler 可异步 fail 并清理当前状态。
- `Flotis/OpenAIRealtimeTranscriber.swift:50-59` stop 固定 sleep。
- `Flotis/DashScopeParaformerRealtimeTranscriber.swift:53-62` stop 固定 sleep。
- `Flotis/VolcengineBigASRRealtimeTranscriber.swift:55-70` stop 固定 sleep。

#### P1 - HTTP/GLM 转写无法取消，UI 可能长期卡住

`FileSpeechTranscribing` 协议没有 cancel。HTTP/GLM 上传和 SSE 读取任务没有保存 handle。录音停止进入 `.transcribing` 后，`toggleRecording()` 只显示 busy，不会取消网络请求；`cancel()` 也只能取消 recorder/streaming transcriber，取消不了已启动的 HTTP task。

证据：

- `Flotis/SpeechTranscribing.swift:14-16`
- `Flotis/VoiceInputController.swift:211-225`
- `Flotis/VoiceInputController.swift:27-29`
- `Flotis/VoiceInputController.swift:32-43`

#### P1 - 用户可输入任意音频格式/采样率/声道，可能崩溃或发错音频

设置页把 `sampleRate/channels/inputAudioFormat` 全部暴露成文本字段，`channels` 直接 `Int($0)` 保存。实时捕获里把 channels 转成 `AVAudioChannelCount(channels)`，负数或过大值可能触发整数转换问题；同时捕获实际总是输出 PCM16 interleaved，但 UI 允许声明 `g711`、stereo、非 24k OpenAI、Dash/Volc 不支持组合等，容易向服务端发送与声明不一致的音频。

证据：

- `Flotis/VoiceSettingsView.swift:497-506`
- `Flotis/VoiceSettingsView.swift:545-554`
- `Flotis/StreamingAudioCapture.swift:27-31`
- `Flotis/StreamingAudioCapture.swift:101-104`

#### P1 - `kind` 与 `wireProtocol` 分离导致协议切换时保留不兼容字段和旧密钥

配置 UI 允许单独改 provider kind 和 wireProtocol。store normalization 只修正 unsupported protocol 和补 `apiKeyReference`，不会按目标协议重置 endpoint、model、audio 参数、prompt 或 API key 引用。用户从 OpenAI 切到 Dash/Volc/GLM 后，可能继续使用旧 endpoint/model/key；如果只改 host 不换 key，就会把旧厂商 key 发给新厂商。

证据：

- `Flotis/VoiceSettingsView.swift:468-480`
- `Flotis/VoiceSettingsView.swift:538-542`
- `Flotis/TranscriptionProviderStore.swift:174-201`
- `Flotis/VoiceInputController.swift:82-101`
- `Flotis/VoiceInputController.swift:312-316`

#### P1 - Provider UserDefaults 解码失败会直接覆盖用户配置

`SpeechProviderStore.load()` 如果 UserDefaults 有数据但 decode 失败，会回退默认 providers 并立即 `save()` 到同一个 key。结果是损坏的一次 decode 会把用户 provider 配置覆盖掉，没有备份、迁移错误提示或 last-known-good。原 Keychain items 也会变成孤儿引用。

证据：

- `Flotis/TranscriptionProviderStore.swift:141-155`

#### P1 - GLM-ASR 没有实现官方 30 秒 / 25 MB 限制

GLM provider 是文件上传 + SSE 返回，但 controller 允许无限时长录音；停止后才上传。官方限制是 `.wav/.mp3`、文件 `<= 25 MB`、音频 `<= 30 秒`。超过限制时用户录了很久，最后服务端拒绝，整段 dictation 丢失。

证据：

- `Flotis/TranscriptionProviderConfig.swift:197-215`
- `Flotis/VoiceInputController.swift:133-158`
- `Flotis/VoiceInputController.swift:194-225`
- `Flotis/OpenAICompatibleTranscriber.swift:123-287`

#### P1 - 切到 Apple Speech 会把旧 key 引用从配置抹掉但不删除 Keychain item

任何 provider 都可以把 kind 改成 Apple。normalization 会设置 `apiKeyReference = nil`，但不会删除原引用对应的 Keychain item。之后删除 provider 时只能删除当前 provider 上仍可见的 reference，旧 secret 永久孤儿化。

证据：

- `Flotis/VoiceSettingsView.swift:468-480`
- `Flotis/TranscriptionProviderStore.swift:177-180`
- `Flotis/TranscriptionProviderStore.swift:105-114`

#### P2 - URL/TLS 没有校验，可能向不安全或错误主机发送 key 和音频

UI 允许任意 baseURL/realtimeURL/endpointPath。transcriber 只用 `URL(string:)` 判断可解析，没有强制 `https/wss`、没有 host allowlist、没有明确提示跨厂商 key 风险。ATS 可能拦截部分 `http/ws`，但应用层仍缺少配置防线。

证据：

- `Flotis/VoiceSettingsView.swift:488-506`
- `Flotis/OpenAICompatibleTranscriber.swift:10-21`
- `Flotis/OpenAICompatibleTranscriber.swift:132-145`
- `Flotis/OpenAIRealtimeTranscriber.swift:190-225`
- `Flotis/DashScopeParaformerRealtimeTranscriber.swift:161-180`
- `Flotis/VolcengineBigASRRealtimeTranscriber.swift:248-267`

#### P2 - 通用 union 配置把不支持或语义错误的字段暴露给所有实时协议

Realtime 设置统一暴露 `inputAudioFormat/sampleRate/channels/prompt/serverVAD`，但各协议支持不同。Dash payload 不使用 prompt/server VAD；Volc 的 `model` 实际被用作 resource id，request body 里 `model_name` 固定为 `bigmodel`；Volc `enableServerVAD` 被映射成 `enable_nostream`，从命名和语义上都不像 VAD，需要按火山最新文档和真机联调确认。

证据：

- `Flotis/VoiceSettingsView.swift:497-506`
- `Flotis/DashScopeParaformerRealtimeTranscriber.swift:183-210`
- `Flotis/VolcengineBigASRRealtimeTranscriber.swift:77-79`
- `Flotis/VolcengineBigASRRealtimeTranscriber.swift:115-137`

#### P2 - OpenAI Realtime GA 协议形态与当前实现漂移

代码仍使用 `OpenAI-Beta: realtime=v1` 和 flat `session.input_audio_format/input_audio_transcription/turn_detection` 字段；当前 OpenAI Realtime transcription 文档展示的是 `session.type = "transcription"` 与嵌套 `audio.input.format/transcription/turn_detection`。默认模型仍是 `gpt-4o-mini-transcribe`，而当前低延迟 realtime 文档推荐 `gpt-realtime-whisper`。旧 beta 兼容性需要真实 key 验证，静态审计不能断言完全不可用，但协议漂移已经明确。

证据：

- `Flotis/OpenAIRealtimeTranscriber.swift:24-25`
- `Flotis/OpenAIRealtimeTranscriber.swift:227-255`
- `Flotis/TranscriptionProviderConfig.swift:117-135`

#### P2 - Provider schema 向后兼容有 fallback，但没有完整迁移策略

新增 `wireProtocol` 是 optional，旧 v1 snapshot 可以 decode，并通过 `resolvedWireProtocol` 回退旧 OpenAI 行为，这是正向点。但当前 UserDefaults key 仍叫 `flotis.speechProviders.v1`，没有显式 migration 版本；老用户的 persisted providers 不会自动补入 D/E/F 三个新 preset，只能手动 add；normalization 后也不会立即 save，字段补齐和旧数据修正不落盘。

证据：

- `Flotis/TranscriptionProviderConfig.swift:70`
- `Flotis/TranscriptionProviderConfig.swift:229-243`
- `Flotis/TranscriptionProviderStore.swift:15`
- `Flotis/TranscriptionProviderStore.swift:141-155`
- `Flotis/TranscriptionProviderStore.swift:174-201`

#### P2 - 多个 stop 流程依赖固定 sleep，而不是协议 ack

Apple 500ms、OpenAI 700ms、Dash 900ms、Volc 1.2s 都是假定 final 会在固定时间内到达。网络慢、模型延迟或 server final 较晚时会丢尾句；网络快时又增加无谓延迟。Dash 代码已经解析 `task-finished`，但 stop 不等待它；阿里文档明确要求 finish-task 后继续收结果直到 task-finished。

证据：

- `Flotis/AppleSpeechTranscriber.swift:91-99`
- `Flotis/OpenAIRealtimeTranscriber.swift:50-59`
- `Flotis/DashScopeParaformerRealtimeTranscriber.swift:53-62`
- `Flotis/DashScopeParaformerRealtimeTranscriber.swift:101-107`
- `Flotis/VolcengineBigASRRealtimeTranscriber.swift:55-70`

#### P2 - 实时音频写入没有串行 writer/backpressure/drain

tap 里的每个音频 chunk 都创建一个 `Task { @MainActor ... }`，再调用 `appendRealtimeAudio`。没有 serial audio writer、发送队列、backpressure 或 stop drain。网络慢时会堆积 tasks；进入 `.stopping` 后 guard 会丢弃后续 chunks；已发送 chunks 与 terminal finish 之间也可能竞态。

证据：

- `Flotis/VoiceInputController.swift:102-107`
- `Flotis/VoiceInputController.swift:254-263`

#### P2 - `AVAudioRecorder.record()` 返回值被忽略

HTTP 录音启动只创建 recorder 并调用 `record()`，不检查返回 Bool。若底层未开始录音，状态仍会进入 recording，停止后上传空文件或不存在的文件。

证据：

- `Flotis/AudioRecorder.swift:68-70`
- `Flotis/VoiceInputController.swift:144-153`

#### P2 - DashScope 重复句子会被错误吞掉

`appendSegment` 如果 `base.hasSuffix(trimmed)` 就直接返回 base。真实语音中合法重复“好的。好的。”、“yes yes”可能被当作重复 partial 去重而丢掉第二句。

证据：

- `Flotis/DashScopeParaformerRealtimeTranscriber.swift:296-307`

#### P2 - transcriber 内部状态跨 receive task / stop / cancel 共享，缺少 actor 或锁

OpenAI/Dash/Volc transcriber 都有 receive loop 异步更新 transcript/isConnected，同时 stop/cancel 在其他 async path 读写同一状态。Swift class 不是 actor，没有显式锁。实际数据竞争需要 Thread Sanitizer 或结构化并发重构验证，但静态上是明确风险。

证据：

- `Flotis/OpenAIRealtimeTranscriber.swift:10-14`, `Flotis/OpenAIRealtimeTranscriber.swift:66-87`, `Flotis/OpenAIRealtimeTranscriber.swift:265-271`
- `Flotis/DashScopeParaformerRealtimeTranscriber.swift:12-18`, `Flotis/DashScopeParaformerRealtimeTranscriber.swift:69-90`, `Flotis/DashScopeParaformerRealtimeTranscriber.swift:233-239`
- `Flotis/VolcengineBigASRRealtimeTranscriber.swift:12-15`, `Flotis/VolcengineBigASRRealtimeTranscriber.swift:81-99`, `Flotis/VolcengineBigASRRealtimeTranscriber.swift:305-311`

#### P2 - Apple Speech 自动 final 时 controller 状态可能不同步

Apple recognition callback 在 `result.isFinal` 时会调用 `finalTranscriptHandler` 并停止 engine/task，但 `VoiceInputController` 的 final handler 只更新 preview，不把 `.recording` 切回 idle，也不自动注入。用户看到状态仍可能是 recording。

证据：

- `Flotis/AppleSpeechTranscriber.swift:66-69`
- `Flotis/VoiceInputController.swift:300-303`

#### P2 - HTTP provider/key 可在录音期间被删除或切换，停止时才重新读取 key

HTTP start 只校验当时有 key；stop 时又用 captured provider 的 `apiKeyReference` 重新从 Keychain 读取。如果用户在录音期间通过设置删除当前 provider 或 key，stop 会失败并丢录音。配置 UI 没有 active session 锁。

证据：

- `Flotis/VoiceInputController.swift:133-137`
- `Flotis/VoiceInputController.swift:194-199`
- `Flotis/TranscriptionProviderStore.swift:105-120`

#### P3 - 长 HTTP 录音会把整段文件读入内存并构造完整 multipart body

OpenAI HTTP 和 GLM HTTP 都用 `Data(contentsOf:)` 读取整个音频，再把完整 multipart body 放入内存。长录音或大文件会产生明显内存峰值；GLM 还有 25MB/30s 限制但应用层未提前截断。

证据：

- `Flotis/OpenAICompatibleTranscriber.swift:96-104`
- `Flotis/OpenAICompatibleTranscriber.swift:255-263`

#### P2 - Apple Speech “设备端”文档说法没有被代码强制

项目文档把 Apple Speech 描述成“设备端”，但代码创建 `SFSpeechAudioBufferRecognitionRequest` 后只设置 `shouldReportPartialResults = true`，没有设置 `requiresOnDeviceRecognition = true`，也没有检查 `speechRecognizer.supportsOnDeviceRecognition`。因此它不能被当作严格离线/设备端隐私边界。

证据：

- `Flotis/AppleSpeechTranscriber.swift:54-57`
- `docs/CURRENT_STATE.md:9`
- `docs/ARCHITECTURE.md:55`
- `docs/PROJECT_MAP.md:40`

#### P2 - Keychain 命名空间和生命周期偏弱，且 UI 缺少清除 key

Keychain query 只使用 generic password + account，没有 `kSecAttrService`、access group 或 access control；UI 只有保存按钮，没有清除/替换确认；空白字符串之外的空格 key 会被视为已配置。这里不应夸大为其他 app 必然可读，但命名空间、迁移和生命周期管理都偏弱。

证据：

- `Flotis/KeychainSecretStore.swift:8-55`
- `Flotis/VoiceSettingsView.swift:509-522`
- `Flotis/TranscriptionProviderStore.swift:123-130`

#### P2 - Provider editor 每个字段改动都即时持久化，没有 draft/apply/cancel/validation

provider binding setter 直接 `providerStore.updateProvider`，每次输入 URL、model、sampleRate、kind、wireProtocol 都会落盘。用户输入一半的 URL、负数、空 model 或协议切换半成品会立即影响 active provider；全局语音热键可以在半配置状态下启动。

证据：

- `Flotis/VoiceSettingsView.swift:441-446`
- `Flotis/TranscriptionProviderStore.swift:98-103`

### 文档与当前源码冲突

#### P2 - 文档仍按旧状态描述 22 个 Swift 源文件和三 provider

当前 `rg --files Flotis | sort` 显示 24 个 Swift 源文件；`SpeechProviderConfig.defaultProviders` 已包含 6 个 provider/preset。文档和 AGENTS 仍多处写 22 个 Swift 源文件、三 provider 或三条转写路径，容易误导后续维护和测试范围。

证据：

- `AGENTS.md:35`, `AGENTS.md:44`, `AGENTS.md:66`, `AGENTS.md:79`
- `docs/CURRENT_STATE.md:8-10`
- `docs/PROJECT_MAP.md:12`, `docs/PROJECT_MAP.md:31`, `docs/PROJECT_MAP.md:43`
- `docs/ARCHITECTURE.md:55-96`
- `Flotis/TranscriptionProviderConfig.swift:217-224`

#### P2 - `DO_NOT_BREAK` 的 provider/schema 禁区已落后于当前源码

`DO_NOT_BREAK` 写 Provider 配置是 3 个默认 provider、固定 A/B/C UUID，但当前源码已有 D/E/F 默认 provider ID。后续 agent 如果按旧禁区工作，可能把新 provider 当作非标准改动误删或漏测。

证据：

- `docs/DO_NOT_BREAK.md:16`
- `Flotis/TranscriptionProviderConfig.swift:90-95`
- `Flotis/TranscriptionProviderConfig.swift:217-224`

#### P2 - HTTP 临时音频文档仍写 `.m4a`，但 GLM 已使用 `.wav`

当前 `recordingFormat(for:)` 在 GLM protocol 下返回 `.wav`，GLM transcriber 上传 `audio/wav`；文档仍写 HTTP temp 统一 `.m4a` 和 `Content-Type: audio/m4a`。

证据：

- `Flotis/VoiceInputController.swift:245-251`
- `Flotis/OpenAICompatibleTranscriber.swift:255-263`
- `docs/ARCHITECTURE.md:87-96`
- `docs/DO_NOT_BREAK.md:18`, `docs/DO_NOT_BREAK.md:29`, `docs/DO_NOT_BREAK.md:56`
- `docs/PROJECT_MAP.md:45`, `docs/PROJECT_MAP.md:65`

#### P2 - 测试文档缺少新 provider、协议切换、GLM 限制和 key migration 场景

`docs/TESTING.md` 的手动矩阵仍只覆盖 Apple/OpenAI Realtime/OpenAI HTTP，没有覆盖 DashScope、Volcengine、GLM、`kind/wireProtocol` 切换、URL/TLS 校验、Keychain orphan、GLM 30s/25MB 限制等新风险。

证据：

- `docs/TESTING.md:36-55`
- `Flotis/TranscriptionProviderConfig.swift:22-28`
- `Flotis/TranscriptionProviderConfig.swift:157-215`

#### P3 - `CURRENT_STATE` 工作区状态已经过期

`CURRENT_STATE` 写“本轮自查为只读分析，`.DS_Store` 存在，无其他未跟踪业务文件”，但当前 `git status --short` 已有多个修改文件和新增 `AGENTS.md`、`CLAUDE.md`、`GEMINI.md`、`docs/`、Dash/Volc Swift 文件。

证据：

- `docs/CURRENT_STATE.md:54`
- 当前 `git status --short` 输出见本报告 `VALIDATION_RESULT`。

## RECOMMENDED_FIX_ORDER

建议优先级：

1. 先修注入安全边界：粘贴前轮询确认 frontmost PID 等于目标，失败则 abort；恢复剪贴板时引入 pasteboard `changeCount`；禁用 `⌘V/⌘C/⌘Q/无 Command 的单修饰字母` 等危险快捷键；队列加上限或 coalesce。
2. 再修语音 session 生命周期：引入 session generation/identity、保存并取消 Task handle、HTTP 转写可 cancel、stop 等实际协议 final ack，不再靠固定 sleep。
3. 重做 provider 配置模型：以 `wireProtocol` 作为单一判别入口，协议专属 typed config、默认值、校验和 UI；协议切换时原子迁移，清理/重新绑定 key。
4. 加配置数据保护：UserDefaults schema version、decode 失败备份、last-known-good、不自动覆盖坏数据；Keychain 增加 stable service、clear key UI 和 orphan 清理。
5. 更新 docs 和手动测试矩阵：把 24 Swift、6 provider、GLM wav/限制、新第三方实时路径、协议切换/key 迁移全部纳入。

## DOCS_CONTENT_SUMMARY

- `/Users/vita/Vitemis/AGENTS.md`：定义 Codex 可写 `codex-report/`，要求路径核对、保护用户改动、报告命名和报告体字段。
- `AGENTS.md`：定义 Flotis 项目入口、必须阅读文档、修改边界、禁区、关键链路和最终报告字段；其中 Swift 文件数量和 provider 范围已与当前源码不一致。
- `docs/CURRENT_STATE.md`：记录 2026-06-25 的旧状态，仍描述 22 Swift、3 provider 和旧工作区状态。
- `docs/PROJECT_MAP.md`：记录旧目录和关键文件地图，未包含 Dash/Volc 新 provider 文件和 6 provider 默认集。
- `docs/ARCHITECTURE.md`：描述旧三路径语音架构、剪贴板注入链路和安全机制，未覆盖新增第三方协议和 GLM wav/SSE。
- `docs/DO_NOT_BREAK.md`：列出工程禁区、格式/协议禁区、路径和验证要求，但 provider 默认数量、HTTP 临时音频和协议内容已落后。
- `docs/TESTING.md`：列出构建命令、无测试 target、手动验证矩阵；矩阵未覆盖新增 provider 和配置迁移风险。
- `docs/NEXT_TARGET.md`：当前无 active target。

## VALIDATION_RESULT

已运行：

- `pwd` -> `/Users/vita/Vitemis/Flotis`
- `git rev-parse --show-toplevel` -> `/Users/vita/Vitemis/Flotis`
- `git status --short` -> 当前存在用户已有未提交改动，另新增本报告所在 `codex-report/`。
- `rg --files Flotis | sort` -> 当前 24 个 Swift 源文件。
- `git diff --check` -> 通过，无输出。

未运行构建/测试。原因：用户要求把只读审计问题写入 Markdown 报告；本轮只新增报告文件，不改业务源码。项目也没有测试 target。

## UNCERTAINTIES

- `⌘V` 合成事件是否会再次触发用户注册的 Carbon `⌘V` command hotkey，需要真机验证；静态审计只确认配置允许该危险组合。
- 错误 app 注入、Space 切换、慢激活、剪贴板 manager 竞争需要 macOS 真机手动矩阵验证。
- OpenAI 旧 beta Realtime payload 是否仍被服务端兼容，需要真实 OpenAI key 联调；静态审计只确认与当前公开文档有协议漂移。
- Volcengine `enable_nostream` 字段的服务端实际接受情况需要按最新火山官方文档和真实账号联调确认；静态审计只确认当前代码字段命名和 UI 语义不可靠。
- 多 transcriber class 的数据竞争需要 Thread Sanitizer 或 actor/serial executor 重构后验证。

## NEXT_RECOMMENDED_ACTION

不要直接继续堆 provider。下一步建议先做最小修复包：

1. 修 `ClipboardPasteInjector` 的目标 app 确认、pasteboard `changeCount` 防覆盖和危险快捷键校验。
2. 给 `VoiceInputController` 引入 session generation 和 cancellable task 管理，先挡住旧 stop 覆盖新会话。
3. 给 provider 设置增加 Apply/Cancel + schema validation，禁止半配置状态被全局热键启动。
4. 同步更新 `AGENTS.md` 和 `docs/`，把 24 Swift、6 provider、GLM/Dash/Volc 的真实状态写准。
