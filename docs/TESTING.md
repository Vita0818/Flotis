# TESTING

最近验证日期：2026-08-04

## 环境与边界

- 两个 macOS application target，deployment target 13.0，Swift 5.0。
- XcodeGen 生成 `Flotis.xcodeproj`；scheme 为 `Flotis`、`FlotisInputMethod` 与独立的 `FlotisInputMethodTests`。
- 主 App 当前产品路径依赖 Carbon、AppKit、Speech、AVFoundation 与 Darwin 文件系统调用；保留的旧 `ClipboardPasteInjector` 仍编译真实 macOS Accessibility/`CGEvent` 代码但当前不可达。输入法 target 依赖 AppKit/InputMethodKit。二者都不能用 iOS Simulator 验证核心交互。App 源码不再导入 Security 或调用系统钥匙串。
- 无第三方依赖，无仓内 SwiftLint/SwiftFormat 配置。
- 当前没有 UI-test target、SwiftUI snapshot test、Preview fixture 或产品内 debug state 开关；视觉、物理热键、系统剪贴板/返回行为与输入客户端验收必须结合真实 macOS 运行态，不能由主 App 65 个测试或输入法接口 8 个测试替代。
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

19 tests：

- V0.8 语音热键严格映射 start → stop → reviewing/copyAndReturn。
- copy-and-return 成功时原样交给 clipboard writer、重置会话并回 idle；panel 保持可见并缩回小胶囊。
- clipboard writer 失败时保留 reviewing、编辑文字和可区分错误供重试。
- requesting/connecting 保持 cancel；stopping/transcribing/injecting 忽略重复动作。
- Carbon hotkey 使用独占注册。
- press gate 在 release 前只接受一次按下，并可 reset。
- 固定 voice descriptor 为 `⌃⌥A`，并锁定 Carbon key `0` 与 Control/Option。
- 保留旧注入器要求当前 voice 主键及相关修饰键都释放后才允许继续。
- 保留旧注入器的显式胶囊重试只允许重激活捕获目标。
- 四档胶囊尺寸保持稳定，status 不改变 reviewing 高度。
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

### `FlotisInputMethodServiceTests`

8 tests（独立 `FlotisInputMethodTests` target）：

- 当前 session 将原始文本原样交给 endpoint，不 trim 或改写内容。
- 不支持的 protocol version、纯空白和超过 1 MiB 的 UTF-8 payload 在 delivery 前拒绝。
- 新 activation 与匹配的 deactivate 都会让旧 session 失效。
- endpoint 为弱引用；controller 生命周期结束后请求返回 endpoint unavailable。
- client 无法提交时返回可区分的 client failure。

自动化单测刻意针对纯策略、迁移、组装、本地 secret 文件与 mock transport；真实 Carbon、AX、pasteboard、audio engine、跨进程崩溃/断电窗口以及 WebSocket/HTTP 服务端不是 unit-test 能完全替代的边界。

## Presentation / Design System 视觉验收

每次修改 `FlotisDesign.swift`、`FloatingPanelView.swift`、`FloatingPanelController.swift` 或 `VoiceSettingsView.swift` 后，至少手动检查：

- Light / Dark appearance，以及 Reduce Transparency / Increase Contrast 开关前后。
- idle、requesting permission、connecting、recording/streaming、stopping/transcribing、reviewing、failed，以及保留但当前不可达的 injecting；状态不能只靠颜色表达。
- reviewing 中的长 CJK/Latin、多行、滚动、选区、caret、右键 Copy、`⌘C`、复制全部、空文本禁用、取消与复制并返回；点击文本时 panel 可成为 key，但当前确认不应激活或切换任何目标 app。
- 四档静态 panel 尺寸、首次屏幕底边位置、背景拖动、resize 后中心/底边保持、小屏/多屏可见区、显示器拔插/排列变化、跨 Space 与长错误单行截断；连续快速状态切换不能回放旧尺寸或跳到另一屏幕。特别检查靠边小胶囊展开时允许大框临时内移，取消后必须回到展开前位置；若用户主动拖动大框，缩回则采用新位置。
- Settings 只能通过可复用独立窗口打开，不能附着成胶囊 sheet；齿轮重复点击只前置同一窗口，关闭不能误关胶囊。缩放、切页、展开高级项和滚动时，侧栏与页头必须保持在标题栏下方。
- 主表单只显示 Model、Endpoint（Base URL / Path 两个输入共用一个标签）、API Key；Connection Name、多连接侧栏、音频格式、采样率、声道、response mode 以及其他 adapter 选择不出现，Language/Prompt/Temperature 只在折叠高级区。
- OpenAI Compatible 空态、隐藏 active provider、custom endpoint warning/confirmation、Clear API Key、connection test、disabled/error/success、Esc 与 `⌘W`。
- 按钮 hover/focus/disabled 层级、键盘导航、idle 双白圆资源、其余 SF Symbol 与文字标签；idle 外壳当前应为 `108×54`，录音图稿必须保持白圆六条黑色圆角声波，设置图稿必须保持 28 pt 白圆中的 16 pt 黑色八齿齿轮，二者均不得裁切或产生外部黑边，下方 `⌃⌥A` 应为清晰的 12 pt Semibold 系统 Monospaced/动态主文字色。主操作使用系统动态黑/白，红/橙/绿只用于明确语义状态。
- macOS 26+ 原生 Liquid Glass 路径必须核对 `NSGlassEffectView(style: .regular)`、系统默认自适应 tint、无 hosting-root 全表面深色填充，并在真实运行态检查边缘高光与背景适配；macOS 13–15 Material/native bordered fallback 也需真机核对。当前自动化不能证明两条路径的实际像素和交互。

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
| Speech 拒绝/设备不支持 | Apple provider 启动 | 明确报告设备端识别不可用，不退回云端 |
| 简中系统语言 | 将第一首选语言设为简体中文并重启 App | 胶囊、Settings、App 自定义错误与权限说明均为简中；中文标题使用系统默认字体 |
| 英文/其他系统语言 | 将第一首选语言设为英文、繁中或其他语言并重启 App | App 自定义界面统一为英文；英文品牌和标题使用 Serif |
| 多语言顺序 | 第一语言设为日文，后续保留简中并重启 | App 使用英文，不扫描后续简中改写界面语言 |

### 热键与面板

| 场景 | 操作 | 预期 |
|---|---|---|
| 固定 toggle | `⌘⌥⇧0` / `⌃⌥A` | panel 与 voice 各自响应一次；隐藏时 voice 显示胶囊，reviewing 第三次成功复制后保持可见并缩回 idle |
| 胶囊拖动 | 从按钮和审阅文本以外的空白处把小胶囊拖到屏幕边缘，切换到 reviewing 后取消；再在 reviewing 主动拖动并取消 | 可拖动；大框可为保持可见而临时内移，第一次取消后小胶囊回到展开前位置；主动拖动大框后以新中心/底边缩回，文本拖选不会移动窗口 |
| 三段式 voice | 连续完成开始、停止/转写、确认三个阶段 | idle→recording/streaming→reviewing→clipboard copy→idle capsule visible；不会在转写完成时自动复制 |
| 按住/自动重复 | 按住 `⌃⌥A` 约 2 秒后松开 | 整次物理按下只触发一个动作，松开后下一次按下才生效 |
| 处理中误按 | stopping/transcribing 中再次按语音热键 | 忽略，不取消终态处理、不清空即将审阅的转写 |
| 胶囊编辑 | reviewing 点击文本修改，再按 `⌃⌥A` 或点“复制并返回” | 剪贴板获得包含首尾在内的原样编辑文本，审阅框清空并缩回原位置小胶囊；不激活、不切换、不输入到任何目标 app |
| 审阅复制 | reviewing 选中部分文字按 `⌘C`、右键 Copy，再测试复制全部图标 | 部分选区或全文进入剪贴板；文本仍可继续编辑，窗口不随拖选移动 |
| 编辑后取消 | reviewing 修改后按 Esc/取消 | 清空本次文本并回 idle，不复制 |
| 复制后下一轮 | 第三次成功缩回后再按一次 voice hotkey | 当前可见小胶囊直接开始新录音；不会重复复制上一轮文字 |
| 热键冲突 | 让系统或其他 app 独占 `⌃⌥A` 后启动 Flotis | 错误持久显示；解除冲突后自动重试成功 |
| 旧命令兼容 | 启动 V0.8 并检查旧 commands.json | 不展示命令、不注册命令热键，也不改写或删除旧文件 |

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

仓内没有 SwiftLint/SwiftFormat。最低门槛是主 App 与输入法接口各自的完整 `xcodebuild build` / `xcodebuild test`（按变更范围执行）以及 `git diff --check`；纯 parse 不等于完整工程验证。
