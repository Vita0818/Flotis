# PROJECT_MAP

最近自查日期：2026-08-04

本文描述当前仓库结构。事实来源为 `project.yml`、生成后的 `Flotis.xcodeproj/project.pbxproj`、`run.sh`、当前源码和测试。

## 目录结构总览

```text
Flotis/
├── Flotis.icon/        主 App 的 Icon Composer 源（icon.json + 图层资源）
├── Flotis/             27 个 app Swift 源文件 + Assets.xcassets + XcodeGen Info.plist + InfoPlist String Catalog
├── FlotisTests/        5 个 XCTest 源文件
├── FlotisInputMethod/  4 个 InputMethodKit Swift 源文件 + XcodeGen Info.plist + SVG/TIFF 输入源图标
├── FlotisInputMethodTests/ 1 个隔离 XCTest 源文件
├── Flotis.xcodeproj/   xcodegen 生成工程
├── docs/               项目常驻状态、架构、禁区和测试说明
├── codex-report/       时间戳审计/实施报告
├── project.yml         XcodeGen 规格（2 application + 2 unit-test targets）
└── run.sh              冷启动构建与运行辅助脚本
```

## Target / 工程配置

| Target | 类型 | 平台 | 入口 / 依赖 | 职责 |
|---|---|---|---|---|
| `Flotis` | application | macOS 13+ | `Flotis/FlotisApp.swift` | `LSUIElement=YES`、禁止多实例的 V0.8 悬浮语音输入胶囊 |
| `FlotisTests` | unit-test bundle | macOS 13+ | depends on `Flotis` | 快捷键/复制返回/旧注入策略、转写组装、provider 配置与迁移测试 |
| `FlotisInputMethod` | application / InputMethodKit bundle | macOS 13+ | `FlotisInputMethod/main.swift` | `LSBackgroundOnly=YES` 的独立输入源声明、客户端会话与直接文字提交接口；当前不含语音/provider 链路 |
| `FlotisInputMethodTests` | unit-test bundle | macOS 13+ | 直接编译 protocol/service 源码，不启动输入法 host | 协议版本、payload 上限、会话失效、弱 endpoint 与提交结果策略 |

- Bundle ID：App 为 `com.Vita0818.FlotisMac`，输入法为 `com.Vita0818.FlotisInputMethod`；对应测试 bundle 分别为 `com.Vita0818.FlotisMacTests` 与 `com.Vita0818.FlotisInputMethodTests`。
- 版本：主 App `MARKETING_VERSION=0.8.0`、`CURRENT_PROJECT_VERSION=1`；输入法接口 `MARKETING_VERSION=0.1.0`、`CURRENT_PROJECT_VERSION=3`。
- Swift language version：5.0；`project.yml` 的 `info.properties` 每次由 XcodeGen 写入 `Flotis/Info.plist` 与 `FlotisInputMethod/Info.plist`；development language 为英文。
- 用法描述：`NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription` 的英文基值来自 `project.yml`，简中翻译来自 `Flotis/InfoPlist.xcstrings`。
- 主 App 图标：根目录 `Flotis.icon` 以 `wrapper.icon` 加入 Resources，`ASSETCATALOG_COMPILER_APPICON_NAME=Flotis`；构建生成 `Flotis.icns`、`Assets.car` 与 `CFBundleIconFile/CFBundleIconName=Flotis`。
- 无第三方 package、entitlements、sandbox 或显式 code-signing 配置。

## App 源文件

`Flotis/` 当前 27 个 Swift 文件：

| 文件 | 主类型 / 职责 |
|---|---|
| `FlotisApp.swift` | `FlotisApp` / `AppDelegate`；装配 provider store、voice controller、capsule panel、可复用独立 `FlotisSettingsWindowController` 与两个固定 hotkey；voice hotkey 在 panel 隐藏时恢复可见性，第三次复制成功后由 idle 状态缩回小胶囊而不关闭；退出时取消语音会话；保留旧 `.injecting` 终止保护 |
| `AppState.swift` | 中央 `ObservableObject` UI/语音状态 |
| `VoiceInputMode.swift` | `VoiceInputMode`、含 reviewing 的 `VoiceInputState` 与纯 `VoiceHotkeyAction` 映射 |
| `VoiceInputController.swift` | `@MainActor` session-generation 状态机；执行三类 runtime plan，最终转写先审阅，第三次动作把原样编辑文本写入系统剪贴板，成功后重置会话并回 idle，失败保留文字供重试；不返回窗口关闭结果、不捕获目标 app、不调用注入器 |
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
| `ClipboardPasteInjector.swift` | 保留但当前产品路径不可达的旧兼容实现：有界注入队列、目标 PID/AX/自身 key window/完整语音快捷键释放核验、PID 定向 `⌘V`、类型化失败结果与剪贴板安全恢复 |
| `HotkeyManager.swift` | Carbon 全局热键独占增量注册、press/release 门控、错误状态与重试；V0.8 App 只注册 `⌘⌥⇧0` panel 与 `⌃⌥A` voice 两项 |
| `PromptCommand.swift` | 旧命令与快捷键数据模型；V0.8 仍为兼容源码及固定热键描述提供类型，voice descriptor 为 Carbon key `0`/A 与 Control+Option |
| `CommandStore.swift` | 旧命令 JSON CRUD 与安全策略；V0.8 主入口不实例化、不展示、不注册命令热键 |
| `FlotisDesign.swift` | 胶囊与 Settings 共用的 Presentation / Design System：动态系统色、canvas、Material/Liquid Glass fallback、字体与共享设置组件 |
| `FloatingPanelController.swift` | 首次位于屏幕底边中央的 borderless/nonactivating floating `NSPanel`；允许整窗背景拖动，圆角 material mask 同时约束窗口阴影；合并尺寸请求，以独立逻辑位置锚点保持用户选择的中心/底边，状态 resize 的可见区临时钳位不覆盖锚点，用户拖动才更新 |
| `FloatingPanelView.swift` | `108×54` 双按钮 idle（开始录音使用用户提供的 28 pt 白圆六条黑声波图，设置使用 28 pt 白圆承载 16 pt 黑色八齿齿轮，下方快捷键为 12 pt Semibold 系统 Monospaced/动态主文字色，其余语音状态图标沿用 SF Symbols）、单行工作/错误态、原生可选择/复制的审阅编辑器与四档静态布局；审阅页提供复制全部、取消、复制并返回，设置按钮打开独立 Settings 窗口 |
| `VoiceSettingsView.swift` | 可缩放 `820×600`（最小 `760×540`）独立 Settings 窗口；固定侧栏分为通用/转写，当前可达通用页只说明三段式复制快捷键与拖动，不再展示 AX 权限；可见表单只开放 OpenAI Compatible 的 Model、Endpoint、API Key 与必要动作，保存即设为当前 connection；多连接管理、其他 adapter 及旧权限/概览/命令 view 仅留作不可达兼容源码 |
| `UIStrings.swift` | `AppLanguage` 第一首选语言解析与集中简中/英文 UI 文案，包括 Settings 的标准退出动作 |
| `AccessibilityPermission.swift` | 保留但当前产品路径不可达的 AX 状态检查、提示式授权请求与系统设置入口；复制并返回流程不使用 |

实际文件数以 `rg --files Flotis -g '*.swift'` 为准，当前为 27。

`Flotis/Info.plist` 是 XcodeGen 生成的源 plist，包含版本变量、`LSUIElement`、`LSMultipleInstancesProhibited` 与权限说明基值；`Flotis/InfoPlist.xcstrings` 提供麦克风与 Speech Recognition 权限说明的英文/简中版本并进入 App resources build phase。

`Flotis/Assets.xcassets/VoiceWaveformButton.imageset` 保存 28/56/84 px 的 idle 开始录音 PNG，`SettingsGearButton.imageset` 保存 16/32/48 px 的透明黑色齿轮 PNG；SwiftUI 为后者提供 28 pt 白圆底。用户提供的未缩放参考原图分别保存在 `docs/assets/voice-waveform-button-reference.png` 与 `docs/assets/settings-gear-button-reference.png`，便于后续核对或重新生成派生尺寸。

根目录 `Flotis.icon` 是独立于胶囊按钮图稿的应用级 Icon Composer 文档；当前包含 `icon.json` 和 `Assets/message.badge.waveform.png`。它只进入主 `Flotis` target，不进入隔离输入法 target。Release 构建会把它编译成系统多尺寸 `Flotis.icns`，当前安装副本位于 `/Applications/Flotis.app`。

## Input Method 源文件

| 文件 | 主类型 / 职责 |
|---|---|
| `FlotisInputMethod/main.swift` | 输入法进程入口；从 Info.plist 读取 connection name 与 bundle ID，使用 `IMKServer(name:bundleIdentifier:)` 只创建一个按 plist 解析 controller/delegate 的 server，并运行 AppKit event loop |
| `FlotisInputMethod/FlotisInputController.swift` | `IMKInputController`；激活/关闭时登记或失效 session，普通键盘输入透传，通过当前 `NSTextInputClient` 在插入点提交显式文本；菜单提供人工接口测试入口 |
| `FlotisInputMethod/FlotisInputMethodProtocol.swift` | version `1` commit request/result/failure 与最大 1 MiB、非空、当前 session 校验 |
| `FlotisInputMethod/FlotisInputMethodService.swift` | MainActor 进程内服务；仅弱持有当前 controller endpoint，不记录、不持久化提交文本 |

`FlotisInputMethod/Info.plist` 由 XcodeGen 生成，包含 `LSBackgroundOnly`、`InputMethodConnectionName`、`InputMethodServerControllerClass`、顶层/模式级 `TISInputSourceID`、`ComponentInputModeDict` 与 TIFF 输入源图标键。build `3` 已用 ad-hoc 身份签名并复制到用户 Input Methods 目录，稳定后台启动冒烟通过；当前登录会话尚未把它加入 TIS 输入源缓存，真实 client 提交需重新登录后验证。它仍未与主 App 建立 IPC。

## Presentation / Design System 地图

- `FlotisTheme` 只使用随 Light/Dark appearance 动态解析的系统 `.primary`、`.secondary` 与 `separatorColor`；主要操作保持系统白/黑单色，红、橙、绿只用于录音、警告、成功和失败等有限语义状态。
- `FlotisSystemCanvas` 在 macOS 14+ 使用 SwiftUI `windowBackground`，macOS 13 使用 `.windowBackground` `NSVisualEffectView` fallback，保持系统窗口 canvas 且不引入固定品牌底色。
- 结构化内容统一使用 `regularMaterial`、1 pt 系统 separator 与 continuous rounded rectangle。macOS 26 且编译器支持时，交互表面和按钮可使用 Liquid Glass；macOS 13–15 回退为原生 `regularMaterial`、`.bordered` / `.borderedProminent`。
- `FlotisType` 根据显示文本选择标题字体：包含中文时使用系统默认字体，英文品牌与标题使用 Serif；正文使用系统默认字体，快捷键和技术信息使用 Monospaced。
- `FloatingPanelView` 与 `VoiceSettingsView` 共用上述 palette、字体和系统控件；视觉层不改变语音状态机、connection schema、本地 secret store 或保留的旧注入安全边界。macOS 26+ 的胶囊外壳使用原生 `NSGlassEffectView(style: .regular)` 与 20 pt continuous corner，保持系统默认自适应 tint，hosting content 不再铺全表面深色背景；macOS 27+ 开启 interactive glass。macOS 13–25 回退到 AppKit visual-effect 的可拉伸 alpha mask 与原生阴影。idle 为 `108×54`，开始录音和设置按钮分别使用用户提供的 28 pt 白圆黑声波图与 28 pt 白圆/16 pt 黑色八齿齿轮图，下方快捷键为 12 pt Semibold 系统 Monospaced/动态主文字色；普通工作态 `188×56`，错误/提示态 `280×56`，reviewing `420×160`，不再按状态文案追加高度。
- 胶囊齿轮直接调用 AppDelegate 持有的 `FlotisSettingsWindowController`；同一可缩放 `820×600`（最小 `760×540`）窗口复用且不依赖字符串 selector，也不再附着到胶囊 sheet。固定左侧栏承载产品标识、“通用 / 转写”和退出，右侧页面独立滚动；`SettingsView` 同时可作为系统 Settings scene 的根视图。“退出 Flotis / Quit Flotis”调用标准 `NSApplication.terminate`，由 `AppDelegate.applicationWillTerminate` 统一停止热键并取消语音资源。
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
| `HotkeyAndInjectionPolicyTests.swift` | 19 tests：V0.8 start/stop/copy-and-return 动作策略、固定 `⌃⌥A` 描述符、复制成功重置/复用小胶囊、复制失败保留审阅、Carbon 独占/press-release 门控、胶囊 resize/钳位后缩回位置恢复，以及保留旧注入器的安全策略回归 |
| `TranscriptAssemblyTests.swift` | Apple 空 final/停顿/纠错/相邻片段、OpenAI 多 item 乱序/partial-final、Dash 重复句、ASCII/CJK 边界 |
| `SpeechProviderConfigurationTests.swift` | v3 canonical 编码、v1/v2 只读迁移、LKG/坏数据恢复、connection CRUD/事务回滚、preset 与凭据/test fingerprint 边界，以及本地 secret store 的权限、并发、损坏与符号链接防护 |
| `TranscriptionAdapterRuntimeTests.swift` | 六 adapter registry/runtime plan、HTTP multipart/严格响应、WAV/M4A、自定义连接、Key 回显脱敏、GLM SSE、Realtime GA scripted lifecycle |
| `LocalizationTests.swift` | 第一首选语言矩阵、繁中/其他语言英文回退、偏好顺序与双语选择 |
| `FlotisInputMethodTests/FlotisInputMethodServiceTests.swift` | 8 个隔离测试：精确文本交付、协议/空白/大小拒绝、旧 session 失效、deactivate、endpoint 释放与客户端失败 |

当前没有 UI-test target、SwiftUI snapshot test 或 preview fixture；两个 unit-test target 都不替代胶囊、Settings 或真实输入法客户端的 macOS 运行态验证。

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
| `project.yml` / `xcodegen generate` | 生成主 app、输入法接口与两个 tests target/schemes |
| `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` | 无签名本地构建验证 |
| `xcodebuild ... CODE_SIGNING_ALLOWED=NO test` | 运行 unit tests |
| `run.sh` | kill 旧实例、复用固定临时 DerivedData、生成、构建并打开 app；不再删除缓存或重置 AX TCC，ad-hoc 产物会提示配置稳定 Apple Development 签名 |

构建产物通常位于 DerivedData 的 `Build/Products/Debug/Flotis.app` 与 `FlotisInputMethod.app`；输入法安装路径 build setting 为 `$(HOME)/Library/Input Methods`，普通 `build` 不会执行安装。

主 App 当前另有一份已验证的 ad-hoc Release 安装副本 `/Applications/Flotis.app`；它不是输入法安装目录，也不意味着 `FlotisInputMethod.app` 已被重新安装或接线。

## 需要后续确认

- `VoiceInputMode` / `AppState.voiceMode` 是否应移除或接入产品 UI：`UNKNOWN`。
- UI 状态是否应跨重启持久化：`UNKNOWN`。
- 正式签名、notarization、hardened runtime 与分发方式：尚未配置。
- 输入法 target 的固定 Apple Development 身份仍未配置；ad-hoc build `3` 已实际安装并可稳定启动，但输入源发现需要重新登录，跨 app 文本客户端矩阵与主 App 本地 IPC仍需后续确认。
