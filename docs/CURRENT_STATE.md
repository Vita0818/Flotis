# CURRENT_STATE

最近一次自查日期：2026-07-30

## 当前真实状态总览

- Flotis V0.8 是 macOS 悬浮语音输入胶囊；`project.yml` 当前声明 `MARKETING_VERSION=0.8.0`、build `1`。仓库当前没有 Git tag，历史中的 `v0.1`–`v0.7` 是提交信息而非 tag。
- XcodeGen 工程包含 `Flotis` app 与 `FlotisTests` unit-test 两个 target；app 有 27 个 Swift 源文件，测试有 5 个 Swift 文件，无第三方依赖。
- app 为 `LSUIElement=YES`，无 Dock 图标；`LSMultipleInstancesProhibited=YES` 防止两个 Flotis 进程争抢全局热键；deployment target 为 macOS 13.0。
- 六个版本化转写 adapter 仍完整注册：Apple on-device、OpenAI-compatible HTTP、OpenAI Realtime GA、DashScope Paraformer、Volcengine BigASR、GLM ASR HTTP/SSE。当前 Settings 展示层只开放 OpenAI Compatible；其余 connection、adapter、preset、迁移与 runtime 能力仅暂时隐藏，没有被删除。全新安装仍只创建 Apple connection。
- V0.8 主链路为同一语音热键依次执行“开始录音 → 停止并等待转写 → 审阅/编辑 → 确认注入”；命令网格、命令设置 tab 和命令热键已退出运行入口，但旧 `commands.json` 与相关兼容源码未删除。
- connection 配置 v3、应用自管凭据隔离、v1/v2 只读迁移、OpenAI Compatible 新增/编辑 UI、Test Connection 和可取消语音会话保持不变。
- App 界面语言自动读取第一首选系统语言：明确的简体中文标识使用简中，繁体中文、英文及其他语言统一回退英文；不提供手动语言开关，也不改变 provider 的转写语言。
- 2026-07-26 已对 OpenAI Compatible Settings 最终源码运行 `xcodegen generate`、完整 Debug build 和 unit tests：最终构建成功，49 tests、0 failures；此前旧版工作台曾在 macOS 26.5 Light appearance 打开检查，但本轮精简表面尚未运行态目视。
- 2026-07-27 已完成胶囊紧凑与边缘精修：AppKit 成为唯一外壳裁切 owner，SwiftUI 改为向内描边；`xcodegen generate`、独立 Debug build 和 49 个 unit tests 均成功，并在 macOS 26.5.2 运行态对比了 AX 警告状态。
- 2026-07-28 待机胶囊最终微调为 `120×56`：只显示录音、设置两个按钮及下方灰色语音快捷键符号，不再显示品牌名或启动说明；相较上一版 `128×56` 只收窄 8 pt，高度、按钮尺寸、10 pt 按钮间距和 11 pt 系统次级灰快捷键均保持不变，避免再次变大或牺牲可读性。该比例已通过 XcodeGen、独立 Debug build 与 49 个 unit tests；按用户要求没有启动 App 或打开 Settings，因此最终观感留给用户在常用构建中确认。缺少 AX 权限不会在尚未执行注入时主动撑大胶囊，权限状态仍在 Settings 醒目展示，实际注入失败后仍会展开明确提示和系统设置入口。录音、处理、审阅和其他错误态继续保留必要状态信息。Settings 共用页头新增醒目的双语一键退出按钮，使用 AppKit 标准 terminate 路径。
- 2026-07-28 针对浅色模式的尖角矩形高光和双边毛躁再次收敛外壳：`NSVisualEffectView.maskImage` 现在用可拉伸圆角 alpha mask 同时约束 material 与窗口服务器阴影，CALayer mask 只负责裁切 hosted subviews；窗口显示和静态尺寸切换后会重新计算阴影。SwiftUI 已移除整圈 1 pt separator 描边，避免它与 material/原生阴影叠成明显双边。尺寸、圆角值、按钮和所有语音状态未改。XcodeGen、独立 Debug build 与 49 个 unit tests 通过；没有启动 App 或打开 Settings，因此浅色模式最终像素观感仍待用户在常用构建中确认。
- 2026-07-30 已移除全部系统钥匙串运行时依赖：删除 `KeychainSecretStore`、`import Security` 与所有 `SecItem*` 调用，生产链路统一改用 `LocalSecretStore`。API key 明文只写入 `~/Library/Application Support/Flotis/secrets.json`，以版本化 JSON、目录 fd、`openat(..., O_NOFOLLOW)`、同目录 `fsync + renameat` 原子替换、进程内共享锁与 `.secrets.lock` 跨进程写锁、目录 `0700` / 文件 `0600` 管理；跨进程锁只在单调时钟下重试最多 500 ms，避免另一进程卡死时永久冻结 UI。符号链接、非普通文件、非当前用户所有、损坏或超过 1 MiB 的文件会被拒绝且不会覆盖。connection v3 继续只保存 `apiKeyReference`，因此 schema 与六个 adapter 不变。Flotis 不读取、迁移或删除旧钥匙串条目，已有用户需在新构建中重新输入一次 API key；正在运行的旧构建必须退出后，新实现才会生效。XcodeGen、独立 Debug build 与 53 tests 全部通过，最终 dylib 无 Security.framework 直接链接或 `SecItem*` 未定义符号；本轮未启动 App 或接触真实凭据。
- 2026-07-30 已完成胶囊交互稳定性收敛：待机仍为 `120×56`，普通工作态改为 `188×56`，错误/提示态统一 `280×56`，审阅态改为 `420×160`，状态文案不再额外增加高度。尺寸请求会合并为最后一次，并始终基于启动时屏幕的固定底边锚点计算；显示面板和屏幕参数变化时会重新核对锚点，全窗口背景不再可拖动。齿轮直接打开 AppDelegate 持有且复用的独立 `760×560` 设置窗口，不再依赖字符串 selector 或胶囊 sheet；可见配置只剩 Model、Endpoint、API Key 和必要动作，connection name/多连接管理隐藏，保存后自动设为当前 OpenAI Compatible connection。审阅框改为原生 `NSTextView`，支持选择、编辑、右键与 `⌘C`，并增加无文字标签的复制全部按钮。Carbon 热键改为独占注册并监听 press/release，按住不再重复穿越状态；stopping/transcribing 中的额外按键改为忽略；注入前等待 `⌘⌥⇧R` 的修饰键和主键 R 全部释放，并要求 Flotis 自身 key window 已让出键盘焦点。XcodeGen、独立 Debug build 与 57 tests、0 failures 通过；未启动 App，运行态视觉、焦点和跨 Space 行为仍需新构建真机确认。
- 用户已用真实 OpenAI-compatible connection 完成录音、转写并进入 reviewing，且在 AX 已授权时点击胶囊“输入”成功；修复后的第三次全局热键、跨 Space、剪贴板管理器竞争及其余 provider 真实账号端到端仍需 macOS 真机验证。

## 已有能力

| 能力 | 入口 / 关键类型 | 自动化覆盖 | 当前验证 |
|---|---|---|---|
| V0.8 悬浮语音胶囊 | `FloatingPanelController` / `FloatingPanelView` / `FlotisDesign` | Debug build + 57 tests；无 UI/snapshot test | 四档静态尺寸、固定屏幕锚点和原生审阅编辑器已构建；运行态选择/复制与焦点待验 |
| OpenAI Compatible Settings | `FlotisSettingsWindowController` / `SettingsView` / `SpeechProviderSettingsView` | 构建覆盖；provider/secret 行为由 24 个配置单测覆盖 | 可复用独立窗口只展示 Model/Endpoint/API Key、必要动作和标准退出；运行态待目视 |
| 简中 / 英文自动适配 | `AppLanguage` / `UIStrings` / `InfoPlist.xcstrings` | 首选语言矩阵、双语选择与权限资源编译 | 构建/单测通过；双语运行态排版待目视 |
| Carbon 全局热键 | `HotkeyManager` / `VoiceHotkeyAction` | 独占注册、press/release 门控与动作策略单测 | 开始/停止/进入 reviewing 已真机触发；修复后的第三次注入待新构建复测 |
| 旧命令数据兼容 | `CommandStore` / `commands.json` | 旧策略单测 | 不再展示或注册命令热键 |
| 安全剪贴板注入 | `ClipboardPasteInjector` | 队列容量、过期策略与完整快捷键释放单测 | 胶囊按钮注入已真机成功；第三次热键与面板焦点让出待新构建复测 |
| Apple Speech 设备端转写 | `AppleSpeechTranscriber` / `AppleTranscriptAccumulator` | 空 final、停顿分段、重叠纠错与相邻片段单测 | 真机复测待验 |
| OpenAI Realtime GA 转写 | `OpenAIRealtimeTranscriber` | 多 item 乱序、partial/final 组装及 scripted session/append/commit/terminal | 真实 key 待验 |
| DashScope Realtime | `DashScopeParaformerRealtimeTranscriber` | 重复句与文本边界单测 | 真实 key 待验 |
| Volcengine BigASR Realtime | `VolcengineBigASRRealtimeTranscriber` | schema、registry/runtime plan 单测 | 真实 key 待验 |
| OpenAI-compatible HTTP multipart | `OpenAIHTTPTranscriber` | 自定义 endpoint/model、WAV/M4A multipart、严格响应、取消边界 | OpenRouter 真实 happy path 已进入 reviewing；失败与边界矩阵待验 |
| GLM HTTP SSE | `GLMASRHTTPTranscriber` | Content-Type、JSON event、delta/done/`[DONE]` 与错误脱敏 | mock 通过；真实 key 待验 |
| 统一 connection / adapter registry | `TranscriptionConnection` / `TranscriptionAdapterRegistry` | 6 个唯一 adapter 与 3 类通用 runtime plan | 通过 |
| Connection Test | `TranscriptionConnectionTester` | 合成音频、HTTP 与 Realtime mock、空文本合法、任意形态 Key 回显脱敏 | 通过 |
| Provider v1/v2→v3 迁移 | `SpeechProviderSnapshotMigration` / `SpeechProviderStore` | 六类、自定义实例、排序、active、引用、v2 LKG | 通过 |
| 应用自管 API key 存储 | `LocalSecretStore` | 跨实例并发/持久化、替换/删除、`0700`/`0600`、损坏文件与符号链接拒绝；既有 reference 轮换/回滚测试 | 配置套件 24 tests、完整 57 tests 均通过；真实用户路径待新构建首次保存 |

## 已解决的 2026-07-10 审计问题

- 注入前确认目标 PID 存活且仍为 frontmost；激活失败、用户中途切换 app、修饰键超时或 AX 权限丢失都会终止，不再发送 `⌘V`。
- 注入队列和 burst 有容量/时效上限；剪贴板仅在 `changeCount` 未变化时恢复，复杂类型无法完整快照时拒绝注入。
- 可打印全局快捷键必须包含 Command 和至少一个额外修饰键，避免 `⌘V`、`⌘C`、`⌘Q` 等系统级冲突；热键按差异增量注册并自动重试失败项。
- `VoiceInputController` 用 session generation、可取消 task 和会话内 connection/key 快照隔离旧回调；实时音频使用有界串行队列并在 terminal commit 前 drain。
- Realtime stop 改为等待协议终态/ack；OpenAI 按 `item_id` / `content_index` / previous item 关系组装，Dash 等待 `task-finished`，Volc 等待终端事件/包。
- `StreamingAudioCapture.stop()` 会先移除 tap/停 engine，保持 generation 有效地排空所有 in-flight conversion，并以 end-of-stream flush `AVAudioConverter` 尾帧；`cancel()` 才立即失效 generation 并丢弃待处理音频。
- 运行时改为 `TranscriptionAdapterID → TranscriptionAdapterRegistry → ownedCapture/pcmStream/recordedFile`；`VoiceInputController` 不再按厂商或 wire protocol 分支。协议专属参数、HTTPS/WSS 校验、可信 host 提示、凭据边界和草稿 Save/Cancel 保持不变。
- UserDefaults 主数据升级为 canonical v3 connection；v2/v1 只作为只读迁移输入，保留 UUID、名称、排序、active ID 与安全边界不变的 `apiKeyReference`，并继续使用 last-known-good、坏数据备份和事务回滚。
- Settings 的展示 allowlist 当前仅包含 `openai-audio-transcriptions-http-v1`；Add 直接创建该 adapter 的内存草稿，列表与概览不会加载隐藏 adapter。底层同 adapter 多 connection、六 adapter schema/preset、迁移与 runtime 保持不变。
- Test Connection 使用程序内生成的无隐私短音频验证实际 transport、音频上传与响应结构；合成音不要求产生非空转写。错误摘要有长度上限并按本次实际 Key 精确脱敏，不保存响应正文或转写内容。
- 最终复核补齐了 secret 清理失败回滚、坏 v3/v2 的对应 LKG 恢复与 legacy v1 fallback、Volc resource ID 的 schema/runtime 同源校验，并移除了 Volc 无效 language 配置。

## V0.8 界面与交互基线（2026-07-27）

- `FlotisDesign.swift` 现在为胶囊与 Settings 提供同一套 Presentation / Design System：主要颜色只使用动态 `.primary` / `.secondary` 与系统 separator，随 Light/Dark appearance 解析为系统白/黑；录音、警告、成功和失败才使用有限的红/橙/绿语义色。
- Settings 使用动态 window canvas、`regularMaterial + 1 pt separator` 内容卡；中文页面标题采用系统默认字体，英文品牌与标题采用 Serif，正文采用系统默认字体，技术字段采用 Monospaced，并继续使用 SF Symbols。macOS 26+ 的交互控件使用原生 Liquid Glass，macOS 13–15 回退到系统 Material 与 bordered controls。
- `UIStrings.swift` 集中提供简中与英文文案；`AppLanguage` 只检查第一首选语言，识别 `zh-Hans` / `zh-CN` / `zh-SG` / `zh-MY` 为简中，繁中及其余语言使用英文。应用内日期也固定使用所选中/英文 locale，权限提示由 `InfoPlist.xcstrings` 提供英文与简中版本。
- 主窗口仍是屏幕底部居中的无标题小胶囊；外壳为 20 pt continuous corner，AppKit visual-effect material mask 负责圆角材质与原生窗口阴影，CALayer mask 裁切 hosted subviews，SwiftUI 不再绘制整圈外框。待机态不显示品牌名、状态圆或说明文字，只保留录音、设置两个 SF Symbol 按钮和下方灰色 Monospaced 快捷键符号；非待机状态继续用图标、文字和有限语义色明确表达录音、处理、审阅、注入或失败。
- idle 尺寸为 `120×56`，普通非 idle compact 为 `188×56`，错误/提示态为 `280×56`，reviewing 为 `420×160`；所有非审阅态固定 56 pt 高，不再因状态文案追加 42 pt。idle 的双按钮水平间距为 10 pt，下方快捷键使用 11 pt Monospaced 与系统次级灰。尺寸请求只应用最后一次，窗口固定锚定启动屏幕底部中央、无动画且不允许整窗背景拖动，避免异步旧尺寸、错误提示和附属设置页推动胶囊。
- 齿轮直接打开 AppDelegate 持有并复用的独立 `760×560` 设置窗口；不再从胶囊弹出 sheet，也不再依赖字符串 selector、分段导航、概览卡、协议/预设选择、connection name 或多连接侧栏。页头只保留 OpenAI Compatible、AX 状态图标、标准“退出 Flotis / Quit Flotis”和关闭按钮；可见主表单只有 Model、Endpoint（内部 Base URL + Path）、API Key、Test/Save/Cancel，只有自定义 host 才显示必要安全确认，Language/Prompt/Temperature 收入折叠高级区。保存成功后自动设为当前 OpenAI Compatible connection。退出仍走 `NSApplication.shared.terminate(nil)`；注入中禁用并由 `applicationShouldTerminate` 统一兜底。
- `⌘⌥⇧R` 在 idle/failed 开始录音，在 recording/streaming 停止，在 reviewing 注入；requesting/connecting 可取消，stopping/transcribing/injecting 的重复按键忽略。Carbon 使用独占注册和 press/release 门控，按住组合键只触发一次。
- reviewing 的第三次 Carbon hotkey 触发时，注入器会在 5 秒 operation 有效期内等待修饰键和主键 R 全部释放，并确认 Flotis 自身 key window 已让出焦点；超过时限仍安全失败。
- 转写 adapter 返回最终文本后不再自动注入，而是释放录音/网络 runtime 后进入 `reviewing`。原生审阅文本框支持编辑、鼠标选择、右键与 `⌘C`，工具栏另有复制全部、取消和输入三个图标按钮。
- 注入仍完全复用 `ClipboardPasteInjector`。失败时回到 reviewing 并保留文字，不会丢失用户修改；成功后清空文本并回到 idle。
- App 启动时只向 `HotkeyManager` 注册 panel/voice 两个固定热键；命令 singleton 不再由 `AppDelegate` 装配，旧命令文件不读取、不改写、不删除。

## Apple 转写累积修复（2026-07-12）

- 真机发现 Apple 短句可能先返回有效 partial、再返回空 final，旧实现无条件 `transcript = value`，会把“你好”等有效结果清空并触发“没有可输入的转写文字”。
- 同一覆盖逻辑也会在停顿后的新结果只包含后段时丢失前段。该问题位于 `AppleRecognitionState`，不是 reviewing、焦点捕捉或 `ClipboardPasteInjector`。
- 新 `AppleTranscriptAccumulator` 使用 `SFTranscriptionSegment.timestamp/duration` 合并：重叠时间范围视为同一假设修订并替换，不重叠范围按语音顺序追加，空结果不抹除已有非空文本。
- Apple partial/final handler 现在统一发布 accumulator 的完整文本。OpenAI Realtime、DashScope、GLM 已有 item/segment/delta 累积；Volc 的 full-result 路径会忽略空 transcript，因此未改其他 provider 协议实现。

## 尚未完成 / 需要人工确认

- **真机端到端**：Carbon、`CGEvent`、AX 权限、非激活面板焦点、跨 Space、目标 app 慢激活以及剪贴板管理器竞争无法由当前 unit tests 证明。
- **Apple 真机复测**：需要再次验证“你好”短句、两个词中间静音 3–5 秒、连续纠错与重复词；自动化只证明累积策略，不能替代真实 `SFSpeechRecognizer` 回调序列。
- **胶囊编辑/复制焦点**：原生 `NSTextView.needsPanelToBecomeKey`、复制全部按钮、面板让出 key window 与 last non-Flotis target 组合已构建通过，但鼠标选区、`⌘C`、右键 Copy 及“点击胶囊编辑后按全局热键回注原 app”仍需真机验证。
- **视觉无障碍与兼容矩阵**：macOS 26.5 Light appearance 的旧版 Settings 工作台曾完成目视；本轮 OpenAI Compatible 精简后的空态、列表、表单与隐藏 active provider 状态尚未运行态目视。Dark、Reduce Transparency、Increase Contrast、macOS 13 fallback、所有 voice state 及长错误/长转写仍需人工矩阵。
- **双语运行态排版**：语言解析和完整 57 个单测已通过，权限 String Catalog 也已编译检查；本轮未分别以简中、英文和其他语言启动 App 做完整目视，因此长英文在所有胶囊/设置状态下的实际截断仍需人工确认。
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

本轮交互稳定性修复开始时，工作树已经包含统一 UI 设计语言、简中/英文适配、OpenAI Compatible Settings 展示收敛、应用自管 secret store、第三次热键注入修复、权限本地化资源、语言策略测试、XcodeGen 生成物、项目上下文和文档改动，以及 Xcode 用户界面状态文件。本轮在此基础上继续修改胶囊/设置展示、窗口尺寸调度、热键 press/release、注入焦点与完整快捷键释放、对应策略测试和文档，没有覆盖或回退既有改动，尚未 add/commit/push。判断当前实际状态时仍以 `git status --short` 为准。

## 文档与源码冲突

历史上项目入口 `AGENTS.md` 中“24 个 app Swift / 3 个 XCTest”曾与源码冲突，后续已修正为 26/4；新增 `FlotisDesign.swift` 后为 27/4，本轮增加语言策略测试后同步为 27/5。此前文档声称存在 v0.4 tag，但 `git tag --list` 为空，现有文档继续区分提交信息和 tag。后续若文档再次与源码、`project.yml` 或测试冲突，仍以可构建的当前源码与工程配置为准。
