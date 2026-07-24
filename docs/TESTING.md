# TESTING

最近验证日期：2026-07-12

## 环境与边界

- macOS app，deployment target 13.0，Swift 5.0。
- XcodeGen 生成 `Flotis.xcodeproj`；scheme `Flotis` 包含 app 与 unit tests。
- 依赖 Carbon、AppKit、Speech、AVFoundation、Security 与真实 macOS Accessibility，不能用 iOS Simulator 验证核心交互。
- 无第三方依赖，无仓内 SwiftLint/SwiftFormat 配置。
- API key 明文不进入仓库、UserDefaults 或测试 fixture；自动化只使用内存 fake transport 与虚拟字符串。真实 provider 测试需由操作者在 UI 写入 Keychain。

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
  -derivedDataPath /tmp/FlotisDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
xcodebuild \
  -project Flotis.xcodeproj \
  -scheme Flotis \
  -configuration Debug \
  -derivedDataPath /tmp/FlotisDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
git diff --check
git status --short
```

2026-07-12 V0.8 胶囊基线结果：

- `xcodegen generate`：成功。
- Debug build：`BUILD SUCCEEDED`。
- XCTest：`TEST SUCCEEDED`，45 tests、0 failures。
- 启动冒烟：`open -n /tmp/FlotisDerivedData/Build/Products/Debug/Flotis.app` 后进程保持运行，随后关闭测试实例；未执行视觉截图或交互矩阵。
- 测试日志存在非致命环境/未来语言模式提示：macOS 13 deployment target 链接由 macOS 14 构建的 XCTest dylib、test host 下 App Intents `linkd` 连接日志，以及 `AppleSpeechTranscriber` 在 Swift 5 模式下对 async context 中 `NSLock` 的 Swift 6 兼容性 warning；均未造成构建或测试失败。
- 按用户要求，本轮未创建、读取或使用真实 API key，未请求真实供应商，未采集麦克风，也未触发 Accessibility/`CGEvent` 注入。

## 当前自动化覆盖

### `HotkeyAndInjectionPolicyTests`

7 tests：

- V0.8 语音热键严格映射 start → stop → reviewing/inject。
- requesting/connecting/stopping/transcribing 保持 cancel，injecting 拒绝重复动作。
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

20 tests：

- 六个稳定 adapter ID、canonical v3 编码以及 unsupported/legacy 字段省略。
- 全新 v3 仅有 Apple connection；Add 只创建内存 draft，Save 前不持久化。
- 通用 HTTP 默认 WAV PCM16 16 kHz mono，prompt/temperature 默认 nil；preset 只填字段，不改 identity/adapter。
- v2 六类 + 自定义 connection 无损迁移：UUID、名称、顺序、active ID、endpoint/model/options 与 Keychain reference 保留；v1 兼容迁移仍受测。
- 同 adapter 多 connection 的 endpoint/model/key reference 相互隔离。
- secret boundary 覆盖 adapter、scheme、host、effective port、auth；边界变化会轮换 reference，清理失败时配置与新 secret 回滚。
- provider 删除时若 secret 清理失败，connection/UserDefaults 删除会回滚。
- 坏 v3 从 v3 LKG 恢复；坏 v2 可从 v2 LKG 迁移；两者均保留原 authoritative bytes 与 corrupt backup。
- API key 明文不会进入 v3 snapshot；Test Connection fingerprint 覆盖配置与 credential revision，名称变化不失效。
- 自定义 endpoint 显式 approval 与不安全/歧义 URL 拒绝。

### `TranscriptionAdapterRuntimeTests`

10 tests：

- registry 恰好注册六个唯一 adapter；重复 ID 被拒绝，六条路径只生成声明的三类通用 runtime plan。
- OpenAI-compatible HTTP 生成严格 multipart WAV；自定义 endpoint/model/key 按 connection 隔离；显式 M4A 使用匹配扩展名与 MIME。
- HTTP 只接受 `application/json` 与顶层 `text`，错误 Content-Type/嵌套猜测被拒绝。合成测试音得到合法空 `text` 时仍可判定 transport/响应结构成功。
- 失败摘要限长；自定义端点原样回显非 `sk-*` 的任意 opaque API key 时仍被精确脱敏。
- GLM SSE 要求正确 media type、有效 JSON、明确 delta/done 与 `[DONE]`，并脱敏错误中的实际 Key。
- scripted OpenAI Realtime 验证 GA `session.update`、audio append、manual commit、commit ack 与 completed terminal lifecycle。

自动化单测刻意针对纯策略、迁移、组装和 mock transport；真实 Carbon、AX、pasteboard、audio engine、Keychain 持久 item、WebSocket/HTTP 服务端不是 unit-test 能完全替代的边界。

## 真机手动验证矩阵

### 构建、启动与权限

| 场景 | 操作 | 预期 |
|---|---|---|
| 冷启动 | `./run.sh` | 工程生成/构建成功，app 启动；因脚本重置 TCC 需重新授权 |
| AX 未授权 | 拒绝/撤销 Accessibility 后在 reviewing 触发输入 | 胶囊保留文字并显示权限错误，不发送 `CGEvent`，目标 app 不收到文本 |
| 麦克风拒绝 | 拒绝 microphone | 会话进入明确 failed，可取消/重试，不遗留 audio engine |
| Speech 拒绝/设备不支持 | Apple provider 启动 | 明确报告设备端识别不可用，不退回云端 |

### 热键与面板

| 场景 | 操作 | 预期 |
|---|---|---|
| 固定 toggle | `⌘⌥⇧0` / `⌘⌥⇧R` | panel 与 voice 各自响应一次；隐藏时 voice 会先显示胶囊 |
| 三段式 voice | 连续完成开始、停止/转写、确认三个阶段 | idle→recording/streaming→reviewing→injecting→idle；不会在转写完成时自动注入 |
| 胶囊编辑 | reviewing 点击文本并修改，再按 `⌘⌥⇧R` | 修改后文本注入最后一个有效的非 Flotis 输入目标 |
| 编辑后取消 | reviewing 修改后按 Esc/取消 | 清空本次文本并回 idle，不注入 |
| 注入失败重试 | reviewing 时让目标退出或撤销 AX 后确认 | 返回 reviewing 且保留修改文本，恢复条件后可再次确认 |
| 热键冲突 | 在系统/其他 app 占用组合后保存 | 错误持久显示；解除冲突后自动重试成功 |
| 旧命令兼容 | 启动 V0.8 并检查旧 commands.json | 不展示命令、不注册命令热键，也不改写或删除旧文件 |

### 剪贴板注入

| 场景 | 操作 | 预期 |
|---|---|---|
| 普通语音确认 | 目标 app 文本框有焦点，reviewing 再按语音热键 | 审阅文本注入，原剪贴板恢复 |
| 修饰键不释放 | 持续按住触发组合超过 timeout | 不粘贴，返回失败 |
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
| 全新安装 | 清空本 app defaults 后启动 | v3 只创建 Apple connection；网络连接由用户在统一 Add 界面新增 |
| v2 升级 | 用含六类和自定义实例的 v2 snapshot 启动 | 迁移为 v3；UUID、名称、顺序、active、模型、endpoint 与安全的 key reference 不丢；v2 bytes 不改 |
| v1 升级 | 用旧 A/B/C snapshot 启动 | 先按 legacy 规则规范，再写 v3；用户自定义 provider/model 不丢 |
| v3/v2 损坏 | 注入不可 decode bytes，并准备对应 LKG | 原 bytes 备份、不被默认值覆写；使用对应 LKG 或安全默认并报错 |
| adapter 切换 | OpenAI→Dash/Volc/GLM/Apple | 不支持字段重置；旧 key reference 不复用，旧 item 在保存成功后清理 |
| 自定义 host | 改非 trusted HTTPS/WSS host | Save 前要求显式批准，并显示 key/音频目标 host |
| 不安全 URL | 输入 http/ws、userinfo、query、fragment、歧义 path | Save 被拒绝 |
| Add/半编辑配置 | 新增或输入一半 URL 后 Cancel/触发全局 voice | runtime 仍使用已保存配置；Cancel 不落盘 |
| 同 adapter 多实例 | 建两个不同 endpoint/model/key 的 HTTP connection | 独立显示、编辑、选择；凭据和配置不串用 |
| Test Connection | 使用内置合成音测试 HTTP/Realtime | 验证 transport 与响应结构，不采麦克风；空 transcript 可成功；失败不泄漏 key/响应正文 |
| 无 key 激活 | 选择需要 key 但未保存 key 的 connection | Set Current/Picker 禁用或失败并提示 |
| Clear key | 清除 active connection key | key 删除，active 安全切回 ready connection/Apple |
| legacy Keychain | 安装含旧无-service item 的版本后升级 | 首次 load 迁移到 scoped service，旧 exact item 删除 |

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
