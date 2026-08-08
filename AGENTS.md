# Flotis 项目常驻上下文

本文件继承 `/Users/vita/Vitemis/AGENTS.md` 中的 Vitemis 通用 Agent 规则。若本文件与通用规则冲突，在不违反系统和用户指令的前提下，以更具体、更严格的项目规则为准。

本文是 AI Agent 每轮进入本仓库时的入口文件。执行任何代码修改、配置修改、构建脚本修改或测试源码修改之前，必须先按顺序阅读并核对下列文档：

0. `/Users/vita/Vitemis/AGENTS.md`
1. `docs/CURRENT_STATE.md`
2. `docs/PROJECT_MAP.md`
3. `docs/ARCHITECTURE.md`
4. `docs/DO_NOT_BREAK.md`
5. `docs/TESTING.md`
6. `docs/NEXT_TARGET.md`（如果存在）

如果文档与源码、工程配置、测试或脚本冲突，必须以当前源码和配置为准，并在最终报告中明确指出冲突位置和采用源码为准的原因。

## 工作目录检查

每轮开始先在项目根目录执行：

```sh
pwd
git rev-parse --show-toplevel
git status --short
```

要求：

- `pwd` 与 `git rev-parse --show-toplevel` 必须指向同一个仓库根目录：`/Users/vita/Vitemis/Flotis`。
- 如果当前目录不是 Git root，停止修改，只报告路径问题。
- 读取 `git status --short` 后，先区分用户已有改动与本轮计划改动；不得覆盖、回退或清理用户已有改动。

## 修改边界

本仓库包含 macOS 悬浮语音输入胶囊与隔离的 InputMethodKit 输入法接口（XcodeGen 两个 application target + 两个 unit-test target）。现有 `Flotis` app 保持 `LSUIElement=YES`、无 Dock 图标，共 31 个 Swift 源文件和 6 个 XCTest 源文件；`FlotisInputMethod` 为 `LSBackgroundOnly=YES`，有 4 个 Swift 源文件、SVG/TIFF 输入源图标，独立策略测试目录有 1 个 XCTest 源文件。无第三方依赖。

未来常规任务可以按用户要求修改业务源码；但在只要求项目自查或文档更新的任务中，只允许修改：

- `AGENTS.md`
- `docs/` 下的项目说明文档

除非用户明确要求，不要修改：

- `Flotis/`（全部 31 个 app 源文件）
- `FlotisInputMethod/`（输入法接口源码与生成的 Info.plist）
- `project.yml`
- `run.sh`
- `Flotis.xcodeproj/`

## 禁止事项

- 不执行破坏性 Git 操作：`git reset --hard`、`git clean -fd`、`git checkout .`、强制 push、删除用户未提交文件。
- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR；编辑、整理、修复、验证或准备工作都不等于提交请求。
- 若用户要求提交，只提交当前 Git root 中与本任务相关的文件；不得递归进入、暂存、提交或推送子仓库、submodule、nested Git repo 或依赖 checkout。
- 不引入新依赖，不改构建脚本，不改测试源码，除非任务明确要求。
- 不把密钥、token、证书私钥、shared secret、账号密码、完整指纹、完整 API 响应、完整转写文本或个人隐私路径写入文档。
- 不绕过辅助功能（Accessibility）权限检查、应用自管凭据隔离或 Carbon 全局热键注册边界。
- 不把 OpenAI Realtime WebSocket 协议（`session.update` / `input_audio_buffer.append` / `commit` / `transcription.*` 事件）、OpenAI HTTP 转写 multipart 协议、命令 JSON 格式、`config.json` schema 或旧 provider 迁移键当作一次性内部细节随意改名。
- 不在缺辅助功能权限时调用 `CGEvent` 模拟 ⌘V（`ClipboardPasteInjector` 在 `AccessibilityPermission.check()` 失败时必须返回明确的 accessibility failure，不得绕过）。
- 不把 API key 明文写入 UserDefaults、日志或项目文档。明文只允许位于 `~/Library/Application Support/Flotis/config.json` 对应 provider 的 `options.apiKey`；该目录保持 `0700`，`config.json` 与 `.config.lock` 保持 `0600`。运行时 connection 仍使用 `apiKeyReference` 做内存查找，但不再有独立凭据文件。
- Flotis 运行时不得导入 `Security`、调用 `SecItem*`、读取、迁移或删除旧系统钥匙串条目；旧版本遗留条目只能由用户自行处理。
- 未经用户明确要求，不复制或安装产物到 `~/Library/Input Methods`，不切换当前输入源，也不启动输入法进程做真实文本提交。
- 输入法接口不得记录或持久化提交文本，不得接管普通键盘输入；请求必须匹配当前激活的 InputMethodKit 会话，旧焦点会话不得向新客户端提交文本。

## 项目理解要求

修改前至少确认：

- 入口：`Flotis/FlotisApp.swift`（`@main struct FlotisApp`，`AppDelegate` 装配；`Settings` 场景承载 `SettingsView`）。
- 输入法入口：`FlotisInputMethod/main.swift` 以 plist-based `IMKServer(name:bundleIdentifier:)` 只创建一个 server；`FlotisInputController` 为每个激活客户端登记新 session，以 `NSTextInputClient.insertText` 直接提交显式请求，普通 `inputText` 返回 `false`。build `3` 已用本机 ad-hoc 身份安装到用户 Input Methods 目录并完成稳定启动冒烟，但当前登录会话尚未发现输入源，需重新登录后做真实 client 测试；`FlotisInputMethodService` / `FlotisInputMethodSessionGate` 仍仅为进程内接口，未加入本地 IPC、未连接现有 `VoiceInputController`。
- 语音输入主链路：`HotkeyManager`（Carbon 全局热键触发）→ `VoiceInputController`（`@MainActor`、session generation 状态机）→ `TranscriptionAdapterRegistry` 按 adapter 生成 `ownedCapture` / `pcmStream` / `recordedFile` 通用 runtime → Apple Speech、OpenAI Realtime、DashScope Paraformer Realtime、Volcengine BigASR Realtime、OpenAI HTTP 或 GLM ASR HTTP Stream → 可编辑 `reviewing` → 将原样审阅文本写入系统剪贴板 → 成功后清空会话、回到 `idle` 并让审阅框缩回原位置的小胶囊；panel 保持可见。默认仍走单 model route；用户开启多模型对比时，当前第一版只接受 2–4 个已保存且就绪的 recorded-file route（可来自同一 provider 的不同模型），由一个 `AudioRecorder` 生成同一临时文件并通过 `FileTranscriptionComparisonRunner` 并发转写，单项失败隔离。至少一项成功后按配置顺序展示全部候选并自动打开第一个成功项；用户可点击候选或用仅在该状态临时注册的“上一个/下一个结果”可配置快捷键（默认 `⌥←` / `⌥→`）在成功项间循环切换，第三次固定 voice hotkey 复制当前正在查看/编辑的结果。该行为不做质量评分或自动判定“最佳”。当前主链路不捕获目标 app、不请求 AX，也不发送 `CGEvent`/`⌘V`；`ClipboardPasteInjector` 仅作为不可达的旧兼容实现保留。
- 状态机：`VoiceInputState` 仍保留 idle/requestingPermission/connecting/recording/streaming/stopping/transcribing/reviewing/injecting/failed 兼容 case；当前 `toggleRecording()` 通过 `VoiceHotkeyAction` 分派 start/stop/cancel/copyAndReturn/none，生产路径不会进入 `injecting`。
- 命令兼容：`CommandStore`、8 个默认 UUID 与 `~/Library/Application Support/Flotis/commands.json` 格式仍保留，但 V0.12 主入口不实例化 store、不展示命令 UI、不注册命令热键，也不改写或删除旧命令文件。
- 配置：`SpeechProviderStore`、`TranscriptionComparisonStore` 与 `HotkeyConfigurationStore` 共同以 `FlotisConfigurationStore` 的 `~/Library/Application Support/Flotis/config.json` 为唯一运行时真源。schema v2 参考 Intatis 使用顶层 `$schema`、`model`、`provider_order`、`enabled_providers`、`comparison.models`、可选 `shortcuts` 与按语义化 provider ID 索引的 `provider` 字典；每个 provider 只保存一次共享 endpoint、language、audio/transcription options、`options.apiKey` 与 credential revision，并通过自己的 `models` 字典公开多个模型，每个模型还可保存可选显示名称。model selector 只在第一个 `/` 分割，格式为 `<provider-id>/<model-id>`，所以 OpenRouter 的 model ID 可以继续包含 `/`。`shortcuts` 只保存可配置的 panel 显隐、上一个对比结果、下一个对比结果描述符，不保存固定 voice hotkey。`config.json` 禁止持久化 Apple provider；空 catalog 时 Apple on-device 仅作为内部 fallback。底层以同一个进程锁 + `.config.lock` 跨进程锁执行 read-modify-atomic-write，目录 `0700`、文件/锁 `0600`，并通过目录 fd 与 `openat(..., O_NOFOLLOW)` 拒绝符号链接、非普通文件、损坏或异常大的数据。旧 canonical v1、`flotis.transcriptionConnections.v3`、v2/v1、`flotis.transcriptionComparison.v1` 和 `secrets.json` 只作迁移输入；迁移后不再参与运行时读写。当前 Settings adapter 展示层只开放 OpenAI Compatible HTTP，并可在一个 provider 下编辑多个模型及选择任意 2–4 个 model route 对比；其他 adapter/runtime 仍保留，禁止据此裁剪 canonical document、registry、migration 或 runtime。
- 热键：`HotkeyManager` 用 Carbon `RegisterEventHotKey` 独占注册，并同时监听 press/release 以抑制按键重复；V0.12 的 Carbon ID 继续固定为 `togglePanel=100`、`toggleVoice=200`、`previousComparisonResult=300`、`nextComparisonResult=400`。voice descriptor 仍固定为 `⌃⌥A`（Carbon virtual key `0`，Control+Option）；用户可在“快捷键”设置中修改 panel 显隐（默认 `⌘⌥⇧0`）以及上一个/下一个对比结果（默认 `⌥←` / `⌥→`），修改后原子写入 canonical `shortcuts` 并增量重新注册。三项必须至少含一个修饰键、彼此不同且不能占用固定 voice descriptor。previous/next 仍仅在对比 reviewing 中至少有两个成功候选时临时注册，离开该状态立即注销，不能在普通使用中长期抢占用户配置的按键。commands 起始 `1000` 的底层兼容实现仍在，但主入口传空列表。
- 应用图标：根目录 `Flotis.icon` 是主 App 的 Icon Composer 源，作为 `Flotis` target resource 编译；`ASSETCATALOG_COMPILER_APPICON_NAME=Flotis`。Xcode 会生成 `Flotis.icns`、`Assets.car` 以及产物 Info.plist 的 `CFBundleIconFile/CFBundleIconName=Flotis`，不得退化成只复制原始 PNG。当前 ad-hoc Release `0.12 (3)` 已安装并启动于 `/Applications/Flotis.app`。
- UI：`FloatingPanelController`（borderless `.nonactivatingPanel`/`.floating`/`hidesOnDeactivate=false`/`.canJoinAllSpaces`，允许拖动；以独立逻辑位置锚点保持用户选择的中心与底边，状态尺寸的可见区临时钳位不回写该锚点，只有用户主动拖动才更新）→ `FloatingPanelView`（idle 为 `108×54`，使用并排的 28 pt 白圆黑声波与 28 pt 白圆/16 pt 黑色八齿齿轮，下方 `⌃⌥A` 使用 12 pt Semibold 系统 Monospaced 与动态主文字色；录音态保留原有状态图标与文案，右侧不再显示 stop 方块，改为单调递增的 `mm:ss`；stopping/transcribing 保留原有省略号状态图标与原有文案，只隐藏右侧重复的禁用 action；单结果审阅为 `420×160`，对比审阅为 `560×300`，2–4 个成功/失败候选用固定双列网格展示，四项为 2×2，自动打开第一个成功项并保留原生可编辑文本区；候选有 Model Display name 时只显示该名称，没有时以 Model ID 为主、Provider 名称为次，不显示 endpoint；保留复制全部/取消/复制并返回和独立设置窗口入口）+ `FloatingPanelLayout`（静态无动画尺寸）；Settings 打开内容尺寸为 `1100×760`、最小内容尺寸为 `820×600`，以“快捷键 / 转写”侧栏分区，左上品牌区只显示 `Flotis` 与版本、不显示应用图标，当前可达页面不展示与主流程无关的 AX 权限。“快捷键”页只保留一张卡：固定 voice 与 panel 显隐、前后对比导航共四行，不再展示重复的 voice 流程或胶囊拖动说明；组合键 surface 固定为 `220×50`、17 pt Monospaced，三项可配置组合的整块 surface 可点，支持逐项/全部恢复并显示持久化、校验或 Carbon 注册错误。转写页的 Provider/Models 主卡按 Intatis 结构实现：左栏是 Provider 列表与模型数，右栏依次为 Provider name、共享 API key、Active model、Connection 与 Models disclosure；Models 中每行独立编辑 Model ID 和可选 Display name，并支持同一 Provider 新增多个模型，卡片下方保留 Test Provider / Save。Connection、Models、Comparison、Advanced 的 disclosure header 全行至少 44 pt 可点，Provider 行至少 48 pt，可对比 route 的整张 44 pt 卡片可点，不能退化成只命中小箭头/checkbox。Flotis 特有的 2–4 个就绪 route 对比放在主卡下方的独立 disclosure，不混入 Provider 共享字段；自定义 host 安全确认、request encoding 与 language/prompt/temperature 高级区继续保留。OpenRouter host 默认使用 `json-base64`，普通 OpenAI-compatible endpoint 默认使用 multipart。
- 界面语言：`AppLanguage` 只按 `Locale.preferredLanguages.first` 自动选择；明确的简体中文标识使用简中，繁体中文、英文和其他语言统一使用英文。此规则只影响 App 文案，不改变 provider 的转写 `language`。
- 权限：当前复制并返回主链路不查询或请求 Accessibility；麦克风与语音识别仍在 `AppleSpeechTranscriber.start()` 等 runtime 懒请求。旧 `AccessibilityPermission` / `ClipboardPasteInjector` 保留用于源码兼容，若未来重新接入，仍必须在缺权时明确失败，绝不能绕过 AX 检查发送 `CGEvent`。

不确定的模块必须标注 `UNKNOWN` 或 `需要后续确认`，不要编造。

## 文档索引

- `docs/PROJECT_MAP.md`：目录、target、入口、关键文件和生成物地图。
- `docs/ARCHITECTURE.md`：总体架构、隔离输入法接口、六条 provider 协议路径、注入链路、数据模型和安全机制。
- `docs/CURRENT_STATE.md`：当前真实状态、已有能力、风险、工作区改动。
- `docs/TESTING.md`：环境、构建、测试、lint/format 与手动验证方式。
- `docs/DO_NOT_BREAK.md`：工程禁区、数据格式、协议、路径和回归要求。
- `docs/NEXT_TARGET.md`：临时下一目标记录；目标完成或不再有效后删除。

## 完成标准

完成任务前至少做到：

- 说明本轮实际阅读/检查过哪些源码、配置或测试。
- 只修改任务范围内文件。
- 保留用户已有改动。
- 运行与任务相称的检查；文档任务至少运行 `git diff --check` 与 `git status --short`。
- 将本轮已完成的持久性改动及时回写到相关项目文档；若无需更新文档，最终报告说明原因。
- 如未运行构建或测试，最终报告必须明确写"未运行构建/测试"。

## 最终报告格式

最终报告建议包含：

1. `MODEL_CHECK_RESULT`：当前模型名称；无法确认时写无法确认。
2. `PATH_CHECK_RESULT`：`pwd`、Git root、是否匹配预期。
3. `FILES_WRITTEN`：新增/修改文件。
4. `PROJECT_AUDIT_SUMMARY`：识别到的项目结构、主要模块和关键链路。
5. `DOCS_CONTENT_SUMMARY`：各文档内容摘要。
6. `VALIDATION_RESULT`：实际运行命令与结果。
7. `UNCERTAINTIES`：无法确认、需要人工确认的点。
8. `NEXT_RECOMMENDED_ACTION`：下一步建议；不要自动继续改业务源码。
