# TESTING

最近验证日期：2026-07-30

## 环境与边界

- macOS app，deployment target 13.0，Swift 5.0。
- XcodeGen 生成 `Flotis.xcodeproj`；scheme `Flotis` 包含 app 与 unit tests。
- 依赖 Carbon、AppKit、Speech、AVFoundation、Darwin 文件系统调用与真实 macOS Accessibility，不能用 iOS Simulator 验证核心交互。App 源码不再导入 Security 或调用系统钥匙串。
- 无第三方依赖，无仓内 SwiftLint/SwiftFormat 配置。
- 当前没有 UI-test target、SwiftUI snapshot test、Preview fixture 或产品内 debug state 开关；视觉验收必须结合真实 macOS 运行态，不能由当前 57 个策略/协议/存储单测替代。
- API key 明文不进入仓库、UserDefaults、connection snapshot 或日志；自动化只使用内存 fake transport 与虚拟字符串。真实 provider 测试需由操作者在 UI 保存到 Flotis 本地 `secrets.json`。

## 标准静态与自动化验证

在仓库根目录运行：

```sh
pwd
git rev-parse --show-toplevel
git status --short
xcodegen generate
xcodebuild \
  -project Flotis.xcodeproj \
  -scheme Flotis \
  -configuration Debug \
  -derivedDataPath /tmp/FlotisBuildDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
xcodebuild \
  -project Flotis.xcodeproj \
  -scheme Flotis \
  -configuration Debug \
  -derivedDataPath /tmp/FlotisTestDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
git diff --check
git status --short
```

为 build 与 test 使用不同的临时 DerivedData。Xcode 26 的 test action 会把 XCTest framework 复制进 test host；复用已跑过 test 的 app bundle 再次执行普通 build，可能在 app validation 阶段把旧测试 framework 当作产品 framework 检查。

2026-07-30 胶囊交互、窗口与热键稳定性修复结果：

- 胶囊当前四档静态尺寸为 idle `120×56`、普通工作态 `188×56`、错误/提示态 `280×56`、reviewing `420×160`；状态消息不再追加高度。panel 调度会取消旧 resize work item，只应用最后一次尺寸，并使用启动屏幕的固定底边锚点；重新显示或屏幕参数变化时会重算有效位置，整窗背景拖动关闭。
- 齿轮直接调用 AppDelegate 持有且复用的 `FlotisSettingsWindowController`，不再走字符串 selector 或 sheet；关闭动作只针对捕获的设置窗口。可见配置去掉 connection 侧栏与 Connection Name，仅保留 Model、一个 Endpoint 标签下的 Base URL/Path、API Key 和必要动作，保存后自动设为当前 connection。
- reviewing 改用原生 `NSTextView`，支持编辑、滚动、鼠标选择、右键与 `⌘C`，并保留显式复制全部按钮。内容表面的装饰 overlay 禁止 hit testing。
- Carbon 注册使用 `kEventHotKeyExclusive`，同时接收 press/release；press gate 抑制按住或重复派发。requesting/connecting 仍可取消，stopping/transcribing/injecting 的额外热键忽略。
- 注入器在目标重新获得焦点前先让 Flotis key window 辞去焦点，并等待 `⌘⌥⇧R` 的修饰键和主键 R 全部释放；相关纯策略测试覆盖完整组合键释放。
- `xcodegen generate`：成功。
- 独立 Debug build：`/tmp/FlotisInteractionFixCompleteBuild-20260730` 下 `BUILD SUCCEEDED`。
- 完整 XCTest：`/tmp/FlotisInteractionFixCompleteTest-20260730` 下 57 tests、0 failures；其中 `HotkeyAndInjectionPolicyTests` 11 tests、0 failures。
- 未手动启动 App、未打开 Settings、未访问真实 API key、真实 `secrets.json` 或旧系统钥匙串，也未触发真实 AX/`CGEvent`。窗口位置、文本选区/复制、独立 Settings 打开及三次物理热键仍需新构建真机确认。

2026-07-30 移除系统钥匙串依赖结果：

- 删除 `KeychainSecretStore.swift`、`import Security`、全部 `SecItem*` 调用及三个生产入口的旧单例依赖；XcodeGen 生成工程只编译 `LocalSecretStore.swift`。
- `LocalSecretStore` 使用 `~/Library/Application Support/Flotis/secrets.json`、版本化 JSON、`apiKeyReference` 字典键、目录 fd + `openat/O_NOFOLLOW`、当前用户/普通文件校验、`0700` / `0600` 权限、同目录 `fsync + renameat` 原子替换、共享进程锁与 `.secrets.lock` 跨进程写锁；锁竞争最多等待 500 ms。损坏 JSON、符号链接、越界数据和非当前用户文件均拒绝。
- `SpeechProviderConfigurationTests` 增至 24 tests，新增跨实例并发不丢 reference、跨实例持久化/替换/删除、权限创建与自动收紧、损坏 JSON 保留和符号链接目标不受影响。
- `xcodegen generate`：成功。
- 最终独立 Debug build：`/tmp/FlotisNoKeychainFinalBuild-20260730` 下 `BUILD SUCCEEDED`。
- 最终完整 XCTest：`/tmp/FlotisNoKeychainFinalTest-20260730` 下 53 tests、0 failures。
- 静态源码/工程扫描未发现 `KeychainSecretStore`、`SecItem*` 或 `import Security`；`otool -L` 显示最终 app dylib 不直接链接 `Security.framework`，`nm -u` 未发现 `SecItem*` 符号。
- 未启动 App、未打开 Settings、未访问真实 API key、真实 `secrets.json` 或旧系统钥匙串；文件测试只在独立系统临时目录写入虚拟字符串并清理。因此升级后重新输入 API key 与不再出现系统钥匙串提示仍需用户在新构建中确认。

2026-07-28 浅色模式胶囊边缘与矩形高光修复结果：

- 源码定位到两层叠加：窗口服务器阴影未由圆角 material mask 明确约束，SwiftUI 又绘制了整圈 1 pt separator；浅色模式下容易形成尖角矩形高光和明显双边。
- `NSVisualEffectView` 现在使用带 cap insets 的圆角 alpha `maskImage`，该 AppKit contract 会同时影响 content-view material 与 window shadow；CALayer mask 继续裁切 hosted subviews。显示和尺寸切换后调用 `invalidateShadow()`，SwiftUI 整圈 overlay 已移除。
- 胶囊 `120×56` 尺寸、20 pt continuous corner、按钮、快捷键、窗口层级、非激活行为和语音状态机均未改变。
- `xcodegen generate`：成功。
- Debug build：在独立 `/tmp/FlotisRoundedEdgeBuild-20260728` 下成功。
- 完整 XCTest：在独立 `/tmp/FlotisRoundedEdgeTest-20260728` 下 49 tests、0 failures。
- 当时没有启动 Debug app、打开 Settings 或执行运行态截图；浅色模式的最终边缘与阴影仍需用户在常用构建中目视确认。

2026-07-28 待机胶囊轻微收窄结果：

- idle 几何由 `128×56` 轻微收窄为 `120×56`；只减少 8 pt 宽度，高度、按钮尺寸、10 pt 双按钮间距及 11 pt Monospaced 系统次级灰快捷键均保持不变。
- `xcodegen generate`：成功。
- Debug build：在独立 `/tmp/FlotisCapsuleSmallerBuild-20260728` 下成功。
- 完整 XCTest：在独立 `/tmp/FlotisCapsuleSmallerTest-20260728` 下 49 tests、0 failures。
- 按用户要求，当时没有启动 Debug app、打开 Settings 或执行运行态截图；因此 `120×56` 的最终视觉比例与快捷键可读性仍由用户在常用构建中目视确认。
- 未读取、输入、修改或保存真实 API key，未请求真实 provider，未采集麦克风，也未触发 AX/`CGEvent` 注入。

2026-07-27 胶囊紧凑与边缘精修结果：

- `xcodegen generate`：成功。
- Debug build：在独立 `/tmp/FlotisCapsulePolishBuild-20260727` 下成功。
- 完整 XCTest：在独立 `/tmp/FlotisCapsulePolishTest-20260727` 下 49 tests、0 failures。
- 运行态前后对比：macOS 26.5.2 的 AX 未授权状态由 `304×108` 收到 `304×98`；标题、快捷键说明、设置/录音按钮和两行权限提示均可见，英文启动说明不再提前截断。
- 无状态条的 compact 几何由源码固定为 `280×56`；本轮没有为了截图修改 AX 权限，因此该分支尚需在已授权的新构建上目视确认。reviewing、录音、failed、Dark、Reduce Transparency、Increase Contrast 与 macOS 13 fallback 仍按下方矩阵人工检查。
- 外壳从 AppKit + SwiftUI 双重裁切和 centered stroke，改为 AppKit 单一 20 pt continuous mask + SwiftUI 向内描边；状态区分隔线也改为左右缩进。没有修改窗口层级、非激活行为、底边锚定、语音状态机或快捷键。
- 构建/测试只有既有的 Swift 6 `NSLock` 兼容性与 XCTest deployment warning。

2026-07-26 第三次语音热键注入修复结果：

- 修复前真机复现中，真实 OpenAI-compatible 转写可进入 reviewing，辅助功能已启用，第三次 `⌘⌥⇧R` 注入失败；同一 reviewing 内容点击胶囊“输入”按钮成功。由此将故障范围收敛到 Carbon hotkey 触发后的物理修饰键释放等待，而非 provider、转写、目标 app 或 AX 授权。
- `ClipboardPasteInjector` 不再使用固定 0.8 秒释放窗口，改为复用当前 operation 已有 5 秒 monotonic 有效期的剩余时间；过期仍失败，AX、目标 PID/frontmost、pasteboard `changeCount` 与剪贴板恢复校验均未放宽。
- `xcodegen generate`：成功。
- 定向 XCTest：`HotkeyAndInjectionPolicyTests` 7 tests、0 failures。
- 完整 XCTest：在独立 `/tmp/FlotisModifierReleaseFullTest-019f9c0b` 下 49 tests、0 failures。
- Debug build：在独立 `/tmp/FlotisModifierReleaseBuild-019f9c0b` 下成功。
- 本轮没有替换或重启用户正在运行的旧构建；修复后的第三次物理热键端到端注入仍需用新构建真机复测。构建/测试仍只有既有 Swift 6 锁兼容性与 XCTest deployment warning。

2026-07-26 OpenAI Compatible Settings 精简结果：

- `xcodegen generate`：成功；生成工程保持六 adapter 源码与既有测试 target。
- Debug build：最终源码在独立 `/tmp/FlotisOpenAISettingsFinalBuild-019f9c0b` 下 `BUILD SUCCEEDED`。
- XCTest：最终源码在独立 `/tmp/FlotisOpenAISettingsFinalTest-019f9c0b` 下 `TEST SUCCEEDED`，49 tests、0 failures。
- 展示过滤只位于 `VoiceSettingsView.swift`；当时现有 registry、migration、fresh-store、同 adapter 多 connection、OpenAI HTTP multipart/M4A 与凭据边界测试全部继续通过。
- 本轮未启动 App 做运行态目视，也未使用真实 API key 或请求供应商；OpenAI Compatible 空态、隐藏 active provider、精简表单排版和自定义 host 交互仍需人工检查。

2026-07-26 简中 / 英文自动适配结果：

- `xcodegen generate`：成功；生成工程的 development region 为 `en`，known regions 包含 `en`、`zh-Hans`，`InfoPlist.xcstrings` 已进入 Resources。
- Debug build：最终源码在独立 `/tmp/FlotisLocalizationFinalBuildDerivedData` 下构建成功。
- XCTest：最终源码在独立 `/tmp/FlotisLocalizationFinalTestDerivedData` 下测试成功，49 tests、0 failures；新增 4 个语言策略测试覆盖简中、繁中、英文、其他语言、空/非法标识与多语言偏好顺序。
- 构建产物检查：基础 Info.plist 权限说明为英文，`en.lproj/InfoPlist.strings` 为英文，`zh-Hans.lproj/InfoPlist.strings` 为简中。
- 本轮未分别以简中/英文/其他语言启动 App 做运行态目视；权限弹窗实际语言、长英文排版和不同 voice state 仍需人工矩阵。

2026-07-26 统一 UI 设计语言结果：

- `xcodegen generate`：成功，生成工程已包含 `FlotisDesign.swift`。
- Debug build：在全新的 `/tmp/FlotisUIVisualDerivedData` 下 `BUILD SUCCEEDED`。
- XCTest：在最终源码对应的独立 `/tmp/FlotisUIFinalVerificationDerivedData` 下 `TEST SUCCEEDED`，45 tests、0 failures。
- 运行态视觉冒烟：在 macOS 26.5、Light appearance 启动 Debug app，实际打开检查 idle 胶囊、AX 未授权状态条、设置 sheet、独立 Settings scene、语音概览、connection 列表/编辑器及新增草稿；close、segmented navigation 和 Add draft 均能操作，未保存连接名称在分段往返后保持，点击 Cancel 后恢复持久化值。
- 未授权麦克风或 Accessibility，未采集音频、未发送 `CGEvent`、未使用真实 API key、未请求第三方 provider。reviewing、recording/streaming、failed 等 voice state 未做运行态状态注入，仍列入人工矩阵。
- 首次尝试复用旧 `/tmp/FlotisDerivedData` 时，源码已编译通过，但 app validation 因目录中遗留的 XCTest framework 缺少可验证的 `Info.plist` 而失败；切换到全新 DerivedData 后完整 build 成功，判定为临时构建产物污染而非源码失败。
- 非致命 warning 与既有基线一致：Swift 5 模式下 `AppleSpeechTranscriber` 的 `NSLock` Swift 6 兼容性 warning、macOS 13 test target 链接由 macOS 14 构建的 XCTest dylib，以及 test host 下 App Intents `linkd` 日志。

2026-07-12 V0.8 胶囊基线结果：

- `xcodegen generate`：成功。
- Debug build：`BUILD SUCCEEDED`。
- XCTest：`TEST SUCCEEDED`，45 tests、0 failures。
- 启动冒烟：`open -n /tmp/FlotisDerivedData/Build/Products/Debug/Flotis.app` 后进程保持运行，随后关闭测试实例；未执行视觉截图或交互矩阵。
- 测试日志存在非致命环境/未来语言模式提示：macOS 13 deployment target 链接由 macOS 14 构建的 XCTest dylib、test host 下 App Intents `linkd` 连接日志，以及 `AppleSpeechTranscriber` 在 Swift 5 模式下对 async context 中 `NSLock` 的 Swift 6 兼容性 warning；均未造成构建或测试失败。
- 按用户要求，本轮未创建、读取或使用真实 API key，未请求真实供应商，未采集麦克风，也未触发 Accessibility/`CGEvent` 注入。

## 当前自动化覆盖

### `HotkeyAndInjectionPolicyTests`

11 tests：

- V0.8 语音热键严格映射 start → stop → reviewing/inject。
- requesting/connecting 保持 cancel；stopping/transcribing/injecting 忽略重复动作。
- Carbon hotkey 使用独占注册。
- press gate 在 release 前只接受一次按下，并可 reset。
- `⌘⌥⇧R` 的修饰键与主键 R 都释放后才允许继续注入。
- 四档胶囊尺寸保持稳定，status 不改变 reviewing 高度。
- 可打印全局快捷键要求 Command + 额外修饰键。
- `⌘V` 及常见 app 系统快捷键被拒绝。
- 默认三修饰键命令仍有效。
- 注入队列容量有界。
- operation 使用 monotonic age 判定过期。

### `TranscriptAssemblyTests`

8 tests：

- Apple 有效 partial 后的空 final 不清空文本。
- Apple 静音间隔后的非重叠 segment 保留前后两段。
- Apple 同一时间范围的纠错假设替换而不重复。
- Apple 时间边界相邻的两个 segment 均保留。
- OpenAI completion 乱序时按 conversation item 顺序输出。
- partial 被同 `item_id/content_index` 的 final 正确替换。
- DashScope 合法重复句保留。
- ASCII 单词边界插空格，CJK 不被错误插空格。

### `SpeechProviderConfigurationTests`

24 tests：

- 六个稳定 adapter ID、canonical v3 编码以及 unsupported/legacy 字段省略。
- 全新 v3 仅有 Apple connection；Add 只创建内存 draft，Save 前不持久化。
- 通用 HTTP 默认 WAV PCM16 16 kHz mono，prompt/temperature 默认 nil；preset 只填字段，不改 identity/adapter。
- v2 六类 + 自定义 connection 无损迁移：UUID、名称、顺序、active ID、endpoint/model/options 与 `apiKeyReference` 保留；v1 兼容迁移仍受测。
- 同 adapter 多 connection 的 endpoint/model/key reference 相互隔离。
- secret boundary 覆盖 adapter、scheme、host、effective port、auth；边界变化会轮换 reference，清理失败时配置与新 secret 回滚。
- provider 删除时若 secret 清理失败，connection/UserDefaults 删除会回滚。
- 坏 v3 从 v3 LKG 恢复；坏 v2 可从 v2 LKG 迁移；两者均保留原 authoritative bytes 与 corrupt backup。
- API key 明文不会进入 v3 snapshot；Test Connection fingerprint 覆盖配置与 credential revision，名称变化不失效。
- 自定义 endpoint 显式 approval 与不安全/歧义 URL 拒绝。
- `LocalSecretStore` 跨实例持久化、替换、删除与并发保存不丢 reference；目录 `0700`、secret/lock 文件 `0600`，读取时会收紧意外放宽的文件权限。
- 损坏 JSON 不会被静默覆盖；secret 路径为符号链接时读、写、删均拒绝且不会影响链接目标。

### `TranscriptionAdapterRuntimeTests`

10 tests：

- registry 恰好注册六个唯一 adapter；重复 ID 被拒绝，六条路径只生成声明的三类通用 runtime plan。
- OpenAI-compatible HTTP 生成严格 multipart WAV；自定义 endpoint/model/key 按 connection 隔离；显式 M4A 使用匹配扩展名与 MIME。
- HTTP 只接受 `application/json` 与顶层 `text`，错误 Content-Type/嵌套猜测被拒绝。合成测试音得到合法空 `text` 时仍可判定 transport/响应结构成功。
- 失败摘要限长；自定义端点原样回显非 `sk-*` 的任意 opaque API key 时仍被精确脱敏。
- GLM SSE 要求正确 media type、有效 JSON、明确 delta/done 与 `[DONE]`，并脱敏错误中的实际 Key。
- scripted OpenAI Realtime 验证 GA `session.update`、audio append、manual commit、commit ack 与 completed terminal lifecycle。

### `LocalizationTests`

4 tests：

- `zh-Hans`、`zh-CN`、`zh-SG`、`zh-MY` 作为第一首选语言时选择简中。
- 繁体中文、英文、日文、法文、粤语、空数组和非法标识回退英文。
- 只允许第一首选语言决定界面语言；后续列表中的简中不能覆盖第一语言。
- 简中与英文 case 分别选择对应文案。

自动化单测刻意针对纯策略、迁移、组装、本地 secret 文件与 mock transport；真实 Carbon、AX、pasteboard、audio engine、跨进程崩溃/断电窗口以及 WebSocket/HTTP 服务端不是 unit-test 能完全替代的边界。

## Presentation / Design System 视觉验收

每次修改 `FlotisDesign.swift`、`FloatingPanelView.swift`、`FloatingPanelController.swift` 或 `VoiceSettingsView.swift` 后，至少手动检查：

- Light / Dark appearance，以及 Reduce Transparency / Increase Contrast 开关前后。
- idle、requesting permission、connecting、recording/streaming、stopping/transcribing、reviewing、injecting、failed；状态不能只靠颜色表达。
- reviewing 中的长 CJK/Latin、多行、滚动、选区、caret、右键 Copy、`⌘C`、复制全部、空文本禁用、取消与输入；点击文本时 panel 可成为 key，但注入前必须把焦点还给目标。
- 四档静态 panel 尺寸、固定启动屏幕底边锚点、小屏/多屏边界、显示器拔插/排列变化、跨 Space 与长错误单行截断；连续快速状态切换不能回放旧尺寸或跳到另一屏幕。
- Settings 只能通过可复用独立窗口打开，不能附着成胶囊 sheet；齿轮重复点击只前置同一窗口，关闭不能误关胶囊。
- 主表单只显示 Model、Endpoint（Base URL / Path 两个输入共用一个标签）、API Key；Connection Name、多连接侧栏、音频格式、采样率、声道、response mode 以及其他 adapter 选择不出现，Language/Prompt/Temperature 只在折叠高级区。
- OpenAI Compatible 空态、隐藏 active provider、custom endpoint warning/confirmation、Clear API Key、connection test、disabled/error/success、Esc 与 `⌘W`。
- 按钮 hover/focus/disabled 层级、键盘导航、SF Symbol 与文字标签；主操作使用系统动态黑/白，红/橙/绿只用于明确语义状态。
- macOS 26 原生 Liquid Glass 路径与 macOS 13–15 Material/native bordered fallback。当前自动化不能证明 fallback 的实际像素和交互。

## 真机手动验证矩阵

### 构建、启动与权限

| 场景 | 操作 | 预期 |
|---|---|---|
| 冷启动 | `./run.sh` | 工程生成/构建成功，app 启动；因脚本重置 TCC 需重新授权 |
| AX 未授权 | 拒绝/撤销 Accessibility 后在 reviewing 触发输入 | 胶囊保留文字并显示权限错误，不发送 `CGEvent`，目标 app 不收到文本 |
| 麦克风拒绝 | 拒绝 microphone | 会话进入明确 failed，可取消/重试，不遗留 audio engine |
| Speech 拒绝/设备不支持 | Apple provider 启动 | 明确报告设备端识别不可用，不退回云端 |
| 简中系统语言 | 将第一首选语言设为简体中文并重启 App | 胶囊、Settings、App 自定义错误与权限说明均为简中；中文标题使用系统默认字体 |
| 英文/其他系统语言 | 将第一首选语言设为英文、繁中或其他语言并重启 App | App 自定义界面统一为英文；英文品牌和标题使用 Serif |
| 多语言顺序 | 第一语言设为日文，后续保留简中并重启 | App 使用英文，不扫描后续简中改写界面语言 |

### 热键与面板

| 场景 | 操作 | 预期 |
|---|---|---|
| 固定 toggle | `⌘⌥⇧0` / `⌘⌥⇧R` | panel 与 voice 各自响应一次；隐藏时 voice 会先显示胶囊 |
| 三段式 voice | 连续完成开始、停止/转写、确认三个阶段 | idle→recording/streaming→reviewing→injecting→idle；不会在转写完成时自动注入 |
| 按住/自动重复 | 按住 `⌘⌥⇧R` 约 2 秒后松开 | 整次物理按下只触发一个动作，松开后下一次按下才生效 |
| 处理中误按 | stopping/transcribing 中再次按语音热键 | 忽略，不取消终态处理、不清空即将审阅的转写 |
| 胶囊编辑 | reviewing 点击文本并修改，再按 `⌘⌥⇧R` | 修改后文本注入最后一个有效的非 Flotis 输入目标 |
| 审阅复制 | reviewing 选中部分文字按 `⌘C`、右键 Copy，再测试复制全部图标 | 部分选区或全文进入剪贴板；文本仍可继续编辑，窗口不随拖选移动 |
| 编辑后取消 | reviewing 修改后按 Esc/取消 | 清空本次文本并回 idle，不注入 |
| 注入失败重试 | reviewing 时让目标退出或撤销 AX 后确认 | 返回 reviewing 且保留修改文本，恢复条件后可再次确认 |
| 热键冲突 | 在系统/其他 app 占用组合后保存 | 错误持久显示；解除冲突后自动重试成功 |
| 旧命令兼容 | 启动 V0.8 并检查旧 commands.json | 不展示命令、不注册命令热键，也不改写或删除旧文件 |

### 剪贴板注入

| 场景 | 操作 | 预期 |
|---|---|---|
| 普通语音确认 | 目标 app 文本框有焦点，reviewing 再按语音热键 | 审阅文本注入，原剪贴板恢复 |
| 完整组合键释放 | reviewing 中按语音热键后正常释放 `⌘⌥⇧R` | 修饰键和主键 R 都释放后，在当前 5 秒 operation 有效期内继续注入 |
| 组合键不释放 | 持续按住任一修饰键或 R 直到 operation 过期 | 不粘贴，返回失败 |
| 快速连按 | 连续触发超过队列/burst 上限 | 新请求受控失败，不产生长期 backlog/过期粘贴 |
| 目标退出 | 入队后立即退出目标 app | 不向其他 frontmost app 粘贴 |
| 用户切 app | 激活/等待期间切到第三个 app | operation abort，第三个 app 不收到文本 |
| 跨 Space/慢激活 | 目标在另一 Space 或激活较慢 | 仅在目标 PID 真正 frontmost 时粘贴，否则失败 |
| 外部复制竞争 | 注入后恢复前在另一 app Copy | 新 clipboard 内容被保留，不被旧 snapshot 覆盖 |
| 复杂剪贴板 | 文件、图片、富文本、延迟 provider | 能完整快照才注入；否则安全失败且原内容不丢 |
| 剪贴板管理器 | 启用常见 manager 后重复上述场景 | 不覆盖 manager 新写内容；记录任何真实竞争 |

注意：completion=true 只能证明安全核验、event post 与剪贴板结局，需目视确认目标控件确实消费文本。

### Connection 配置与迁移

| 场景 | 操作 | 预期 |
|---|---|---|
| 全新安装 | 清空本 app defaults 后启动 | v3 只创建 Apple connection；Settings 显示 OpenAI Compatible 空态，由用户点击 Add 创建未持久化草稿 |
| v2 升级 | 用含六类和自定义实例的 v2 snapshot 启动 | 迁移为 v3；UUID、名称、顺序、active、模型、endpoint 与安全的 key reference 不丢；v2 bytes 不改 |
| v1 升级 | 用旧 A/B/C snapshot 启动 | 先按 legacy 规则规范，再写 v3；用户自定义 provider/model 不丢 |
| v3/v2 损坏 | 注入不可 decode bytes，并准备对应 LKG | 原 bytes 备份、不被默认值覆写；使用对应 LKG 或安全默认并报错 |
| Settings 可见性 | 预置六类及多个 OpenAI HTTP connection，打开、编辑、关闭 Settings | UI 只显示 OpenAI HTTP；完整 snapshot、隐藏 connection、active ID 与 `apiKeyReference` 不因过滤而改变 |
| 隐藏 active provider | 让 Apple/Realtime 等隐藏 connection 保持 active 后打开 Settings | 概览显示“当前未使用 OpenAI Compatible”，编辑器只选择首个可见 OpenAI connection且不自动激活 |
| adapter 切换兼容 fixture | 通过迁移/兼容测试执行 OpenAI→Dash/Volc/GLM/Apple | 普通 Settings 不提供该入口；底层不支持字段重置、secret boundary 与旧本地记录清理仍受回归覆盖 |
| 自定义 host | 在 OpenAI Compatible 中改非 trusted HTTPS host | Save 前要求显式批准，并显示 key/音频目标 host |
| 不安全 URL | 输入 http/ws、userinfo、query、fragment、歧义 path | Save 被拒绝 |
| Add/半编辑配置 | 新增或输入一半 URL 后 Cancel/触发全局 voice | runtime 仍使用已保存配置；Cancel 不落盘 |
| 同 adapter 多实例 | 建两个不同 endpoint/model/key 的 HTTP connection | 独立显示、编辑、选择；凭据和配置不串用 |
| Test Connection | 使用内置合成音测试 HTTP/Realtime | 验证 transport 与响应结构，不采麦克风；空 transcript 可成功；失败不泄漏 key/响应正文 |
| 无 key 激活 | 选择需要 key 但未保存 key 的 connection | Set Current/Picker 禁用或失败并提示 |
| Clear key | 清除 active connection key | key 删除，active 安全切回 ready connection/Apple |
| 本地文件权限 | 保存虚拟 key 后检查 Flotis 目录、`secrets.json` 与 `.secrets.lock` | 分别为 `0700`、`0600`、`0600`；文件被意外放宽时，下次读取会安全收紧 |
| 损坏/符号链接 | 用损坏 JSON 或指向其他文件的符号链接占据 secret 路径 | 拒绝读写和删除，不覆盖损坏 bytes，不修改链接目标 |
| 多实例保存 | 两个本地 store/两个 Flotis 进程同时保存不同 connection | read-modify-write 由进程内共享锁与跨进程写锁串行化，不丢另一条 reference |
| 旧钥匙串条目 | 从使用旧系统钥匙串的构建升级 | 新构建完全不访问、迁移或删除旧条目；connection 保留但需要重新输入一次 API key |

### 六个语音路径

| Provider | 手动步骤 | 必验结果 |
|---|---|---|
| Apple Speech | 说“你好”；再说两个词并在中间静音 3–5 秒；测试同段纠错、重复词、自然 final、手动 stop、cancel | 短句不被空 final 清空；停顿前后都保留；纠错不重复拼接；只用设备端；final 进入 reviewing 而非注入；无 orphan recording |
| OpenAI Realtime | 多个停顿形成多 item，再 stop | partial 连续；乱序 final 不丢句；commit 后等待终态；可取消 |
| DashScope | 说“好的。好的。”再 stop | 重复句保留；finish-task 后结果收至 task-finished |
| Volcengine | 开/关二遍识别，各录一段 | resource ID/model name 正确；terminal packet 后完成；错误包有提示 |
| OpenAI-compatible HTTP | 默认 `.wav` 与迁移/显式 `.m4a`、自定义 endpoint/model、stop/cancel | MIME/文件匹配；multipart 磁盘流式上传；严格顶层 `text`；cancel 立即结束 |
| GLM HTTP SSE | 接近 30 秒、超过/接近 25 MiB、cancel | 倒计时自动 stop；超限上传前拦截；partial SSE 与 `[DONE]` 正确 |

每个网络 provider 还应验证：无效 key、401/403、429、5xx、断网、慢网络、服务端提前关闭、redirect。Authorization 与完整转写文本不得写入测试报告。

## 建议的并发/诊断验证

- 使用 Thread Sanitizer 分别跑 OpenAI/Dash/Volc stop、cancel、服务端 error 与立即重试，确认 actor/锁/generation 边界无数据竞争。
- 使用 Network Link Conditioner 模拟高延迟/丢包，检查 writer backpressure、drain 和 terminal timeout。
- 对 realtime provider 在说完最后一个短音节后立即 stop，和 cancel 行为对照录音，确认 graceful stop 能交付 conversion queue/`AVAudioConverter` 尾帧而 cancel 不继续发送。
- 在 stop/transcribing 中立即切 provider、清 key、删除 provider并重试，确认旧 task 不覆盖新 session。
- 对 GLM 做 29 秒自动 stop 与 30 秒边缘测试；不要上传真实敏感语音。

## Lint / Format

仓内没有 SwiftLint/SwiftFormat。最低门槛是完整 `xcodebuild build`、`xcodebuild test` 与 `git diff --check`；纯 parse 不等于完整工程验证。
