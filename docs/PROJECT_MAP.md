# PROJECT_MAP

最近自查日期：2026-08-07

本文描述当前仓库结构。事实来源为 `project.yml`、生成后的 `Flotis.xcodeproj/project.pbxproj`、`run.sh`、当前源码和测试。

## 目录结构总览

```text
Flotis/
├── Flotis.icon/        主 App 的 Icon Composer 源（icon.json + 图层资源）
├── Flotis/             31 个 app Swift 源文件 + Assets.xcassets + XcodeGen Info.plist + InfoPlist String Catalog
├── FlotisTests/        6 个 XCTest 源文件
├── FlotisInputMethod/  4 个 InputMethodKit Swift 源文件 + XcodeGen Info.plist + SVG/TIFF 输入源图标
├── FlotisInputMethodTests/ 1 个隔离 XCTest 源文件
├── Flotis.xcodeproj/   xcodegen 生成工程
├── docs/               项目常驻状态、架构、禁区、测试说明与 config.json 手工配置教程
├── codex-report/       时间戳审计/实施报告
├── project.yml         XcodeGen 规格（2 application + 2 unit-test targets）
└── run.sh              冷启动构建与运行辅助脚本
```

## Target / 工程配置

| Target | 类型 | 平台 | 入口 / 依赖 | 职责 |
|---|---|---|---|---|
| `Flotis` | application | macOS 13+ | `Flotis/FlotisApp.swift` | `LSUIElement=YES`、禁止多实例的 V0.12 悬浮语音输入胶囊 |
| `FlotisTests` | unit-test bundle | macOS 13+ | depends on `Flotis` | 快捷键/复制返回/旧注入策略、转写组装、provider 配置与迁移、多连接对比策略测试 |
| `FlotisInputMethod` | application / InputMethodKit bundle | macOS 13+ | `FlotisInputMethod/main.swift` | `LSBackgroundOnly=YES` 的独立输入源声明、客户端会话与直接文字提交接口；当前不含语音/provider 链路 |
| `FlotisInputMethodTests` | unit-test bundle | macOS 13+ | 直接编译 protocol/service 源码，不启动输入法 host | 协议版本、payload 上限、会话失效、弱 endpoint 与提交结果策略 |

- Bundle ID：App 为 `com.Vita0818.FlotisMac`，输入法为 `com.Vita0818.FlotisInputMethod`；对应测试 bundle 分别为 `com.Vita0818.FlotisMacTests` 与 `com.Vita0818.FlotisInputMethodTests`。
- 版本：主 App `MARKETING_VERSION=0.12`、`CURRENT_PROJECT_VERSION=3`；输入法接口 `MARKETING_VERSION=0.1.0`、`CURRENT_PROJECT_VERSION=3`。
- Swift language version：5.0；`project.yml` 的 `info.properties` 每次由 XcodeGen 写入 `Flotis/Info.plist` 与 `FlotisInputMethod/Info.plist`；development language 为英文。
- 用法描述：`NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription` 的英文基值来自 `project.yml`，简中翻译来自 `Flotis/InfoPlist.xcstrings`。
- 主 App 图标：根目录 `Flotis.icon` 以 `wrapper.icon` 加入 Resources，`ASSETCATALOG_COMPILER_APPICON_NAME=Flotis`；构建生成 `Flotis.icns`、`Assets.car` 与 `CFBundleIconFile/CFBundleIconName=Flotis`。
- 无第三方 package、entitlements、sandbox 或显式 code-signing 配置。

## App 源文件

`Flotis/` 当前 31 个 Swift 文件：

| 文件 | 主类型 / 职责 |
|---|---|
| `FlotisApp.swift` | `FlotisApp` / `AppDelegate`；装配 provider/comparison/hotkey store、voice controller、capsule panel 与可复用独立 `FlotisSettingsWindowController`；把快捷键配置变化实时转给 Carbon manager，启动时清理对比偏好中已不存在的 model selector；退出时取消语音会话；保留旧 `.injecting` 终止保护 |
| `AppState.swift` | 中央 `ObservableObject` UI/语音状态；持有录音开始时间、对比候选、当前选中 ID 与每个候选的独立审阅编辑文本；安装候选时自动打开首个成功项，并提供跳过失败项的循环导航 |
| `VoiceInputMode.swift` | `VoiceInputMode`、含 reviewing 的 `VoiceInputState` 与纯 `VoiceHotkeyAction` 映射 |
| `VoiceInputController.swift` | `@MainActor` session-generation 状态机；默认执行单个三类 runtime plan；对比模式会在开始时快照 2–4 个 recorded-file runtime，用一个 recorder 生成共享文件并并发转写。最终结果先审阅，第三次动作把当前正在查看且原样编辑的文本写入系统剪贴板；暴露前后候选导航，不捕获目标 app、不调用注入器 |
| `SpeechTranscribing.swift` | streaming/file runtime 协议；配置在 adapter 创建 runtime 时完成快照 |
| `TranscriptionAdapterRegistry.swift` | 六个版本化 adapter 的唯一 registry、runtime factory 与通用执行计划 |
| `TranscriptionComparison.swift` | canonical 顶层 `comparison.models` 选择 store、最多 4 个 `<provider-id>/<model-id>` selector、`TranscriptCandidate`、共享录音文件的并发 `FileTranscriptionComparisonRunner`、顺序恢复与单项失败隔离 |
| `TranscriptionConnectionTester.swift` | 使用内置非隐私音频执行本地能力、HTTP 或 Realtime 协议探测 |
| `AppleSpeechTranscriber.swift` | 强制设备端 Apple Speech + `AVAudioEngine`；按 segment 时间范围累积 partial/final，防止空 final 和停顿覆盖 |
| `OpenAIRealtimeTranscriber.swift` | OpenAI GA Realtime transcription、串行发送、turn 组装 |
| `DashScopeParaformerRealtimeTranscriber.swift` | DashScope Paraformer WebSocket 生命周期与结果组装 |
| `VolcengineBigASRRealtimeTranscriber.swift` | Volcengine BigASR WebSocket 二进制协议与终态等待 |
| `OpenAICompatibleTranscriber.swift` | `OpenAIHTTPTranscriber` 与 `GLMASRHTTPTranscriber`；OpenAI-compatible multipart、OpenRouter JSON+Base64、GLM multipart/SSE；HTTP 上传可取消 |
| `AudioRecorder.swift` | `.m4a` / `.wav` 临时录音与启动/结束校验 |
| `StreamingAudioCapture.swift` | 16/24 kHz、单声道 PCM16 捕获、深拷贝与串行转换 |
| `TranscriptionProviderConfig.swift` | 运行时 model route/connection 模型、adapter schema、multipart/JSON+Base64 request encoding、独立 preset catalog、legacy v1/v2/v3 snapshot decode bridge |
| `FlotisConfigurationStore.swift` | `config.json` schema v2 与 Intatis 式 `provider → shared options + models` 映射；只在 selector 第一个 `/` 分割；canonical v1 自动升级；进程/跨进程锁、目录 fd + `openat/O_NOFOLLOW`、私有权限、限大小校验与同目录原子替换 |
| `HotkeyConfiguration.swift` | panel 显隐、上一个/下一个对比结果三项可配置 descriptor、默认值、冲突/修饰键校验，以及 canonical `shortcuts` 分区的加载、read-modify-write 持久化与恢复默认；固定 voice descriptor 不由此 store 修改 |
| `TranscriptionProviderStore.swift` | canonical provider-group/model-route/key CRUD、共享 endpoint/凭据、稳定 route UUID 派生、统一文档事务与内存回滚、旧 v1/v2/v3/LKG/comparison/secret 一次性只读迁移；Apple 只作空 catalog 内部 fallback，不进入配置 |
| `LocalSecretStore.swift` | 仅为旧 `secrets.json` 一次性迁移读取保留的兼容 store；不再是生产运行时配置/凭据真源 |
| `ClipboardPasteInjector.swift` | 保留但当前产品路径不可达的旧兼容实现：有界注入队列、目标 PID/AX/自身 key window/完整语音快捷键释放核验、PID 定向 `⌘V`、类型化失败结果与剪贴板安全恢复 |
| `HotkeyManager.swift` | Carbon 全局热键独占增量注册、press/release 门控、错误状态与重试；panel 使用用户配置 descriptor、voice 固定 `⌃⌥A`，仅在多结果 reviewing 中临时注册用户配置的前后导航 descriptor 并在离开时注销；设置变化即时替换旧注册 |
| `PromptCommand.swift` | 旧命令与快捷键数据模型；V0.12 仍为兼容源码、固定 voice descriptor 与三项可配置快捷键的默认 descriptor 提供类型 |
| `CommandStore.swift` | 旧命令 JSON CRUD 与安全策略；V0.12 主入口不实例化、不展示、不注册命令热键 |
| `FlotisDesign.swift` | 胶囊与 Settings 共用的 Presentation / Design System：动态系统色、canvas、Material/Liquid Glass fallback、字体与共享设置组件 |
| `FloatingPanelController.swift` | 首次位于屏幕底边中央的 borderless/nonactivating floating `NSPanel`；允许整窗背景拖动，圆角 material mask 同时约束窗口阴影；合并尺寸请求，以独立逻辑位置锚点保持用户选择的中心/底边，状态 resize 的可见区临时钳位不覆盖锚点，用户拖动才更新 |
| `FloatingPanelView.swift` | `108×54` 双按钮 idle（开始录音使用用户提供的 28 pt 白圆六条黑声波图，设置使用 28 pt 白圆承载 16 pt 黑色八齿齿轮，下方快捷键为 12 pt Semibold 系统 Monospaced/动态主文字色）、保留原有状态图标/文案的录音 `mm:ss`、重复 action 抑制、`420×160` 单结果审阅和 `560×300` 对比审阅；对比页用固定双列网格展示 2–4 个成功/失败候选，四项为 2×2，首个成功项直接显示在原生编辑器；候选优先只显示 Model Display name，无名称时显示主 Model ID + 次 Provider，不显示 endpoint；保留复制全部、取消、复制并返回 |
| `VoiceSettingsView.swift` | 内容默认 `1100×760`、最小 `820×600` 的独立 Settings 窗口根视图；固定侧栏分为快捷键/转写，左上品牌区不显示图标；快捷键页以一张卡展示固定 voice 和三项可配置组合，移除流程/拖动说明，使用 `220×50`、17 pt 的大号组合键 surface 与原生录制控件，并支持逐项/全部恢复和错误显示；转写页装配 Intatis 式 provider/model editor，其他 adapter 及旧权限/概览/命令 view 仍不可达 |
| `IntatisStyleSpeechProviderSettingsView.swift` | Intatis 式 Provider/Models 主卡：左侧 Provider 列表与模型数，右侧 Provider name、共享 API key、Active model、Connection/Models 区、逐模型 Model ID/Display name 与 Add/Delete；Provider 行至少 48 pt，折叠标题与对比 route 整行至少 44 pt 可点；卡下提供 Test Provider/Save，并把 2–4 route Comparison 和高级转写参数保留为独立扩展区 |
| `UIStrings.swift` | `AppLanguage` 第一首选语言解析与集中简中/英文 UI 文案，包括 Settings 的标准退出动作 |
| `AccessibilityPermission.swift` | 保留但当前产品路径不可达的 AX 状态检查、提示式授权请求与系统设置入口；复制并返回流程不使用 |

实际文件数以 `rg --files Flotis -g '*.swift'` 为准，当前为 31。

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
- `FloatingPanelView` 与 `VoiceSettingsView` 共用上述 palette、字体和系统控件；视觉层不改变语音状态机、canonical config 或保留的旧注入安全边界。macOS 26+ 的胶囊外壳使用原生 `NSGlassEffectView(style: .regular)` 与 20 pt continuous corner，保持系统默认自适应 tint，hosting content 不再铺全表面深色背景；macOS 27+ 开启 interactive glass。macOS 13–25 回退到 AppKit visual-effect 的可拉伸 alpha mask 与原生阴影。idle 为 `108×54`，开始录音和设置按钮分别使用用户提供的 28 pt 白圆黑声波图与 28 pt 白圆/16 pt 黑色八齿齿轮图，下方快捷键为 12 pt Semibold 系统 Monospaced/动态主文字色；录音态保留原有状态图标与文案，以计时替代 stop 方块；stopping/transcribing 保留原有省略号状态图标与文案，只抑制右侧重复 action；普通工作态 `188×56`，错误/提示态 `280×56`，单结果 reviewing `420×160`，对比 reviewing `560×300`。
- 胶囊齿轮直接调用 AppDelegate 持有的 `FlotisSettingsWindowController`；同一窗口以 `1100×760` 内容尺寸打开、最小内容尺寸 `820×600`，复用且不依赖字符串 selector，也不再附着到胶囊 sheet。HostingController 装配后显式设置 `contentMinSize` 与 `setContentSize`，防止实际窗口被 SwiftUI 最小尺寸收窄而破坏 Intatis 式双栏。固定左侧栏承载无图标的 `Flotis`/版本、“快捷键 / 转写”和退出，右侧页面独立滚动；`SettingsView` 同时可作为系统 Settings scene 的根视图。“退出 Flotis / Quit Flotis”调用标准 `NSApplication.terminate`，由 `AppDelegate.applicationWillTerminate` 统一停止热键并取消语音资源。
- `SpeechSettingsPresentation` 是纯 adapter 展示 allowlist，目前只匹配 `openai-audio-transcriptions-http-v1`。筛选结果用于 Intatis 式 Provider 列表、详情 editor 与 model-route 对比选择，绝不写回或裁剪 `SpeechProviderStore`；一个 provider 共享 endpoint/key 并可拥有多个带可选显示名称的模型，不同 provider 仍各自隔离。Flotis 特有 comparison/advanced 区位于主 Provider/Models 卡下方，不改变 canonical 配置边界。

## 界面语言地图

- `AppLanguage.current` 只读取 `Locale.preferredLanguages.first`。明确的 `zh-Hans`、`zh-CN`、`zh-SG`、`zh-MY` 选择简中；`zh-Hant`、繁中地区、英文及其他语言选择英文。
- `UIStrings.localized(english:simplifiedChinese:)` 覆盖胶囊、Settings、热键、录音、连接测试和六条 adapter 的 App 自定义提示；服务端原始消息与系统 framework 错误不伪造翻译。
- 内建 legacy connection 的旧默认中英文名称只在显示层按稳定 UUID/已知默认名映射；用户自定义名称、旧测试摘要和迁移 snapshot 不做语言迁移。
- App UI 语言与 provider 的 `language`（语音识别/转写 locale）完全分离。

## Provider / 传输协议地图

| 固定 ID 前缀 | `TranscriptionAdapterID` | 通用 runtime plan | 音频/模型要点 |
|---|---|---|---|
| `AAAAAAAA` | `apple-on-device` | owned capture | 设备端、locale 可配 |
| `BBBBBBBB` | `openai-realtime-transcription-ga` | PCM stream | 模型可配、PCM16 24 kHz mono、manual commit |
| `CCCCCCCC` | `openai-audio-transcriptions-http-v1` | recorded file | 默认 `gpt-4o-mini-transcribe`、WAV PCM16 16 kHz mono；兼容迁移的 M4A |
| `DDDDDDDD` | `dashscope-paraformer-ws-v1` | PCM stream | `paraformer-realtime-v2`、PCM 16 kHz mono |
| `EEEEEEEE` | `volcengine-bigasr-ws-v3` | PCM stream | `model_name=bigmodel`、独立 `resourceID`、PCM 16 kHz mono |
| `FFFFFFFF` | `glm-asr-http-sse-v4` | recorded file | `glm-asr-2512`、WAV、30 秒 / 25 MiB、严格 SSE 终态 |

运行时以 `TranscriptionAdapterID` 查 registry；controller 只按通用 runtime plan 分派。表中固定 UUID 只属于 legacy/preset 兼容层；schema v2 用语义化 provider ID，并为每个 `<provider-id>/<model-id>` selector 确定性派生内部 route UUID。`SpeechProviderWireProtocol` / `kind` 仅是未编码的 legacy 兼容计算层，preset 不参与 runtime 判断。

上表六个 adapter、preset、迁移和 runtime 均继续保留；Settings 当前只显示 OpenAI Compatible HTTP provider，不代表其他 runtime 已删除。`apple-on-device` 不能出现在 schema v2 provider catalog 中，只在 catalog 为空时作为内部 on-device fallback。

## 测试文件

| 文件 | 覆盖 |
|---|---|
| `HotkeyAndInjectionPolicyTests.swift` | 23 tests：V0.12 start/stop/copy-and-return 动作策略、固定 `⌃⌥A`、三项可配置快捷键默认值/冲突校验/canonical 持久化、录音计时生命周期、`560×300` 对比布局、复制成功重置/复用小胶囊、复制失败保留审阅、Carbon 独占/press-release 门控、胶囊 resize/钳位后缩回位置恢复，以及保留旧注入器的安全策略回归 |
| `TranscriptAssemblyTests.swift` | Apple 空 final/停顿/纠错/相邻片段、OpenAI 多 item 乱序/partial-final、Dash 重复句、ASCII/CJK 边界 |
| `SpeechProviderConfigurationTests.swift` | canonical v2 shape、空 catalog 不写 Apple、旧数据迁移、同 provider 多模型/共享 key、provider/key 同文件 CRUD 与回滚、权限/损坏防护、preset 与凭据/test fingerprint 边界；旧 secret reader 安全性仍作兼容回归 |
| `TranscriptionAdapterRuntimeTests.swift` | 六 adapter registry/runtime plan、HTTP multipart 与 OpenRouter JSON+Base64、严格响应、WAV/M4A、自定义 endpoint、Key 回显脱敏、GLM SSE、Realtime GA scripted lifecycle |
| `LocalizationTests.swift` | 第一首选语言矩阵、繁中/其他语言英文回退、偏好顺序与双语选择 |
| `TranscriptionComparisonTests.swift` | 5 tests：同一 provider 多 model selector 的 2–4 项偏好/持久化/坏数据保留、同一文件 fan-out、单 route 失败隔离、按顺序自动打开首个成功项、跳过失败项的前后循环导航、切换时分别保留编辑内容与当前项复制 |
| `FlotisInputMethodTests/FlotisInputMethodServiceTests.swift` | 8 个隔离测试：精确文本交付、协议/空白/大小拒绝、旧 session 失效、deactivate、endpoint 释放与客户端失败 |

当前没有 UI-test target、SwiftUI snapshot test 或 preview fixture；两个 unit-test target 都不替代胶囊、Settings 或真实输入法客户端的 macOS 运行态验证。

## 持久化与临时数据

- 旧命令：`~/Library/Application Support/Flotis/commands.json`，V0.12 主入口不加载、不修改、不删除；兼容 store 仍保持 JSON 数组与 atomic write contract。
- Provider、active model、显示顺序、对比选择、三项可配置全局快捷键与 API key 的唯一真源：`~/Library/Application Support/Flotis/config.json`。schema version `2`，顶层为 `$schema`、`schema_version`、`model`、`provider_order`、`enabled_providers`、`comparison.models`、可选 `shortcuts`、`provider`；`provider.<id>.options` 只保存一次共享 endpoint/key，`provider.<id>.models` 可列出多个模型，每个 model entry 可选保存 `name` 作为 Display name。`shortcuts` 不包含固定 voice descriptor。
- selector 格式为 `<provider-id>/<model-id>`，只在第一个 `/` 分割；因此 OpenRouter 的 `openai/...` model ID 可原样保存。`config.json` 不持久化 Apple provider。
- 手工编写、字段约束、完整 OpenRouter 同 Provider 双模型对比模板、权限和损坏恢复流程见 [`docs/CONFIGURATION_GUIDE.md`](CONFIGURATION_GUIDE.md)。
- Settings 的可见性过滤不裁剪 canonical document；打开、编辑或关闭设置页不会删除隐藏 provider、改写隐藏 active selector 或清理其 key/reference。
- Flotis 目录权限为 `0700`，`config.json` 与 `.config.lock` 为 `0600`；同一进程锁与最多等待 500 ms 的跨进程锁覆盖完整 read-modify-write，同目录私有临时文件、`fsync`、`renameat` 与目录同步完成原子替换。
- canonical schema v1 会在安全校验后原子升级为 v2 并移除 Apple 条目；旧 `flotis.transcriptionConnections.v3`/LKG、v2/LKG、v1、`flotis.transcriptionComparison.v1` 和 `secrets.json` 只在 canonical 文件不存在时作为一次性只读迁移输入；不覆写或删除旧 bytes，迁移后不再参与运行时读写。
- 旧系统钥匙串条目不属于新存储链路；Flotis 不读取、迁移或删除它们，升级用户需重新输入一次 API key。
- 临时录音/连接测试音频：系统 temp 下 `Flotis-Audio-*.m4a` 或 `Flotis-Audio-*.wav`；一次对比会话只创建一个录音文件并把同一 URL 传给全部 selected file transcriber，完成、失败或取消后清理。
- 临时 multipart：系统 temp 下 `Flotis-Multipart-*`；仅清理本应用前缀、普通文件且超过 24 小时的项。

## 脚本与生成物

| 文件 / 命令 | 用途 |
|---|---|
| `project.yml` / `xcodegen generate` | 生成主 app、输入法接口与两个 tests target/schemes |
| `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` | 无签名本地构建验证 |
| `xcodebuild ... CODE_SIGNING_ALLOWED=NO test` | 运行 unit tests |
| `run.sh` | kill 旧实例、复用固定临时 DerivedData、生成、构建并打开 app；不再删除缓存或重置 AX TCC，ad-hoc 产物会提示配置稳定 Apple Development 签名 |

构建产物通常位于 DerivedData 的 `Build/Products/Debug/Flotis.app` 与 `FlotisInputMethod.app`；输入法安装路径 build setting 为 `$(HOME)/Library/Input Methods`，普通 `build` 不会执行安装。

主 App 当前单文件配置、Intatis 式 Provider/Models、多模型对比、可配置快捷键与精简快捷键页版本已于 2026-08-07 以 ad-hoc Release `0.12 (3)` 安装并启动于 `/Applications/Flotis.app`。最新 Release 位于 `/private/tmp/FlotisShortcutUI-ReleaseInstall-20260807/Build/Products/Release/Flotis.app`；严格签名、主 App 79 tests、输入法 8 tests、两个 application build，以及 build/安装可执行文件、`Flotis.icns`、`Assets.car` 逐字节核对均通过。被替换的可配置快捷键旧界面版本保存在 `/private/tmp/Flotis-before-shortcut-ui-install-20260807-2211.app`，更早的 `0.8.0 (2)` 仍保存在 `/private/tmp/Flotis-before-v0.12-install-20260806-1453.app`。安装过程未读取或改写 Provider/API key，也未触碰输入法目录。

## 需要后续确认

- `VoiceInputMode` / `AppState.voiceMode` 是否应移除或接入产品 UI：`UNKNOWN`。
- UI 状态是否应跨重启持久化：`UNKNOWN`。
- 正式签名、notarization、hardened runtime 与分发方式：尚未配置。
- 输入法 target 的固定 Apple Development 身份仍未配置；ad-hoc build `3` 已实际安装并可稳定启动，但输入源发现需要重新登录，跨 app 文本客户端矩阵与主 App 本地 IPC仍需后续确认。
