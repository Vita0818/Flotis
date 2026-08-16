# TESTING

最近验证日期：2026-08-16

## 环境与边界

- 两个 macOS application target，deployment target 13.0，Swift 5.0。
- XcodeGen 生成 `Flotis.xcodeproj`；scheme 为 `Flotis`、`FlotisInputMethod` 与独立的 `FlotisInputMethodTests`。
- 主 App 当前产品路径依赖 Carbon、AppKit、Speech、AVFoundation 与 Darwin 文件系统调用；保留的旧 `ClipboardPasteInjector` 仍编译真实 macOS Accessibility/`CGEvent` 代码但当前不可达。输入法 target 依赖 AppKit/InputMethodKit。二者都不能用 iOS Simulator 验证核心交互。App 源码不再导入 Security 或调用系统钥匙串。
- 无第三方依赖，无仓内 SwiftLint/SwiftFormat 配置。
- 当前没有 UI-test target、SwiftUI snapshot test、Preview fixture 或产品内 debug state 开关；视觉、物理热键、系统剪贴板/返回行为、多模型真实服务与输入客户端验收必须结合真实 macOS 运行态，不能由主 App 单元测试或输入法接口 8 个测试替代。
- API key 明文不进入仓库、UserDefaults、日志或单独凭据文件；自动化只使用临时目录、内存 fake transport 与虚拟字符串。真实 provider 的 key 由操作者在 UI 保存到私有权限 `config.json` 对应 provider 的 `options.apiKey`。

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
xcodebuild \
  -project Flotis.xcodeproj \
  -scheme FlotisInputMethod \
  -configuration Debug \
  -derivedDataPath /tmp/FlotisInputMethodBuildDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
xcodebuild \
  -project Flotis.xcodeproj \
  -scheme FlotisInputMethodTests \
  -configuration Debug \
  -derivedDataPath /tmp/FlotisInputMethodTestDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
git diff --check
git status --short
```

为 build 与 test 使用不同的临时 DerivedData。Xcode 26 的 test action 会把 XCTest framework 复制进 test host；复用已跑过 test 的 app bundle 再次执行普通 build，可能在 app validation 阶段把旧测试 framework 当作产品 framework 检查。

2026-08-16 V0.13 版本与安装验证：

- 主 App `MARKETING_VERSION` 提升为 `0.13`、`CURRENT_PROJECT_VERSION` 提升为 `4`；输入法保持 `0.1.0 (3)`。`xcodegen generate` 后，生成工程和主 App Release Info.plist 均展开为 `0.13 (4)`，输入法生成设置仍为 `0.1.0 (3)`。
- 主 App Debug build `/private/tmp/Flotis-v013-MainBuild-20260816` 与输入法 Debug build `/private/tmp/Flotis-v013-InputBuild-20260816` 均成功。唯一主测试 bundle ID 的 `/private/tmp/Flotis-v013-MainTests-20260816-1624.xcresult` 为 82 tests、0 failures、0 skipped；输入法 `/private/tmp/Flotis-v013-InputTests-20260816-1624.xcresult` 为 8 tests、0 failures、0 skipped。
- ad-hoc Release 位于 `/private/tmp/Flotis-v013-Release-20260816/Build/Products/Release/Flotis.app`；bundle ID 为 `com.Vita0818.FlotisMac`，严格签名校验通过，`Flotis.icns`、`Assets.car` 与可执行文件均存在。构建只保留既有 Apple Speech async-context `NSLock` Swift 6 兼容 warning，以及 XCTest deployment/本机 Xcode 诊断提示。
- 安装前正常退出了两个旧隔离预览；原 `/Applications/Flotis.app` 的 `0.12 (3)` 移到 `/private/tmp/Flotis-before-v0.13-install-20260816-1626.app`。新 `0.13 (4)` 已复制安装、注册 Launch Services 并启动，运行进程来自 `/Applications/Flotis.app/Contents/MacOS/Flotis`；安装副本的可执行文件、`Flotis.icns` 与 `Assets.car` 和 Release 逐字节一致，安装副本严格签名校验通过。
- 没有重新安装、启动或切换用户 Input Methods 副本，没有修改输入法版本；没有读取或输出 Provider/API key、完整配置或转写文本，也没有录音、请求 provider、产生费用或修改系统输入源。

2026-08-16 compact 原生 Liquid Glass 恢复与重新安装验证：

- 用户在 Dark appearance 发现已安装胶囊仍是固定白色。源码根因是 `FloatingPanelView.compactCapsule` 在既有 `NSGlassEffectView(style: .regular)` / `.popover` material 上又绘制 `245/255` 不透明圆角 fill、0.5 pt 黑边和固定近黑文字；当前删除整个 SwiftUI background/overlay，并把快捷键恢复为动态系统主文字色。`FloatingPanelController` 的原生玻璃、旧系统 fallback、阴影、拖动、双击、Space 位置策略和三档静态尺寸未改。
- `xcodegen generate` 与 `git diff --check` 成功。主 App Debug build `/private/tmp/FlotisGlassFix-MainBuild-20260816`、输入法 Debug build `/private/tmp/FlotisGlassFix-InputBuild-20260816` 均成功；唯一测试 bundle ID 的主 App `/private/tmp/FlotisGlassFix-MainTests-20260816.xcresult` 为 82 Success、输入法 `/private/tmp/FlotisGlassFix-InputTests-20260816.xcresult` 为 8 Success。`xcresulttool` 在受限环境无法生成自己的 `TestReport` 临时内容，因此最终数量直接从两个 xcresult 的只读 SQLite `TestCaseRuns` 表核对；主 App 控制台摘要也明确为 82 tests、0 failures。
- 唯一 bundle ID `com.Vita0818.FlotisGlassFixPreview20260816` 的签名 Debug 预览位于 `/private/tmp/FlotisGlassFix-Preview-20260816/Build/Products/Debug/Flotis.app`。按项目规定尝试通过 Computer Use 获取真实窗口时，服务明确返回 `Computer Use was not approved to use Flotis`；没有改用绕过权限的 GUI 自动化，所以本轮不把 Light/Dark 背景采样、Reduce Transparency 或 Increase Contrast 标为运行态通过。此前截图仍只证明 `96×36` 几何、内容和交互，不再证明当前颜色/material token。
- 新 ad-hoc Release 位于 `/private/tmp/Flotis-v013-GlassFix-Release-20260816-1845/Build/Products/Release/Flotis.app`，最终 Info.plist 为 `0.13 (4)` / `com.Vita0818.FlotisMac`，严格签名通过，`Flotis.icns`、`Assets.car` 与可执行文件存在。被替换的固定白底 `0.13 (4)` 已移动到 `/private/tmp/Flotis-before-transparent-glass-fix-v0.13-20260816-1954.app`；玻璃修复版已安装、注册 Launch Services 并从 `/Applications/Flotis.app/Contents/MacOS/Flotis` 启动。安装副本的可执行文件、`Flotis.icns` 与 `Assets.car` 和 Release 逐字节一致，安装副本严格验签通过。
- 本轮没有改动版本号、用户 `config.json`、Provider/API key、语音状态机或输入法源码；没有录音、请求 provider、产生费用，也没有重新安装、启动或切换用户 Input Methods 副本。

2026-08-16 跨 Space 位置瞬移修复验证：

- 根因位于 `FloatingPanelController`：panel 为支持拖动而长期设置 `isMovable=true`，系统可在 Space/显示环境过渡时自行搬动窗口，随后 live frame/逻辑锚点恢复产生可见瞬移。当前鼠标事件之外固定为 `false`；非审阅 mouse-down 仍显式调用 `performDrag(with:)`，reviewing 只在 `super.sendEvent` 分发该 mouse-down 的调用期间临时允许原生 background drag，不改变胶囊外观、尺寸、双击 Settings、reviewing 编辑或程序 resize。
- `HotkeyAndInjectionPolicyTests` 的既有交互测试新增断言：系统管理移动必须关闭，非审阅单击仍为显式 drag、双击仍为 Settings，reviewing 单/双击仍走保留 background drag 的原生转发。定向测试 `/private/tmp/FlotisSpaceTransitionTargetedTests-20260816` 为 26 tests、0 failures。
- `xcodegen generate` 成功。主 App Debug build `/private/tmp/FlotisSpaceTransitionMainBuildFinal-20260816` 与输入法 Debug build `/private/tmp/FlotisSpaceTransitionInputBuildFinal-20260816` 均成功；完整主 App XCTest `/private/tmp/FlotisSpaceTransitionMainTestsFinal-20260816` 为 82 tests、0 failures，输入法 XCTest `/private/tmp/FlotisSpaceTransitionInputTestsFinal-20260816` 为 8 tests、0 failures。
- 唯一 bundle ID `com.Vita0818.FlotisSpaceTransitionPreview20260816` 的 ad-hoc Debug 预览位于 `/private/tmp/FlotisSpaceTransitionPreview-20260816/Build/Products/Debug/Flotis.app`。本机 Computer Use 拒绝访问 Flotis，未启动可控画面流，因此没有把真实 Space 滑动动画、compact 拖动或 reviewing 点击标为运行态通过；没有改用绕过权限的 GUI 自动化，也没有安装或覆盖 `/Applications/Flotis.app`。

2026-08-16 voice 快捷键开放配置验证：

- Settings 唯一快捷键卡片仍严格只有四个 `52` pt 行，没有新增提示、说明或操作；voice 行改为与 panel/previous/next 相同的 `156×38` / 15 pt 可点击录制 surface。保存后写入 canonical `shortcuts.toggle_voice`，`HotkeyManager` 保持 Carbon ID `200` 并差异替换旧注册，胶囊观察同一 store、即时显示新组合。
- 校验覆盖四项都至少含一个修饰键且互不重复；新增策略测试证明 voice 可改、保存重载后仍保留，并证明旧 schema v2 的 shortcuts 对象缺少 `toggle_voice` 时回退默认 `⌃⌥A`。provider 与 comparison 分区仍由同一 read-modify-write 保留。
- `xcodegen generate` 成功。主 App Debug build `/private/tmp/FlotisVoiceHotkeyMainBuild-20260816` 与输入法 Debug build `/private/tmp/FlotisVoiceHotkeyInputBuild-20260816` 均成功。
- 使用唯一 bundle ID `com.Vita0818.FlotisVoiceHotkeyTests20260816` 的完整主 App XCTest `/private/tmp/FlotisVoiceHotkeyMainTests-20260816` 为 82 tests、0 failures、0 skipped；独立输入法 XCTest `/private/tmp/FlotisVoiceHotkeyInputTests-20260816` 为 8 tests、0 failures。
- 唯一 bundle ID `com.Vita0818.FlotisVoiceHotkeyPreview20260816` 的 ad-hoc Debug 预览位于 `/private/tmp/FlotisVoiceHotkeyPreview-20260816/Build/Products/Debug/Flotis.app`，`codesign --verify --deep --strict` 通过；没有安装或覆盖 `/Applications/Flotis.app`。
- 未读取或修改真实 `config.json`、Provider/API key，未录音、请求 provider、启动预览或触碰输入法安装副本。物理录制、旧/新 voice 组合即时切换及胶囊文字变化仍需人工确认。

2026-08-16 Settings 快捷键页第二次极简化验证：

- 唯一快捷键卡片只保留四个 `52` pt 行；固定 voice 只显示无底板 `⌃⌥A`，三项可配置组合从旧 `220×50` / 17 pt 收为 `156×38` / 15 pt，并移除铅笔、常驻对比说明、hover help、逐项恢复和全部恢复控件。直接点击组合键进入同尺寸原生录制态，临时提示收为“按下组合键”；Esc、校验、canonical 持久化、Carbon 增量重注册和真实错误显示路径未改。
- `xcodegen generate` 成功。主 App Debug build `/private/tmp/FlotisShortcutsMinimalCompile-20260816` 与输入法 Debug build `/private/tmp/FlotisShortcutsMinimalInputBuild-20260816` 均成功。
- 使用唯一 bundle ID `com.Vita0818.FlotisShortcutsMinimalTestsFinal20260816` 的最终完整主 App XCTest `/private/tmp/FlotisShortcutsMinimalMainTestsFinal-20260816` 为 80 tests、0 failures、0 skipped；独立输入法 XCTest `/private/tmp/FlotisShortcutsMinimalInputTests-20260816` 为 8 tests、0 failures、0 skipped。结果数量由对应 `.xcresult` 读取确认。
- 可直接检查的 ad-hoc Debug 预览位于 `/private/tmp/FlotisShortcutsMinimalPreview-20260816/Build/Products/Debug/Flotis.app`，bundle ID 为 `com.Vita0818.FlotisShortcutsMinimalPreview20260816`，`codesign --verify --deep --strict` 通过；没有安装或覆盖 `/Applications/Flotis.app`。
- Computer Use 对既有运行态连续两次启动 ScreenCaptureKit 画面流均返回 `-3811`，因此按原生界面验收规则停止继续尝试；本轮没有把快捷键页截图、像素层级或点击录制标为运行态通过。源码层级、完整构建与状态/持久化单测均通过，但 Light/Dark、最小窗口、真实点击录制和错误换行仍需在该预览或后续安装版本中目视确认。
- 未读取或修改真实 `config.json`、Provider/API key，未录音、请求 provider、触发费用或触碰输入法安装副本。构建仍只有既有 Apple Speech `NSLock` Swift 6 兼容 warning、XCTest deployment 与本机 Xcode 诊断提示。

2026-08-16 最小胶囊、原生拖动与双击 Settings 验证：

- 用户参考图为 `284×164 px`，其中可见胶囊精确测得 `192×72 px`，按 `@2x` 还原为 `96×36 pt`；圆点约 `6 pt`。实现使用相同 `96×36`、18 pt 圆角、6 pt 圆点、7 pt 间距和单个 15 pt Semibold Monospaced `⌃⌥A`。`Ask` 仅作为参考图内容存在；按用户最后指示，compact 表面不显示品牌名，也没有按钮、图标、计时、状态/错误句、双击提示或其他说明。
- `xcodegen generate` 成功。最终主 App Debug build `/private/tmp/FlotisCapsuleShortcutMainBuild-20260816` 与输入法 Debug build `/private/tmp/FlotisCapsuleShortcutInputBuild-20260816` 均为 `BUILD SUCCEEDED`。
- 使用唯一 bundle ID `com.Vita0818.FlotisCapsuleShortcutMainTests20260816` 的完整主 App XCTest `/private/tmp/FlotisCapsuleShortcutMainTests-20260816` 为 80 tests、0 failures；独立输入法 XCTest `/private/tmp/FlotisCapsuleShortcutInputTests-20260816` 为 8 tests、0 failures。`HotkeyAndInjectionPolicyTests` 维持 24 tests，并将交互策略锁定为非审阅单击 `beginDrag`、双击 `openSettings`、reviewing 鼠标事件 `forward`。
- 唯一 bundle ID `com.Vita0818.FlotisCapsuleShortcutDragVisual20260816` 的签名隔离 Debug 预览位于 `/private/tmp/FlotisCapsuleShortcutDragVisual-20260816/Build/Products/Debug/Flotis.app`。Computer Use 捕获的最终 idle 窗口为 `/private/tmp/Flotis-Minimal-Capsule-Shortcut-20260816.jpeg`；参考图副本为 `/private/tmp/Flotis-Minimal-Capsule-Reference-20260816.png`，实现按 `2×` 归一化后的等画布并排比较为 `/private/tmp/Flotis-Capsule-Reference-vs-Shortcut-Implementation-20260816.png`，`design-qa.md` 最终为 passed，无 P0/P1/P2 残留。
- 运行态原生 drag gesture 已从 compact SwiftUI surface 成功进入 panel 的 `performDrag(with:)`；单击保持 compact 且不打开 Settings，双击打开既有 `1100×760` Settings。reviewing 事件转发由纯策略测试锁定，避免破坏文本拖选和双击选词。最后一次试图把三项交互合并进同一 ScreenCaptureKit stream 时，Computer Use 遇到环境错误 `-3811`；此前分开的 drag/single/double 运行态结果、最终 idle 截图与 XCTest 不受影响。视觉验收没有按 voice hotkey、录音、请求麦克风/provider、读取/改写配置或触碰输入法。
- 为解除 Carbon 占用并取得真实 idle 绿点，验收时通过原生 `⌘Q` 正常退出了已安装旧版和两个旧隔离预览；最终隔离预览保持为 compact 状态供直接查看。当前实现没有安装或覆盖 `/Applications/Flotis.app`。

2026-08-07 Settings 快捷键页精简与重新安装验证：

- 以用户提供的已安装 Settings 截图为真实问题依据，侧栏品牌区移除应用图标，“General/概览”改名为“Shortcuts/快捷键”；删除固定 voice 流程、胶囊拖动说明、重复 section 标题与每行长描述，只在一张卡中保留固定 voice 和三项可配置组合。当时组合键 surface 由最小 `92×32` / 11 pt 扩至固定 `220×50` / 17 pt，原生录制态同尺寸，录制提示为 14 pt；可配置项整块 surface 可点。该尺寸与恢复控件 contract 已被 2026-08-16 的第二次极简化取代。
- `xcodegen generate` 成功。主 App Debug build `/private/tmp/FlotisShortcutUI-MainBuild-20260807` 与输入法 Debug build `/private/tmp/FlotisShortcutUI-InputBuild-20260807` 均成功。
- 使用隔离 bundle ID `com.Vita0818.FlotisShortcutUIRegression20260807` 的完整主 App XCTest `/private/tmp/FlotisShortcutUI-MainTests-20260807` 为 79 tests、0 failures；独立输入法 XCTest `/private/tmp/FlotisShortcutUI-InputTests-20260807` 为 8 tests、0 failures。
- ad-hoc Release `/private/tmp/FlotisShortcutUI-ReleaseInstall-20260807/Build/Products/Release/Flotis.app` 为 `0.12 (3)`，通过 `codesign --verify --deep --strict`。上一版已移动到 `/private/tmp/Flotis-before-shortcut-ui-install-20260807-2211.app`；新版本已安装到 `/Applications/Flotis.app`、注册 Launch Services 并启动，安装可执行文件、`Flotis.icns` 与 `Assets.car` 和 Release 逐字节一致。更早的可配置快捷键首次安装产物为 `/private/tmp/FlotisHotkeyReleaseInstall-20260807/Build/Products/Release/Flotis.app`，其替换前副本仍在 `/private/tmp/Flotis-before-configurable-hotkeys-install-20260807-2150.app`。
- 原生 Computer Use 服务连续两次启动失败；按产品设计工作流没有改用未授权 GUI 自动化，也没有把当前像素结果标为视觉通过。编译、签名、安装内容和启动链路已核验，最终层级、间距与命中观感仍需用户在已安装应用中目视确认。
- 保留既有 `AppleSpeechTranscriber` async-context `NSLock` Swift 6 兼容 warning、XCTest deployment 与本机 Xcode 诊断提示；本轮没有新增编译 warning。没有录音、请求 provider、产生费用、读取或修改真实 API key，也没有覆盖、启动或切换用户 Input Methods 副本。

2026-08-07 可配置 panel / 对比导航快捷键验证：

- 通用设置新增 panel 显隐、上一个成功结果、下一个成功结果三项录制与恢复入口；默认值仍为 `⌘⌥⇧0`、`⌥←`、`⌥→`，固定 voice `⌃⌥A` 未开放修改。策略覆盖无修饰键、固定 voice 冲突、三项重复拒绝，以及 canonical `shortcuts` 保存、重载并保持 provider/comparison 分区不变；`HotkeyAndInjectionPolicyTests` 为 23 tests、0 failures。
- `xcodegen generate` 成功。主 App Debug build `/private/tmp/FlotisHotkeyMainBuild-20260807` 与输入法 Debug build `/private/tmp/FlotisHotkeyInputBuild-20260807` 均成功。
- 使用隔离 bundle ID `com.Vita0818.FlotisHotkeyRegression20260807` 的完整主 App XCTest `/private/tmp/FlotisHotkeyMainTests-20260807` 为 79 tests、0 failures；独立输入法 XCTest `/private/tmp/FlotisHotkeyInputTests-20260807` 为 8 tests、0 failures。
- `docs/CONFIGURATION_GUIDE.md` 的两个完整 JSON 文档代码块已由 Ruby JSON parser 验证；其余四个 `json` 代码块是有意展示的局部字段片段。
- 构建只保留既有的 `AppleSpeechTranscriber` async-context `NSLock` Swift 6 兼容 warning，以及 XCTest deployment/本机 Xcode 诊断提示；本轮新增源码没有编译错误或新增 warning。该第一阶段尚未启动 UI、录音、请求 provider、读取或修改真实 API key，也尚未安装/替换 `/Applications/Flotis.app` 或用户 Input Methods 副本；随后完成的安装与界面精简见上一节。物理按键录制、Carbon 新旧 descriptor 即时切换和对比态临时注册/注销仍列入人工矩阵。

2026-08-06 V0.12 版本与安装验证：

- 主 App `MARKETING_VERSION` 提升为 `0.12`、`CURRENT_PROJECT_VERSION` 提升为 `3`；输入法保持 `0.1.0 (3)`。`xcodegen generate` 后，生成工程与 Release Info.plist 均展开为 `0.12 (3)`。
- 沙箱内第一次 Release build 仅因 Icon Composer 无法访问系统导出服务失败；在正常 Xcode 环境用同一源码重跑后成功。ad-hoc Release 位于 `/private/tmp/Flotis-v012-Release-20260806/Build/Products/Release/Flotis.app`，严格签名校验通过，`Flotis.icns` 与 `Assets.car` 均存在。
- 唯一 bundle ID 的完整主 App XCTest `/private/tmp/Flotis-v012-MainTests-20260806` 为 77 tests、0 failures；输入法 Debug build `/private/tmp/Flotis-v012-InputBuild-20260806` 成功，输入法 XCTest `/private/tmp/Flotis-v012-InputTests-20260806` 为 8 tests、0 failures。保留既有 Apple Speech Swift 6 锁兼容 warning 与 XCTest deployment warning。
- 安装前 `/Applications/Flotis.app` 为 `0.8.0 (2)`。旧副本已移动到 `/private/tmp/Flotis-before-v0.12-install-20260806-1453.app`，新 `0.12 (3)` 已安装、注册 Launch Services 并启动；最终签名有效，安装可执行文件和 `Flotis.icns` 与 Release 产物逐字节一致，进程从 `/Applications/Flotis.app/Contents/MacOS/Flotis` 运行。
- 本轮没有读取或改写真实 Provider/API key、没有录音或请求供应商，也没有覆盖、启动或切换 `~/Library/Input Methods/FlotisInputMethod.app`。

2026-08-06 Settings / 录音状态 / 多结果导航交互验证：

- Settings 的 Connection、Models、Comparison、Advanced 使用全宽最小 44 pt button，Provider 行至少 48 pt，对比 route 整卡至少 44 pt。录音状态保留原有图标与文案，用 `recordingStartedAt` 驱动 `mm:ss` 并替代右侧 stop 方块；stopping/transcribing 保留原有省略号状态图标与原有文案，只抑制右侧重复的禁用 action。对比 reviewing 为 `560×300` 固定双列网格，首个成功项自动打开，`⌥←` / `⌥→` 跳过失败项并循环导航；候选优先只显示会话开始时快照的 Model Display name，无名称时显示主 Model ID + 次 Provider，不显示 endpoint。
- 新增/修正的策略覆盖使 `HotkeyAndInjectionPolicyTests` 增至 21 tests；`TranscriptionComparisonTests` 仍为 5 tests，覆盖自动首项、失败跳过、前后 wrap、每项编辑保持及 voice hotkey 复制当前项。先用默认 bundle 跑定向测试时，已运行的 `/Applications/Flotis.app` 因 `LSMultipleInstancesProhibited` 在断言前阻止 test host；改用唯一测试 bundle ID 后定向 26 tests、0 failures，确认不是源码或断言失败。
- `xcodegen generate` 成功；主 App Debug build `/private/tmp/FlotisUXFinalMainBuild-20260806`、输入法 Debug build `/private/tmp/FlotisUXFinalInputBuild-20260806` 均成功。唯一 bundle ID 的完整主 App XCTest `/private/tmp/FlotisUXFinalMainTests-20260806` 为 77 tests、0 failures；独立输入法 XCTest `/private/tmp/FlotisUXFinalInputTestsVerbose-20260806` 为 8 tests、0 failures。
- 唯一 bundle ID `com.Vita0818.FlotisUXHandoff` 的 ad-hoc Release 预览产物位于 `/private/tmp/FlotisUXHandoff-20260806/Build/Products/Release/Flotis.app`，并通过 `codesign --verify --deep --strict`；它未启动、未安装，也没有替换当前 `/Applications/Flotis.app`。
- 构建只保留既有的 `AppleSpeechTranscriber` async-context `NSLock` Swift 6 兼容 warning，以及 XCTest deployment/本机 Xcode 诊断提示；本轮新增源码没有引入新的编译 warning。
- 通过规定的原生 Computer Use 路径尝试做交互截图对照时，服务启动连续失败，因此未用其他 GUI 自动化替代，也没有把本轮标为视觉通过。全行鼠标命中、录音计时观感、四项 2×2、物理 Option 方向键注册/注销仍需人工运行态确认。
- 本轮没有读取或改写真实 API key、没有录音、没有请求 provider 或产生费用、没有安装/替换 `/Applications/Flotis.app`，也没有安装、启动或切换输入法。

2026-08-05 Intatis 式 Provider/Models Settings 验证：

- 源码与真实界面参考来自 Intatis 的 `IntatisSettingsPanel` / `IntatisDesign`，运行态参考图为 `/private/tmp/Intatis-Providers-Reference-20260805.jpeg`（折叠）和 `/private/tmp/Intatis-Models-Reference-20260805.jpeg`（Models 展开），视口均为 `1100×760`。
- Flotis 隔离 Debug bundle 的最终运行态捕获为 `/private/tmp/Flotis-Intatis-Style-Models-Collapsed-Composited-20260805.png` 与 `/private/tmp/Flotis-Intatis-Style-Models-Expanded-Composited-20260805.png`，均为 Retina `2200×1584`，即 `1100×792` 外框、`1100×760` 内容。API key 字段只显示占位状态，没有输出密钥。
- 同屏比较图 `/private/tmp/Intatis-Flotis-Models-Collapsed-Comparison-20260805.png` 与 `/private/tmp/Intatis-Flotis-Models-Expanded-Comparison-20260805.png` 均为 `2200×760`，左侧 Intatis、右侧 Flotis。检查了 Provider 列表/选中态、模型计数、Provider name/API key/Active model、Connection/Models disclosure、Add/Delete model、Model ID/Display name、Test Provider/Save、间距、边框、字号与展开层级。
- 第一轮真实捕获发现 HostingController 会把请求的 1100 pt 内容宽度收缩到 `820` pt，只显示窄版布局；这是 P1 视觉问题。修复为在 hosting controller 装配后先设置 `contentMinSize=820×600`，再显式 `setContentSize(1100×760)`，最终折叠与展开均保持 Intatis 式双栏。
- 当前用户 catalog 中存在多个独立 Provider group、每组一个模型，因此最终截图的模型数量与 Intatis 示例的单 Provider 多模型数据不同；没有为截图合并、保存或迁移真实配置。界面和 store 仍支持在同一 Provider 下新增多个模型，并保存每个模型的可选 Display name。
- 主 App 使用唯一测试 bundle ID 的签名 test host 完成 75 tests、0 failures；输入法 application Debug build 成功，输入法 8 tests、0 failures。没有真实 provider 请求、录音、费用、配置保存、主 App 安装或输入法安装；临时视觉捕获 hook 已从源码完全移除。

2026-08-05 schema v2 同 Provider 多模型修正验证：

- `config.json` 当前为 schema v2：一个 provider 保存一次 endpoint/API key/options 和多个 models，active/comparison 使用只在第一个 `/` 分割的完整 selector；fresh document 与迁移结果都不写 Apple。
- OpenRouter route 使用 `json-base64`，fake transport 验证最终 URL、`application/json`、完整 `openai/...` model ID、WAV format 和可还原的 Base64 RIFF 音频；普通 OpenAI-compatible multipart 路径仍保留。
- canonical v1 fixture 验证自动原子升级、Apple 条目删除、同 Provider 两个 slash model ID、active selector 与 key 保留；旧 UserDefaults v3/v2/v1、comparison v1 与 `secrets.json` 仍只作迁移输入。
- Settings 代码路径覆盖 Intatis 式 Provider 列表、Provider name/共享 API key/Active model、Connection/Models disclosure、逐模型 Model ID/Display name、Request Encoding 和同 Provider 多模型对比。折叠/展开新表单已按上节运行态核对；真实 OpenRouter key、真实录音和计费仍须按下方矩阵人工验证。
- `xcodegen generate` 成功；主 App `build-for-testing` `/tmp/FlotisSchemaV2MainBuild-20260805`、输入法 Debug build `/tmp/FlotisSchemaV2InputBuild-20260805` 与 ad-hoc Release `/tmp/FlotisSchemaV2Release-20260805` 均成功。Release 通过 `codesign --verify --deep --strict`。
- schema v2 阶段曾有一次 M4A fixture 受本机 CoreAudio 环境阻止；随后使用唯一测试 bundle ID 的签名 hosted runner 重跑同一完整主测试集，最终 75 tests、0 failures。与本轮直接相关的配置、模型 Display name、5 个对比测试及 OpenRouter JSON+Base64 请求测试均通过；输入法 8 tests、0 failures。
- Release `0.8.0 (2)` 已替换安装并启动于 `/Applications/Flotis.app`，bundle ID 为 `com.Vita0818.FlotisMac`；可执行文件和 `Flotis.icns` 与 Release 产物逐字节一致。旧 app 可从 `/private/tmp/Flotis-before-schema-v2-install-20260805-221200.app` 恢复。安装实例启动后，实际 `config.json` 权限为 `0600`、schema 为 `2`、Apple adapter 条目数量为 `0`；核验没有输出 Provider 内容或 API key。
- `git diff --check` 通过，最终 `git status --short` 保留本任务源码、测试、工程与文档改动。没有真实录音、没有向 OpenRouter 或其他 Provider 发请求/产生费用，也没有重新安装或切换输入法。

2026-08-05 schema v1 单文件阶段历史验证结果（已由 v2 取代）：

- 当时 `config.json` 已完成同文件 key、`.config.lock`、read-modify-atomic-write、`0700`/`0600` 权限与坏文件拒绝，并通过当时的 72 个主 App 测试。其按 UUID connection 索引的 schema v1 不是当前配置格式，只作为 v2 迁移输入。
- 当时 ad-hoc Release `0.8.0 (2)` 已安装到 `/Applications/Flotis.app`；该阶段的安装副本随后已由上节记录的 schema v2 Release 重新构建并替换。

2026-08-05 多模型 recorded-file 对比历史验证结果（交互已由 2026-08-06 版本取代）：

- 当时新增 `TranscriptionComparisonStore` / `FileTranscriptionComparisonRunner` 与 5 个策略测试，覆盖 2–4 项偏好、坏数据不覆写、同一 file URL fan-out、provider 失败隔离、结果顺序与人工选择门控。该阶段的“不预选”和 `560×250` 横向布局已被 2026-08-06 的自动首项、方向键导航与 `560×300` 双列布局取代。
- 第一次完整主测试在测试代码执行前被已运行的 `/Applications/Flotis.app` 占用 `LSMultipleInstancesProhibited`；系统日志明确返回 “already running”。正常退出该安装实例后，定向 `TranscriptionComparisonTests` 5 tests、0 failures，完整主 App `/tmp/FlotisComparisonMainTestsFinal-20260805.xcresult` 为 70 tests、0 failures。这不是编译、签名或断言问题。
- `xcodegen generate` 成功；主 App Debug build `/tmp/FlotisComparisonMainBuildFinal-20260805`、输入法 Debug build `/tmp/FlotisComparisonInputBuildFinal-20260805` 成功；输入法 `/tmp/FlotisComparisonInputTestsFinal-20260805.xcresult` 为 8 tests、0 failures。`git diff --check` 通过。
- 构建仍只有既有的 `AppleSpeechTranscriber` async-context `NSLock` Swift 6 兼容 warning，以及 XCTest deployment dylib/本机 Xcode 诊断提示；新增对比测试自身未再引入锁 warning。
- 本轮没有读取或修改真实 API key、没有录音或请求任何 provider，也没有安装/启动输入法、切换输入源、调用 AX 或发送 `CGEvent`。用户随后明确要求安装当时实现：Release `/tmp/FlotisComparisonInstall-20260805` 使用 `CODE_SIGN_IDENTITY=-` 构建成功并通过 `codesign --verify --deep --strict`；旧 app 移到 `/private/tmp/Flotis-before-multiprovider-install-20260805-1524.app`，新 app 安装到 `/Applications/Flotis.app`。安装版本为 `0.8.0 (1)`、bundle ID `com.Vita0818.FlotisMac`，可执行文件与 Release 产物逐字节一致，启动后进程稳定；设置与应用支持数据未删除。这里记录的是历史安装，不代表 2026-08-06 新交互已安装或已做运行态验收。

2026-08-04 Icon Composer 应用图标与主 App 安装验证结果：

- 用户新增的根目录 `Flotis.icon` 包含 `icon.json` 与一张 `1636×1280` RGBA 图层；已按 Xcode 原生 Icon Composer 路径加入主 `Flotis` target Resources，并设置 `ASSETCATALOG_COMPILER_APPICON_NAME=Flotis`。XcodeGen 生成工程把它识别为 `wrapper.icon`，没有改动独立输入法的 TIFF 图标或 target。
- Debug 与 Release 的 `actool` 都同时编译 `Assets.xcassets` 和 `Flotis.icon`；产物生成 `Flotis.icns`、`Assets.car`，最终 Info.plist 为 `CFBundleIconFile=Flotis`、`CFBundleIconName=Flotis`。从 `.icns` 导出的 256 px 系统帧为白色圆角底、灰色对话框与声波；安装副本与 Release 产物的可执行文件和 `.icns` 分别逐字节一致。
- `xcodegen generate` 成功；主 App Debug build `/tmp/FlotisAppIconDebugBuild-20260804`、输入法 Debug build `/tmp/FlotisAppIconInputBuild-20260804` 成功。完整主 App XCTest `/tmp/FlotisAppIconMainTests-20260804` 为 65 tests、0 failures；输入法 XCTest `/tmp/FlotisAppIconInputTests-20260804` 为 8 tests、0 failures。
- 主 App Release `/tmp/FlotisAppIconRelease-20260804` 使用 `CODE_SIGN_IDENTITY=-` 构建成功并通过 `codesign --verify --deep --strict`。完整 app 已安装到 `/Applications/Flotis.app`、注册 Launch Services 并成功启动；安装版本为 `0.8.0 (1)`、bundle ID `com.Vita0818.FlotisMac`。这是 ad-hoc 本机身份，不等于 Developer ID/notarized 分发。
- 本轮没有重新安装、启动或切换 `FlotisInputMethod.app`，没有录音、访问 provider/API key、修改系统权限或触发剪贴板确认链路。

2026-08-04 idle 胶囊再收窄与快捷键清晰度验证结果：

- `FloatingPanelLayout.idlePanelWidth` 从 116 pt 调整为 108 pt，高度仍为 54 pt；两个 `30×30` hit area、8 pt 间距、两枚图稿、action、无障碍标签和其余三档 panel 尺寸未改。位置策略 fixture 同步改为当前宽度，并继续覆盖中心/底边保持、可见区钳位与 reviewing 后恢复逻辑锚点。
- 下方固定 `⌃⌥A` 从 11 pt Medium 系统 Monospaced/动态次级灰改为 12 pt Semibold 系统 Monospaced/动态主文字色，继续单行显示且不把字体或颜色写死为特定 Light/Dark 值。
- 使用签名隔离 build `/tmp/FlotisShorterCapsuleVisual-20260804` 做真实运行态检查；Computer Use 截图精确为 `108×54`，两枚按钮未裁切或拥挤，快捷键清晰可见，AX tree 仍暴露 `Start`、`Settings` 与完整 `Press ⌃⌥A to start recording`。随后已正常退出预览；没有点击 Start、录音、修改 Settings、访问 provider/API key/AX，也没有安装、启动或切换输入法。
- `xcodegen generate` 成功；主 App Debug build `/tmp/FlotisShorterCapsuleMainBuild-20260804`、输入法 Debug build `/tmp/FlotisShorterCapsuleInputBuild-20260804` 成功。完整主 App XCTest `/tmp/FlotisShorterCapsuleMainTests-20260804` 为 65 tests、0 failures；输入法 XCTest `/tmp/FlotisShorterCapsuleInputTests-20260804` 为 8 tests、0 failures。
- 本次运行态只覆盖当前系统 appearance 的窗口级白底合成；Dark、Reduce Transparency、Increase Contrast 与 macOS 13–25 material fallback 仍保留在人工视觉矩阵中。

2026-08-04 黑色八齿设置图标验证结果：

- 用户提供的 `1061×1061` RGBA PNG 透明通道确认为完整八齿齿轮；原图已更新到 `docs/assets/settings-gear-button-reference.png`，并生成 `SettingsGearButton.imageset` 的 16×16、32×32、48×48 三档透明黑色资源。
- `FloatingPanelView` 用 28 pt 固定白圆承载 16 pt 黑色齿轮，与旁边 28 pt 白圆黑声波使用同一视觉语法；两个 `30×30` hit area、8 pt 间距、Settings 无障碍标签/帮助与 action 均未改变。亮背景由黑齿轮提供识别，暗背景由白圆提供识别，未给整个原生 glass 重新加 tint。
- 第一版只给旧白齿轮增加约 0.75 pt 深色轮廓，真实白底窗口截图仍过轻，因此未保留；最终新图在真实白底运行态中轮廓和中心孔清晰，AX tree 仍暴露 `Start`/`Settings`，实际打开并关闭既有 Settings 窗口成功。
- `xcodegen generate` 成功；主 App Debug build `/tmp/FlotisNewGearMainBuild-20260804`、输入法 Debug build `/tmp/FlotisNewGearInputBuild-20260804` 成功。完整主 App XCTest `/tmp/FlotisNewGearMainTests-20260804` 为 65 tests、0 failures；输入法 XCTest `/tmp/FlotisNewGearInputTests-20260804` 为 8 tests、0 failures。
- 视觉检查后已正常退出临时 app；没有点击 Start、录音、修改 Settings、访问 provider/API key/AX，也没有安装、启动或切换输入法。

2026-08-04 `⌃⌥A` voice hotkey 验证结果：

- `KeyboardShortcutDescriptor.toggleVoice` 已固定为 Carbon virtual key `0`/A 与 Control+Option；胶囊与 Settings 共用的显示值为 `⌃⌥A`。策略测试同时锁定 key code、modifier 与 display contract，既有 Carbon exclusive registration 和 press/release gate 未改变。
- 通用三段式 Settings 说明不包含具体键位，本次无需修改 `UIStrings`。start → stop → reviewing/copy-and-return 状态机、panel 可见性、剪贴板写入与旧注入器不可达边界未改。
- `xcodegen generate` 成功；主 App Debug build `/tmp/FlotisControlOptionAMainBuild-20260804`、输入法 Debug build `/tmp/FlotisControlOptionAInputBuild-20260804` 成功。完整主 App XCTest `/tmp/FlotisControlOptionAMainTests-20260804` 为 65 tests、0 failures；输入法 XCTest `/tmp/FlotisControlOptionAInputTests-20260804` 为 8 tests、0 failures。
- 本轮未手动启动产品 App、未按物理组合键、未录音、未访问 provider/凭据/AX，也未安装或启动输入法。`⌃⌥A` 的真实 start/stop/copy-and-return 三次触发仍在手动矩阵中。

2026-08-04 `⌃⌥⇧W` voice hotkey 临时方案验证结果（已被后续 `⌃⌥A` 取代）：

- `KeyboardShortcutDescriptor.toggleVoice` 已固定为 Carbon virtual key `13`/W 与 Control+Option+Shift；胶囊与 Settings 共用的显示值为 `⌃⌥⇧W`。策略测试同时锁定 key code、modifier 与 display contract，既有 Carbon exclusive registration 和 press/release gate 未改变。
- Settings 已移除 F5/麦克风键及系统功能键说明，恢复为与具体键位解耦的三段式操作文案。start → stop → reviewing/copy-and-return 状态机、panel 可见性、剪贴板写入与旧注入器不可达边界未改。
- `xcodegen generate` 成功；主 App Debug build `/tmp/FlotisCtrlOptionShiftWMainBuild-20260804`、输入法 Debug build `/tmp/FlotisCtrlOptionShiftWInputBuild-20260804` 成功。完整主 App XCTest `/tmp/FlotisCtrlOptionShiftWMainTests-20260804` 为 65 tests、0 failures；输入法 XCTest `/tmp/FlotisCtrlOptionShiftWInputTests-20260804` 为 8 tests、0 failures。
- 当时未手动启动产品 App、未按物理组合键、未录音、未访问 provider/凭据/AX，也未安装或启动输入法。该结果只作为已取代方案的历史记录，不再属于当前手动矩阵。

2026-08-04 标准 F5 voice hotkey 临时方案验证结果（已被后续固定组合键方案取代）：

- `KeyboardShortcutDescriptor.toggleVoice` 已固定为 Carbon virtual key `0x60`/标准 F5、无修饰键；胶囊与 Settings 共用的显示值为 `F5`。新增策略测试同时锁定 key code、modifier 与 display contract，既有 Carbon exclusive registration 和 press/release gate 未改变。
- 本机 Apple 顶排仍处于系统功能模式；按 Apple 官方定义，麦克风图标在该模式下属于系统功能而非标准 F5。Flotis 没有改系统设置、监听 consumer-control 听写事件或引入 Input Monitoring：当前模式需按 `Fn-F5`，直接按麦克风图标需先由用户在 Keyboard Settings 启用标准功能键。
- `xcodegen generate` 成功；最终主 App Debug build `/tmp/FlotisF5FinalMainBuild-20260804`、输入法 Debug build `/tmp/FlotisF5InputBuild-20260804` 成功。最终完整主 App XCTest `/tmp/FlotisF5FinalMainTests-20260804` 为 65 tests、0 failures；输入法 XCTest `/tmp/FlotisF5InputTests-20260804` 为 8 tests、0 failures。
- 独立一次性 `LSUIElement` Carbon 探针在本机以 `kVK_F5`、0 modifiers、`kEventHotKeyExclusive` 注册返回 `status=0, registered=yes`，随后立即注销并删除临时探针。该结果证明标准 F5 当前可被 Carbon 独占注册，但不证明默认系统功能模式下的物理麦克风键会发出标准 F5。
- 当时未启动 App、未按物理麦克风键、未录音、未触发系统听写、未访问 provider/凭据/AX，也未安装或启动输入法。该结果只作为已取代方案的历史记录，不再属于当前手动矩阵。

2026-08-04 原生 Liquid Glass 修正验证结果：

- 根因确认：macOS 26+ 外壳已是 `NSGlassEffectView(style: .regular)`，但整面 `tintColor = .black` 与 SwiftUI hosting root 的 18% 黑色背景叠加后，把系统自适应材质压成普通深色磨砂。修正移除这两层，继续保留原生 `.regular`、20 pt 圆角、macOS 27+ `effectIsInteractive` 与 macOS 13–25 material fallback；未改胶囊尺寸、图稿、点击区域、快捷键、拖动、审阅或语音状态机。
- 使用本机签名身份构建 `/tmp/FlotisNativeGlassVisual-20260804` 并通过 Computer Use 启动隔离预览；真实运行态确认 `116×54` idle 胶囊恢复系统亮色自适应表面与边缘高光，Start/Settings/快捷键 AX 元素仍存在。窗口级截图服务会把透明窗口单独合成在白底，无法可靠证明彩色背景折射，因此跨背景动态采样仍保留为人工目视项。
- `xcodegen generate` 成功；主 App Debug build `/tmp/FlotisNativeGlassMainBuild-20260804`、输入法 Debug build `/tmp/FlotisNativeGlassInputBuild-20260804` 成功。完整主 App XCTest `/tmp/FlotisNativeGlassMainTests-20260804.xcresult` 为 64 tests、0 failures；输入法 XCTest `/tmp/FlotisNativeGlassInputTests-20260804.xcresult` 为 8 tests、0 failures。
- 测试前已正常退出旧 Xcode Debug 实例和隔离视觉预览；视觉核验没有点击录音/设置按钮，没有访问麦克风、provider、API key、AX 或剪贴板，也没有安装、启动或切换输入法。

2026-08-04 审阅取消位置恢复验证结果：

- 根因是 reviewing 大框靠近屏幕边缘时会被可见区钳位，而旧实现下一次 resize 直接以这个临时大框 frame 计算锚点，导致取消缩回后沿用被移动的中心。现在 panel 独立保存 `FloatingPanelPositionAnchor`；程序 resize 的 `windowDidMove` 不回写锚点，用户拖动才更新。
- 新增右侧边缘矩阵：`116×54` 胶囊位于可见区右缘，展开 `420×160` 时临时左移，缩回仍恢复原 `x/y`。定向 `HotkeyAndInjectionPolicyTests` 在 `/tmp/FlotisPanelAnchorTargetedTest` 为 18 tests、0 failures。
- `xcodegen generate` 成功；最终主 App Debug build `/tmp/FlotisPanelAnchorFinalBuild`、输入法 Debug build `/tmp/FlotisPanelAnchorInputBuild` 成功；最终完整主 App XCTest `/tmp/FlotisPanelAnchorFinalTest` 为 64 tests、0 failures，输入法 XCTest `/tmp/FlotisPanelAnchorInputTest` 为 8 tests、0 failures。
- 本轮未启动 App、未录音、未请求 provider、未访问凭据，也未安装/启动输入法。真实窗口拖到屏幕边缘后完成转写并取消的组合仍需当前构建运行态确认。

2026-08-04 三段式复制并返回验证结果：

- reviewing 热键策略由 `copyAndClose` 改为 `copyAndReturn`；`VoiceInputController.toggleRecording()` 不再返回窗口 action outcome。第三次热键和右侧“复制并返回”按钮共用同一同步 clipboard 路径：只用 trim 拒绝纯空白，实际写入保留用户编辑文本原样；成功推进 generation、清空文字并回 `idle`，失败保持 reviewing/文字和可重试错误。
- AppDelegate、panel controller 与 SwiftUI view 中的 `.closePanel` / `onClosePanel` 路径已移除。复制成功后 panel 保持可见，`VoiceInputState` 回 idle 触发 `420×160` 审阅框按 `FloatingPanelPositionAnchor` 缩回原位置的 `116×54` 小胶囊；隐藏状态下触发 voice hotkey 仍会恢复胶囊可见性。
- `xcodegen generate` 成功；主 App Debug build `/tmp/FlotisCopyReturnMainBuild-20260804` 与输入法 Debug build `/tmp/FlotisCopyReturnInputBuild-20260804` 成功。最终完整主 App XCTest `/tmp/FlotisCopyReturnMainTestsPassed-20260804` 为 64 tests、0 failures；隔离输入法 XCTest `/tmp/FlotisCopyReturnInputTestsRetry-20260804` 为 8 tests、0 failures。
- 主测试最初被 Xcode 中仍在调试的旧 Flotis 唯一实例占用，LaunchServices 在测试代码执行前拒绝启动 host；该 app 受对应 `debugserver` 保持，普通/强制结束 app PID 均未释放。结束仅对应的 debugserver 后，同一源码在全新 DerivedData 全部通过，不是编译、签名或断言失败。
- 本轮没有启动新 App、录音、请求 provider、访问凭据、安装/启动输入法、调用 AX 或发送 `CGEvent`。真实三次物理热键、剪贴板内容与审阅框缩回原胶囊位置仍需人工验证。

2026-08-04 三段式复制并关闭历史验证结果（同日稍后的复制并返回决定已取代该行为）：

- reviewing 热键策略由 `inject` 改为 `copyAndClose`；第三次热键和审阅确认按钮共用 `VoiceInputController.toggleRecording()` 的 outcome。clipboard writer 只用 trim 拒绝纯空白，实际写入保留用户编辑文本原样；成功才重置 session/文字并返回 `.closePanel`，失败保持 reviewing/文字并显示错误。
- 当前可达入口已移除目标 app 捕获、`ClipboardPasteInjector.inject`、AX 轮询/提示和 Settings AX 卡；旧注入器、安全失败类型、`.injecting` state 与测试仍保留但不可达。审阅页右侧确认改为“复制并关闭”，左侧复制全部仍只复制、不关闭。
- `xcodegen generate` 成功；主 App Debug build `/tmp/FlotisCopyCloseBuild` 与输入法 Debug build `/tmp/FlotisCopyCloseInputBuild` 成功；最终主 App XCTest `/tmp/FlotisCopyCloseTest2` 为 63 tests、0 failures，其中 `HotkeyAndInjectionPolicyTests` 为 17 tests，新增复制成功重置/关闭请求与复制失败保留审阅两个测试；隔离输入法 XCTest `/tmp/FlotisCopyCloseInputTest` 为 8 tests、0 failures。
- 第一次 `/tmp/FlotisCopyCloseTest` 只因旧 `/private/tmp/FlotisLiquidGlassVisualBuild/.../Flotis` 预览仍运行、`LSMultipleInstancesProhibited=YES` 阻止 test host 启动而失败；仅退出 PID 68934 后，全新 DerivedData 的同一源码全部通过，不是编译或断言失败。
- 该阶段未启动新 App、未采集麦克风、未请求 provider、未读取/保存真实 API key，也未调用 AX/`CGEvent`。当时尚待人工验证的 panel 关闭行为现已从产品路径删除。

2026-08-03 胶囊比例与 Liquid Glass 精修验证结果：

- idle 几何由 `120×56` 轻收为 `116×54`，双按钮间距由 10 pt 收为 8 pt；设置图稿由 26 pt 收为 24 pt，并从用户原图重新生成 24×24、48×48、72×72 三档 asset。两个按钮的 `30×30` hit area、无障碍标签/帮助、action、快捷键与非 idle 状态均未改变。
- macOS 26+ 的整个 panel surface 使用原生 `NSGlassEffectView(style: .regular)` 与 20 pt 圆角；macOS 27+ 开启 `effectIsInteractive`。SwiftUI hosting content 只在该路径增加 18% 黑色对比层；macOS 13–25 继续走 `.popover` `NSVisualEffectView`、alpha `maskImage` 与原生阴影 fallback。
- `xcodegen generate` 成功；签名视觉 build `/tmp/FlotisLiquidGlassVisualBuild` 成功，未签名主 App build `/tmp/FlotisLiquidGlassCompile` 成功，输入法 Debug build `/tmp/FlotisLiquidGlassInputBuild` 成功。最终主 App XCTest `/tmp/FlotisLiquidGlassFinalMainTest` 为 61 tests、0 failures；输入法 XCTest `/tmp/FlotisLiquidGlassInputTest` 为 8 tests、0 failures。
- Computer Use 在真实 macOS 运行态捕获最终 `116×54` idle 胶囊，并完成旧版/新版全胶囊与 24 pt 齿轮局部合成对比；设置按钮仍暴露为 `Settings` button，打开/关闭既有独立 Settings 窗口正常。`design-qa.md` 最终为 passed。
- 坐标式拖动冒烟落入录音按钮区域并短暂进入 recording；已立即终止且重启临时视觉预览，没有执行 stop/transcribe、provider 请求、reviewing 或注入。由于这次误触，最终 glass surface 的空白区拖动未再次做坐标自动化；拖动策略单测与此前真实拖动验证仍通过，但新 surface 的人工拖动保留在手动矩阵。

2026-08-03 idle 录音按钮视觉替换验证结果：

- 用户提供的 `1009×1010` PNG 原图已原样保存在 `docs/assets/voice-waveform-button-reference.png`，并生成 `Flotis/Assets.xcassets/VoiceWaveformButton.imageset` 的 28×28、56×56、84×84 三档资源。首次把 loose PNG 当 bundle resource 时 SwiftUI 运行态没有解析到命名图；改为 asset catalog 后恢复稳定加载。
- 原图的黑色声波实际是透明镂空；首次运行态会透出 material 成为灰色。最终在 28 pt 图稿内加入完全被白圆覆盖的黑色 backing，使镂空稳定呈现为黑色且不会产生外部黑边。修改只发生在 idle 开始录音分支；30×30 点击区域、Start 无障碍标签/帮助、action、快捷键和非 idle 状态图标均未改变。
- `xcodegen generate` 成功；主 App 最终签名 Debug build `/tmp/FlotisVoiceButtonVisualBuild` 成功，输入法 Debug build `/tmp/FlotisVoiceButtonFinalInputBuild` 成功。主 App 最终 XCTest `/tmp/FlotisVoiceButtonFinalTest2` 为 61 tests、0 failures；输入法 XCTest `/tmp/FlotisVoiceButtonFinalInputTest` 为 8 tests、0 failures。
- 第一次最终主 App test `/tmp/FlotisVoiceButtonFinalTest` 仅因视觉预览实例仍在运行、`LSMultipleInstancesProhibited=YES` 阻止 test host 启动而失败；正常退出该预览实例后，同一源码在全新 DerivedData 中重跑全部通过，不是编译或测试断言失败。
- 已在真实 macOS 运行态检查 idle 胶囊，并将参考图与运行态按钮做并排放大对比；白圆、六条黑色圆角声波的数量、顺序和比例一致，`design-qa.md` 结论为 passed。为避免真实录音副作用，没有点击 Start，因此未申请麦克风、未访问 provider/API key、未触发 AX 或发送 `CGEvent`。

2026-08-03 设置按钮视觉替换验证结果：

- 用户提供的 `1139×1138` 透明 PNG 已原样保存在 `docs/assets/settings-gear-button-reference.png`，并生成 `Flotis/Assets.xcassets/SettingsGearButton.imageset` 的 26×26、52×52、78×78 三档资源；SHA-256 与用户临时原图一致。SwiftUI 使用原始色彩与透明区域，不再使用 `gearshape` SF Symbol。
- 设置按钮继续使用原 `30×30` 点击区域、Settings 无障碍标签/帮助与 `onOpenSettings()` action，仅将居中的可见图稿改为 26 pt。录音按钮、快捷键、胶囊尺寸、语音状态和 Settings 内容没有改变。
- `xcodegen generate` 成功；主 App 签名 Debug build `/tmp/FlotisSettingsButtonVisualBuild` 与输入法 Debug build `/tmp/FlotisSettingsButtonFinalInputBuild` 均成功。主 App XCTest `/tmp/FlotisSettingsButtonFinalTest` 为 61 tests、0 failures；输入法 XCTest `/tmp/FlotisSettingsButtonFinalInputTest` 为 8 tests、0 failures。
- Computer Use 在真实 idle 胶囊中确认白色齿轮的外圈齿、三段内构、中心圆点与参考一致，并实际点击 Settings、打开既有独立设置窗口、再正常关闭返回胶囊；AX tree 中该控件仍为 `Settings` button。没有改动任何配置、凭据或权限。
- 参考图与运行态 `30×30` 按钮区域已组成同一张放大比较图；最新 `design-qa.md` 为 passed。Dark、Reduce Transparency 与 Increase Contrast 尚未分别截图，但图稿使用固定原始白色、透明区域继续显示既有原生 material。

2026-08-02 输入法签名、安装与运行态验证结果：

- Release build 使用 `CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=-` 生成本机 ad-hoc 签名的 build `3`；项目未配置 Development Team，因此这是“Sign to Run Locally”级别的本机验证身份，不是稳定 Apple Development 或发布签名。最终产物与安装副本均通过 `codesign --verify --deep --strict`。
- 输入法元数据改为 `LSBackgroundOnly=YES`，顶层与 `Flotis Voice` mode 均声明并打包 `FlotisInputMethodIcon.tiff`。安装副本位于 `~/Library/Input Methods/FlotisInputMethod.app`，其可执行文件与 Release product 逐字节一致，`CFBundleVersion=3`。
- 首次安装的 build `2` 在 `_IMKServerLegacy initWithName:controllerClass:delegateClass:` 崩溃；入口由 legacy nil-delegate initializer 改为 `IMKServer(name:bundleIdentifier:)` 后，build `3` 可稳定后台运行。已在确认进程持续存活且无新崩溃报告后正常终止冒烟实例，安装副本保留但当前不在运行。
- `TISRegisterInputSource` 返回 `0`，但当前登录会话对 bundle `com.Vita0818.FlotisInputMethod` 与 mode `com.Vita0818.FlotisInputMethod.Voice` 的精确枚举仍为 `0`。尝试正常刷新 `TextInputMenuAgent` 未改变结果；SIP 拒绝原地 kickstart `com.apple.imklaunchagent`，未绕过系统保护。下一步必须由用户注销并重新登录，再在 Keyboard Settings 启用 `Flotis Voice`。
- `FlotisInputMethodTests` 使用独立 `/tmp/FlotisInputMethodInstallTest3`：8 tests、0 failures、0 unexpected；主 `Flotis` scheme 使用 `/tmp/FlotisInstallRegression`：61 tests、0 failures、0 unexpected。没有访问 provider/API key、麦克风、剪贴板或辅助功能。
- 因当前会话尚未发现输入源，没有切换到 `Flotis Voice`，也没有在 TextEdit 执行菜单 commit、普通键盘透传或焦点竞态矩阵；本轮只证明签名/安装副本有效且 server 可稳定启动，不证明任何文本客户端已收到文字。

2026-08-01 隔离 InputMethodKit 接口验证结果：

- `xcodegen generate` 成功；生成工程含 `Flotis`、`FlotisInputMethod`、`FlotisTests`、`FlotisInputMethodTests` 四个 target，以及三个 scheme。
- `FlotisInputMethod` 独立 Debug build 在 `/tmp/FlotisInputMethodDerived` 成功；生成 app 的 Info.plist 已展开 bundle ID、connection/controller class、顶层/模式级 input-source ID 与 macOS 13 minimum version；`otool -L` 确认链接 InputMethodKit/AppKit，`nm` 确认 Objective-C runtime class `_OBJC_CLASS_$_FlotisInputController` 存在。
- `FlotisInputMethodTests` 在 `/tmp/FlotisInputMethodTestsDerived` 为 8 tests、0 failures，覆盖精确原文、协议版本、空白、1 MiB 上限、旧/关闭 session、弱 endpoint 与 client failure。
- 原 `Flotis` scheme 在独立 `/tmp/FlotisRegressionDerived` 回归为 61 tests、0 failures。既有非致命 warning 仍是 `AppleSpeechTranscriber` 在 Swift 5 模式下的 Swift 6 `NSLock` 兼容提示，以及 macOS 13 test target 链接较新 XCTest dylib；本次未修改对应源码。
- 没有复制到 `~/Library/Input Methods`、启动输入法、切换系统输入源、连接主 App、访问麦克风/provider/API key 或向真实文本客户端提交文字。因此自动化只证明 bundle/接口可构建与纯策略正确，不证明系统发现或客户端兼容。

2026-08-01 拖动、辅助功能、注入与 Settings 重构验证结果：

- 根因确认：panel 源码明确关闭了 `isMovableByWindowBackground`，且每次 resize/show 都回到底部中央；`run.sh` 每次启动主动 reset Accessibility TCC，同时 Debug app 为 ad-hoc 签名；注入目标是在结束阶段按“最近 app”推断且焦点恢复窗口过短，失败只返回 Bool；旧 Settings 把权限、退出、连接与表单动作堆在同一平面。
- panel 现允许从非交互背景拖动，`resizedOrigin` 策略单测覆盖保持用户中心/底边和屏幕可见区钳制；原生 `NSTextView.mouseDownCanMoveWindow=false` 保持文字拖选优先。
- AX 状态检查保持非提示式，用户点击授权或实际注入缺权才发起提示式请求并打开系统设置。`run.sh` 通过 `bash -n`，复用固定临时 DerivedData，不再删除缓存或运行 `tccutil reset`，并对 ad-hoc 产物输出稳定签名提示。
- controller 在录音开始前捕获目标 app；注入策略覆盖显式面板重激活、第三方 app 切换拒绝、PID 定向 `⌘V`、完整快捷键释放、operation 过期和类型化失败文案。没有放宽 AX、frontmost、pasteboard 或剪贴板恢复核验。
- Settings 运行态 Light appearance 冒烟覆盖通用页、转写页、折叠高级区、右侧滚动和窗口尺寸约束；视觉检查发现并修复了内容展开时侧栏/页头向标题栏溢出，最终 GeometryReader 约束下 chrome 固定。没有输入、保存或清除 API key。
- `xcodegen generate` 与 `bash -n run.sh`：成功。
- 最终独立 Debug build：`/tmp/FlotisFourFixesFinalBuild`，成功；第一次沙箱内验证被 SwiftUI macro plugin 的 `sandbox_apply` 拦截，使用正常 Xcode 构建权限后同一源码通过，不是源码错误。
- 最终完整 XCTest：`/tmp/FlotisFourFixesFinalTest`，61 tests、0 failures、0 skipped。
- 已启动并关闭独立 Debug 测试实例做视觉/拖动冒烟；未授予 Accessibility、未采集麦克风、未读取或保存真实 API key、未请求 provider、未向真实目标文本框发送 `CGEvent`。AX 授权跨重编译稳定性与真实目标消费粘贴仍需用户在 Apple Development 签名的新构建上确认。

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

26 tests：

- V0.13 语音热键严格映射 start → stop → reviewing/copyAndReturn。
- copy-and-return 成功时原样交给 clipboard writer、重置会话并回 idle；panel 保持可见并缩回小胶囊。
- clipboard writer 失败时保留 reviewing、编辑文字和可区分错误供重试。
- requesting/connecting 保持 cancel；stopping/transcribing/injecting 忽略重复动作。
- Carbon hotkey 使用独占注册。
- press gate 在 release 前只接受一次按下，并可 reset。
- voice descriptor 默认 `⌃⌥A`（Carbon key `0` 与 Control/Option），但可录制、持久化为其他合法组合；旧 shortcuts 缺少 `toggle_voice` 时回退默认值。
- panel/previous/next 可配置 descriptor 保留 `⌘⌥⇧0` / `⌥←` / `⌥→` 默认值；四项共同覆盖至少一个修饰键、重复拒绝，以及 canonical `shortcuts` 持久化/重载且不改 provider/comparison 分区。
- 录音开始时间在 recording→streaming 期间保持，在离开捕获态后清空；计时格式覆盖 `mm:ss` 与小时边界。
- 保留旧注入器要求当前 voice 主键及相关修饰键都释放后才允许继续。
- 保留旧注入器的显式胶囊重试只允许重激活捕获目标。
- reviewing 之外所有状态和 status/error 都保持 `96×36`；单结果 reviewing 为 `420×160`，对比 reviewing 为 `560×300`。
- 非审阅 compact 单次 mouse-down 进入原生拖动，双击打开 Settings；reviewing 鼠标事件不被 panel 截获。
- panel 在 mouse-down 分发之外禁止系统管理移动，避免 Space/显示环境过渡改写相对屏幕位置；显式 compact drag 与 reviewing background drag 策略仍可达。
- 对比 reviewing 使用独立 `560×300` 静态尺寸，单结果仍为 `420×160`。
- panel resize 保持用户拖动后的水平中心与底边。
- panel resize 会把拖动位置钳制在目标屏幕可见区。
- reviewing 大框被可见区临时钳位后，缩回小胶囊仍使用展开前的逻辑位置锚点。
- 旧注入失败保留可区分的用户错误文案。
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

28 tests：

- 六个稳定 adapter ID、runtime connection v3 编码兼容以及 unsupported/legacy 字段省略。
- 全新 canonical config 是空 provider catalog，不持久化 Apple；Add 只创建内存 draft，Save 前不持久化，也不写 UserDefaults。
- 通用 HTTP 默认 WAV PCM16 16 kHz mono，prompt/temperature 默认 nil；preset 只填字段，不改 identity/adapter。
- canonical v1 自动升级为 grouped v2：Apple 条目删除，slash model ID、active selector、endpoint/options/key 保留；旧 v3/v2/v1 connection、comparison v1 与 `secrets.json` 只读迁移，canonical 存在后忽略旧源。
- 同一个 OpenRouter provider 拥有两个模型和一份共享 endpoint/key/reference；不同 provider 的边界继续隔离。
- secret boundary 覆盖 adapter、scheme、host、effective port、auth；边界变化会轮换 reference，provider、新 key 与旧 key 清理在同一 canonical 原子事务内提交，失败一起回滚。
- provider/model 更新、删除、Clear key 与 comparison 分区更新都不覆盖同文件其他字段；损坏 canonical JSON 被拒绝且原 bytes 不被默认值覆写。
- API key 明文只进入 canonical `provider.<id>.options.apiKey`；Test Connection fingerprint 覆盖配置与 credential revision，名称变化不失效。
- 自定义 endpoint 显式 approval 与不安全/歧义 URL 拒绝。
- Canonical Flotis 目录 `0700`，`config.json` / `.config.lock` 为 `0600`；旧 `LocalSecretStore` 的并发、损坏与符号链接防护仍作为一次性迁移读取器回归保留。

### `TranscriptionAdapterRuntimeTests`

11 tests：

- registry 恰好注册六个唯一 adapter；重复 ID 被拒绝，六条路径只生成声明的三类通用 runtime plan。
- OpenAI-compatible HTTP 生成严格 multipart WAV；OpenRouter 生成 JSON+Base64 `input_audio` 并保留完整 slash model ID；自定义 endpoint/model/key 按 provider 隔离；显式 M4A 使用匹配扩展名与 MIME。
- HTTP 只接受 `application/json` 与顶层 `text`，错误 Content-Type/嵌套猜测被拒绝。合成测试音得到合法空 `text` 时仍可判定 transport/响应结构成功。
- 失败摘要限长；自定义端点原样回显非 `sk-*` 的任意 opaque API key 时仍被精确脱敏。
- GLM SSE 要求正确 media type、有效 JSON、明确 delta/done 与 `[DONE]`，并脱敏错误中的实际 Key。
- scripted OpenAI Realtime 验证 GA `session.update`、audio append、manual commit、commit ack 与 completed terminal lifecycle。

### `LocalizationTests`

4 tests：

- `zh-Hans`、`zh-CN`、`zh-SG`、`zh-MY` 作为第一首选语言时选择简中。
- 繁体中文、英文、日文、法文、粤语、空数组和非法标识回退英文。

### `TranscriptionComparisonTests`

5 tests：

- 对比偏好至少需要 2 个 model selector，最多按顺序保存 4 个；同 Provider 的多个 slash model ID 可分别选择，正好 2 个仍保持开启，降为 1 个自动关闭。
- 损坏偏好安全回退为关闭且不会在加载阶段覆盖原 bytes。
- 候选安装后按 selector/display 顺序自动打开首个成功项；前后导航跳过失败项并在两端循环，切换成功候选时分别保留编辑内容。
- reviewing 第三次动作复制当前候选的当前编辑文本并清空会话；控制器前后导航与点击候选共用同一 selection 状态。
- runner 把同一个录音 file URL 交给所有 job，按 selector 顺序返回，并把单个 route 错误隔离成失败候选。
- 只允许第一首选语言决定界面语言；后续列表中的简中不能覆盖第一语言。
- 简中与英文 case 分别选择对应文案。

### `FlotisInputMethodServiceTests`

8 tests（独立 `FlotisInputMethodTests` target）：

- 当前 session 将原始文本原样交给 endpoint，不 trim 或改写内容。
- 不支持的 protocol version、纯空白和超过 1 MiB 的 UTF-8 payload 在 delivery 前拒绝。
- 新 activation 与匹配的 deactivate 都会让旧 session 失效。
- endpoint 为弱引用；controller 生命周期结束后请求返回 endpoint unavailable。
- client 无法提交时返回可区分的 client failure。

自动化单测刻意针对纯策略、迁移、组装、本地 secret 文件、对比 fan-out 与 mock transport；真实 Carbon、AX、pasteboard、audio engine、跨进程崩溃/断电窗口以及多个 WebSocket/HTTP 服务端不是 unit-test 能完全替代的边界。

## Presentation / Design System 视觉验收

每次修改 `FlotisDesign.swift`、`FloatingPanelView.swift`、`FloatingPanelController.swift`、`VoiceSettingsView.swift` 或 `IntatisStyleSpeechProviderSettingsView.swift` 后，至少手动检查：

- Light / Dark appearance，以及 Reduce Transparency / Increase Contrast 开关前后。
- idle、requesting permission、connecting、recording/streaming、stopping/transcribing、reviewing、failed，以及保留但当前不可达的 injecting。compact 状态按最新最小化要求只用语义圆点作可见差异，完整状态/错误必须仍出现在 accessibility value；reviewing 内候选成功/失败不能只靠颜色表达。
- 单结果 reviewing 中的长 CJK/Latin、多行、滚动、选区、caret、右键 Copy、`⌘C`、复制全部、空文本禁用、取消与复制并返回；对比 reviewing 还要检查 2–4 个候选的固定双列布局（四项为 2×2、无横向滚动）、成功/失败的非颜色表达、Display name 存在时只显示该名称、Display name 为空时显示主 Model ID + 次 Provider、endpoint 不可见、长名称/model/provider 截断、首个成功项自动打开、用户配置的 previous/next（默认 `⌥←` / `⌥→`）跳过失败项并循环，以及候选切换后的编辑内容保持。点击文本时 panel 可成为 key，但当前确认不应激活或切换任何目标 app。
- compact `96×36`、单结果审阅 `420×160`、对比审阅 `560×300` 三档静态 panel 尺寸、首次屏幕底边位置、从 compact 任意位置开始的原生拖动、resize 后中心/底边保持、小屏/多屏可见区、显示器拔插/排列变化与跨 Space；切换桌面的整个系统动画期间胶囊都必须保持同一相对屏幕位置，不能先落在旧/错误位置再在动画结束瞬移。所有非审阅状态与 status/error 必须保持同一 compact frame，不能因隐藏文案产生尺寸跳变。连续快速状态切换不能回放旧尺寸或跳到另一屏幕。特别检查靠边小胶囊展开时允许大框临时内移，取消后必须回到展开前位置；若用户主动拖动大框，缩回则采用新位置。
- Settings 只能通过 compact 胶囊双击打开可复用独立窗口，单击不得打开，reviewing 双击必须保留文本选词；不能附着成胶囊 sheet，重复双击只前置同一窗口，关闭不能误关胶囊。实际内容初始尺寸应为 `1100×760`、最小 `820×600`；缩放、切页、展开 Models/Connection/高级项和滚动时，侧栏与页头必须保持在标题栏下方，1100 pt 宽时主卡必须保持双栏。侧栏左上只显示 `Flotis` 与版本、不得出现应用图标，导航应为“快捷键 / 转写”。快捷键页只能有一张紧凑卡和四个 `52` pt 行；voice、panel、previous、next 四项都使用 `156×38` / 15 pt Monospaced 的轻量 surface，整块可点，录制态保持同尺寸、获得键盘焦点并可用 Esc 取消。常态不得显示流程、拖动、对比条件、hover help、铅笔或恢复控件；真实错误文本不得被裁切。Connection、Models、Comparison、Advanced 标题应整行至少 44 pt 可点，Provider 行至少 48 pt，对比 route 整卡可切换；点击文案或空白区域也必须生效。
- 转写页的主卡应与 Intatis 信息层级一致：左侧 Providers 标题/Add、Provider 列表与模型数；右侧 Provider name、共享 API key、Active model、Connection 和 Models disclosure。Models 展开后每个模型有独立 Model ID、可选 Display name 和删除动作，并可 Add model；Test Provider/Save 在卡片下方。音频格式、采样率、声道、response mode 和其他 adapter 选择不出现。
- Flotis 特有的 2–4 route Comparison 与费用提醒放在主卡下方的独立 disclosure；Language/Prompt/Temperature 继续位于高级区。检查 OpenAI Compatible 空态、多 provider 新增/切换/未保存草稿门控、同 Provider 多模型、隐藏 adapter 保留、OpenRouter 自动 JSON+Base64、custom endpoint warning/confirmation、Clear API Key、Test Provider、对比不足 2 项/超过 4 项/失效项 reconcile、disabled/error/success、Esc 与 `⌘W`。
- compact 外壳必须为 `96×36`、18 pt 圆角的透明系统 glass/material；SwiftUI 内容层不得出现固定白色/不透明填充或自定义整圈描边，快捷键文字必须随 Light/Dark appearance 使用动态主文字色。内容只能是 6 pt 状态圆点和 15 pt Semibold Monospaced 的当前 voice 快捷键，二者垂直居中、间距 7 pt。修改 voice 后文字必须即时更新，不得继续显示旧组合。不得出现品牌名、旧双白圆资源、SF Symbol、齿轮、计时、状态/错误文字、双击提示、说明或额外 action；录音/流式红点、处理中/失败橙点、idle 绿点应清楚但不抢过快捷键。
- macOS 26+ 原生 `NSGlassEffectView(style: .regular)` panel 容器、窗口阴影与 macOS 13–25 Material fallback 仍需真机核对。至少把胶囊跨明暗背景移动并分别切换 Light/Dark，确认表面会采样背景、系统边缘高光仍存在且文字保持可读；Reduce Transparency/Increase Contrast 打开后应遵循系统 fallback，而不是退化成代码写死的白底。此前参考图 QA 只证明 `96×36` 几何、内容层级与双击入口，不再作为固定浅色 token 的当前依据。

## 真机手动验证矩阵

### 输入法安装与客户端

仅在用户明确要求安装后执行；稳定 Apple Development 身份是重复安装与长期使用的目标，ad-hoc 身份只适合本机冒烟并必须明确其缓存/身份限制：

| 场景 | 操作 | 预期 |
|---|---|---|
| 系统发现 | 将签名后的 `FlotisInputMethod.app` 安装到用户 Input Methods 目录，再按当前 macOS 要求刷新登录会话/输入源列表 | Keyboard Settings 中只出现声明的 `Flotis Voice` 输入源；不影响主 Flotis app |
| 激活与透传 | 在 TextEdit 选择 Flotis Voice 后输入普通键盘文字 | 普通文字由客户端正常处理，输入法不吞键、不产生额外文本 |
| 菜单接口测试 | 在空白文本框保持 caret，执行输入法菜单“插入接口测试文本” | 测试文本只出现在当前插入点；切换目标后的旧 session 不会提交 |
| 客户端矩阵 | 分别在 TextEdit、Notes、浏览器普通 input/textarea 与至少一个不支持标准文本输入的控件测试 | 标准 IMK client 可提交；不支持的控件安全失败，不向其他 app 发送文字 |
| 焦点竞态 | 触发请求前后快速切 app、关窗口、换文本框或禁用输入源 | 延迟请求因 session 不匹配或 client 缺失被拒绝，不落入新目标 |
| 隐私检查 | 检查 Console、UserDefaults 与应用支持目录 | 不出现接口测试文本或未来 transcript；输入法不创建 secret/audio/clipboard 数据 |

### 构建、启动与权限

| 场景 | 操作 | 预期 |
|---|---|---|
| 冷启动 | `./run.sh` | 工程生成/增量构建成功，app 启动；脚本不删除 DerivedData、不重置 TCC；ad-hoc 产物会提示配置稳定签名 |
| AX 未授权 | 拒绝/撤销 Accessibility 后完成三段式语音 | 第三次仍可复制并返回小胶囊，不显示 AX 提示、不发送 `CGEvent`；Settings 不展示 AX 卡 |
| 麦克风拒绝 | 拒绝 microphone | 会话进入明确 failed，可取消/重试，不遗留 audio engine |
| Speech 拒绝/设备不支持 | 空 catalog 时启动内部 Apple 设备端 fallback | 明确报告设备端识别不可用，不退回云端；`config.json` 不出现 Apple Provider |
| 简中系统语言 | 将第一首选语言设为简体中文并重启 App | 胶囊、Settings、App 自定义错误与权限说明均为简中；中文标题使用系统默认字体 |
| 英文/其他系统语言 | 将第一首选语言设为英文、繁中或其他语言并重启 App | App 自定义界面统一为英文；英文品牌和标题使用 Serif |
| 多语言顺序 | 第一语言设为日文，后续保留简中并重启 | App 使用英文，不扫描后续简中改写界面语言 |

### 热键与面板

| 场景 | 操作 | 预期 |
|---|---|---|
| 默认 toggle | 默认 panel `⌘⌥⇧0` / voice `⌃⌥A` | panel 与 voice 各自响应一次；隐藏时 voice 显示胶囊，reviewing 第三次成功复制后保持可见并缩回 idle |
| compact Settings 入口 | idle/录音/处理/failed 分别单击、双击；reviewing 文本双击 | 单击不打开 Settings；非审阅双击打开或前置同一个独立窗口；reviewing 双击正常选词，不触发 Settings；胶囊表面不显示该操作的提示或图标 |
| 自定义 panel 快捷键 | 在“快捷键”页录制一个新的双修饰键组合，再分别按旧组合和新组合 | 新组合立即显示并控制 panel；旧组合不再触发；重启后仍恢复新组合；重新录制默认 descriptor 后可回到默认值 |
| 自定义 voice 快捷键 | 点击语音输入行录制一个未占用的新组合，再观察胶囊并分别按旧组合、新组合，最后重启 | 胶囊立即只显示新组合；旧组合不再触发 voice，新组合继续执行 start/stop/copy-and-return；重启后仍恢复新组合 |
| 自定义对比导航 | 把 previous/next 改为两个不同组合，分别在 idle、单结果 reviewing 与多结果 reviewing 中按下 | 前两种状态不抢占按键；仅多结果 reviewing 中临时生效、跳过失败项并循环；离开后立即注销 |
| 快捷键校验 | 对任一行尝试无修饰键、与另一项相同，并用其他 app 独占一个合法新组合 | 前两种不写入并显示明确错误；外部 Carbon 冲突可见且解除冲突后自动重试，不覆盖原 `config.json` 其他分区 |
| 胶囊拖动 | 从 compact 胶囊圆点、快捷键或其余任意表面开始拖到屏幕边缘，切换到 reviewing 后取消；再从 reviewing 的非文本区域主动拖动并取消 | compact 任意位置均进入原生窗口拖动且不误开 Settings；大框可为保持可见而临时内移，第一次取消后小胶囊回到展开前位置；主动拖动大框后以新中心/底边缩回，文本拖选不会移动窗口 |
| 三段式 voice | 连续完成开始、停止/转写、确认三个阶段 | idle→recording/streaming→reviewing→clipboard copy→idle capsule visible；所有非审阅阶段保持同一 `96×36` 胶囊，只由圆点在 idle 绿、录音红、处理中橙之间变化，不出现按钮、计时、状态句或提示；不会在转写完成时自动复制 |
| 对比三段式 | 在一个 OpenRouter Provider 下建立 2–4 个 ready model route、勾选并开启对比；依次开始、停止、查看结果 | endpoint/key 只配置一次；麦克风只录制一次；各模型请求并发处理；`560×300` 审阅页按选择顺序用双列展示，四项为 2×2，首个成功项自动打开且无需横向滚动 |
| 对比导航与编辑 | 自动打开候选 A 后修改，按当前 next（默认 `⌥→`）到 B 修改，再按当前 previous（默认 `⌥←`）回 A，最后按当前 voice 快捷键 | A/B 各自编辑内容保持；导航快捷键跳过失败项并在边界循环；第三次 voice hotkey 只复制当前 A；候选清空、临时导航热键注销、panel 缩回原位置 idle |
| 对比部分失败 | 让一个 endpoint 返回错误、另一个成功 | 成功结果仍可选择/编辑；失败卡显示失败语义和可查看的受限错误，不取消成功项、不泄漏 key/完整响应 |
| 对比取消 | 录音中和并发转写中分别取消 | 所有 request/transcriber 取消，共享临时文件清理，不出现延迟候选覆盖下一会话 |
| 按住/自动重复 | 按住当前 voice 快捷键约 2 秒后松开 | 整次物理按下只触发一个动作，松开后下一次按下才生效 |
| 处理中误按 | stopping/transcribing 中再次按语音热键 | 忽略，不取消终态处理、不清空即将审阅的转写 |
| 胶囊编辑 | reviewing 点击文本修改，再按当前 voice 快捷键或点“复制并返回” | 剪贴板获得包含首尾在内的原样编辑文本，审阅框清空并缩回原位置小胶囊；不激活、不切换、不输入到任何目标 app |
| 审阅复制 | reviewing 选中部分文字按 `⌘C`、右键 Copy，再测试复制全部图标 | 部分选区或全文进入剪贴板；文本仍可继续编辑，窗口不随拖选移动 |
| 编辑后取消 | reviewing 修改后按 Esc/取消 | 清空本次文本并回 idle，不复制 |
| 复制后下一轮 | 第三次成功缩回后再按一次 voice hotkey | 当前可见小胶囊直接开始新录音；不会重复复制上一轮文字 |
| 热键冲突 | 让系统或其他 app 独占当前 voice 或任一其他用户配置组合后启动 Flotis | 错误持久显示；解除冲突后自动重试成功 |
| 旧命令兼容 | 启动 V0.13 并检查旧 commands.json | 不展示命令、不注册命令热键，也不改写或删除旧文件 |

### 当前剪贴板确认

| 场景 | 操作 | 预期 |
|---|---|---|
| 第三次热键 | reviewing 再按语音热键 | 系统剪贴板替换为原样审阅文本，状态回 idle，panel 保持可见并缩回原位置小胶囊；不恢复旧剪贴板 |
| 审阅确认按钮 | 点击右侧“复制并返回” | 与第三次热键完全一致 |
| 复制全部按钮 | 点击左侧复制图标 | 全文进入剪贴板但仍停留 reviewing，panel 不关闭，可继续编辑 |
| 部分复制 | 选中文字按 `⌘C` 或右键 Copy | 只复制选区，reviewing 与原文保持 |
| 纯空白 | 将审阅内容改成纯空白后确认 | 动作禁用或显示无可复制文字；panel/审阅不丢失 |
| 外部粘贴 | 成功返回小胶囊后由用户在任意 app 手动 `⌘V` | 由用户选择的位置收到剪贴板文字；Flotis 不参与目标选择或事件发送 |

保留的 `ClipboardPasteInjector` 不是当前产品手测项。只有未来用户明确重新启用旧注入路径时，才恢复 AX、目标 PID/frontmost、完整快捷键释放、队列/过期、复杂剪贴板 snapshot、外部 clipboard 竞争与恢复矩阵；在此之前不得把这些结果描述为当前三段式流程的要求。

### Provider 配置与迁移

| 场景 | 操作 | 预期 |
|---|---|---|
| 全新安装 | 在无 canonical 文件与旧输入时启动 | schema v2 `config.json` 的 provider catalog 为空且没有 Apple 条目；Settings 显示 OpenAI Compatible 空态，由用户点击 Add 创建未持久化草稿 |
| canonical v1 升级 | 用含 Apple、OpenRouter 和 slash model ID 的 schema v1 文件启动 | 原子改写为 v2；Apple 删除；Provider、模型、endpoint、active 与 key 保留；selector 只在首个 `/` 分割 |
| 旧分散配置升级 | 用 v3/v2/v1 snapshot、comparison v1 与旧 secret 启动 | 一次写入 canonical v2；网络配置、名称、顺序、active、模型、endpoint、可恢复 comparison、key/reference 尽量保留，Apple 不持久化；旧 bytes 不改，之后改动旧源不影响运行时 |
| canonical 损坏 | 用不可 decode、未知 schema 或结构不一致的 bytes 占据 `config.json` | Provider/comparison 在内存安全降级并报错，所有保存被拒绝，原 bytes 不被默认值覆写 |
| Settings 可见性 | 预置多个 adapter/provider/model，打开、编辑、关闭 Settings | adapter UI 只显示 OpenAI HTTP；Intatis 式左 Provider/右详情主卡不改变完整 canonical document，隐藏 provider/model、active selector 与 key/reference 不因过滤而改变 |
| 隐藏 active provider | 让 Realtime 等隐藏 route 保持 active 后打开 Settings | editor 选择首个可见 OpenAI provider 但不因打开页面自动激活；只有显式 Save 才改变当前 route |
| adapter 切换兼容 fixture | 通过迁移/兼容测试执行 OpenAI→Dash/Volc/GLM/Apple | 普通 Settings 不提供该入口；底层不支持字段重置、secret boundary 与旧本地记录清理仍受回归覆盖 |
| 自定义 host | 在 OpenAI Compatible 中改非 trusted HTTPS host | Save 前要求显式批准，并显示 key/音频目标 host |
| 不安全 URL | 输入 http/ws、userinfo、query、fragment、歧义 path | Save 被拒绝 |
| Add/半编辑配置 | 新增或输入一半 URL 后 Cancel/触发全局 voice | runtime 仍使用已保存配置；Cancel 不落盘 |
| 同 Provider 多模型 | 在一个 OpenRouter Provider 的 Models disclosure 中 Add 两个 `openai/...` 模型，并分别填写 Display name | endpoint/key 只保存一次；两个 Model ID/name 独立持久化，两个 route 在 Comparison 中独立出现并可并发选择，Active model 只决定默认单模型路径 |
| 多 Provider 隔离 | 建两个不同 endpoint/key/name 的 HTTP Provider | 左侧 Provider 列表独立显示并带模型数；凭据和配置不串用，Save 后仅显式 Active model 成为当前 route |
| 对比偏好持久化 | 选择 2–4 个 selector 并开启，重启后再删除其中一个模型 | `comparison.enabled` / `comparison.models` 的顺序/开关恢复；失效 selector 被 reconcile，剩余少于 2 项时自动关闭；同文件 provider/key 不被改写 |
| 对比分区损坏 | 向 canonical 顶层写入非法 comparison/ID 结构后启动 | 对比安全关闭并提示，原 canonical bytes 不被空默认覆盖 |
| Test Connection | 使用内置合成音测试 HTTP/Realtime | 验证 transport 与响应结构，不采麦克风；空 transcript 可成功；失败不泄漏 key/响应正文 |
| 无 key 激活 | 选择需要 key 但未保存 key 的 route | Set Current/Picker 禁用或失败并提示 |
| Clear key | 清除 active Provider 的共享 key | key 删除，该 Provider 的全部模型变为未就绪；不得只让一个 sibling model 继续偷偷使用旧 key |
| 本地文件权限 | 保存虚拟 key 后检查 Flotis 目录、`config.json` 与 `.config.lock` | 分别为 `0700`、`0600`、`0600`；API key 与 endpoint/model 位于同一 provider options/models 结构 |
| 损坏/符号链接 | 用损坏 JSON 或指向其他文件的符号链接占据 canonical 路径 | 拒绝读写，不覆盖损坏 bytes，不修改链接目标 |
| 多实例保存 | 两个本地 store/两个 Flotis 进程同时更新不同 provider/comparison 分区 | read-modify-write 由进程内共享锁与跨进程写锁串行化，不丢另一个分区的更新 |
| 旧钥匙串条目 | 从使用旧系统钥匙串的构建升级 | 新构建完全不访问、迁移或删除旧条目；网络 Provider 保留但需要重新输入一次 API key |

### 六个语音路径

| Provider | 手动步骤 | 必验结果 |
|---|---|---|
| Apple Speech | 说“你好”；再说两个词并在中间静音 3–5 秒；测试同段纠错、重复词、自然 final、手动 stop、cancel | 短句不被空 final 清空；停顿前后都保留；纠错不重复拼接；只用设备端；final 进入 reviewing 而非注入；无 orphan recording |
| OpenAI Realtime | 多个停顿形成多 item，再 stop | partial 连续；乱序 final 不丢句；commit 后等待终态；可取消 |
| DashScope | 说“好的。好的。”再 stop | 重复句保留；finish-task 后结果收至 task-finished |
| Volcengine | 开/关二遍识别，各录一段 | resource ID/model name 正确；terminal packet 后完成；错误包有提示 |
| OpenAI-compatible HTTP | OpenAI multipart、OpenRouter JSON+Base64、默认 `.wav` 与迁移/显式 `.m4a`、自定义 endpoint/model、stop/cancel | URL/encoding 与 Provider 匹配；完整 model ID 不被首个 `/` 后再次截断；严格顶层 `text`；cancel 立即结束 |
| GLM HTTP SSE | 接近 30 秒、超过/接近 25 MiB、cancel | 倒计时自动 stop；超限上传前拦截；partial SSE 与 `[DONE]` 正确 |

每个网络 provider 还应验证：无效 key、401/403、429、5xx、断网、慢网络、服务端提前关闭、redirect。Authorization 与完整转写文本不得写入测试报告。

对比模式至少先用同一 OpenRouter Provider 的两个模型，再用两个不同 OpenAI-compatible Provider，验证同一 `.wav` 文件内容/大小一致、请求近似同时开始、候选顺序不受完成先后影响、逐 route 费用提示可见、最严格 upload/录制限制生效，以及全部失败时只进入一次全局失败。Realtime、Apple、DashScope、Volcengine 与 GLM 不是当前 Settings 可选的对比范围，不得用单个 route 测试结果推导其已支持共享捕获。

## 建议的并发/诊断验证

- 使用 Thread Sanitizer 分别跑 OpenAI/Dash/Volc stop、cancel、服务端 error 与立即重试，确认 actor/锁/generation 边界无数据竞争。
- 使用 Network Link Conditioner 模拟高延迟/丢包，检查 writer backpressure、drain 和 terminal timeout。
- 对 realtime provider 在说完最后一个短音节后立即 stop，和 cancel 行为对照录音，确认 graceful stop 能交付 conversion queue/`AVAudioConverter` 尾帧而 cancel 不继续发送。
- 在 stop/transcribing 中立即切 provider、清 key、删除 provider并重试，确认旧 task 不覆盖新 session。
- 对 GLM 做 29 秒自动 stop 与 30 秒边缘测试；不要上传真实敏感语音。

## Lint / Format

仓内没有 SwiftLint/SwiftFormat。最低门槛是主 App 与输入法接口各自的完整 `xcodebuild build` / `xcodebuild test`（按变更范围执行）以及 `git diff --check`；纯 parse 不等于完整工程验证。
