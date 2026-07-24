# PROJECT_MAP

最近自查日期：2026-07-12

本文描述当前仓库结构。事实来源为 `project.yml`、生成后的 `Flotis.xcodeproj/project.pbxproj`、`run.sh`、当前源码和测试。

## 目录结构总览

```text
Flotis/
├── Flotis/             26 个 app Swift 源文件
├── FlotisTests/        4 个 XCTest 源文件
├── Flotis.xcodeproj/   xcodegen 生成工程
├── docs/               项目常驻状态、架构、禁区和测试说明
├── codex-report/       时间戳审计/实施报告
├── project.yml         XcodeGen 规格（app + unit-test target）
└── run.sh              冷启动构建与运行辅助脚本
```

## Target / 工程配置

| Target | 类型 | 平台 | 入口 / 依赖 | 职责 |
|---|---|---|---|---|
| `Flotis` | application | macOS 13+ | `Flotis/FlotisApp.swift` | `LSUIElement=YES` 的 V0.8 悬浮语音输入胶囊 |
| `FlotisTests` | unit-test bundle | macOS 13+ | depends on `Flotis` | 快捷键/注入策略、转写组装、provider 配置与迁移测试 |

- Bundle ID：App 为 `com.Vita0818.FlotisMac`，测试 bundle 为 `com.Vita0818.FlotisMacTests`。
- 版本：`MARKETING_VERSION=0.8.0`，`CURRENT_PROJECT_VERSION=1`。
- Swift language version：5.0；Info.plist 自动生成。
- 用法描述：`NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`。
- 无第三方 package、entitlements、sandbox 或显式 code-signing 配置。

## App 源文件

`Flotis/` 当前 26 个 Swift 文件：

| 文件 | 主类型 / 职责 |
|---|---|
| `FlotisApp.swift` | `FlotisApp` / `AppDelegate`；装配 provider store、voice controller、capsule panel 与两个固定 hotkey，退出时取消语音会话 |
| `AppState.swift` | 中央 `ObservableObject` UI/语音状态 |
| `VoiceInputMode.swift` | `VoiceInputMode`、含 reviewing 的 `VoiceInputState` 与纯 `VoiceHotkeyAction` 映射 |
| `VoiceInputController.swift` | `@MainActor` session-generation 状态机；执行三类 runtime plan，并在最终转写后先审阅、再显式注入 |
| `SpeechTranscribing.swift` | streaming/file runtime 协议；配置在 adapter 创建 runtime 时完成快照 |
| `TranscriptionAdapterRegistry.swift` | 六个版本化 adapter 的唯一 registry、runtime factory 与通用执行计划 |
| `TranscriptionConnectionTester.swift` | 使用内置非隐私音频执行本地能力、HTTP 或 Realtime 协议探测 |
| `AppleSpeechTranscriber.swift` | 强制设备端 Apple Speech + `AVAudioEngine`；按 segment 时间范围累积 partial/final，防止空 final 和停顿覆盖 |
| `OpenAIRealtimeTranscriber.swift` | OpenAI GA Realtime transcription、串行发送、turn 组装 |
| `DashScopeParaformerRealtimeTranscriber.swift` | DashScope Paraformer WebSocket 生命周期与结果组装 |
| `VolcengineBigASRRealtimeTranscriber.swift` | Volcengine BigASR WebSocket 二进制协议与终态等待 |
| `OpenAICompatibleTranscriber.swift` | `OpenAIHTTPTranscriber` 与 `GLMASRHTTPTranscriber`；磁盘流式 multipart/SSE |
| `AudioRecorder.swift` | `.m4a` / `.wav` 临时录音与启动/结束校验 |
| `StreamingAudioCapture.swift` | 16/24 kHz、单声道 PCM16 捕获、深拷贝与串行转换 |
| `TranscriptionProviderConfig.swift` | canonical v3 connection、adapter schema、独立 preset catalog、legacy v1/v2 decode bridge |
| `TranscriptionProviderStore.swift` | connection CRUD、v1/v2→v3 只读迁移、LKG/坏数据恢复、Keychain 事务 |
| `KeychainSecretStore.swift` | scoped generic-password CRUD 与旧无-service item 精确迁移 |
| `ClipboardPasteInjector.swift` | 有界注入队列、目标 PID/AX/修饰键核验、剪贴板安全恢复 |
| `HotkeyManager.swift` | Carbon 全局热键增量注册、错误状态与重试；V0.8 App 只注册 panel/voice 两项 |
| `PromptCommand.swift` | 旧命令与快捷键数据模型；V0.8 仍为兼容源码及固定热键描述提供类型 |
| `CommandStore.swift` | 旧命令 JSON CRUD 与安全策略；V0.8 主入口不实例化、不展示、不注册命令热键 |
| `FloatingPanelController.swift` | 屏幕底部居中的 borderless/nonactivating floating `NSPanel`，按状态无动画调整尺寸 |
| `FloatingPanelView.swift` | 小胶囊状态、可编辑转写审阅、取消/输入、设置入口与静态布局 |
| `VoiceSettingsView.swift` | Settings 当前展示语音概览与转写连接两 tab；旧命令编辑 view 暂留为不可达兼容源码 |
| `UIStrings.swift` | 集中 UI 字符串 |
| `AccessibilityPermission.swift` | AX 信任检查与系统设置入口 |

实际文件数以 `rg --files Flotis -g '*.swift'` 为准，当前为 26。

## Provider / 传输协议地图

| 固定 ID 前缀 | `TranscriptionAdapterID` | 通用 runtime plan | 音频/模型要点 |
|---|---|---|---|
| `AAAAAAAA` | `apple-on-device` | owned capture | 设备端、locale 可配 |
| `BBBBBBBB` | `openai-realtime-transcription-ga` | PCM stream | 模型可配、PCM16 24 kHz mono、manual commit |
| `CCCCCCCC` | `openai-audio-transcriptions-http-v1` | recorded file | 默认 `gpt-4o-mini-transcribe`、WAV PCM16 16 kHz mono；兼容迁移的 M4A |
| `DDDDDDDD` | `dashscope-paraformer-ws-v1` | PCM stream | `paraformer-realtime-v2`、PCM 16 kHz mono |
| `EEEEEEEE` | `volcengine-bigasr-ws-v3` | PCM stream | `model_name=bigmodel`、独立 `resourceID`、PCM 16 kHz mono |
| `FFFFFFFF` | `glm-asr-http-sse-v4` | recorded file | `glm-asr-2512`、WAV、30 秒 / 25 MiB、严格 SSE 终态 |

运行时以 `TranscriptionAdapterID` 查 registry；controller 只按通用 runtime plan 分派。`SpeechProviderWireProtocol` / `kind` 仅是未编码的 legacy 兼容计算层，preset 不参与 runtime 判断。

## 测试文件

| 文件 | 覆盖 |
|---|---|
| `HotkeyAndInjectionPolicyTests.swift` | V0.8 三段式语音热键动作、危险快捷键拒绝、注入队列容量与 operation 过期 |
| `TranscriptAssemblyTests.swift` | Apple 空 final/停顿/纠错/相邻片段、OpenAI 多 item 乱序/partial-final、Dash 重复句、ASCII/CJK 边界 |
| `SpeechProviderConfigurationTests.swift` | v3 canonical 编码、v1/v2 只读迁移、LKG/坏数据恢复、connection CRUD/事务回滚、preset 与凭据/test fingerprint 边界 |
| `TranscriptionAdapterRuntimeTests.swift` | 六 adapter registry/runtime plan、HTTP multipart/严格响应、WAV/M4A、自定义连接、Key 回显脱敏、GLM SSE、Realtime GA scripted lifecycle |

## 持久化与临时数据

- 旧命令：`~/Library/Application Support/Flotis/commands.json`，V0.8 主入口不加载、不修改、不删除；兼容 store 仍保持 JSON 数组与 atomic write contract。
- Connection 主快照：UserDefaults `flotis.transcriptionConnections.v3`。
- v3 恢复/诊断：`flotis.transcriptionConnections.v3.lastKnownGood`、`flotis.transcriptionConnections.corruptBackup`、`flotis.transcriptionConnections.corruptBackupMetadata`。
- 旧输入：`flotis.speechProviders.v2`、其旧 LKG 与 `flotis.speechProviders.v1` 仅用于只读迁移；迁移不会覆盖旧 bytes。
- API key：Keychain generic password；service `com.flotis.Flotis.speech-provider-api-key`，account 为 `apiKeyReference`。
- 临时录音/连接测试音频：系统 temp 下 `Flotis-Audio-*.m4a` 或 `Flotis-Audio-*.wav`。
- 临时 multipart：系统 temp 下 `Flotis-Multipart-*`；仅清理本应用前缀、普通文件且超过 24 小时的项。

## 脚本与生成物

| 文件 / 命令 | 用途 |
|---|---|
| `project.yml` / `xcodegen generate` | 生成 app + tests 工程与 scheme |
| `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` | 无签名本地构建验证 |
| `xcodebuild ... CODE_SIGNING_ALLOWED=NO test` | 运行 unit tests |
| `run.sh` | kill 旧实例、删 DerivedData、重置 AX TCC、生成、构建并打开 app |

构建产物通常位于 DerivedData 的 `Build/Products/Debug/Flotis.app`；本次验证使用 `/tmp/FlotisDerivedData`。

## 需要后续确认

- `VoiceInputMode` / `AppState.voiceMode` 是否应移除或接入产品 UI：`UNKNOWN`。
- UI 状态是否应跨重启持久化：`UNKNOWN`。
- 正式签名、notarization、hardened runtime 与分发方式：尚未配置。
