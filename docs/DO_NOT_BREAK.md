# DO_NOT_BREAK

最近自查日期：2026-07-30

本文件记录当前可构建实现中的稳定边界。修改相关代码前必须同时核对源码、`project.yml` 与测试；若文档冲突，以当前源码/配置为准并报告差异。

## 工程边界

- app target `Flotis`：macOS 13+、`LSUIElement=YES`、`LSMultipleInstancesProhibited=YES`、Swift 5.0。
- unit-test target `FlotisTests` 依赖 app target；新增核心策略/迁移逻辑时应补纯单测。
- 不无故引入第三方依赖、sandbox、entitlements、signing 或 bundle ID 变更。
- `Flotis.xcodeproj` 与 `Flotis/Info.plist` 由 `project.yml` 生成。修改 target/source/build setting 或 `info.properties` 后必须运行 `xcodegen generate` 并验证生成工程与最终 app 产物；版本值必须继续展开 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`。
- 不把 `run.sh` 当普通测试命令：它会删除 DerivedData 并重置 Accessibility TCC。

## 界面语言边界

- App 语言只由第一首选语言决定：明确简体中文时使用简中，繁体中文、英文及其他语言使用英文。不得退化为只判断 `zh` 前缀，也不得扫描后续偏好语言后改选简中。
- UI 语言与 `TranscriptionConnection.language` / `selectedSpeechLocale` 分离；后者是转写语言，不能随界面语言自动改写。
- 英文是 `project.yml` 的 development language 和权限用法描述 fallback；`InfoPlist.xcstrings` 必须继续包含英文与 `zh-Hans` 权限文案并进入 resources build phase。
- 不得为了切换界面语言批量改写已有 connection 名称、最近测试摘要或旧 `commands.json`。内建名称只能在确认稳定 UUID 且名称仍匹配已知默认值时做显示层映射。
- adapter raw value、UUID、UserDefaults key、`apiKeyReference`、endpoint/model/header/event 名称和协议 payload 都不是 UI 文案，禁止本地化。

## 用户数据格式

### 命令

- 路径：`~/Library/Application Support/Flotis/commands.json`。
- V0.8 主入口不得加载、改写或删除旧命令文件，也不得注册 command ID `1000+` 热键；旧源码暂留兼容。未来删除或迁移必须由明确版本化方案驱动。
- 格式：`[PromptCommand]` JSON；写入必须继续使用 atomic option。
- 8 个默认命令 UUID `1111…`–`8888…` 与默认 `⌘⌥⇧1..8` 属于兼容边界；若需迁移必须显式版本化，不能静默重编号。
- 标题/正文/排序改变不能触发全量热键重注册；仅 enabled/shortcut 改变发出 hotkey configuration change。

### Connection snapshot

- 主键：`flotis.transcriptionConnections.v3`。
- v3 shape：`TranscriptionConnectionStoreSnapshot { schemaVersion, presetCatalogVersion, connections, activeConnectionID }`；canonical connection 使用嵌套 endpoint/authentication/audio/options/test record，不能重新编码 legacy `kind` 或 `wireProtocol`。
- 恢复键：`flotis.transcriptionConnections.v3.lastKnownGood`、`flotis.transcriptionConnections.corruptBackup`、`flotis.transcriptionConnections.corruptBackupMetadata`。
- 旧键 `flotis.speechProviders.v2`、`flotis.speechProviders.v2.lastKnownGood` 与 `flotis.speechProviders.v1` 只能作为只读 migration input。迁移成功或失败都不得覆写旧 authoritative bytes；decode 失败不得用默认数据覆盖坏 bytes。
- 全新安装只创建 Apple connection；独立 preset catalog 不能被自动实例化成六条用户 connection。
- 六个 legacy UUID 必须保持稳定：A Apple、B OpenAI Realtime、C OpenAI HTTP、D DashScope、E Volcengine、F GLM。迁移还必须保留自定义实例、用户名称、顺序、有效 active ID 与安全边界未变的 `apiKeyReference`。
- `TranscriptionAdapterID` 的六个 raw value 是持久化兼容边界：`apple-on-device`、`openai-audio-transcriptions-http-v1`、`openai-realtime-transcription-ga`、`dashscope-paraformer-ws-v1`、`volcengine-bigasr-ws-v3`、`glm-asr-http-sse-v4`。改名必须显式迁移和版本化。
- preset catalog 与 connection/runtime 分离。preset 只能填充 draft 字段，不能改变 connection identity、成为 runtime discriminator 或覆盖用户自定义连接。
- `TranscriptionAdapterRegistry` 是 adapter→runtime 的唯一注册点；`VoiceInputController` 只能按 `ownedCapture` / `pcmStream` / `recordedFile` 分派，不得重新加入 vendor、adapter 或 legacy wire-protocol switch。
- 当前 Settings 只展示 OpenAI Compatible 是 Presentation 策略，不是数据迁移。禁止把可见数组写回 snapshot，或因打开/关闭 Settings 而删除隐藏 connection、改写隐藏 active ID、清理其本地 secret reference、裁剪 preset/registry。

### API key / 应用自管本地存储

- UserDefaults/connection snapshot 只能保存 `apiKeyReference`，绝不能保存 key 明文；明文只允许存在当前会话内存与 `~/Library/Application Support/Flotis/secrets.json`。
- `LocalSecretStore` 是唯一生产凭据后端。Flotis app 源码不得导入 `Security`、调用 `SecItem*`，不得读取、迁移或删除旧系统钥匙串条目。
- `secrets.json` 必须保持版本化 envelope（当前 `schemaVersion = 1`）和 `apiKeyReference → secret` 映射；reference 只能作为 JSON 字典键，禁止拼接为文件路径。
- `~/Library/Application Support/Flotis` 必须保持 `0700`，`secrets.json` 与 `.secrets.lock` 必须保持 `0600`。读写必须使用不跟随符号链接的目录 fd 与 `openat`；进程内使用共享锁，多进程使用 `.secrets.lock` 的 advisory write lock 覆盖完整 read-modify-write，且跨进程竞争必须有限等待、不可永久阻塞 UI。写入必须使用同目录私有临时文件、`fsync`、`renameat` 原子替换与目录同步。
- 必须拒绝符号链接、非普通文件、损坏/未知 schema、异常大的文件、空白或超限的 reference/secret；遇到损坏数据时禁止静默按空 store 覆写。
- 空白 key 必须 trim 后拒绝。UI 必须保留 Clear 能力。
- adapter、scheme、host、effective port 或 auth type 改变即跨越 secret boundary；不得复用旧 key reference。配置成功持久化后才能删除旧 secret；清理失败必须回滚配置和本次新 secret。
- 删除 connection、改为 Apple 或显式 Clear 时应清理当前可达 key；失败必须向 UI 报错并保持原 connection/snapshot 可用。
- Connection Test 的成功/失败记录只能保存固定成功摘要或受限脱敏错误；服务端原样回显任意形态的本次 API key 时，必须先按完整值精确脱敏，不能只依赖 `sk-*` 等 provider-specific pattern。
- 保存、替换或清除 credential 必须推进 `credentialRevision`，使旧 Test Connection fingerprint 失效；显示名称变化不应使测试失效。
- 本地文件不具备独立加密能力，只依赖 macOS 当前用户权限与可选 FileVault；文案不得暗示其具备钥匙串级隔离。删除也不得宣称完成物理介质安全擦除。

## Provider schema 与 endpoint

- Settings 展示 allowlist 当前只能包含 `openai-audio-transcriptions-http-v1`；新增入口必须直接创建该 adapter 的内存 draft，不能隐式持久化默认 connection。其他五个 adapter 仍须保留 schema、preset、迁移、测试与 runtime 能力。
- 当前隐藏 Connection Name 与多 connection 侧栏只属于 Presentation 收敛；不得删除、合并或覆盖底层其他 connection。可见 OpenAI Compatible 草稿成功保存并具备 key 后必须设为当前 connection，避免界面只剩一套配置但运行时仍静默使用隐藏 provider。
- OpenAI Compatible 的精简 UI 仍必须保留自定义 host 明示确认、凭据目标 host、Clear API Key、Test Connection 与 Save/Cancel；这些安全/事务能力不能作为“高级选项”隐藏。
- Realtime 只能用 `wss`，HTTP 只能用 `https`。
- URL 不允许 user/password、query、fragment；path 必须 `/` 开头，禁止 `//`、`://`、`?`、`#` 和反斜杠等歧义形式。
- 非 schema trusted host 只能在用户显式批准后保存；UI 必须展示 API key/音频会发送到的 host。
- Authorization-bearing HTTP upload 不跟随 redirect。
- adapter schema 声明为固定的模型/音频字段不能重新暴露成任意文本输入；`StreamingAudioCapture` 只接受 16/24 kHz、mono PCM16。不支持字段必须在 normalization/编码时省略，不能持久化空占位。
- Connection/Command editor 保持 draft + Save/Cancel；Add 也只能先创建内存 draft。半输入 URL、未保存 adapter 切换或未配置 key 不得成为 active runtime 配置。

## 协议禁区

### OpenAI Realtime GA

- `session.update` 必须保持 `session.type = "transcription"` 与嵌套 `session.audio.input` 结构。
- 默认模型 `gpt-realtime-whisper` 可由 connection 编辑，输入 contract 固定为 PCM16 24 kHz mono，当前采用 `turn_detection = null` + client manual commit。
- 不恢复旧 `OpenAI-Beta: realtime=v1` header 或 flat `input_audio_format/input_audio_transcription` session 字段。
- client→server 核心事件：`session.update`、`input_audio_buffer.append`、`input_audio_buffer.commit`。
- server 事件必须使用精确 GA 名称与字段：`session.updated`、`input_audio_buffer.committed`、`conversation.item.input_audio_transcription.delta/completed`；禁止用 `contains` 或 legacy alias 宽松猜测。
- server completion 可能跨 speech item 乱序；必须继续按 `item_id`、`content_index` 与 previous item 关系组装，不能用单一全局 final 覆盖前文。
- stop 必须等待 session/commit/item 终态或受控超时，不能改回固定 sleep。

### DashScope Paraformer

- 默认模型 `paraformer-realtime-v2`、PCM 16 kHz mono。
- `finish-task` 后必须继续收 `result-generated`，直到 `task-finished`；不能发完即断开或用固定 sleep。
- final segment 合并必须保留真实重复内容，不能用 `hasSuffix` 粗暴去重。

### Volcengine BigASR

- 音频 PCM 16 kHz、16-bit、mono；request `model_name` 固定为 `bigmodel`。
- `resourceID` 与 model name 是不同概念，不能再次塞回一个可任意编辑的“模型”字段。
- 二遍识别字段拼写为 `enable_nonstream`；它不是通用 server VAD 开关。
- 必须保持二进制 frame 编解码、显式 terminal event/packet 等待和受控错误解析。

### OpenAI HTTP

- 默认 endpoint `/v1/audio/transcriptions`、默认模型 `gpt-4o-mini-transcribe`，新通用 BYOK connection 默认 WAV PCM16 16 kHz mono；v2 迁移或显式配置的 `.m4a` 仍须按其 MIME 正确上传。
- Endpoint 在 canonical schema 中继续分为 `baseURL + path`；UI 精简不得通过合并字段绕过 scheme/host/port/path 校验或 secret boundary。Language、prompt、temperature 可折叠，音频与 JSON response mode 可隐藏但必须保留旧值和 normalize contract。
- multipart 上传应继续通过临时文件/streamed request，不能重新用 `Data(contentsOf:)` 加完整 in-memory body。
- file transcriber 必须支持 cancel。
- 只接受 2xx、`application/json` 和顶层字符串 `text`；不能猜测 `data.text` 或任意嵌套字段。prompt/temperature 为 nil 时不得发送。

### GLM ASR HTTP Stream

- 固定模型 `glm-asr-2512`，录音 `.wav`，支持 SSE 增量返回并以 `[DONE]` 结束。
- 保持应用层 `<= 30 秒`、`<= 25 MiB` 的倒计时/自动停止和上传前预检；不能仅依赖服务端拒绝。
- `stream=true` 表示 HTTP response streaming，不代表 realtime audio upload。
- 只接受 `text/event-stream`；`data:` 必须是有效 JSON，且必须收到 `[DONE]`。不得把任意 JSON、EOF 或未声明事件静默当成成功终态。

### Apple Speech

- 只有 `supportsOnDeviceRecognition == true` 才能启动，并保持 `requiresOnDeviceRecognition = true`。
- partial/final 不得再次无条件覆盖完整 transcript。空 final 不能清除已有非空 partial；同一时间范围的假设要替换，停顿后不重叠的 segment 要保留并按顺序追加。
- Apple handler 必须发布 accumulator 的完整文本，而不是本次 callback 的原始局部字符串。
- final/error 是实际终态；不能改回停止后固定等待若干毫秒。

## 语音生命周期与并发

- `VoiceInputController` 的 session generation/identity guard 不得绕过。任何异步 callback 在修改 UI、清理资源或注入文本前都必须验证当前 session。
- V0.8 最终转写必须先进入 `reviewing`，不得恢复“provider 完成即自动注入”。进入 reviewing 前应释放已完成的 capture/transcriber/runtime；reviewing 文本允许用户编辑。
- reviewing 文本必须保持原生可选择/可复制能力，至少支持鼠标选区、`⌘C` 和显式复制全部；不能用窗口背景拖动或不可命中的装饰 overlay 吞掉文本交互。
- reviewing 的热键动作必须是显式 inject；注入失败必须保留当前编辑文本并回到 reviewing，成功后才允许清空文本。injecting 期间不得接受重复注入。
- requesting/connecting 可由热键取消；stopping/transcribing 已进入终态处理时，额外热键必须忽略而不是清空本次会话。
- operation task、audio writer、limit task、streaming/file transcriber、capture/recorder 都必须可取消；App 退出也必须调用 cancel。
- connection 和 key 在会话开始时快照到 adapter runtime。stop 阶段不得重新依赖一个可能已被 UI 删除/切换的 connection 或本地 secret 记录。
- realtime chunk 必须进入有界串行 writer；overflow 应失败并提示，stop 必须先 drain 再 terminal commit/finish。
- `StreamingAudioCapture.stop()` 必须保持当前 generation/converter 有效，直到 tap callback group、conversion queue 与 converter end-of-stream 尾帧全部 drain；只有 `cancel()` 可以先失效 generation 丢弃待处理 chunk。
- transcriber 的 socket sender 与共享状态必须保持 actor/锁隔离，旧连接回调不能污染新连接。
- `AudioRecorder.prepareToRecord()`、`record()` 与最终文件检查返回值不可忽略。

## 热键与注入安全边界

- 缺 AX 权限时 `ClipboardPasteInjector` 必须立即 `completion(false)`；禁止以任何方式绕过检查发 `CGEvent`。
- 发 `⌘V` 前必须再次确认：operation 未过期、目标进程存活且 PID 未变、目标仍为 frontmost、Flotis 自身不再持有 key window、语音快捷键的修饰键与主键 R 均已释放、AX 仍可信、pasteboard `changeCount` 仍是 app 管理值。
- 用户在激活等待中切到第三方 app 时必须 abort，不能把文本发给当前任意 frontmost app。
- 队列必须保持有界（当前 max in-flight 4、burst 8、operation 5 秒过期）或采用同等安全的 backpressure；不得恢复无上限 backlog。
- 剪贴板无法完整复制全部 item/type 时拒绝注入。恢复只在 `changeCount` 未被外部更新时进行，且要检查 `writeObjects` 成功。
- 完整语音快捷键等待超时必须失败，不能只等修饰键、不等主键 R，也不能超时后照常粘贴。
- completion=true 只代表安全核验、event post 与 clipboard outcome 成功；不得在 UI 文案中声称已证明目标控件消费文本。
- 点击胶囊编辑导致 Flotis 获得键盘焦点时，只能使用 `ClipboardPasteInjector` 已记录且重新核验的最近非 Flotis target；不得直接向任意 frontmost app 或未核验 PID 发事件。
- 可打印全局快捷键必须包含 Command + 至少一个额外修饰键；固定 toggle、重复项与 `⌘V` 等危险组合必须拒绝。
- hotkey handler 必须同时监听 press/release 并以 gate 抑制 auto-repeat；注册必须保持 `kEventHotKeyExclusive`。handler 安装失败时不得继续注册；单项失败状态必须可见并自动重试，event signature 必须核验。
- panel 的真实 `window.isVisible` 与 `AppState.isPanelVisible` 必须同步；voice hotkey 在 panel 隐藏时应先恢复胶囊可见性。
- panel 尺寸变更必须合并旧请求并只应用最后一次，锚点屏幕与底边位置不得随异步状态重算而漂移；整窗背景不得抢占审阅文本的拖选。Settings 必须使用独立窗口，不能重新附着成推动胶囊的 sheet。
- idle 可以不主动展开 AX 权限提示，但 Settings 必须持续显示真实 AX 状态；缺 AX 导致实际注入失败后，胶囊必须显示权限错误和系统设置入口，不能吞掉失败或假装注入成功。
- Settings 的一键退出必须走 `NSApplication.terminate` → `applicationWillTerminate`，不得用 `exit`/kill 绕过热键与语音资源清理；`.injecting` 期间不仅要禁用页头按钮，`applicationShouldTerminate` 还必须统一拒绝菜单、`⌘Q` 等其他终止请求，避免剪贴板尚未完成安全恢复。

## 临时文件

- 录音/连接测试前缀：`Flotis-Audio-`，扩展名按 recorded-file connection/runtime 为 `.m4a` 或 `.wav`；连接测试生成物同样必须在成功、失败和取消路径清理。
- multipart 前缀：`Flotis-Multipart-`。
- 清理只能删除 app 自有前缀、普通文件且修改时间超过 24 小时的项；禁止扫描删除任意 `/tmp` 文件。
- 每条成功、失败、取消路径都应尽快清理本会话临时文件。

## Test Connection 边界

- 必须复用真实 adapter/runtime contract，不得退化成只 ping URL 或只请求模型列表。
- 测试音频必须由应用生成或内置且不含用户隐私；不得读取麦克风、历史录音或用户转写文本。本实现使用短合成音，因此成功只证明连接、音频传输和响应结构，不证明识别质量，也不得强制 transcript 非空。
- HTTP 测试必须覆盖 multipart 与响应结构；Realtime 测试必须走 start→append→commit/stop→terminal。HTTP 成功不能推导 Realtime 兼容。
- 测试记录 fingerprint 必须覆盖 endpoint/model/options/credential revision 和 adapter version；显示名称变化不应失效，配置或凭据变化必须失效。
- 所有成功、失败、取消路径都必须 cancel runtime 并删除测试临时文件；不得持久化完整响应、Authorization、transcript 或 API key。

## 回归门槛

源码、工程或测试变更完成前至少运行：

```sh
xcodegen generate
xcodebuild -project Flotis.xcodeproj -scheme Flotis -configuration Debug -derivedDataPath /tmp/FlotisDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Flotis.xcodeproj -scheme Flotis -configuration Debug -derivedDataPath /tmp/FlotisDerivedData CODE_SIGNING_ALLOWED=NO test
git diff --check
git status --short
```

协议、AX/CGEvent、本地 secret store 或 audio engine 变更还需按 `docs/TESTING.md` 做对应文件系统/真机矩阵；自动化构建/单测不能替代真实权限和供应商联调。
