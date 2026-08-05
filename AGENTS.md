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

本仓库包含 macOS 悬浮语音输入胶囊与隔离的 InputMethodKit 输入法接口（XcodeGen 两个 application target + 两个 unit-test target）。现有 `Flotis` app 保持 `LSUIElement=YES`、无 Dock 图标，共 27 个 Swift 源文件和 5 个 XCTest 源文件；`FlotisInputMethod` 为 `LSBackgroundOnly=YES`，有 4 个 Swift 源文件、SVG/TIFF 输入源图标，独立策略测试目录有 1 个 XCTest 源文件。无第三方依赖。

未来常规任务可以按用户要求修改业务源码；但在只要求项目自查或文档更新的任务中，只允许修改：

- `AGENTS.md`
- `docs/` 下的项目说明文档

除非用户明确要求，不要修改：

- `Flotis/`（全部 27 个 app 源文件）
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
- 不把 OpenAI Realtime WebSocket 协议（`session.update` / `input_audio_buffer.append` / `commit` / `transcription.*` 事件）、OpenAI HTTP 转写 multipart 协议、命令 JSON 格式、provider UserDefaults schema 当作一次性内部细节随意改名。
- 不在缺辅助功能权限时调用 `CGEvent` 模拟 ⌘V（`ClipboardPasteInjector` 在 `AccessibilityPermission.check()` 失败时必须返回明确的 accessibility failure，不得绕过）。
- 不把 API key 明文写入 UserDefaults、connection snapshot、日志或文档。明文只允许写入 `~/Library/Application Support/Flotis/secrets.json`；该目录保持 `0700`、文件保持 `0600`，connection 仅保存引用字符串 `apiKeyReference`。
- Flotis 运行时不得导入 `Security`、调用 `SecItem*`、读取、迁移或删除旧系统钥匙串条目；旧版本遗留条目只能由用户自行处理。
- 未经用户明确要求，不复制或安装产物到 `~/Library/Input Methods`，不切换当前输入源，也不启动输入法进程做真实文本提交。
- 输入法接口不得记录或持久化提交文本，不得接管普通键盘输入；请求必须匹配当前激活的 InputMethodKit 会话，旧焦点会话不得向新客户端提交文本。

## 项目理解要求

修改前至少确认：

- 入口：`Flotis/FlotisApp.swift`（`@main struct FlotisApp`，`AppDelegate` 装配；`Settings` 场景承载 `SettingsView`）。
- 输入法入口：`FlotisInputMethod/main.swift` 以 plist-based `IMKServer(name:bundleIdentifier:)` 只创建一个 server；`FlotisInputController` 为每个激活客户端登记新 session，以 `NSTextInputClient.insertText` 直接提交显式请求，普通 `inputText` 返回 `false`。build `3` 已用本机 ad-hoc 身份安装到用户 Input Methods 目录并完成稳定启动冒烟，但当前登录会话尚未发现输入源，需重新登录后做真实 client 测试；`FlotisInputMethodService` / `FlotisInputMethodSessionGate` 仍仅为进程内接口，未加入本地 IPC、未连接现有 `VoiceInputController`。
- 语音输入主链路：`HotkeyManager`（Carbon 全局热键触发）→ `VoiceInputController`（`@MainActor`、session generation 状态机）→ `TranscriptionAdapterRegistry` 按 adapter 生成 `ownedCapture` / `pcmStream` / `recordedFile` 通用 runtime → Apple Speech、OpenAI Realtime、DashScope Paraformer Realtime、Volcengine BigASR Realtime、OpenAI HTTP 或 GLM ASR HTTP Stream → 可编辑 `reviewing` → 将原样审阅文本写入系统剪贴板 → 成功后清空会话、回到 `idle` 并让审阅框缩回原位置的小胶囊；panel 保持可见。当前主链路不捕获目标 app、不请求 AX，也不发送 `CGEvent`/`⌘V`；`ClipboardPasteInjector` 仅作为不可达的旧兼容实现保留。
- 状态机：`VoiceInputState` 仍保留 idle/requestingPermission/connecting/recording/streaming/stopping/transcribing/reviewing/injecting/failed 兼容 case；当前 `toggleRecording()` 通过 `VoiceHotkeyAction` 分派 start/stop/cancel/copyAndReturn/none，生产路径不会进入 `injecting`。
- 命令兼容：`CommandStore`、8 个默认 UUID 与 `~/Library/Application Support/Flotis/commands.json` 格式仍保留，但 V0.8 主入口不实例化 store、不展示命令 UI、不注册命令热键，也不改写或删除旧命令文件。
- Provider 配置：`SpeechProviderStore`（singleton）→ UserDefaults 主键 `flotis.transcriptionConnections.v3`（显式 schema/catalog version、last-known-good、坏数据备份；保留 v2/v1 键只作只读迁移输入）；API key → `LocalSecretStore` 的版本化 `secrets.json`，以 `apiKeyReference` 为记录 ID、同目录原子替换、进程内共享锁 + `.secrets.lock` 跨进程写锁、目录 `0700` / 文件 `0600`，通过目录 fd 与 `openat(..., O_NOFOLLOW)` 拒绝符号链接、非普通文件、损坏或异常大的数据。当前 Settings 展示层只开放 OpenAI Compatible HTTP，其他 adapter/connection 仅隐藏，禁止据此裁剪 snapshot、registry、migration 或 runtime。
- 热键：`HotkeyManager` 用 Carbon `RegisterEventHotKey` 独占注册，并同时监听 press/release 以抑制按键重复；V0.8 只注册固定 ID `togglePanel=100`/`toggleVoice=200`，默认 togglePanel=⌘⌥⇧0、toggleVoice=⌃⌥A（Carbon virtual key `0`，Control+Option）。commands 起始 `1000` 的底层兼容实现仍在，但主入口传空列表。
- 应用图标：根目录 `Flotis.icon` 是主 App 的 Icon Composer 源，作为 `Flotis` target resource 编译；`ASSETCATALOG_COMPILER_APPICON_NAME=Flotis`。Xcode 会生成 `Flotis.icns`、`Assets.car` 以及产物 Info.plist 的 `CFBundleIconFile/CFBundleIconName=Flotis`，不得退化成只复制原始 PNG。当前 ad-hoc Release `0.8.0 (1)` 已安装到 `/Applications/Flotis.app`。
- UI：`FloatingPanelController`（borderless `.nonactivatingPanel`/`.floating`/`hidesOnDeactivate=false`/`.canJoinAllSpaces`，允许拖动；以独立逻辑位置锚点保持用户选择的中心与底边，状态尺寸的可见区临时钳位不回写该锚点，只有用户主动拖动才更新）→ `FloatingPanelView`（idle 为 `108×54`，使用并排的 28 pt 白圆黑声波与 28 pt 白圆/16 pt 黑色八齿齿轮，下方 `⌃⌥A` 使用 12 pt Semibold 系统 Monospaced 与动态主文字色；其余为小胶囊状态 + 原生可选择/复制的转写审阅 + 复制全部/取消/复制并返回 + `FlotisSettingsWindowController` 独立设置窗口入口）+ `FloatingPanelLayout`（静态无动画尺寸）；Settings 为可缩放 `820×600`（最小 `760×540`）独立窗口，以“通用 / 转写”侧栏分区，当前可达页面不再展示与主流程无关的 AX 权限。`VoiceSettingsView` 的可见转写表单只保留 OpenAI Compatible 的 model/endpoint/API key、自定义 host 安全确认与 Test Connection，保存后设为当前 connection；底层 connection name/多实例仍保留但当前隐藏，language/prompt/temperature 位于高级区。
- 界面语言：`AppLanguage` 只按 `Locale.preferredLanguages.first` 自动选择；明确的简体中文标识使用简中，繁体中文、英文和其他语言统一使用英文。此规则只影响 App 文案，不改变 connection 的转写 `language`。
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
