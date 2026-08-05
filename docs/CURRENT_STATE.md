# CURRENT_STATE

最近一次自查日期：2026-08-04

## 当前真实状态总览

- Flotis V0.8 是 macOS 悬浮语音输入胶囊；`project.yml` 当前声明主 App `MARKETING_VERSION=0.8.0`、build `1`，隔离输入法 `MARKETING_VERSION=0.1.0`、build `3`。仓库当前没有 Git tag，历史中的 `v0.1`–`v0.7` 是提交信息而非 tag。
- XcodeGen 工程现在包含 `Flotis`、`FlotisInputMethod` 两个 application target，以及 `FlotisTests`、`FlotisInputMethodTests` 两个 unit-test target。主 app 仍有 27 个 Swift 源文件与 5 个测试源文件；隔离输入法有 4 个 Swift 源文件与 1 个测试源文件；无第三方依赖。
- app 为 `LSUIElement=YES`，无 Dock 图标；`LSMultipleInstancesProhibited=YES` 防止两个 Flotis 进程争抢全局热键；deployment target 为 macOS 13.0。
- 六个版本化转写 adapter 仍完整注册：Apple on-device、OpenAI-compatible HTTP、OpenAI Realtime GA、DashScope Paraformer、Volcengine BigASR、GLM ASR HTTP/SSE。当前 Settings 展示层只开放 OpenAI Compatible；其余 connection、adapter、preset、迁移与 runtime 能力仅暂时隐藏，没有被删除。全新安装仍只创建 Apple connection。
- V0.8 主链路为同一语音热键依次执行“开始录音 → 停止并等待转写 → 审阅/编辑 → 复制并返回小胶囊”。第三次热键和审阅确认按钮都只写系统剪贴板；成功后清空会话、回到 `idle`，审阅框按已保存的位置锚点缩回小胶囊且 panel 保持可见，失败则保留文字/审阅态供重试。当前不捕获目标 app、不请求 AX、不发送 `CGEvent`/`⌘V`；旧 `ClipboardPasteInjector` 与 `AccessibilityPermission` 仅作为不可达兼容源码保留。命令网格、命令设置 tab 和命令热键也仍退出运行入口，旧 `commands.json` 未删除。
- connection 配置 v3、应用自管凭据隔离、v1/v2 只读迁移、OpenAI Compatible 新增/编辑 UI、Test Connection 和可取消语音会话保持不变。
- App 界面语言自动读取第一首选系统语言：明确的简体中文标识使用简中，繁体中文、英文及其他语言统一回退英文；不提供手动语言开关，也不改变 provider 的转写语言。
- 2026-07-26 已对 OpenAI Compatible Settings 最终源码运行 `xcodegen generate`、完整 Debug build 和 unit tests：最终构建成功，49 tests、0 failures；此前旧版工作台曾在 macOS 26.5 Light appearance 打开检查，但本轮精简表面尚未运行态目视。
- 2026-07-27 已完成胶囊紧凑与边缘精修：AppKit 成为唯一外壳裁切 owner，SwiftUI 改为向内描边；`xcodegen generate`、独立 Debug build 和 49 个 unit tests 均成功，并在 macOS 26.5.2 运行态对比了 AX 警告状态。
- 2026-07-28 待机胶囊最终微调为 `120×56`：只显示录音、设置两个按钮及下方灰色语音快捷键符号，不再显示品牌名或启动说明；相较上一版 `128×56` 只收窄 8 pt，高度、按钮尺寸、10 pt 按钮间距和 11 pt 系统次级灰快捷键均保持不变，避免再次变大或牺牲可读性。该比例已通过 XcodeGen、独立 Debug build 与 49 个 unit tests；按用户要求没有启动 App 或打开 Settings，因此最终观感留给用户在常用构建中确认。缺少 AX 权限不会在尚未执行注入时主动撑大胶囊，权限状态仍在 Settings 醒目展示，实际注入失败后仍会展开明确提示和系统设置入口。录音、处理、审阅和其他错误态继续保留必要状态信息。Settings 共用页头新增醒目的双语一键退出按钮，使用 AppKit 标准 terminate 路径。
- 2026-07-28 针对浅色模式的尖角矩形高光和双边毛躁再次收敛外壳：`NSVisualEffectView.maskImage` 现在用可拉伸圆角 alpha mask 同时约束 material 与窗口服务器阴影，CALayer mask 只负责裁切 hosted subviews；窗口显示和静态尺寸切换后会重新计算阴影。SwiftUI 已移除整圈 1 pt separator 描边，避免它与 material/原生阴影叠成明显双边。尺寸、圆角值、按钮和所有语音状态未改。XcodeGen、独立 Debug build 与 49 个 unit tests 通过；没有启动 App 或打开 Settings，因此浅色模式最终像素观感仍待用户在常用构建中确认。
- 2026-07-30 已移除全部系统钥匙串运行时依赖：删除 `KeychainSecretStore`、`import Security` 与所有 `SecItem*` 调用，生产链路统一改用 `LocalSecretStore`。API key 明文只写入 `~/Library/Application Support/Flotis/secrets.json`，以版本化 JSON、目录 fd、`openat(..., O_NOFOLLOW)`、同目录 `fsync + renameat` 原子替换、进程内共享锁与 `.secrets.lock` 跨进程写锁、目录 `0700` / 文件 `0600` 管理；跨进程锁只在单调时钟下重试最多 500 ms，避免另一进程卡死时永久冻结 UI。符号链接、非普通文件、非当前用户所有、损坏或超过 1 MiB 的文件会被拒绝且不会覆盖。connection v3 继续只保存 `apiKeyReference`，因此 schema 与六个 adapter 不变。Flotis 不读取、迁移或删除旧钥匙串条目，已有用户需在新构建中重新输入一次 API key；正在运行的旧构建必须退出后，新实现才会生效。XcodeGen、独立 Debug build 与 53 tests 全部通过，最终 dylib 无 Security.framework 直接链接或 `SecItem*` 未定义符号；本轮未启动 App 或接触真实凭据。
- 2026-07-30 已完成胶囊交互稳定性收敛：待机仍为 `120×56`，普通工作态改为 `188×56`，错误/提示态统一 `280×56`，审阅态改为 `420×160`，状态文案不再额外增加高度。尺寸请求会合并为最后一次，并始终基于启动时屏幕的固定底边锚点计算；显示面板和屏幕参数变化时会重新核对锚点，全窗口背景不再可拖动。齿轮直接打开 AppDelegate 持有且复用的独立 `760×560` 设置窗口，不再依赖字符串 selector 或胶囊 sheet；可见配置只剩 Model、Endpoint、API Key 和必要动作，connection name/多连接管理隐藏，保存后自动设为当前 OpenAI Compatible connection。审阅框改为原生 `NSTextView`，支持选择、编辑、右键与 `⌘C`，并增加无文字标签的复制全部按钮。Carbon 热键改为独占注册并监听 press/release，按住不再重复穿越状态；stopping/transcribing 中的额外按键改为忽略；注入前等待 `⌘⌥⇧R` 的修饰键和主键 R 全部释放，并要求 Flotis 自身 key window 已让出键盘焦点。XcodeGen、独立 Debug build 与 57 tests、0 failures 通过；未启动 App，运行态视觉、焦点和跨 Space 行为仍需新构建真机确认。
- 2026-08-01 已修复用户反馈的四项交互问题：胶囊恢复整窗背景拖动，状态尺寸变化保持拖动后的水平中心与底边并钳制到当前可见屏幕；AX 入口区分非提示式状态检查与用户发起的提示式授权请求，`run.sh` 不再删除 DerivedData 或重置 Accessibility TCC，并改用稳定临时 DerivedData；语音会话在开始录音前捕获目标 app，审阅/重试沿用同一已核验 PID，注入返回明确失败类型并用 PID 定向发送 `⌘V`；Settings 重构为可缩放 `820×600`（最小 `760×540`）窗口，以“通用 / 转写”侧栏和职责卡片整理权限、快捷键、连接、凭据、高级参数与连接测试。已在 Light appearance 运行态检查胶囊拖动及两页 Settings，修正过右侧滚动导致页头/侧栏被推入标题栏的问题；最终 `xcodegen generate`、Debug build 与 61 tests、0 failures 通过。未授予系统 AX 权限、未采集麦克风、未读取或保存真实 API key，也未向真实目标文本框发送 `CGEvent`，因此真实端到端注入仍需用户授权后复测。
- 2026-08-01 按用户“先不要改现在的”要求新增了完全隔离的 `FlotisInputMethod` InputMethodKit 接口：独立 `IMKServer`/`IMKInputController` target 可向当前 IMK 文本客户端直接 commit；普通按键透传。version `1` 请求包含随机 session UUID，并拒绝错误版本、空白、超过 1 MiB 或旧焦点请求；service 不持久化/记录文本且只弱持有当前 endpoint。新 target Debug build 成功，8 tests、0 failures；原 `Flotis` scheme 回归仍为 61 tests、0 failures。没有修改本轮开始时已有的 `Flotis/` 业务源码，没有安装/启动输入法、切换输入源或接入现有语音链路，因此系统发现、真实客户端兼容和跨进程传输仍未验证。
- 2026-08-02 已按用户明确要求完成输入法本地签名、安装与运行态冒烟：target 改为 `LSBackgroundOnly=YES`，补齐顶层/模式级 TIFF 输入源图标，并把 build 提升到 `3`。首次安装后的运行态崩溃定位到 legacy `IMKServer(name:controllerClass:delegateClass:)` 在 nil delegate 下的初始化路径；入口已改用从 Info.plist 解析 controller/delegate 的 `IMKServer(name:bundleIdentifier:)`，最终产物通过严格 ad-hoc 签名校验，安装到 `~/Library/Input Methods/FlotisInputMethod.app` 后可稳定保持后台运行且不再生成崩溃报告。`TISRegisterInputSource` 返回成功，但当前登录会话的输入源缓存仍未列出 bundle/source；受 SIP 保护的 `imklaunchagent` 不能原地重启，因此需要用户注销并重新登录后才能启用 `Flotis Voice` 并继续 TextEdit/客户端提交矩阵。最终输入法 8 tests 与主 App 61 tests 均为 0 failures；尚未把“可启动”描述为“真实客户端已收到文字”。
- 2026-08-03 已将 idle 录音按钮替换为用户提供的白圆、六条黑色圆角声波图：原图保存在 `docs/assets/voice-waveform-button-reference.png`，App 使用 `Assets.xcassets/VoiceWaveformButton.imageset` 的 1x/2x/3x 版本。修改只作用于 idle 的开始录音视觉，既有 `30×30` 点击区域、Start 无障碍标签/帮助、快捷键与 action 未变，stop/cancel/retry/inject 等状态图标继续沿用原逻辑。运行态视觉对比和 Design QA 已通过；XcodeGen、主 App/输入法 Debug build、主 App 61 tests 与输入法 8 tests 均通过。视觉验收没有点击按钮，因此未申请麦克风权限、未启动 provider，也未触发 AX/`CGEvent`。
- 2026-08-03 已将胶囊设置按钮的 SF Symbol 替换为用户提供的白色齿轮图：`1139×1138` 原图原样保存在 `docs/assets/settings-gear-button-reference.png`，后续比例微调将 `Assets.xcassets/SettingsGearButton.imageset` 收到 24×24、48×48、72×72 三档资源。既有 `30×30` 点击区域、Settings 无障碍标签/帮助与打开设置窗口 action 未变。运行态确认图稿与录音钮视觉重量平衡，并实际完成 Settings 打开/关闭交互；最新 Design QA passed，XcodeGen、主 App/输入法 Debug build、主 App 61 tests 与输入法 8 tests 均通过。没有修改设置内容、凭据、权限或任何语音/注入链路。
- 2026-08-03 已完成胶囊比例与 Liquid Glass 精修：idle 从 `120×56` 轻收为 `116×54`，双按钮间距由 10 pt 收为 8 pt，白色齿轮可见图稿由 26 pt 收为 24 pt，两个控制仍保留原 `30×30` 点击区域。编译器支持且运行于 macOS 26+ 时，整个 panel 外壳改由 20 pt 圆角的原生 `NSGlassEffectView` 承载，并增加轻微深色对比层；macOS 27+ 启用原生 interactive glass，旧系统继续使用既有 `.popover` `NSVisualEffectView`、可拉伸 alpha mask 与原生阴影。普通工作态 `188×56`、错误/提示态 `280×56`、reviewing `420×160` 以及动作、快捷键、无障碍、拖动/resize 和语音状态机未改。真实运行态前后/齿轮局部对比与 Settings 打开关闭通过，最终主 App 61 tests、输入法 8 tests 和两 application build 均通过。
- 2026-08-04 曾按用户当时的决定把三段式最终动作改成“复制并关闭”：`VoiceHotkeyAction.reviewing` 当时改为 `copyAndClose`，`VoiceInputController` 通过可替换 clipboard writer 原样写入审阅文本，成功返回 panel close outcome 并重置会话，失败保留 reviewing/文本。该阶段主 App 63 tests、输入法 8 tests 均为 0 failures；同日稍后的“复制并返回小胶囊”决定已取代关闭行为。
- 2026-08-04 已修复审阅框取消后小胶囊不能回到展开前位置的问题：`FloatingPanelController` 现在独立保存用户位置的水平中心/底边锚点，reviewing 大框为保持可见而产生的临时钳位不会再覆盖该锚点；只有用户主动拖动窗口才更新它，因此 idle→reviewing→取消会恢复原胶囊位置，在 reviewing 中主动拖动后则以新位置为准。新增靠屏幕右缘展开/钳位/缩回回归用例；XcodeGen、两个 application Debug build、主 App 64 tests 与输入法 8 tests 均通过。本轮未启动 App，真实拖动与取消组合仍需当前构建运行态确认。
- 2026-08-04 用户随后明确要求删除成功后的隐藏胶囊步骤：reviewing 现在映射为 `copyAndReturn`，第三次全局热键与右侧“复制并返回”按钮都调用同一同步复制路径；成功后推进 generation、清空审阅文本并回 `idle`，不再产生 close outcome 或调用窗口关闭回调。状态尺寸变化会直接把审阅框缩回保存锚点处的 `116×54` 小胶囊。`xcodegen generate`、两个 application Debug build、主 App 64 tests 与输入法 8 tests 均通过；物理三次热键与真实剪贴板/缩回组合仍待当前构建人工验证。
- 2026-08-04 已修正“调用了原生 API 但看起来仍像普通磨砂”的 Liquid Glass 问题：根因是 `NSGlassEffectView(style: .regular)` 又被设置了整面黑色 `tintColor`，SwiftUI hosting root 同时铺了 18% 黑色背景，两层共同压平了系统高光、折射与自适应表现。当前 macOS 26+ 路径已移除这两层，只保留原生 `.regular` glass、20 pt 圆角和 macOS 27+ `effectIsInteractive`；旧系统 material fallback、尺寸、图稿、点击区域、快捷键、拖动与状态机均未改。签名隔离 Debug 预览已在真实 macOS 运行态检查，胶囊恢复系统亮色自适应材质和边缘高光；窗口级截图会把透明背景单独合成到白底，不能作为跨背景折射的像素证明。`xcodegen generate`、主 App/输入法 Debug build、主 App 64 tests 与输入法 8 tests 均通过。视觉核验未点击任何控件，未录音、未访问 provider/凭据、未调用 AX，也未安装或启动输入法。
- 2026-08-04 用户先放弃标准 F5 方案并短暂改用 `⌃⌥⇧W`，随后又将固定 voice hotkey 简化为当前的 `⌃⌥A`（Carbon virtual key `0`，Control+Option）。胶囊辅助标签与通用 Settings 都从同一 descriptor 显示当前组合，Settings 说明保持与具体键位解耦的通用三段式文案。start/stop/copy-and-return、Carbon 独占注册与 press/release 去重均未改，不修改系统键盘/听写设置，也不重新接入旧注入器。`xcodegen generate`、两个 application Debug build、主 App 65 tests 与输入法 8 tests 均通过；物理组合键与三次真实触发尚待当前构建人工验收。
- 2026-08-04 用户又用新的 `1061×1061` 透明黑色八齿齿轮替换了固定白色复杂齿轮。原图已更新到 `docs/assets/settings-gear-button-reference.png`，`SettingsGearButton.imageset` 改为 16/32/48 px；idle 设置按钮在 SwiftUI 中以 28 pt 白圆承载 16 pt 黑齿轮，与旁边 28 pt 白圆黑声波按钮形成同一视觉语法。此前为旧白齿轮试验的深色轮廓/衬底未保留，整块原生 glass 也没有重新加 tint。真实白底运行态截图确认两枚图标都清晰，Settings 窗口打开/关闭正常；XcodeGen、两个 application Debug build、主 App 65 tests 与输入法 8 tests 均通过。
- 2026-08-04 按用户最新比例要求，idle 胶囊只在横向由 `116×54` 再收为 `108×54`，高度、两个 `30×30` 点击区域、8 pt 间距、图稿、action 与无障碍标签均未改变；下方快捷键由 11 pt Medium 系统 Monospaced/动态次级灰改为 12 pt Semibold 系统 Monospaced/动态主文字色。签名隔离预览的真实窗口截图精确为 `108×54`，两枚按钮未裁切或拥挤，`⌃⌥A` 更清楚，AX tree 仍暴露 Start、Settings 与完整快捷键说明；预览后已正常退出，未触发录音或修改设置。`xcodegen generate`、两个 application Debug build、主 App 65 tests 与输入法 8 tests 全部通过。
- 2026-08-04 根目录新增的 `Flotis.icon` 已作为主 App 的原生 Icon Composer 资源接入：XcodeGen 将它生成为 `wrapper.icon` resource，主 target 固定 `ASSETCATALOG_COMPILER_APPICON_NAME=Flotis`。Debug/Release 产物均生成 `Flotis.icns` 与 `Assets.car`，最终 Info.plist 自动包含 `CFBundleIconFile/CFBundleIconName=Flotis`；编译后的系统图标为白色圆角底、灰色对话框与声波。ad-hoc Release `0.8.0 (1)` 已通过 `codesign --verify --deep --strict`，完整安装到 `/Applications/Flotis.app`、注册 Launch Services 并成功启动；安装副本的可执行文件和 `Flotis.icns` 与 Release 产物逐字节一致。主 App 65 tests、输入法 8 tests 与两个 Debug application build 全部通过；独立输入法安装副本未改动。
- 此前用户曾用真实 OpenAI-compatible connection 完成录音、转写并进入 reviewing，且在旧 AX 注入版本中点击胶囊“输入”成功；该历史结果不代表 2026-08-04 当前复制并返回流程已做真机端到端验证。

## 已有能力

| 能力 | 入口 / 关键类型 | 自动化覆盖 | 当前验证 |
|---|---|---|---|
| V0.8 悬浮语音胶囊 | `FloatingPanelController` / `FloatingPanelView` / `FlotisDesign` | Debug build + 65 tests；无 UI/snapshot test | macOS 26+ 原生自适应 `.regular` Glass 的运行态外观已检查；四档静态尺寸、背景拖动、逻辑位置锚点及钳位后缩回恢复已构建并有策略测试；`⌃⌥A` 描述符已受测，物理三次热键/系统剪贴板/缩回和真实拖动取消仍待真机验证 |
| 隔离输入法提交接口 | `FlotisInputMethod` / `FlotisInputController` / `FlotisInputMethodService` | Release build + 严格签名校验 + 8 session/提交策略 tests | build `3` 已 ad-hoc 签名并安装，后台启动冒烟稳定；当前登录会话尚未发现输入源，需重新登录后做真实 IMK client 矩阵；未连接主 App |
| OpenAI Compatible Settings | `FlotisSettingsWindowController` / `SettingsView` / `SpeechProviderSettingsView` | 构建覆盖；provider/secret 行为由配置单测覆盖 | 通用/转写两页、固定侧栏页头、右侧滚动与窗口缩放已做 Light 运行态目视 |
| 简中 / 英文自动适配 | `AppLanguage` / `UIStrings` / `InfoPlist.xcstrings` | 首选语言矩阵、双语选择与权限资源编译 | 构建/单测通过；双语运行态排版待目视 |
| Carbon 全局热键 | `HotkeyManager` / `VoiceHotkeyAction` | 独占注册、press/release 门控、start/stop/copyAndReturn 与成功/失败策略单测 | 开始/停止/进入 reviewing 曾真机触发；第三次复制并返回待当前构建真机复测 |
| 旧命令数据兼容 | `CommandStore` / `commands.json` | 旧策略单测 | 不再展示或注册命令热键 |
| 旧安全剪贴板注入兼容 | `ClipboardPasteInjector` | 目标重激活、PID 定向、失败类型、队列容量、过期与完整快捷键释放策略单测 | 当前生产入口不可达，不再要求 AX 真机复测；若未来明确重新接入，原安全边界仍必须完整回归 |
| Apple Speech 设备端转写 | `AppleSpeechTranscriber` / `AppleTranscriptAccumulator` | 空 final、停顿分段、重叠纠错与相邻片段单测 | 真机复测待验 |
| OpenAI Realtime GA 转写 | `OpenAIRealtimeTranscriber` | 多 item 乱序、partial/final 组装及 scripted session/append/commit/terminal | 真实 key 待验 |
| DashScope Realtime | `DashScopeParaformerRealtimeTranscriber` | 重复句与文本边界单测 | 真实 key 待验 |
| Volcengine BigASR Realtime | `VolcengineBigASRRealtimeTranscriber` | schema、registry/runtime plan 单测 | 真实 key 待验 |
| OpenAI-compatible HTTP multipart | `OpenAIHTTPTranscriber` | 自定义 endpoint/model、WAV/M4A multipart、严格响应、取消边界 | OpenRouter 真实 happy path 已进入 reviewing；失败与边界矩阵待验 |
| GLM HTTP SSE | `GLMASRHTTPTranscriber` | Content-Type、JSON event、delta/done/`[DONE]` 与错误脱敏 | mock 通过；真实 key 待验 |
| 统一 connection / adapter registry | `TranscriptionConnection` / `TranscriptionAdapterRegistry` | 6 个唯一 adapter 与 3 类通用 runtime plan | 通过 |
| Connection Test | `TranscriptionConnectionTester` | 合成音频、HTTP 与 Realtime mock、空文本合法、任意形态 Key 回显脱敏 | 通过 |
| Provider v1/v2→v3 迁移 | `SpeechProviderSnapshotMigration` / `SpeechProviderStore` | 六类、自定义实例、排序、active、引用、v2 LKG | 通过 |
| 应用自管 API key 存储 | `LocalSecretStore` | 跨实例并发/持久化、替换/删除、`0700`/`0600`、损坏文件与符号链接拒绝；既有 reference 轮换/回滚测试 | 配置套件与当前完整 65 tests 均通过；真实用户路径待新构建首次保存 |

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
- 主窗口仍是屏幕底部居中的无标题小胶囊；外壳为 20 pt continuous corner。macOS 26+ 使用原生 `NSGlassEffectView(style: .regular)` 的系统自适应材质，不再设置整面黑色 `tintColor`，SwiftUI hosting content 也不再铺全表面深色背景，因此系统高光、折射与背景采样不会被自定义填充压平；macOS 27+ 的 glass 会响应交互。macOS 13–25 继续由 AppKit visual-effect material mask 负责圆角材质与原生窗口阴影，CALayer mask 裁切 hosted subviews，SwiftUI 不绘制整圈外框。待机态不显示品牌名、状态圆或说明文字，只保留用户提供的 28 pt 白圆黑声波录音图、28 pt 白圆/16 pt 黑色八齿齿轮设置图和下方 12 pt Semibold 系统 Monospaced 动态主文字色快捷键符号；当前可达非待机状态用图标、文字和有限语义色明确表达录音、处理、审阅、复制错误或失败。
- idle 尺寸为 `108×54`，普通非 idle compact 为 `188×56`，错误/提示态为 `280×56`，reviewing 为 `420×160`；idle 之外的非审阅态固定 56 pt 高，不再因状态文案追加 42 pt。idle 的双按钮水平间距为 8 pt，下方快捷键使用 12 pt Semibold 系统 Monospaced 与动态主文字色。尺寸请求只应用最后一次；窗口首次显示在屏幕底部中央，之后允许整窗背景拖动。用户选择的中心/底边由独立逻辑锚点保存，尺寸变化仍钳制到可见屏幕，但临时钳位不覆盖锚点，所以审阅框取消缩回时可恢复展开前位置；用户主动拖动任一尺寸窗口才更新锚点。
- 齿轮直接打开 AppDelegate 持有并复用的可缩放 `820×600` 设置窗口（最小 `760×540`）；不再从胶囊弹出 sheet，也不依赖字符串 selector。左侧只保留产品标识、“通用 / 转写”与退出；通用页集中三段式快捷键和拖动说明，不再展示 AX，转写页按连接、凭据、高级选项与测试分卡。可见转写主表单仍只有 OpenAI Compatible 的 Model、Endpoint（内部 Base URL + Path）、API Key、Test/Save/Cancel，只有自定义 host 才显示必要安全确认，Language/Prompt/Temperature 收入折叠高级区。保存成功后自动设为当前 OpenAI Compatible connection。退出仍走 `NSApplication.shared.terminate(nil)`；旧 `.injecting` 退出保护保留但当前不可达。
- `⌃⌥A` 在 idle/failed 开始录音，在 recording/streaming 停止，在 reviewing 复制并返回；requesting/connecting 可取消，stopping/transcribing/injecting 的重复按键忽略。Carbon 使用独占注册和 press/release 门控，按住组合键只触发一次。
- reviewing 的第三次 Carbon hotkey 不再等待修饰键释放或恢复目标焦点，而是同步把原样审阅文本写入剪贴板；写入成功后 controller 清空会话并回 `idle`，panel 保持可见并按逻辑位置锚点缩回小胶囊，下一次 voice hotkey 直接开始新录音。
- 转写 adapter 返回最终文本后释放录音/网络 runtime，再进入 `reviewing`。原生审阅文本框支持编辑、鼠标选择、右键与 `⌘C`，工具栏有复制全部、取消和复制并返回三个图标按钮。
- 复制失败时保持 reviewing、panel 与修改文字并显示错误；成功后才推进 generation、清空文字并回 idle。`ClipboardPasteInjector` 不再由当前产品入口调用。
- App 启动时只向 `HotkeyManager` 注册 panel/voice 两个固定热键；命令 singleton 不再由 `AppDelegate` 装配，旧命令文件不读取、不改写、不删除。

## Apple 转写累积修复（2026-07-12）

- 真机发现 Apple 短句可能先返回有效 partial、再返回空 final，旧实现无条件 `transcript = value`，会把“你好”等有效结果清空并触发“没有可输入的转写文字”。
- 同一覆盖逻辑也会在停顿后的新结果只包含后段时丢失前段。该问题位于 `AppleRecognitionState`，不是 reviewing、焦点捕捉或 `ClipboardPasteInjector`。
- 新 `AppleTranscriptAccumulator` 使用 `SFTranscriptionSegment.timestamp/duration` 合并：重叠时间范围视为同一假设修订并替换，不重叠范围按语音顺序追加，空结果不抹除已有非空文本。
- Apple partial/final handler 现在统一发布 accumulator 的完整文本。OpenAI Realtime、DashScope、GLM 已有 item/segment/delta 累积；Volc 的 full-result 路径会忽略空 transcript，因此未改其他 provider 协议实现。

## 尚未完成 / 需要人工确认

- **输入法运行态与接线**：`FlotisInputMethod.app` build `3` 已使用本地 ad-hoc 身份签名、复制到用户 Input Methods 目录并完成稳定启动冒烟；它仍没有固定 Apple Development Team/代码身份，当前登录会话的 TIS 缓存也尚未发现该输入源。用户注销并重新登录、启用 `Flotis Voice` 后，仍需完成 TextEdit/浏览器等真实客户端矩阵。主 App 到输入法的认证本地 IPC 尚未设计和实现，当前不能把“已安装且可启动”描述为“语音已经能通过输入法上屏”。
- **当前复制返回真机端到端**：三次物理 Carbon 热键、审阅编辑后的原样系统剪贴板内容、成功缩回原位置小胶囊、复制失败时 panel 保留以及跨 Space 行为无法由当前 unit tests 完全证明。当前路径不涉及 `CGEvent`、AX 或目标 app 激活。
- **Apple 真机复测**：需要再次验证“你好”短句、两个词中间静音 3–5 秒、连续纠错与重复词；自动化只证明累积策略，不能替代真实 `SFSpeechRecognizer` 回调序列。
- **胶囊编辑/复制焦点**：原生 `NSTextView.needsPanelToBecomeKey`、复制全部按钮和 copy-and-return 状态路径已构建通过，但鼠标选区、`⌘C`、右键 Copy 及“编辑后按第三次全局热键复制并返回”的真实剪贴板/窗口组合仍需真机验证。
- **视觉无障碍与兼容矩阵**：macOS 26.5 Light appearance 的旧版 Settings 工作台曾完成目视；本轮 OpenAI Compatible 精简后的空态、列表、表单与隐藏 active provider 状态尚未运行态目视。Dark、Reduce Transparency、Increase Contrast、macOS 13 fallback、所有 voice state 及长错误/长转写仍需人工矩阵。
- **双语运行态排版**：语言解析和当前完整 65 个主 App 单测已通过，权限 String Catalog 也已编译检查；本轮未分别以简中、英文和其他语言启动 App 做完整目视，因此“Copy and return”英文在审阅态的实际辅助标签及通用语音快捷键 Settings 说明仍需人工确认。
- **真实供应商联调**：OpenAI、DashScope、Volcengine、GLM 的认证、服务端事件顺序、错误包和限流行为需分别使用有效账号验证；按本轮用户要求未创建、读取或使用真实 API key，也未发出真实供应商请求。
- **签名/分发**：主 App 当前安装到 `/Applications/Flotis.app` 的 Release `0.8.0 (1)` 与输入法 Release build `3` 都使用 ad-hoc 签名，没有 Developer Team、notarization 或正式发布流水线；ad-hoc 足以做本机启动冒烟，但不是稳定开发/发布身份。重复重编译时 TCC 或输入源缓存可能把产物识别为新代码身份；要让授权与重复安装更稳定，需要在 Xcode 选择固定 Apple Development Team 后用同一 bundle ID 构建。
- **`VoiceInputMode` 疑似 vestigial**：`AppState.voiceMode` 仍存在，但真实分派依据是 adapter registry 返回的通用 runtime plan。
- **部分 UI 状态不持久化**：`isPanelVisible`、`selectedSpeechLocale`、`voiceMode` 重启后重置；是否应持久化仍为产品决策。
- **无 README/CHANGELOG**：项目入口文档仍以 `AGENTS.md` 与 `docs/` 为主。

## 当前风险边界

- 当前 `SystemTranscriptClipboardWriter` 的 success 只表示 `NSPasteboard.setString` 返回成功；物理热键是否按预期让审阅框缩回原位置小胶囊仍需运行态观察。旧 `ClipboardPasteInjector` 当前不可达；若未来重新启用，其 success 仍只表示目标核验、事件 post 与剪贴板结局安全，不证明目标控件已消费粘贴。
- `FlotisInputMethodService` 的 success 同样只表示当前 IMK client 存在且调用了 `insertText`；即使输入法已安装并可稳定启动，在重新登录后的目视客户端矩阵完成前仍不宣称目标控件已显示文本。session UUID 只解决焦点时序，不等于未来 IPC 的调用方认证。
- 为支持 Carbon 全局热键与 `CGEvent`，app 当前未沙箱化。正式分发前必须单独评估 hardened runtime、签名和 notarization。
- 第三方协议已有静态 schema、mock transport、超时/终态保护与严格响应解析，但公开服务端协议可能演进；升级 API 前必须重跑自动化与真实 provider 矩阵。
- `run.sh` 使用固定的临时 DerivedData 做增量构建，不再删除缓存或执行 `tccutil reset Accessibility`；脚本会在产物为 ad-hoc 签名时提示配置稳定 Apple Development 签名。

## 工作区状态

2026-08-01 四项修复开始时，工作树仅有用户已有的 Xcode `UserInterfaceState.xcuserstate` 改动；四项修复的业务源码、测试、脚本与文档随后留在未提交工作树。输入法接口及 2026-08-02 安装验证开始时这些改动均已存在，本次没有覆盖或回退它们，也没有改动既有 `Flotis/` 或 `FlotisTests/` 源码；本次新增 `FlotisInputMethod/`、`FlotisInputMethodTests/`，并更新 XcodeGen 工程规格/生成工程、输入法元数据/入口/图标及文档。已安装的 build `3` 位于用户 Input Methods 目录；没有 add/commit/push，实际状态仍以 `git status --short` 为准。

2026-08-03 两次按钮视觉替换在上述未提交工作树上追加了 `Flotis/Assets.xcassets`、两份 `docs/assets/*-reference.png`、`design-qa.md` 与 `FloatingPanelView.swift` 的定向 Presentation 修改，并重新生成工程与更新相关文档；没有覆盖或回退此前业务改动，也没有 add/commit/push。

2026-08-04 复制并关闭行为在上述未提交工作树上定向修改 `VoiceInputMode.swift`、`VoiceInputController.swift`、`FlotisApp.swift`、`FloatingPanelController.swift`、`FloatingPanelView.swift`、`VoiceSettingsView.swift`、`UIStrings.swift`、`HotkeyAndInjectionPolicyTests.swift` 及常驻文档；旧注入器、输入法接口、provider 协议和 secret store 未改。为解除 `LSMultipleInstancesProhibited` 测试阻塞，只退出了 PID 68934 的临时 Liquid Glass 预览实例；没有 add/commit/push。

2026-08-04 胶囊位置恢复修复继续在同一未提交工作树上定向修改 `FloatingPanelController.swift`、`HotkeyAndInjectionPolicyTests.swift` 与相关常驻文档；没有改动转写、剪贴板、输入法、provider、secret store 或脚本，也没有 add/commit/push。

2026-08-04 复制并返回修改继续定向更新 `VoiceInputMode.swift`、`VoiceInputController.swift`、`FlotisApp.swift`、`FloatingPanelController.swift`、`FloatingPanelView.swift`、`UIStrings.swift`、`HotkeyAndInjectionPolicyTests.swift` 与常驻文档；移除了生产路径的 panel close outcome/回调，未改旧注入器、输入法接口、provider、secret store 或脚本。完整主测试最初被 Xcode 中仍在调试的旧 Flotis 唯一实例占用，结束该实例对应的 `debugserver` 后 64 tests 全部通过；没有重新启动 App，也没有 add/commit/push。

2026-08-04 快捷键修改继续在同一未提交工作树上定向更新 `PromptCommand.swift`、`UIStrings.swift`、`HotkeyAndInjectionPolicyTests.swift` 与常驻文档；短暂的 F5 与 `⌃⌥⇧W` 方案已被当前 `⌃⌥A` 取代。最新一次只更新 descriptor、快捷键契约测试与常驻文档，通用 `UIStrings` 不需再改；没有改状态机、provider、输入法、secret store、脚本或任何系统键盘偏好。重新生成工程后两个 application build、主 App 65 tests 与输入法 8 tests 全部通过；没有手动启动产品实例、录音、系统听写或输入法，也没有 add/commit/push。

2026-08-04 最新齿轮替换继续在同一未提交工作树上定向更新 `FloatingPanelView.swift`、`SettingsGearButton.imageset`、设置图标参考图与常驻文档。临时视觉 build 只用于白底图标与 Settings 打开/关闭检查，随后已正常退出；没有点击录音、改设置、访问 provider/凭据/权限，也没有改状态机、输入法、脚本或 add/commit/push。

2026-08-04 应用图标安装继续在同一未提交工作树上接入用户新增的根目录 `Flotis.icon`，定向修改 `project.yml`、XcodeGen 生成工程与常驻文档。主 App ad-hoc Release 已安装到 `/Applications/Flotis.app` 并启动；没有覆盖或重新安装 `~/Library/Input Methods/FlotisInputMethod.app`，也没有 add/commit/push。

## 文档与源码冲突

历史上项目入口 `AGENTS.md` 中“24 个 app Swift / 3 个 XCTest”曾与源码冲突，后续已修正为 26/4；新增 `FlotisDesign.swift` 后为主 app 27/4，增加语言策略测试后为 27/5。输入法接口新增后必须分别记录主 app 的 27+5 与输入法的 4+1，不能把跨 target 重复编译的 protocol/service 误算成额外文件。此前文档声称存在 v0.4 tag，但 `git tag --list` 为空，现有文档继续区分提交信息和 tag。后续若文档再次与源码、`project.yml` 或测试冲突，仍以可构建的当前源码与工程配置为准。
