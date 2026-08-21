# ARCHITECTURE

## 外部依赖优先与禁止功能兜底（Vitemis 强制规则）

本项目继承 `/Users/vita/Vitemis/docs/DEPENDENCY_POLICY.md`。本节是强制约束，不是建议。

- 当用户指定、仓库已经采用，或经许可证、provenance、安全与平台审查可采用的外部依赖提供同等能力时，必须直接集成该依赖的官方 API 或官方扩展点。
- 不得自行重写同等能力，不得新增替代 adapter、shim、compatibility layer、wrapper、proxy、facade、协议翻译层、parallel backend、preview backend、shadow implementation 或“先兜底、以后再换”的实现。
- 本地代码只允许保留官方 API 必需的最薄生命周期、类型、权限、配置和 bundle 接线；不得重新实现、解释、扩展或替代依赖的核心能力。
- exact 依赖因版本、构建、签名、许可证、平台、安全或官方 API 限制无法接入时，必须停止该能力、明确失败、报告 blocker 并请求用户决定；不得静默降级、切换 legacy/另一 provider/backend、使用 cache/mock/简化路径或继续交付不完整替代实现。
- 现有 fallback、adapter 或重复实现不构成先例，后续不得扩展。安全 fail-closed 与明确要求的旧数据解码/迁移不是功能兜底，但必须保持最窄范围，不能演化成备用产品实现。
- 只有用户针对 exact 依赖、exact 范围和退出条件作出的新明文决定才能例外。

最近自查日期：2026-08-20

## 总体架构

Flotis V0.13 是一个 `LSUIElement` macOS app。用户通过 Carbon 全局热键控制非激活悬浮语音胶囊；默认由当前 model route 单独转写，也可选择 2–4 个 recorded-file model route 开启第一版多模型对比，包括同一 Provider 下的多个模型。最终转写先进入可编辑审阅态；对比模式按配置顺序自动打开第一个成功候选，允许点击或用仅在该状态临时注册的可配置前后导航快捷键（默认 `⌥←` / `⌥→`）在成功项间循环查看，但不会做质量评分或自动判断“最佳”。第三次使用当前配置的 voice hotkey 或审阅确认按钮把当前项的原样编辑文本复制到系统剪贴板，复制成功后重置会话、回到 `idle`，并让审阅框缩回原位置的小胶囊而不隐藏 panel。当前产品链路不捕获目标 app、不请求 Accessibility，也不发送 `CGEvent`/`⌘V`。

```text
HotkeyManager / FloatingPanelView
            │
            ▼
VoiceInputController
            │
            ├── single model-route runtime plan
            │    ├── ownedCapture
            │    ├── pcmStream
            │    └── recordedFile
            │
            └── comparison: one recorded file
                 └── 2–4 recorded-file runtimes concurrently
                          │
           TranscriptionAdapterRegistry
                          │
          one result / ordered candidates
                          ▼
             selected editable review
                          │ confirm
                          ▼
             SystemTranscriptClipboardWriter
                          │ success
                          ▼
          clear session + visible idle capsule
```

`AppDelegate` 装配 `AppState`、`SpeechProviderStore`、`TranscriptionComparisonStore`、`VoiceInputController`、`FloatingPanelController`、可复用的 `FlotisSettingsWindowController` 与 `HotkeyManager`。启动时 comparison store 会用完整 model selector 集合移除已不存在的选择；voice action 直接改变语音状态。reviewing 复制成功后 controller 回到 `idle`，现有 panel 尺寸监听把审阅框缩回小胶囊，窗口层不再接收 close outcome。panel 在用户鼠标事件之外保持 `isMovable=false`，让 AppKit/Window Server 在 Space 或显示环境过渡时维持相对屏幕位置；非审阅胶囊由 `FlotisFloatingPanel.sendEvent` 在单次 mouse-down 时直接调用 AppKit `performDrag(with:)`，避免全尺寸 SwiftUI surface 吞掉显式拖动；双击直接调用持有的设置窗口。reviewing 的 mouse-down 只在调用 `super.sendEvent` 时临时允许原生 background drag，使文本、按钮与非交互背景继续由 AppKit/SwiftUI 命中规则区分。独立逻辑锚点仍只由真实用户移动更新，程序 resize 的可见区钳位不回写。设置窗口不依赖字符串 selector，也不挂接会推动父 panel 的 sheet；HostingController 装配后设置 `contentMinSize=820×600`，再显式执行 `setContentSize(1100×760)`，确保 Intatis 式 Provider/Models 双栏不会被 SwiftUI 最小尺寸收窄。Settings 左侧栏的一键退出使用 `NSApplication.shared.terminate(nil)`，因此应用退出仍统一进入 `applicationWillTerminate`，先停止热键并取消当前语音会话。旧 `.injecting` 终止保护、`ClipboardPasteInjector`、`AccessibilityPermission`、`CommandStore`/`PromptCommand` 源码仍保留作兼容，但当前产品入口不会调用旧注入链路或命令链路。

## 隔离的 InputMethodKit 接口

`FlotisInputMethod` 是 `LSBackgroundOnly=YES` 的独立 application bundle，不依赖 `Flotis` target，也没有装配麦克风、provider、凭据、剪贴板、Accessibility 或 Carbon 热键。`main.swift` 从输入法 Info.plist 读取 connection name 与 bundle ID，通过 `IMKServer(name:bundleIdentifier:)` 为进程生命周期只创建一个 server；InputMethodKit 再按 plist 声明为文本客户端建立 `FlotisInputController`。不能退回 legacy controller/delegate initializer 的 nil delegate 路径，该路径已在运行态触发 `_IMKServerLegacy` 崩溃。

```text
future authenticated local transport (尚未实现)
                       │ versioned commit request
                       ▼
          FlotisInputMethodService @MainActor
                       │ current session only
                       ▼
             FlotisInputController
                       │ insertText at current insertion point
                       ▼
              active IMK text client
```

- controller 每次激活都会创建随机 session UUID；新客户端激活、deactivate 或 controller close 都会使旧 session 失效，避免延迟 transcript 落入新的焦点目标。
- request protocol 当前为 version `1`，保留原始文本，但拒绝不支持的版本、纯空白文本、超过 1 MiB 的 UTF-8 payload 和非当前 session。service 只弱持有 endpoint，不记录或持久化文字。
- 显式提交使用当前 `NSTextInputClient.insertText` 和 `NSNotFound` replacement range，表示在客户端当前插入位置 commit；controller 的普通 `inputText` 始终返回 `false`，所以该接口不消费日常键盘输入。
- 输入法菜单目前只有人工“插入接口测试文本”动作，用于未来安装后的最小客户端验证。成功结果只表示存在当前 IMK client 且已调用其提交 API，不能声称所有第三方控件都已目视消费文字。
- build `3` 已以 ad-hoc 身份安装到 `~/Library/Input Methods`，严格签名校验与后台进程启动冒烟通过；`TISRegisterInputSource` 返回成功，但当前登录会话仍未枚举到该 bundle/source，需要重新登录后才能继续激活与真实 client commit 验证。它没有把 `VoiceInputController` 接入；现有 Flotis 最终文本只写入系统剪贴板并返回小胶囊，既不走输入法接口，也不走保留的旧 `ClipboardPasteInjector`。

## Presentation / Design System

`FlotisDesign.swift` 是胶囊与 Settings 共用的 Presentation / Design System 层。`FloatingPanelView` 和 `VoiceSettingsView` 只从该层取得 palette、字体、内容表面、glass button 与设置页组合组件；视觉层不持有语音或 provider 状态，也不改变 `VoiceInputController`、connection schema、`LocalSecretStore` 或 `ClipboardPasteInjector` 的边界。

### JetBrains Mono exact 依赖与字体边界

- **选定依赖**：用户指定 JetBrains Mono；当前固定使用 JetBrains 官方 release `v2.304` 的 `fonts/variable/JetBrainsMono[wght].ttf`，仓内重命名为 `Flotis/Resources/Fonts/JetBrainsMono.ttf`。官方 archive URL 为 `https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip`，archive SHA-256 为 `6f6376c6ed2960ea8a963cd7387ec9d76e3f629125bc33d1fdcd7eb7012f7bbf`，仓内 TTF SHA-256 为 `662a196d58f1183bf2d77428b6d5283fe3f45161ab021bea4036bc98e5cac016`。
- **能力与许可证证据**：官方 font metadata 暴露 `JetBrains Mono` family、Thin 至 ExtraBold named weight instances 与 `JetBrainsMono-Regular` PostScript face，直接提供本任务所需的英文/拉丁等宽界面字体。官方 `JetBrainsMono-OFL.txt` 与 `JetBrainsMono-AUTHORS.txt` 原样随主 App 资源分发；许可证为 SIL Open Font License 1.1，允许应用内商业/非商业使用与再分发。
- **平台与安全/分发边界**：字体是 data asset，不引入可执行第三方代码、package manager、网络运行时或系统级字体安装。macOS 通过官方 `ATSApplicationFontsPath=JetBrainsMono.ttf` 仅为该 App 激活 bundle resource；字体由系统 Core Text 解析，输入法 target 不携带或注册它。升级字体必须重新固定官方版本、来源与 hash，并重跑构建/渲染测试。
- **最薄本地接线**：`FlotisType` 只把既有 brand/title/headline/body/caption/mono weight 请求映射到官方 named face，并为两个 AppKit 文本入口返回对应 `NSFont`；`SettingsView` 与 `FloatingPanelView` 只设置默认 SwiftUI environment font。没有本地重写字体、glyph、shaper、renderer、adapter 或备用字体后端。
- **回退与失败**：JetBrains Mono 不含中文，混排时由 Core Text 原生 glyph cascade 选择 `PingFang` 家族；这是 macOS 文本排版行为，不是 Flotis 的第二字体 renderer。App 在创建 panel/Settings 前核验 TTF resource 与全部所需 weight；资源缺失或 macOS 无法激活任一 face 时显示 critical error 并终止，不允许 SwiftUI 静默改用另一英文字体。
- **LaTeX 例外**：全仓源码/资源扫描没有找到 LaTeX、TeX、MathJax、KaTeX 或其他公式渲染入口，因此本轮没有公式字体调用点可修改。任何后续或外部 formula surface 必须继续使用其 renderer 当前公式字体，不得继承或显式套用 `FlotisType`；只有普通 Flotis 界面文案使用上述 JetBrains Mono/PingFang 组合。

- **动态系统白黑**：`FlotisTheme` 使用随 Light/Dark appearance 动态解析的 `.primary`、`.secondary`、透明度派生 tertiary 与系统 `separatorColor`。主要操作为系统白/黑单色；红、橙、绿只保留给录音、警告、成功和失败等有限语义状态，不维护固定品牌色板。
- **窗口 canvas**：Settings 在 macOS 14+ 使用 SwiftUI `windowBackground`；macOS 13 通过 `.windowBackground` `NSVisualEffectView` fallback。胶囊仍由透明 borderless `NSPanel` 承载：编译器支持且运行于 macOS 26+ 时，hosting content 进入原生 `NSGlassEffectView(style: .regular)`，macOS 27+ 开启 interactive glass；macOS 13–25 回退到 `.popover` `NSVisualEffectView`，其可拉伸圆角 `maskImage` 同时限定 material 与窗口服务器阴影，CALayer mask 仅裁切 hosted subviews，并在显示或静态尺寸切换后刷新原生阴影。compact SwiftUI 内容不再绘制固定白色填充或自定义整圈描边，保持透明并让原生 glass/material 直接采样背景；快捷键使用动态主文字色。reviewing 继续使用既有原生 glass/material 内容结构，窗口服务器阴影与兼容路径继续由 AppKit 管理。
- **内容表面**：结构化内容使用 `regularMaterial`、1 pt separator 和 continuous rounded rectangle；长文本与表单内容保持在系统 canvas / Material 层，不用 glass 覆盖全部正文。
- **Liquid Glass 与兼容路径**：在编译器支持且运行于 macOS 26+ 时，panel 容器继续使用 AppKit `NSGlassEffectView(style: .regular)`，并作为 compact 胶囊的唯一表面；结构化 reviewing/Settings 交互表面仍可使用原生 glass。compact 内容层禁止再用固定白色/不透明 surface 覆盖系统高光、折射与背景采样。macOS 13–25 的 panel 继续回退到 `.popover` material，其他内容/按钮回退到 `regularMaterial` 与原生 `.bordered` / `.borderedProminent`，因此 deployment target 仍为 macOS 13。
- **字体与图标**：Flotis 自有界面所有英文/拉丁字形统一使用 JetBrains Mono；中文 glyph 继续由 Core Text 回退到苹方。标题、正文、caption、快捷键和技术字段保留既有字号/weight 层级，不再切换 Serif、系统正文或系统 Monospaced family。最小胶囊只用 15 pt JetBrains Mono Semibold 的当前 voice 快捷键与一个原生 `Circle`，不显示品牌名、raster image set、SF Symbol 或 emoji；reviewing 与 Settings 的既有功能图标继续使用 SF Symbols。LaTeX 公式 renderer（当前仓库不存在）保持自己的既有公式字体，不属于该界面字体层。
- **应用图标**：根目录 `Flotis.icon` 是主 App 的 Icon Composer source of truth，并以 target resource 交给 `actool`；build setting 使用名称 `Flotis`。因此产物由 Xcode 生成系统多尺寸 `Flotis.icns` 和 `Assets.car`，Info.plist 的 icon name/file 也来自编译结果。历史录音/设置 raster image set 暂时保留但不再用于当前最小胶囊；输入法仍使用自己的 TIFF 输入源图标。
- **共享组合**：reviewing 之外所有状态统一使用 `96×36` compact frame 与 18 pt 连续圆角的透明原生 glass/material 表面，内部只含 6 pt 语义圆点与 15 pt JetBrains Mono Semibold 的当前 voice 快捷键，间距 7 pt；快捷键为动态主文字色，默认显示 `⌃⌥A`，配置变化后即时更新。idle 为绿点，录音/流式为红点，请求/连接/停止/转写/失败或热键错误为橙点；完整状态继续通过 accessibility value 暴露，视觉层不显示品牌名、计时、状态/错误句、图标、动作按钮或设置提示。单结果 reviewing 仍为 `420×160`，对比 reviewing 仍为 `560×300`；对比页顶部继续用固定双列网格表达 2–4 个成功/失败候选与耗时，四项为 2×2。开始会话时从 canonical model entry 快照可选 Display name，有名称的候选只显示该名称，没有名称的候选以 Model ID 为主要文字、Provider 名称为次要文字，endpoint 不进入可见卡片。首个成功项直接在原生编辑器打开，不显示额外选择提示，也不需要横向滚动。尺寸请求只保留最后一次，panel 首次位于屏幕底部中央；panel 平时禁止系统管理移动，非审阅单次 mouse-down 显式进入原生窗口拖动。`FloatingPanelPositionAnchor` 独立保存用户位置的水平中心与底边；状态 resize 的临时钳位不回写逻辑锚点。Settings 使用固定侧栏和右侧独立滚动页面；当前可达页面不展示 AX 状态。

## 界面语言与本地化

`AppLanguage` 与 `UIStrings` 构成独立的 Presentation 文案层。启动时只读取 `Locale.preferredLanguages.first`：明确的简体中文标识（`zh-Hans` 或中国大陆、新加坡、马来西亚地区标识）选择简中；繁体中文、英文和其他语言都选择英文。语言改变后通过重新启动 App 生效，不提供手动切换入口。

- 胶囊、Settings、热键注册、音频捕获、连接测试和各 adapter 的 App 自定义错误都通过同一双语入口生成；英文/拉丁 glyph 进入 JetBrains Mono，中文 glyph 由同一文本排版链路回退到苹方，不再按整段语言选择 Serif 或系统标题字体。
- 日期显示显式使用当前 App 中/英文 locale，避免其他系统 locale 把英文界面中的日期格式化成第三种语言。
- `project.yml` 以英文为 development language 和权限说明基值；`InfoPlist.xcstrings` 为麦克风与 Speech Recognition 权限提示提供英文、简中资源。
- UI 语言不参与 provider language、模型、endpoint、协议事件或 schema 编码。现有用户 provider 名称和历史测试摘要不做持久化迁移；legacy 内建名称仅在兼容显示层处理。
- 服务端返回的原始错误和 Apple/AVFoundation 的系统错误保留真实内容；App 自己添加的 wrapper/fallback 保证中英双语。

## Provider Group、Model Route、Adapter 与 Preset

配置和运行时分成三层：

```text
provider（共享 endpoint/key/options）
          │ models 字典展开
          ▼
model route / TranscriptionConnection ──adapterID──▶ 版本化 adapter ──▶ 通用 runtime plan
          ▲
          └──── preset 只复制建议字段，不参与运行时判别
```

- `FlotisProviderConfiguration` 是 schema v2 canonical provider 数据：一个对象保存一次 name、adapter、共享 endpoint/key/options，并用 `models` 字典拥有多个模型。
- `TranscriptionConnection` 是从 `<provider-id>/<model-id>` 确定性派生的运行时 route 快照，包含稳定内部 UUID、adapter、共享配置与该模型的测试记录；它不是 schema v2 中可独立复制 endpoint/key 的顶层实体。
- `TranscriptionAdapterID` 有六个稳定 raw value；`TranscriptionAdapterRegistry` 是 adapter descriptor 与 runtime factory 的唯一注册点，拒绝重复 ID。
- `VoiceInputController` 只处理 `ownedCapture`、`pcmStream`、`recordedFile` 三类执行计划，不读取厂商名，也不按 adapter/wire protocol switch。
- `TranscriptionProviderPreset` 是独立 catalog。选择预设只为当前 draft 填入默认字段，不改变 connection identity，也不成为 runtime discriminator。
- Settings 另有独立的 adapter Presentation visibility 层：当前 allowlist 只包含 OpenAI Compatible HTTP。可见层允许多个 provider，并允许每个 provider 编辑多个模型、当前 route 与对比选择；过滤不参与 canonical provider 编码、active selector、adapter registry 或 runtime 判别，也不删除隐藏 provider。

## V0.13 热键链路与旧命令兼容

1. `HotkeyManager` 安装 Carbon `kEventHotKeyPressed` 与 `kEventHotKeyReleased` handler；press gate 保证一次物理按下只分派一次，release 后才允许下一次。
2. V0.13 App 传入空 command 列表，常驻注册 panel ID `100` 和 voice ID `200`。voice descriptor 从 canonical `shortcuts.toggle_voice` 读取，默认 `⌃⌥A`（Carbon virtual key `0`，Control+Option）；panel descriptor 来自 `shortcuts.toggle_panel`，默认 `⌘⌥⇧0`。仅当对比 reviewing 中至少有两个成功候选时，增量注册 previous ID `300` 与 next ID `400`，descriptor 分别来自 `shortcuts.previous_comparison_result` / `next_comparison_result`（默认 `⌥←` / `⌥→`）；离开该状态立即注销，避免普通使用时长期抢占用户配置的按键。底层从 `1000` 开始的命令 ID 映射仍为旧数据兼容实现，但当前不可达。
3. 注册使用 Carbon `kEventHotKeyExclusive` 并保持差异同步；生成的 Info.plist 以 `LSMultipleInstancesProhibited=true` 阻止两个 Flotis 进程同时竞争。失败状态保留并通过最小胶囊的橙点与 accessibility value 暴露，同时每 2 秒重试；event handler 安装失败时不会注册孤立 hotkey。
4. `VoiceInputState.hotkeyAction` 是纯策略映射：idle/failed→start，recording/streaming→stop，reviewing→copyAndReturn，requesting/connecting→cancel，stopping/transcribing/injecting→none。
5. `HotkeyConfigurationStore` 从同一 `config.json` 的可选 `shortcuts` 分区加载 voice、panel、previous、next 四项 descriptor；旧 schema v2 缺少整个分区或缺少 `toggle_voice` 时采用对应默认值。设置录制后先拒绝无修饰键或四项重复，再原子持久化；`AppDelegate` 订阅配置变化并调用 manager 的差异同步，未改变的注册不重建。Carbon 冲突仍由既有错误发布与 2 秒重试处理。
6. 当前配置的语音热键在 panel 隐藏时会确保胶囊可见；reviewing 的第三次动作同步写入系统剪贴板。对比 reviewing 已自动持有首个成功项，可配置的前后导航快捷键切换当前成功项后，第三次 voice hotkey 与单结果路径一致地复制当前编辑文本。写入成功直接清空会话并回 `idle`，panel 保持可见、由尺寸监听缩回小胶囊；写入失败保留 reviewing 文本并显示可重试错误。该路径不等待物理组合键释放，因为它不发送键盘事件。
7. 旧 `commands.json` 不被 V0.13 主入口加载、修改或删除；恢复命令产品能力必须另行做显式产品与迁移决策。

## 语音会话状态机

`VoiceInputState`：

```text
idle → requestingPermission → connecting → recording/streaming
     → stopping → transcribing → reviewing → clipboard copy → idle capsule visible
                                │       │
                                │       ├─ comparison: first success selected automatically
                                │       └─ copy failure: keep review
                                └──────────────→ failed
```

关键生命周期约束：

- 每次 `beginSession` / cancel / fail 都推进 `sessionGeneration`。所有异步 callback/task 回主线程前必须匹配 generation，旧会话不能清理或覆盖新会话。
- controller 保存 operation task、realtime writer task、recording limit task、streaming/file transcriber、capture/recorder；取消会统一终止这些资源。
- model route 配置与 provider API key 在会话开始时快照到 adapter runtime。录音期间切换/删除 provider/model 或清除 key，不会让已开始会话在 stop 时重新读取可变配置。
- requesting/connecting 状态向 UI 暴露 Cancel；stopping/transcribing 正在完成终态处理时忽略额外热键，避免误清空即将进入审阅的文本。provider 只在 Settings 中切换。
- adapter 完成后先释放 capture/transcriber/runtime，再将 trim 后的最终文本写入 `transcriptPreview` 并进入 reviewing；reviewing 不持有录音或网络资源。
- 单结果 reviewing 直接把最终文本交给原生 `NSTextView`。对比 reviewing 安装有序 `TranscriptCandidate` 列表时自动选择配置顺序中的首个成功项；`AppState` 把当前候选文本映射到编辑器，点击或用户配置的 previous/next 快捷键（默认 `⌥←` / `⌥→`）切换时跳过失败项、循环导航，并分别保留各自编辑内容，失败候选不可选择。工具栏保留复制全部、取消和“复制并返回”。确认动作复制当前 selection/`transcriptPreview` 的原样内容（仅用 trim 判断是否为空，不改写实际写入文本）；失败保持 reviewing 与编辑文本，成功才推进 generation、清空候选和文本、回 idle，并在保持 panel 可见的同时缩回原位置小胶囊。
- Apple Speech 收到真正 final 时会自动走 graceful stop/review，不会把 UI 留在 recording，也不会自动复制或关闭。

## 多模型 recorded-file 对比

第一版对比刻意复用已有 recorded-file runtime，不尝试把实时 WebSocket 或 Apple owned capture 强行合并到同一麦克风流：

1. `TranscriptionComparisonStore` 从 canonical `config.json` 的 `comparison.models` 与 `comparison.enabled` 读取有序完整 selector；去重后最多 4 个，少于 2 个时不能开启。它只分区更新 comparison，底层在同一文件锁内保留 provider 配置。顶层 `enabled_providers` 表示 catalog 中启用的 Provider，不承担对比列表职责。
2. Settings 当前只让已保存且 `SpeechProviderStore.isProviderReady` 的 OpenAI Compatible model route 参与选择，并明确提示同一录音会发送给每个 route、每个请求都可能单独计费。同一 provider 的 route 共享 `provider.<id>.options` 中的 endpoint/key；comparison 只引用 `<provider-id>/<model-id>`，不复制 provider 数据。
3. 开始会话时 controller 按 selector 顺序从完整 provider store 解析 2–4 个 route，逐个做配置/key 校验并创建 runtime 快照。所有 runtime 必须是 `.recordedFile`，且录音 format、sample rate、channels 完全相同；任何预检失败都在录音前终止并取消已创建 runtime。
4. 一个 `AudioRecorder` 只创建一份 `Flotis-Audio-*` 文件。最大录制时长取所有 selected runtime 的最严格安全上限；停止后 `FileTranscriptionComparisonRunner` 用 task group 把同一个 file URL 并发交给全部 transcriber，每项单独执行 upload-size 预检、耗时记录、空结果检查与错误捕获。
5. runner 在全部任务完成后按原 selector 顺序返回候选。单项失败成为失败卡，不取消其他项；至少一个成功才进入 reviewing，全部失败则会话进入全局 failed。完成、失败、取消与 session 失效路径都取消 transcriber 并清理共享录音文件。
6. 候选只保存在当前 `AppState` 内存中，既不写入 `config.json`、UserDefaults 或日志。Realtime/Apple/DashScope/Volcengine 的共享捕获与“自动评判最佳结果”均不是当前能力。

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

- Settings 可见 editor 按 Intatis 的 Provider/Models 结构组织：左栏管理多个 Provider 并显示各自模型数；右栏显示 Provider name、共享 API key、Active model，Connection disclosure 管理 Base URL/Path/Request Encoding/凭据目标，Models disclosure 以独立 Model ID + 可选 Display name 行管理同一 Provider 的多个模型。Connection、Models、Comparison 与 Advanced 由共享的全宽 disclosure button 承载，最小 hit target 为 44 pt；Provider 行至少 48 pt，每个可对比 route 的整张 44 pt 卡片都是按钮。Test Provider / Save 位于主卡下方；成功保存后所选 route 成为当前单模型路径。每个已保存且就绪的 model route 都可在下方独立 Comparison disclosure 中勾选，因而同 Provider 两个模型可以直接对比；Language、Prompt、Temperature 仍位于主卡之后的高级字段。
- WAV/M4A 兼容选择、16 kHz 单声道音频参数与 response mode 继续由 provider/schema 管理；保存旧 M4A 配置时不得静默改写为 WAV。
- 通用 BYOK 默认生成 PCM16、16 kHz、单声道 `Flotis-Audio-*.wav`；从 legacy v2 迁移或显式选择的兼容 route 仍可使用 `.m4a`。`AudioRecorder` 检查 `prepareToRecord()`、`record()` 与最终文件存在/非空。
- `multipart-form-data` 先流式写入 `Flotis-Multipart-*` 临时文件，再由 `URLSession` 上传，不把整个音频与 multipart 双份常驻内存。OpenRouter 使用 `json-base64`：body 为 JSON，包含 Base64 `input_audio`、完整模型 ID及可选 language/temperature；配置 host 为 `openrouter.ai` 且未显式覆盖时自动选择该编码。
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

当前 Settings 以固定侧栏分为“快捷键 / 转写”，左上品牌区只显示 `Flotis` 与版本，不再显示应用图标。“快捷键”页只保留一张紧凑内容卡，按四个 `52` pt 行显示 voice、panel 显隐及前后对比导航。四项都使用 `156×38`、15 pt JetBrains Mono 的轻量可点击 surface，点击后在相同尺寸的原生录制态直接接收新组合。常态不显示语音流程、胶囊拖动、对比生效条件、第二层 section、hover help、铅笔或恢复控件；只有真实校验、持久化或 Carbon 注册错误才在卡片下出现。当前可达 Settings 不展示与主流程无关的 AX 权限。转写页只会为 OpenAI Compatible HTTP 实例化 editor。主 Provider/Models 卡复刻 Intatis 的信息层级：左侧 Provider 列表/Add，右侧 Provider name、API key、Active model、Connection/Models disclosure，Models 中按行提供 Model ID、Display name 与删除动作，卡片下方是 Test Provider / Save。Flotis 特有的 2–4 route Comparison 与 Language/Prompt/Temperature 位于主卡之后的独立 disclosure，不把 route 选择或高级参数混进 Provider 共享字段。preset 与其他 adapter 选择不可见。没有现有 OpenAI provider 时只显示明确空态，创建内存 draft 后 Cancel 不落盘。底层六套 schema 与多 provider/model route 数据仍用于迁移、normalize、校验、连接测试和 runtime；可见性不是新的 runtime discriminator。URL 校验继续拒绝非 HTTPS、userinfo、query、fragment、反斜杠和歧义 path。自定义 host 仍需用户显式确认，UI 仍显示凭据的精确目标 host。

adapter、scheme、host、effective port 或 auth type 改变会改变 `secretBoundaryIdentifier`：store 生成新 `apiKeyReference`，并在同一次 `config.json` 原子事务里替换 provider 配置、写入可选新 key、移除旧 reference 对应的内存映射，防止旧服务凭据被发送到新目标。文件提交失败时 provider catalog 与 key 一起回滚。

## Canonical 配置持久化与恢复

- 唯一主数据为 `~/Library/Application Support/Flotis/config.json` schema v2。布局参考 Intatis：顶层 `$schema` 与 `schema_version` 标识格式，`model` 保存 `<provider-id>/<model-id>` active selector，`provider_order` 保留 UI 顺序，`enabled_providers` 保存启用 Provider，`comparison.models` 保存有序对比 selector，可选 `shortcuts` 保存 voice、panel、previous、next 四项可配置全局快捷键，`provider` 以语义化 ID 为字典键。旧 schema v2 没有 `shortcuts.toggle_voice` 时解码为默认 `⌃⌥A`。
- selector 只在第一个 `/` 分割，Provider ID 不含 `/`，Model ID 可包含 `/`；因此 `openrouter/openai/gpt-4o-transcribe` 能无损表示 OpenRouter 模型。
- 每个 provider 对象保存 `name`、版本化 `adapter`、多 model 的 `models` 字典、共享 `options`（`baseURL`、`path`、`apiKey`、reference、language、authentication、audio、transcription）及 credential revision；每个 model 可保存可选 `name`（Settings 的 Display name）和独立安全测试摘要。录音、候选 transcript、响应正文和完整失败响应不进入文件。
- Settings 从完整 provider groups/routes 计算可见数组，但绝不把过滤结果写回 store。隐藏 provider、隐藏 active selector 及其 key 不会因打开、编辑或关闭 Settings 而删除或改写。
- canonical schema v1 会在原文件安全校验后原子升级为 v2 并移除 Apple 条目。旧 `flotis.transcriptionConnections.v3`/LKG、`flotis.speechProviders.v2`/LKG、`flotis.speechProviders.v1`、`flotis.transcriptionComparison.v1` 与 `secrets.json` 只在 canonical 文件不存在时作为一次性只读迁移输入；文件建立后不再读取旧源。
- canonical JSON 损坏、schema 未知、符号链接、非普通文件、异常大或非当前用户所有时拒绝覆盖。全新安装创建空 provider catalog；Apple on-device 只作内部 fallback且不持久化。active selector 必须指向存在且有效的 route，需要 key 的 route 还必须从其 provider 的 `options.apiKey` 取得非空值，否则不能激活。
- create/update/delete/clear credential 与 provider/comparison/shortcuts 分区更新均通过 `FlotisConfigurationStore` 的同锁 read-modify-write 提交；一个分区更新不能覆盖另两个分区。失败恢复原内存状态；models/provider 变化时 comparison store 移除不存在的 selector，剩余少于 2 个会自动关闭。

## Test Connection

`TranscriptionConnectionTester` 使用与真实会话相同的 registry/runtime factory：

- Apple 路径只做 locale、recognizer availability 与设备端能力检查，不请求麦克风。
- HTTP/file 与 Realtime 路径使用程序生成的 0.8 秒无隐私 PCM/WAV 或 M4A 合成音；不读取用户录音或历史转写。
- HTTP 根据 route 验证实际 multipart 或 OpenRouter JSON+Base64、状态码、Content-Type 与顶层 `text` 结构；Realtime 验证 start、append、manual commit 和协议终态。合成音不是语音质量样本，因此合法空 `text` 也可证明 transport/响应结构可用。
- 成功只保存时间、adapter version、固定安全摘要与配置 fingerprint，不保存 transcript。失败摘要限制长度，并先按本次内存中的完整 API key 精确脱敏，再做通用凭据模式脱敏。
- fingerprint 覆盖 endpoint/model/options 与 credential revision，但不含用户显示名称；相关配置或凭据变化会自动使旧测试记录失效。

## 单文件配置与凭据边界

- `FlotisConfigurationStore` 是唯一生产配置/凭据后端，路径固定为 `~/Library/Application Support/Flotis/config.json`。API key 明文位于对应 `provider.<id>.options.apiKey`，由该 Provider 全部模型共享；`apiKeyReference` 只供运行时 route/key 快照匹配，不参与文件路径拼接，也不再指向第二个 JSON。
- Flotis 目录强制为 `0700`，`config.json` 与 `.config.lock` 为 `0600`。读写先打开不跟随符号链接的目录描述符；同一进程由共享 `NSLock` 串行化，多进程通过 `.config.lock` 的 POSIX advisory write lock 覆盖完整 read-modify-write。锁竞争使用单调时钟短间隔重试并在 500 ms 后失败。数据写入同目录 `0600` 随机临时文件并 `fsync`，再用 `renameat` 原子替换并同步目录。
- 文件最大 4 MiB、provider 最多 64 个；读取只接受当前 schema、结构一致的 provider order/字典、普通文件、当前用户所有和合法 JSON。符号链接、目录、其他文件类型、损坏或异常大的文件均返回失败，保存不得覆盖坏文件。
- 删除 provider、切换到无需 key 的 adapter、改变 secret boundary 或 UI Clear 会在同一文档事务中清理对应 `options.apiKey`；只删除一个 model 不复制或移动共享 key。文件系统原子替换不承诺物理介质上的安全擦除。
- `LocalSecretStore` 与 `secrets.json` 仅为旧版本一次性迁移读取保留；canonical 文件存在后生产运行时不再访问它。Flotis 仍不导入 `Security`、调用 `SecItem*`，也不读取、迁移或删除旧系统钥匙串条目。
- `config.json` 不做独立加密，安全性依赖 macOS 登录用户权限和可选的 FileVault；同一登录用户权限下的进程仍可能读取，不得把 `0600` 描述成钥匙串级保护。

## 当前剪贴板确认与旧注入兼容

当前产品路径：

1. reviewing 的确认动作先用 trim 结果拒绝纯空白；对比模式自动选择首个成功项，并只允许导航到成功项。实际写入 `SystemTranscriptClipboardWriter` 的仍是当前候选经用户编辑后的原始字符串，不裁剪首尾内容。
2. writer 只把文字写入系统剪贴板；不恢复旧剪贴板，因为复制结果本身就是用户要保留的输出。写入失败时保持 reviewing、原文字和 panel 可见，并显示可重试错误。
3. 写入成功后 controller 推进 session generation、清空 review 并回到 idle；panel 不关闭，现有状态尺寸监听用 `FloatingPanelPositionAnchor` 把审阅框缩回原位置小胶囊。整个过程不查询 AX、不激活其他 app、不创建或发送键盘事件。

`ClipboardPasteInjector` 仍编译并由旧安全策略测试覆盖，但当前没有产品入口调用。若未来明确重新启用，以下边界仍有效：

1. 缺 AX 权限立即失败，绝不发 `CGEvent`。
2. 调用方必须提供或显式捕获本次会话目标；operation 队列最多 4 个 in-flight，burst 最多 8 个，5 秒过期。
3. 仅当剪贴板全部 item/type 可同步复制且 `changeCount` 未在快照期间改变时开始 burst；无法完整快照则拒绝注入。
4. 写入文本后记录 app 管理的 `changeCount`，让 Flotis 辞去焦点并只核验目标 PID/frontmost；第三方切换、进程退出或激活超时均 abort。
5. 等完整语音快捷键释放，发事件前再次核验 AX、目标、焦点、operation 时效与 pasteboard `changeCount`。
6. 只可用 `CGEvent.postToPid` 向已核验 PID 定向发送 `⌘V`；外部 clipboard 更新必须保留，旧 snapshot 仅在 `changeCount` 未变化时恢复。
7. 类型化结果继续区分 AX、目标、焦点、快捷键、剪贴板、过期、事件创建与恢复失败；success 不等于目标控件已消费事件。

V0.13 胶囊为 borderless panel，不提供红色关闭按钮；panel toggle 仍以真实 `window.isVisible` 为准。voice hotkey 在 panel 隐藏时会恢复可见性；reviewing 第三次热键复制成功后保持 panel 可见并缩回 idle 小胶囊，下一次 hotkey 直接开始新录音。只有独立 panel toggle 或应用退出会隐藏/关闭该表面。

## 线程与安全约束

- UI 与 controller 状态在 MainActor。
- WebSocket sender 串行；协议解析/connection/transcript 状态使用 actor 或锁隔离。
- 网络仅允许 HTTPS/WSS；HTTP 与 WebSocket session 共用 no-redirect delegate，携带凭据的请求不跟随重定向。
- API key 不进入 UserDefaults、项目文档或日志；明文只存在当前会话内存与私有权限 `config.json` 的 `options.apiKey`。
- 对比配置只保存完整 model selector 与开关；共享录音、候选转写、逐项错误和耗时只属于当前会话内存/临时文件生命周期，不进入持久化或日志。
- temp cleanup 仅匹配 Flotis 自有前缀、普通文件且超过 24 小时，避免清理无关文件。
