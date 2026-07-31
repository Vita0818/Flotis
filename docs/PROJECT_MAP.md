# PROJECT_MAP

最近自查日期：2026-07-30

本文描述当前仓库结构。事实来源为 `project.yml`、生成后的 `Flotis.xcodeproj/project.pbxproj`、`run.sh`、当前源码和测试。

## 目录结构总览

```text
Flotis/
├── Flotis/             27 个 app Swift 源文件 + XcodeGen Info.plist + InfoPlist String Catalog
├── FlotisTests/        5 个 XCTest 源文件
├── Flotis.xcodeproj/   xcodegen 生成工程
├── docs/               项目常驻状态、架构、禁区和测试说明
├── codex-report/       时间戳审计/实施报告
├── project.yml         XcodeGen 规格（app + unit-test target）
└── run.sh              冷启动构建与运行辅助脚本
```

## Target / 工程配置

| Target | 类型 | 平台 | 入口 / 依赖 | 职责 |
|---|---|---|---|---|
| `Flotis` | application | macOS 13+ | `Flotis/FlotisApp.swift` | `LSUIElement=YES`、禁止多实例的 V0.8 悬浮语音输入胶囊 |
| `FlotisTests` | unit-test bundle | macOS 13+ | depends on `Flotis` | 快捷键/注入策略、转写组装、provider 配置与迁移测试 |

- Bundle ID：App 为 `com.Vita0818.FlotisMac`，测试 bundle 为 `com.Vita0818.FlotisMacTests`。
- 版本：`MARKETING_VERSION=0.8.0`，`CURRENT_PROJECT_VERSION=1`。
- Swift language version：5.0；`project.yml` 的 `info.properties` 每次由 XcodeGen 写入 `Flotis/Info.plist`；development language 为英文。
- 用法描述：`NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription` 的英文基值来自 `project.yml`，简中翻译来自 `Flotis/InfoPlist.xcstrings`。
- 无第三方 package、entitlements、sandbox 或显式 code-signing 配置。

## App 源文件

`Flotis/` 当前 27 个 Swift 文件：

| 文件 | 主类型 / 职责 |
|---|---|
| `FlotisApp.swift` | `FlotisApp` / `AppDelegate`；装配 provider store、voice controller、capsule panel、可复用独立 `FlotisSettingsWindowController` 与两个固定 hotkey，退出时取消语音会话，并在 `.injecting` 剪贴板恢复窗口内统一拒绝终止 |
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
| `TranscriptionProviderStore.swift` | connection CRUD、v1/v2→v3 只读迁移、LKG/坏数据恢复、本地 secret 事务 |
| `LocalSecretStore.swift` | Flotis 自管的版本化 API key JSON；进程内锁、同目录原子替换、私有权限与文件类型/大小校验 |
| `ClipboardPasteInjector.swift` | 有界注入队列、目标 PID/AX/自身 key window/完整语音快捷键释放核验、剪贴板安全恢复 |
| `HotkeyManager.swift` | Carbon 全局热键独占增量注册、press/release 门控、错误状态与重试；V0.8 App 只注册 panel/voice 两项 |
| `PromptCommand.swift` | 旧命令与快捷键数据模型；V0.8 仍为兼容源码及固定热键描述提供类型 |
| `CommandStore.swift` | 旧命令 JSON CRUD 与安全策略；V0.8 主入口不实例化、不展示、不注册命令热键 |
| `FlotisDesign.swift` | 胶囊与 Settings 共用的 Presentation / Design System：动态系统色、canvas、Material/Liquid Glass fallback、字体与共享设置组件 |
| `FloatingPanelController.swift` | 固定启动屏幕底边锚点的 borderless/nonactivating floating `NSPanel`；圆角 material mask 同时约束窗口阴影，合并尺寸请求并只应用最后一次，不允许整窗背景拖动 |
| `FloatingPanelView.swift` | `120×56` 双按钮 idle、单行工作/错误态、原生可选择/复制的审阅编辑器与四档静态布局；设置按钮打开独立 Settings 窗口 |
| `VoiceSettingsView.swift` | 精简独立 Settings 窗口；可见表单只开放 OpenAI Compatible 的 Model、Endpoint、API Key 与必要动作，保存即设为当前 connection；多连接管理、其他 adapter 仅在后台兼容，旧概览/命令 view 暂留为不可达源码 |
| `UIStrings.swift` | `AppLanguage` 第一首选语言解析与集中简中/英文 UI 文案，包括 Settings 的标准退出动作 |
| `AccessibilityPermission.swift` | AX 信任检查与系统设置入口 |

实际文件数以 `rg --files Flotis -g '*.swift'` 为准，当前为 27。

`Flotis/Info.plist` 是 XcodeGen 生成的源 plist，包含版本变量、`LSUIElement`、`LSMultipleInstancesProhibited` 与权限说明基值；`Flotis/InfoPlist.xcstrings` 提供麦克风与 Speech Recognition 权限说明的英文/简中版本并进入 App resources build phase。

## Presentation / Design System 地图

- `FlotisTheme` 只使用随 Light/Dark appearance 动态解析的系统 `.primary`、`.secondary` 与 `separatorColor`；主要操作保持系统白/黑单色，红、橙、绿只用于录音、警告、成功和失败等有限语义状态。
- `FlotisSystemCanvas` 在 macOS 14+ 使用 SwiftUI `windowBackground`，macOS 13 使用 `.windowBackground` `NSVisualEffectView` fallback，保持系统窗口 canvas 且不引入固定品牌底色。
- 结构化内容统一使用 `regularMaterial`、1 pt 系统 separator 与 continuous rounded rectangle。macOS 26 且编译器支持时，交互表面和按钮可使用 Liquid Glass；macOS 13–15 回退为原生 `regularMaterial`、`.bordered` / `.borderedProminent`。
- `FlotisType` 根据显示文本选择标题字体：包含中文时使用系统默认字体，英文品牌与标题使用 Serif；正文使用系统默认字体，快捷键和技术信息使用 Monospaced。
- `FloatingPanelView` 与 `VoiceSettingsView` 共用上述 palette、字体和系统控件；视觉层不改变语音状态机、connection schema、本地 secret store 或注入安全边界。胶囊外壳由 AppKit visual-effect 的可拉伸 alpha mask 形成 20 pt continuous corner，并让窗口服务器阴影使用同一轮廓；CALayer mask 只裁 hosted subviews，SwiftUI 不再叠加整圈 separator。idle 为 `120×56`，普通工作态 `188×56`，错误/提示态 `280×56`，reviewing `420×160`，不再按状态文案追加高度。
- 胶囊齿轮直接调用 AppDelegate 持有的 `FlotisSettingsWindowController`；同一 `760×560` 窗口复用且不依赖字符串 selector，也不再附着到胶囊 sheet。`SettingsView` 同时可作为系统 Settings scene 的根视图；页头的“退出 Flotis / Quit Flotis”调用标准 `NSApplication.terminate`，由 `AppDelegate.applicationWillTerminate` 统一停止热键并取消语音资源。
- `SpeechSettingsPresentation` 是纯展示 allowlist，目前只匹配 `openai-audio-transcriptions-http-v1`。筛选结果只用于 SwiftUI 列表、概览和 editor 选择，绝不写回 `SpeechProviderStore`。

## 界面语言地图

- `AppLanguage.current` 只读取 `Locale.preferredLanguages.first`。明确的 `zh-Hans`、`zh-CN`、`zh-SG`、`zh-MY` 选择简中；`zh-Hant`、繁中地区、英文及其他语言选择英文。
- `UIStrings.localized(english:simplifiedChinese:)` 覆盖胶囊、Settings、热键、录音、连接测试和六条 adapter 的 App 自定义提示；服务端原始消息与系统 framework 错误不伪造翻译。
- 内建 connection 的旧默认中英文名称只在显示层按稳定 UUID/已知默认名映射；用户自定义名称、旧测试摘要和 connection snapshot 不做语言迁移。
- App UI 语言与 connection 的 `language`（语音识别/转写 locale）完全分离。

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

上表六个 adapter、已有 connection、active ID、preset、迁移和 runtime 均继续保留；Settings 当前只显示 `CCCCCCCC` 对应的 OpenAI Compatible HTTP connection，不代表其他路径已删除。

## 测试文件

| 文件 | 覆盖 |
|---|---|
| `HotkeyAndInjectionPolicyTests.swift` | V0.8 语音动作策略、Carbon 独占/press-release 门控、稳定胶囊尺寸、危险快捷键拒绝、完整组合键释放、注入队列容量与 operation 过期 |
| `TranscriptAssemblyTests.swift` | Apple 空 final/停顿/纠错/相邻片段、OpenAI 多 item 乱序/partial-final、Dash 重复句、ASCII/CJK 边界 |
| `SpeechProviderConfigurationTests.swift` | v3 canonical 编码、v1/v2 只读迁移、LKG/坏数据恢复、connection CRUD/事务回滚、preset 与凭据/test fingerprint 边界，以及本地 secret store 的权限、并发、损坏与符号链接防护 |
| `TranscriptionAdapterRuntimeTests.swift` | 六 adapter registry/runtime plan、HTTP multipart/严格响应、WAV/M4A、自定义连接、Key 回显脱敏、GLM SSE、Realtime GA scripted lifecycle |
| `LocalizationTests.swift` | 第一首选语言矩阵、繁中/其他语言英文回退、偏好顺序与双语选择 |

当前没有 UI-test target、SwiftUI snapshot test 或 preview fixture；`FlotisTests` 不渲染胶囊或 Settings，Presentation / Design System 需通过构建和 macOS 运行态目视矩阵验证。

## 持久化与临时数据

- 旧命令：`~/Library/Application Support/Flotis/commands.json`，V0.8 主入口不加载、不修改、不删除；兼容 store 仍保持 JSON 数组与 atomic write contract。
- Connection 主快照：UserDefaults `flotis.transcriptionConnections.v3`。
- Settings 的可见性过滤不裁剪快照；打开、编辑或关闭设置页不会删除隐藏 connection、改写隐藏 active ID 或清理其 `apiKeyReference`。
- v3 恢复/诊断：`flotis.transcriptionConnections.v3.lastKnownGood`、`flotis.transcriptionConnections.corruptBackup`、`flotis.transcriptionConnections.corruptBackupMetadata`。
- 旧输入：`flotis.speechProviders.v2`、其旧 LKG 与 `flotis.speechProviders.v1` 仅用于只读迁移；迁移不会覆盖旧 bytes。
- API key：`~/Library/Application Support/Flotis/secrets.json`；schema version `1`，字典键为 `apiKeyReference`，Flotis 目录权限 `0700`、文件与 `.secrets.lock` 权限 `0600`，同目录临时文件与 `renameat` 完成原子替换；跨进程锁竞争最多等待 500 ms。
- 旧系统钥匙串条目不属于新存储链路；Flotis 不读取、迁移或删除它们，升级用户需重新输入一次 API key。
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
