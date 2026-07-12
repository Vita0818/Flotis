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

本仓库是 macOS 浮动面板语音输入工具（XcodeGen app + unit-test 两个 target，`LSUIElement=YES`，无 Dock 图标），24 个 app Swift 源文件、3 个 XCTest 源文件，无第三方依赖。

未来常规任务可以按用户要求修改业务源码；但在只要求项目自查或文档更新的任务中，只允许修改：

- `AGENTS.md`
- `docs/` 下的项目说明文档

除非用户明确要求，不要修改：

- `Flotis/`（全部 24 个 app 源文件）
- `project.yml`
- `run.sh`
- `Flotis.xcodeproj/`

## 禁止事项

- 不执行破坏性 Git 操作：`git reset --hard`、`git clean -fd`、`git checkout .`、强制 push、删除用户未提交文件。
- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR；编辑、整理、修复、验证或准备工作都不等于提交请求。
- 若用户要求提交，只提交当前 Git root 中与本任务相关的文件；不得递归进入、暂存、提交或推送子仓库、submodule、nested Git repo 或依赖 checkout。
- 不引入新依赖，不改构建脚本，不改测试源码，除非任务明确要求。
- 不把密钥、token、证书私钥、shared secret、账号密码、完整指纹、完整 API 响应、完整转写文本或个人隐私路径写入文档。
- 不绕过辅助功能（Accessibility）权限检查、Keychain 凭据隔离或 Carbon 全局热键注册边界。
- 不把 OpenAI Realtime WebSocket 协议（`session.update` / `input_audio_buffer.append` / `commit` / `transcription.*` 事件）、OpenAI HTTP 转写 multipart 协议、命令 JSON 格式、provider UserDefaults schema 当作一次性内部细节随意改名。
- 不在缺辅助功能权限时调用 `CGEvent` 模拟 ⌘V（`ClipboardPasteInjector` 在 `AccessibilityPermission.check()` 失败时必须 `completion(false)` 返回，不得绕过）。
- 不把 API key 写入 UserDefaults/配置文件——只存 Keychain 引用字符串 `apiKeyReference`。

## 项目理解要求

修改前至少确认：

- 入口：`Flotis/FlotisApp.swift`（`@main struct FlotisApp`，`AppDelegate` 装配；`Settings` 场景承载 `SettingsView`）。
- 语音输入主链路：`HotkeyManager`（Carbon 全局热键触发）→ `VoiceInputController`（`@MainActor`、session generation 状态机）→ 按 `provider.resolvedWireProtocol` 分支：Apple Speech 设备端、OpenAI Realtime、DashScope Paraformer Realtime、Volcengine BigASR Realtime、OpenAI HTTP、GLM ASR HTTP Stream → `ClipboardPasteInjector`（完整快照剪贴板→置文本→确认目标 PID/前台状态→等修饰键释放→模拟 ⌘V→按 `changeCount` 安全恢复）。
- 状态机：`VoiceInputState`（idle/requestingPermission/connecting/recording/streaming/stopping/transcribing/injecting/failed）；`toggleRecording()` 按当前状态分派。
- 命令/预设：`CommandStore`（singleton，8 个默认中文 prompt 命令，固定 UUID `1111…`–`8888…`，⌘⌥⇧1..8）→ `~/Library/Application Support/Flotis/commands.json`（atomic 写）。
- Provider 配置：`SpeechProviderStore`（singleton）→ UserDefaults 主键 `flotis.speechProviders.v2`（显式 schema/catalog version、last-known-good、坏数据备份；保留 `flotis.speechProviders.v1` 只作迁移输入）；API key → Keychain（service = `com.flotis.Flotis.speech-provider-api-key`，account = `apiKeyReference`，`AfterFirstUnlockThisDeviceOnly`，旧无 service item 按精确 persistent ref 迁移）。
- 热键：`HotkeyManager` 用 Carbon `RegisterEventHotKey`；固定 ID `togglePanel=100`/`toggleVoice=200`/commands 起始 `1000`；命令 ID 稳定、增量注册、失败状态持久显示并自动重试；默认 togglePanel=⌘⌥⇧0、toggleVoice=⌘⌥⇧R。
- UI：`FloatingPanelController`（`NSPanel`，`.nonactivatingPanel`/`.floating`/`hidesOnDeactivate=false`/`.canJoinAllSpaces`）→ `FloatingPanelView`（命令网格 + 语音按钮 + provider Picker + 转写预览）+ `FloatingPanelLayout`（自适应尺寸）。
- 权限：`AccessibilityPermission.check()`（非提示式 `AXIsProcessTrustedWithOptions`）；麦克风与语音识别在 `AppleSpeechTranscriber.start()` 等 runtime 懒请求。

不确定的模块必须标注 `UNKNOWN` 或 `需要后续确认`，不要编造。

## 文档索引

- `docs/PROJECT_MAP.md`：目录、target、入口、关键文件和生成物地图。
- `docs/ARCHITECTURE.md`：总体架构、六条 provider 协议路径、注入链路、数据模型和安全机制。
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
