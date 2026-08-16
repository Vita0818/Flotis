# DO_NOT_BREAK

最近自查日期：2026-08-16

本文件记录当前可构建实现中的稳定边界。修改相关代码前必须同时核对源码、`project.yml` 与测试；若文档冲突，以当前源码/配置为准并报告差异。

## 工程边界

- app target `Flotis`：macOS 13+、`LSUIElement=YES`、`LSMultipleInstancesProhibited=YES`、Swift 5.0。
- unit-test target `FlotisTests` 依赖 app target；新增核心策略/迁移逻辑时应补纯单测。
- input-method target `FlotisInputMethod`：macOS 13+、独立 `LSBackgroundOnly=YES` application bundle、InputMethodKit framework、Swift 5.0；顶层与模式级 TIFF 输入源图标必须随 bundle 复制，不得为了接线让它依赖或启动完整 `Flotis` app target。
- `FlotisInputMethodTests` 直接编译 protocol/service 纯源码，不以输入法 app 作为 test host，避免测试时启动永久 event loop。
- 不无故引入第三方依赖、sandbox、entitlements、signing 或 bundle ID 变更。
- `Flotis.xcodeproj`、`Flotis/Info.plist` 与 `FlotisInputMethod/Info.plist` 由 `project.yml` 生成。修改 target/source/build setting 或 `info.properties` 后必须运行 `xcodegen generate` 并验证生成工程与对应最终产物；版本值必须继续展开 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`。
- 主 App 应用图标的 source of truth 是根目录 `Flotis.icon`；必须继续作为 `Flotis` target 的 `wrapper.icon` resource，并保持 `ASSETCATALOG_COMPILER_APPICON_NAME=Flotis`。构建应生成 `Flotis.icns`、`Assets.car` 与匹配的 `CFBundleIconFile/CFBundleIconName`；不得只把图层 PNG 当成 `CFBundleIconFile`，也不得误加到 `FlotisInputMethod` target 覆盖其输入源 TIFF 图标。
- 不把 `run.sh` 当普通测试命令：它会终止旧实例、生成工程、构建并打开 app。脚本必须复用稳定的临时 DerivedData，不得自动删除缓存或执行 `tccutil reset Accessibility`；ad-hoc 签名只能提示风险，不能伪装成可稳定保留 TCC 的发布身份。

## 界面语言边界

- App 语言只由第一首选语言决定：明确简体中文时使用简中，繁体中文、英文及其他语言使用英文。不得退化为只判断 `zh` 前缀，也不得扫描后续偏好语言后改选简中。
- UI 语言与 provider route 的 language / `selectedSpeechLocale` 分离；后者是转写语言，不能随界面语言自动改写。
- 英文是 `project.yml` 的 development language 和权限用法描述 fallback；`InfoPlist.xcstrings` 必须继续包含英文与 `zh-Hans` 权限文案并进入 resources build phase。
- 不得为了切换界面语言批量改写已有 provider 名称、模型测试摘要或旧 `commands.json`。legacy 内建名称只能在确认稳定 UUID 且名称仍匹配已知默认值时做显示层映射。
- adapter raw value、UUID、UserDefaults key、`apiKeyReference`、endpoint/model/header/event 名称和协议 payload 都不是 UI 文案，禁止本地化。

## 用户数据格式

### 命令

- 路径：`~/Library/Application Support/Flotis/commands.json`。
- V0.13 主入口不得加载、改写或删除旧命令文件，也不得注册 command ID `1000+` 热键；旧源码暂留兼容。未来删除或迁移必须由明确版本化方案驱动。
- 格式：`[PromptCommand]` JSON；写入必须继续使用 atomic option。
- 8 个默认命令 UUID `1111…`–`8888…` 与默认 `⌘⌥⇧1..8` 属于兼容边界；若需迁移必须显式版本化，不能静默重编号。
- 标题/正文/排序改变不能触发全量热键重注册；仅 enabled/shortcut 改变发出 hotkey configuration change。

### Canonical config

- 唯一路径：`~/Library/Application Support/Flotis/config.json`；当前 schema version 为 `2`，`$schema` 标识固定为 `https://flotis.app/config/v2`。
- 顶层 shape 必须保持 Intatis 式 `$schema`、`schema_version`、`model`、`provider_order`、`enabled_providers`、`comparison.models`、可选 `shortcuts`、`provider`。`model` 与对比项为 `<provider-id>/<model-id>`；只能在第一个 `/` 分割，Provider ID 禁止 `/`，Model ID 允许包含 `/`。`provider_order` 与 `enabled_providers` 当前都必须与 provider 字典键集合精确对应。
- 每个 `provider.<id>` 必须保存一次 `name`、`adapter`、共享 `options`、多项 `models` 与 credential revision；endpoint 和 API key 必须只位于共享 `options`，不得为每个模型复制，也不得重新拆成另一个运行时 JSON 真源。每个模型只可附带自己的显示名/安全测试摘要。
- canonical schema v1 是可识别的原地迁移输入：必须在安全校验与同一文件锁下原子升级到 v2，移除 Apple 条目并尽量保留网络 Provider/模型/endpoint/key/选择。旧键 `flotis.transcriptionConnections.v3`/LKG、`flotis.speechProviders.v2`/LKG、`flotis.speechProviders.v1`、`flotis.transcriptionComparison.v1` 与旧 `secrets.json` 只能在 canonical 文件不存在时作为一次性只读 migration input；canonical v2 一旦存在不得再从旧源补写或覆盖。
- 全新安装创建空 provider catalog；`apple-on-device` 不得写入 schema v2 的 `provider`、`provider_order`、`enabled_providers` 或 `comparison.models`。Apple on-device 仅可作为空 catalog 的内部 fallback；独立 preset catalog 不能被自动实例化成用户 Provider。
- 六个 legacy UUID 必须保持稳定：A Apple、B OpenAI Realtime、C OpenAI HTTP、D DashScope、E Volcengine、F GLM。迁移还必须保留自定义实例、用户名称、顺序、有效 active ID 与安全边界未变的 `apiKeyReference`。
- `TranscriptionAdapterID` 的六个 raw value 是持久化兼容边界：`apple-on-device`、`openai-audio-transcriptions-http-v1`、`openai-realtime-transcription-ga`、`dashscope-paraformer-ws-v1`、`volcengine-bigasr-ws-v3`、`glm-asr-http-sse-v4`。改名必须显式迁移和版本化。
- preset catalog 与 provider/runtime 分离。preset 只能填充 draft 字段，不能改变 provider identity、成为 runtime discriminator 或覆盖用户自定义配置。
- `TranscriptionAdapterRegistry` 是 adapter→runtime 的唯一注册点；`VoiceInputController` 只能按 `ownedCapture` / `pcmStream` / `recordedFile` 分派，不得重新加入 vendor、adapter 或 legacy wire-protocol switch。
- 当前 Settings 只展示 OpenAI Compatible 是 Presentation 策略，不是数据迁移。禁止把可见数组写回 canonical document，或因打开/关闭 Settings 而删除隐藏 provider/model、改写隐藏 active selector、清理其 key/reference、裁剪 preset/registry。

### 多模型对比偏好

- 对比偏好必须只占 canonical 顶层 `comparison.enabled` 与 `comparison.models`；`enabled_providers` 表示启用的 Provider catalog，不是对比列表。旧 `flotis.transcriptionComparison.v1` 只作首次迁移输入。不得塞入 route 副本、endpoint、API key/reference、录音路径、候选 transcript、错误详情或耗时。
- `comparison.models` 必须保存完整且存在的 selector，去重并保持用户选择顺序，最多 4 个；启用时至少 2 个。provider/model 被删除后应在 reconcile 时移除对应 selector，少于 2 个必须安全关闭。
- 未知 schema 或坏 canonical JSON 必须在内存中回退为关闭并拒绝保存，不得用空默认值覆盖原 authoritative bytes。comparison store 只能在同一文件锁的 read-modify-write 中改 comparison，不能覆盖 provider/active/key。
- 候选和用户对候选的编辑只属于当前 `AppState` 会话；取消、复制成功、新会话或失败清理时必须释放，不得默认跨重启保存或写日志。

### 可配置全局快捷键

- voice、panel 显隐、上一个对比结果、下一个对比结果只允许存于 canonical 顶层 `shortcuts.toggle_voice`、`toggle_panel`、`previous_comparison_result`、`next_comparison_result`；不得另建 UserDefaults 或第二个运行时 JSON 真源。
- 旧 schema v2 缺少整个 `shortcuts` 或缺少其中某项时必须使用当前默认值：voice `⌃⌥A`、panel `⌘⌥⇧0`、previous `⌥←`、next `⌥→`。补写默认值和任意修改都必须使用 `FlotisConfigurationStore` 的同锁 read-modify-write，不能覆盖 provider、active model、comparison 或 API key。
- 四项持久化 descriptor 必须至少包含一个 Command/Option/Shift/Control 修饰键并且彼此不同；Settings 应在写入前给出可理解错误。外部进程占用等 Carbon 注册失败仍必须可见并自动重试，不得因注册失败回退为静默抢占或引入 Input Monitoring。
- descriptor 变化只允许差异注销/注册对应 Carbon ID；未变化项不能被无条件全量重建。previous/next 无论配置为何，都只能在对比 reviewing 且至少两个成功候选时临时注册，离开后立即注销。
- Settings 侧栏必须保持“快捷键 / 转写”；左上 `Flotis` 与版本旁不得重新添加应用图标。“快捷键”页只保留 voice、panel 与前后对比导航的一张紧凑卡和四个 `52` pt 行，不得重新加入语音流程、胶囊拖动、对比生效条件、重复 section、hover help、铅笔或常驻恢复控件。四项都保持 `156×38` / 15 pt Monospaced 的轻量 surface，整块可点并在同尺寸录制态获得键盘焦点。真实校验、持久化或 Carbon 注册错误仍必须可见。

### API key / 应用自管本地存储

- API key 明文不得进入 UserDefaults、日志或项目文档；只允许存在当前会话内存与 canonical `provider.<id>.options.apiKey`。同一 Provider 的模型必须共享这一份 key；运行时 `apiKeyReference` 只能作为 provider/key 的内存匹配 ID，禁止拼接为文件路径。
- `FlotisConfigurationStore` 是唯一生产凭据后端；`LocalSecretStore` 只保留为旧 `secrets.json` 迁移读取器。Flotis app 源码不得导入 `Security`、调用 `SecItem*`，不得读取、迁移或删除旧系统钥匙串条目。
- `~/Library/Application Support/Flotis` 必须保持 `0700`，`config.json` 与 `.config.lock` 必须保持 `0600`。读写必须使用不跟随符号链接的目录 fd 与 `openat`；进程内使用共享锁，多进程使用 `.config.lock` 的 advisory write lock 覆盖完整 read-modify-write，且竞争必须有限等待、不可永久阻塞 UI。写入必须使用同目录私有临时文件、`fsync`、`renameat` 原子替换与目录同步。
- 必须拒绝符号链接、非普通文件、非当前用户所有、损坏/未知 schema、结构不一致或超过 4 MiB 的 canonical 文件，以及空白或超限 key；遇到损坏数据时禁止静默按 fresh document 覆写。
- 空白 key 必须 trim 后拒绝。UI 必须保留 Clear 能力。
- adapter、scheme、host、effective port 或 auth type 改变即跨越 secret boundary；不得复用旧 key reference。新 provider 配置、可选新 key 与旧 key 清理必须由同一次 canonical 原子事务提交；失败必须一起回滚。
- 删除整个 provider 或显式 Clear 时应在同一文档事务清理当前可达 key；只删除一个 model 不得影响仍属于该 Provider 的共享 key。失败必须向 UI 报错并保持原 provider/config 可用。
- Connection Test 的成功/失败记录只能保存固定成功摘要或受限脱敏错误；服务端原样回显任意形态的本次 API key 时，必须先按完整值精确脱敏，不能只依赖 `sk-*` 等 provider-specific pattern。
- 保存、替换或清除 credential 必须推进 `credentialRevision`，使旧 Test Connection fingerprint 失效；显示名称变化不应使测试失效。
- 本地文件不具备独立加密能力，只依赖 macOS 当前用户权限与可选 FileVault；文案不得暗示其具备钥匙串级隔离。删除也不得宣称完成物理介质安全擦除。

## Provider schema 与 endpoint

- Settings 展示 allowlist 当前只能包含 `openai-audio-transcriptions-http-v1`；新增入口必须直接创建该 adapter 的内存 provider draft，不能隐式持久化默认 Provider。其他五个 adapter 仍须保留 schema、preset、迁移、测试与 runtime 能力。
- 当前可见层允许新增、命名和切换多个 OpenAI Compatible provider；一个 provider 必须能编辑多个 model，并可从 ready route 中选择 2–4 个参与对比，包括同 Provider 的不同模型。Intatis 式主卡必须继续以左侧 Provider 列表、右侧 Provider name/API key/Active model、Connection/Models disclosure、逐模型 Model ID/可选 Display name 和卡下 Test Provider/Save 组织；Connection/Models/Comparison/Advanced 的 header 整行至少 44 pt 可点，Provider 行至少 48 pt，对比 route 整卡至少 44 pt 可切换，不能退化为只命中小 chevron/checkbox。Picker/route 选择必须引用完整 selector，不得把可见数组写回 catalog，或在切换 editor 时隐式覆盖/删除其他 provider/model。保存后把显式选择的模型设为当前 route。
- Flotis 特有的 Comparison 与 Language/Prompt/Temperature 必须位于 Intatis 式 Provider/Models 主卡之后，不能塞进 Provider 共享字段或把一个 Provider 的 sibling model 重新拆成重复 endpoint/key。OpenAI Compatible UI 仍必须保留自定义 host 明示确认、凭据目标 host、Clear API Key、Test Provider 与 Save/Cancel；Clear/host/encoding 可随 Connection disclosure 收纳，但不能从可达设置路径消失或绕过安全确认。
- 对比 UI 必须明确提示：同一录音会发送给每个 selected route，并可能分别产生一次请求费用。未保存/无 key/配置无效的 route 不得新选入；已经失效的已选项必须在开始录音前再次严格预检，不能以 UI readiness 代替 runtime 校验。
- Realtime 只能用 `wss`，HTTP 只能用 `https`。
- URL 不允许 user/password、query、fragment；path 必须 `/` 开头，禁止 `//`、`://`、`?`、`#` 和反斜杠等歧义形式。
- 非 schema trusted host 只能在用户显式批准后保存；UI 必须展示 API key/音频会发送到的 host。
- Authorization-bearing HTTP upload 不跟随 redirect。
- adapter schema 声明为固定的模型/音频字段不能重新暴露成任意文本输入；`StreamingAudioCapture` 只接受 16/24 kHz、mono PCM16。不支持字段必须在 normalization/编码时省略，不能持久化空占位。
- Provider/Command editor 保持 draft + Save/Cancel；Add 也只能先创建内存 draft。半输入 URL、空 model 列表、未保存 adapter 切换或未配置 key 不得成为 active runtime 配置。

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

- 默认 endpoint `/v1/audio/transcriptions`、默认模型 `gpt-4o-mini-transcribe`，新通用 BYOK provider 默认 WAV PCM16 16 kHz mono；legacy v2 迁移或显式配置的 `.m4a` 仍须按其 MIME 正确上传。
- Endpoint 在 canonical schema 中继续分为 `baseURL + path`；UI 精简不得通过合并字段绕过 scheme/host/port/path 校验或 secret boundary。Language、request encoding、prompt、temperature 可折叠，音频与 JSON response mode 可隐藏但必须保留旧值和 normalize contract。
- `multipart-form-data` 上传应继续通过临时文件/streamed request，不能重新用 `Data(contentsOf:)` 加完整 in-memory multipart body。
- OpenRouter (`openrouter.ai`) 使用 `json-base64` 请求：最终 URL 为 `https://openrouter.ai/api/v1/audio/transcriptions`，JSON 必须包含 Base64 `input_audio.data`、与文件匹配的 `input_audio.format` 和未经截断的完整 model ID；可选加入 language/temperature，不得发送未声明的 prompt。未显式配置 encoding 的 OpenRouter route 必须自动归一化为 `json-base64`，其他 OpenAI-compatible host 默认 multipart，用户显式覆盖必须保留。
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

- `VoiceInputController` 的 session generation/identity guard 不得绕过。任何异步 callback 在修改 UI、清理资源或提交最终文本前都必须验证当前 session。
- V0.13 最终转写必须先进入 `reviewing`，不得恢复 provider 完成即自动提交。进入 reviewing 前应释放已完成的 capture/transcriber/runtime；reviewing 文本允许用户编辑。
- reviewing 文本必须保持原生可选择/可复制能力，至少支持鼠标选区、`⌘C` 和显式复制全部；不能用窗口背景拖动或不可命中的装饰 overlay 吞掉文本交互。
- reviewing 的当前热键动作必须是 `copyAndReturn`：用 trim 结果判断空白，但必须原样复制用户编辑文本；写入失败必须保留 reviewing/文本并保持 panel 可见，成功后才允许推进 generation、清空文本、回 idle，并让审阅框按逻辑位置锚点缩回小胶囊。成功路径不得隐藏或关闭 panel。当前产品路径不得调用 `ClipboardPasteInjector`、请求 AX 或发送 `CGEvent`/`⌘V`。
- requesting/connecting 可由热键取消；stopping/transcribing 已进入终态处理时，额外热键必须忽略而不是清空本次会话。
- operation task、audio writer、limit task、streaming/file transcriber、capture/recorder 都必须可取消；App 退出也必须调用 cancel。
- model route 和 provider key 在会话开始时快照到 adapter runtime。stop 阶段不得重新依赖一个可能已被 UI 删除/切换的 route 或可变配置记录。
- 对比第一版只允许 2–4 个 `.recordedFile` runtime；当前 Settings 只选择 OpenAI Compatible HTTP。开始录音前必须为每项完成配置/key/runtime 快照，拒绝非 file runtime，并要求 format/sample rate/channels 完全一致；预检失败必须取消此前已创建的 runtime，不能先录音再发现不兼容。
- 一次对比会话必须只有一个 `AudioRecorder` 和一个共享录音文件。所有 selected transcriber 必须收到同一 file URL；最大录制时长采用各 runtime 的最严格安全上限，每项仍独立执行 upload-size 预检。不得为了并发比较重复采集麦克风或为每个 provider 生成内容不同的录音。
- fan-out 必须并发、结果按用户配置顺序恢复，并隔离单项失败；一项错误/空结果/超限不得取消其他成功项。至少一个成功时同时展示成功与失败候选；全部失败才进入全局 failed。取消、退出、session 失效和正常完成都必须取消全部 transcriber 并清理共享文件。
- 对比 reviewing 必须按配置/展示顺序自动打开第一个成功候选，但不得把它描述为最快、评分最高或自动判定的“最佳”结果。点击或用户配置的 previous/next 快捷键（默认 `⌥←` / `⌥→`）只能切换成功候选，必须跳过失败项并在两端循环；切换时保留每个候选的当前编辑文本。`copyAndReturn` 始终复制当前候选，成功复制或取消要同时清空候选和 selection。
- 当前复制并返回路径不得捕获、激活或猜测目标 app；复制结果只留在系统剪贴板，由用户自行决定粘贴位置。若未来重新启用旧注入器，目标捕获和核验仍必须遵守下节兼容边界。
- realtime chunk 必须进入有界串行 writer；overflow 应失败并提示，stop 必须先 drain 再 terminal commit/finish。
- `StreamingAudioCapture.stop()` 必须保持当前 generation/converter 有效，直到 tap callback group、conversion queue 与 converter end-of-stream 尾帧全部 drain；只有 `cancel()` 可以先失效 generation 丢弃待处理 chunk。
- transcriber 的 socket sender 与共享状态必须保持 actor/锁隔离，旧连接回调不能污染新连接。
- `AudioRecorder.prepareToRecord()`、`record()` 与最终文件检查返回值不可忽略。

## 热键、当前复制与旧注入安全边界

- `VoiceInputState.reviewing.hotkeyAction` 必须保持 `copyAndReturn`；idle/failed→start、recording/streaming→stop、requesting/connecting→cancel、stopping/transcribing/injecting→none 的其余映射不得回归。
- voice descriptor 由用户配置、默认 `⌃⌥A`（Carbon virtual key `0`，Control+Option）；panel descriptor 默认 `⌘⌥⇧0`，previous/next 默认 `⌥←` / `⌥→`。previous/next 只能在对比 reviewing 且至少两个成功候选时临时注册，离开后必须注销；不得在 idle、单结果 reviewing 或后台普通使用中长期抢占任何用户配置的导航按键。不得藉热键调整重新接入 Accessibility/Input Monitoring、改写系统键盘/听写设置或改变当前复制并返回状态机。
- 当前复制写入成功后必须直接清空会话并回 idle，不得恢复 `.closePanel` outcome 或窗口关闭回调。失败或纯空白必须保持 panel 与 review 可恢复；复制后的文字必须留在剪贴板，不能用旧注入器的 snapshot restore 覆盖。
- `ClipboardPasteInjector` 当前只作为不可达兼容实现保留；没有用户新的明确产品决策，不得重新接入 AppDelegate、`VoiceInputController` 或审阅按钮。

- 如果旧 `ClipboardPasteInjector` 被独立调用，缺 AX 权限时必须立即返回明确的 accessibility failure；禁止以任何方式绕过检查发 `CGEvent`。当前产品 UI 不展示或请求 AX；未来重新接入时，平时状态刷新仍须非提示式，只有用户明确发起授权或真实注入缺权时才可提示。
- 保留的旧 `ClipboardPasteInjector` 仍按 legacy 默认 A + Control/Option 检查释放，因此在 voice 可配置后更不能直接接回产品路径。若未来明确重接，必须先让 operation 快照触发时的完整 voice descriptor，并在发 `⌘V` 前再次确认：operation 未过期、目标进程存活且 PID 未变、目标仍为 frontmost、Flotis 自身不再持有 key window、该 descriptor 的主键及相关修饰键均已释放、AX 仍可信、pasteboard `changeCount` 仍是 app 管理值。
- 用户在激活等待中切到第三方 app 时必须 abort，不能把文本发给当前任意 frontmost app。
- 队列必须保持有界（当前 max in-flight 4、burst 8、operation 5 秒过期）或采用同等安全的 backpressure；不得恢复无上限 backlog。
- 剪贴板无法完整复制全部 item/type 时拒绝注入。恢复只在 `changeCount` 未被外部更新时进行，且要检查 `writeObjects` 成功。
- 完整语音快捷键等待超时必须失败，不能只等修饰键、不等当前描述符的主键，也不能超时后照常粘贴。
- success 只代表安全核验、PID 定向 event post 与 clipboard outcome 成功；不得在 UI 文案中声称已证明目标控件消费文本。失败结果必须保持可区分，不能再次压扁成无法诊断的单一 Bool。
- 点击胶囊编辑导致 Flotis 获得键盘焦点时，只能使用当前语音 session 开始时捕获并重新核验的非 Flotis target；显式胶囊输入可重激活该目标，从不同第三方 app 触发全局热键则必须 abort。不得直接向任意 frontmost app 或未核验 PID 发事件。
- 旧命令的可打印全局快捷键必须包含 Command + 至少一个额外修饰键；toggle、重复项与 `⌘V` 等危险组合必须拒绝。当前 voice 组合由主入口直接注册，不经过旧命令的 `shortcutSafetyError`，不得据此放宽用户命令快捷键的安全校验；若未来恢复命令入口，必须让命令冲突校验读取当时的四项快捷键配置，不能继续只依赖旧默认常量。
- hotkey handler 必须同时监听 press/release 并以 gate 抑制 auto-repeat；注册必须保持 `kEventHotKeyExclusive`。handler 安装失败时不得继续注册；单项失败必须保留、通过 compact 胶囊的橙点与 accessibility value 暴露并自动重试，event signature 必须核验，不得为此重新增加可见错误句或按钮。
- panel 的真实 `window.isVisible` 与 `AppState.isPanelVisible` 必须同步；voice hotkey 在 panel 隐藏时应恢复胶囊可见性，reviewing 第三次热键复制成功后必须保持 panel 可见并缩回 idle 小胶囊，复制失败时则继续显示 reviewing panel。对比结果只要至少一项成功就必须已有自动 selection；不得重新引入等待人工首次选择的空 selection 状态。
- panel 必须允许用户从非审阅胶囊的任意可见位置拖动，但在用户鼠标事件之外必须保持 `isMovable=false`，使系统在 Space/显示环境过渡中维持相对屏幕位置，不能重新长期开启系统管理移动而产生动画结束后的瞬移。单次 mouse-down 必须由 panel 直接进入原生 `performDrag(with:)`，不得只依赖被全尺寸 SwiftUI surface 吞掉的 background drag。reviewing 的 mouse-down 可仅在原生事件分发调用期间临时允许 background drag，使非交互背景仍可拖、文本与按钮继续优先；不得把可移动状态留到事件之外。尺寸变更要合并旧请求、只应用最后一次，并以独立逻辑锚点保持用户选择的水平中心与底边、将实际 frame 钳制在目标屏幕可见区。程序 resize 为可见性产生的临时钳位不得覆盖逻辑锚点，idle→reviewing→取消或复制成功都必须恢复展开前的小胶囊位置；只有用户主动拖动才更新锚点。reviewing 的鼠标事件必须继续转发给原生编辑器，避免窗口拖动抢占文本拖选或双击选词。Settings 必须使用独立窗口，不能重新附着成推动胶囊的 sheet；其内容滚动不得把侧栏或页头推入标题栏。
- Settings 的窗口内容默认尺寸必须保持 `1100×760`、最小内容尺寸保持 `820×600`；HostingController 赋值后必须显式应用 `contentMinSize` 和 `setContentSize`，不能再次让 SwiftUI fitting size 把实际内容宽度缩成 820 pt、破坏 Provider/Models 双栏。若后续调整尺寸，必须同时用折叠和 Models 展开状态做与 Intatis 参考同屏的运行态视觉回归。
- 当前 compact Presentation contract 为 reviewing 之外所有状态统一 `96×36`、18 pt 连续圆角的透明系统 glass/material 表面；AppKit 原生容器必须是唯一底面，SwiftUI compact 内容不得绘制固定白色/不透明填充或自定义整圈描边，快捷键必须使用随 Light/Dark appearance 解析的动态主文字色。可见内容严格只有 6 pt 语义圆点、7 pt 间距和 15 pt 系统 Semibold Monospaced 的当前 voice 快捷键。不得重新增加品牌名、麦克风、设置齿轮、计时、状态/错误句、说明、hover 提示、动作按钮或任何其他可见元素，也不得把参考图中的 `Ask` 当作提示词移植。idle/成功为绿色，录音/流式为红色，请求/连接/停止/转写/失败/热键错误为橙色；完整状态与错误只通过 accessibility value 暴露。voice 快捷键的 start/stop/copy-and-return 状态映射不得因键位配置或视觉精简改变。
- Settings 的 compact 入口必须是非审阅胶囊双击：单击不得打开设置；double-click 复用现有独立 Settings 窗口；reviewing 中不得由 panel 截获双击，以免破坏原生文本选词。最小胶囊上不得为该交互增加齿轮、文字提示或其他可见 affordance。
- 单结果 reviewing 的 Presentation contract 保持 `420×160`；对比 reviewing 为 `560×300`，必须用固定双列网格容纳 2–4 个候选，四项为 2×2，不能退化为需要横向滚动的一行。首个成功项直接打开原生编辑器，不显示额外的“先选择”提示；既有复制/取消/复制并返回动作保留。候选有非空 Model Display name 时可见卡片只能显示该名称；没有时必须以 Model ID 为主要文字、Provider 名称为次要文字，不能显示 endpoint。失败状态不能只靠颜色表达，长 Display name/model/provider 必须截断，panel 不能超过当前 `600×300` 上限。
- macOS 26+ 的 panel 容器必须继续由原生 `NSGlassEffectView(style: .regular)` 承载，macOS 13–25 的 material fallback 与窗口阴影路径仍须保留。compact SwiftUI 层必须透明，禁止再用固定浅色/深色填充、固定 tint 或覆盖 material 的额外表面压平系统 Liquid Glass；reviewing/Settings 的既有原生 glass/material 兼容路径也不得因最小胶囊改版退化。
- 当前 Settings 不应展示 AX 状态或授权入口，胶囊 reviewing 也不应因缺 AX 展开提示；当前流程只需报告系统剪贴板写入失败。旧 AX 文案/类型可随兼容实现保留，但不得成为可达主流程。
- Settings 的一键退出必须走 `NSApplication.terminate` → `applicationWillTerminate`，不得用 `exit`/kill 绕过热键与语音资源清理；`.injecting` 期间不仅要禁用页头按钮，`applicationShouldTerminate` 还必须统一拒绝菜单、`⌘Q` 等其他终止请求，避免剪贴板尚未完成安全恢复。

## InputMethodKit 接口边界

- `main.swift` 在输入法进程生命周期内只能创建一个 `IMKServer`，并使用 `IMKServer(name:bundleIdentifier:)` 让 InputMethodKit 从当前 bundle plist 解析 controller/delegate；不得改回已证明会在 nil delegate 下崩溃的 legacy initializer。connection name、controller class、顶层/模式级 `TISInputSourceID` 与图标键必须与生成的 Info.plist 保持一致。
- 普通 `inputText` 必须返回 `false`，不能吞掉或改写用户日常键盘输入。显式 commit 只能通过当前 `client()` 的 `insertText` 在当前插入点执行，不得猜测任意 app、PID 或 replacement range。
- 每次 controller activation 必须创建新 session；deactivate、close 或新 activation 必须使旧 session 失效。请求必须核验 protocol version、非空内容、1 MiB 上限和当前 session，验证失败不能触达 client。
- service 只弱持有当前 endpoint，不记录、持久化或打印提交文本。session UUID 是防陈旧请求的时序 token，不是未来 IPC 身份认证；增加跨进程传输前必须另行定义同一签名/用户边界、调用方认证、超时和重放策略。
- 输入法 target 当前不得读取 API key、connection、剪贴板、麦克风或语音文件，也不得调用 AX/`CGEvent`。在主 App 明确接线前，现有主 App 必须继续停在“reviewing → 系统剪贴板复制 → 回到可见 idle 小胶囊”；不得把输入法接口或旧注入器静默接回默认路径。
- 构建不等于安装或可用。未经明确授权，不复制到 `~/Library/Input Methods`、不切换输入源、不启动输入法做真实提交；手动验证必须区分“系统发现”“激活”“client 收到文字”三层结果。即使 `TISRegisterInputSource` 返回成功，新安装/修改的 bundle 仍可能要在注销并重新登录后才出现在当前登录会话的输入源缓存；不得通过关闭 SIP 或强制终止受保护服务绕过该边界。

## 临时文件

- 录音/连接测试前缀：`Flotis-Audio-`，扩展名按 recorded-file route/runtime 为 `.m4a` 或 `.wav`；连接测试生成物同样必须在成功、失败和取消路径清理。
- 对比会话复用同一个 `Flotis-Audio-*` 文件；不得为每个 provider 复制一份，也不得把临时路径或音频内容写入 canonical comparison 字段。runner 完成、全部失败、部分失败、取消和 generation 过期都必须清理。
- multipart 前缀：`Flotis-Multipart-`。
- 清理只能删除 app 自有前缀、普通文件且修改时间超过 24 小时的项；禁止扫描删除任意 `/tmp` 文件。
- 每条成功、失败、取消路径都应尽快清理本会话临时文件。

## Test Connection 边界

- 必须复用真实 adapter/runtime contract，不得退化成只 ping URL 或只请求模型列表。
- 测试音频必须由应用生成或内置且不含用户隐私；不得读取麦克风、历史录音或用户转写文本。本实现使用短合成音，因此成功只证明连接、音频传输和响应结构，不证明识别质量，也不得强制 transcript 非空。
- HTTP 测试必须覆盖 multipart、OpenRouter JSON+Base64 与响应结构；Realtime 测试必须走 start→append→commit/stop→terminal。HTTP 成功不能推导 Realtime 兼容。
- 测试记录 fingerprint 必须覆盖 endpoint/model/options/credential revision 和 adapter version；显示名称变化不应失效，配置或凭据变化必须失效。
- 所有成功、失败、取消路径都必须 cancel runtime 并删除测试临时文件；不得持久化完整响应、Authorization、transcript 或 API key。

## 回归门槛

源码、工程或测试变更完成前至少运行：

```sh
xcodegen generate
xcodebuild -project Flotis.xcodeproj -scheme Flotis -configuration Debug -derivedDataPath /tmp/FlotisBuildDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Flotis.xcodeproj -scheme Flotis -configuration Debug -derivedDataPath /tmp/FlotisTestDerivedData CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Flotis.xcodeproj -scheme FlotisInputMethod -configuration Debug -derivedDataPath /tmp/FlotisInputMethodBuildDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Flotis.xcodeproj -scheme FlotisInputMethodTests -configuration Debug -derivedDataPath /tmp/FlotisInputMethodTestDerivedData CODE_SIGNING_ALLOWED=NO test
git diff --check
git status --short
```

协议、AX/CGEvent、canonical config/凭据存储、audio engine 或 InputMethodKit 变更还需按 `docs/TESTING.md` 做对应文件系统/真机矩阵；自动化构建/单测不能替代真实权限、输入法客户端或供应商联调。
