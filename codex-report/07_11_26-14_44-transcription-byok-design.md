# Flotis 统一语音转写提供商与 BYOK 设计方案

## MODEL_CHECK_RESULT

当前执行模型：Codex / GPT-5。

## PATH_CHECK_RESULT

- `pwd`：`/Users/vita/Vitemis/Flotis`
- Git root：`/Users/vita/Vitemis/Flotis`
- 结果：路径一致，匹配预期仓库根目录。

## FILES_WRITTEN

- 新增实现：`Flotis/TranscriptionAdapterRegistry.swift`、`Flotis/TranscriptionConnectionTester.swift`、`FlotisTests/TranscriptionAdapterRuntimeTests.swift`。
- 重构：connection/schema/store/controller、HTTP/Realtime/原生 transcriber、统一设置/浮窗 UI、测试与 XcodeGen 工程配置。
- 同步：本报告及 `docs/CURRENT_STATE.md`、`PROJECT_MAP.md`、`ARCHITECTURE.md`、`DO_NOT_BREAK.md`、`TESTING.md`。

## SUMMARY

Flotis 的语音转写配置应从“每个厂商对应一个一级选项”调整为“统一管理用户创建的转写连接”。

核心关系：

```text
一个协议适配器 1 ────── N 个用户提供商配置实例
```

- **提供商/连接实例**：用户实际创建和选择的配置，例如“OpenAI 官方”“公司 ASR”“本地 Whisper”。
- **协议适配器**：程序内部实现的 wire protocol，例如 OpenAI Audio Transcriptions HTTP、OpenAI Realtime GA、Apple on-device。
- **厂商预设**：只负责自动填充 Endpoint、Path、模型和限制，不参与运行时类型判断。

同一协议的所有服务商必须使用同一个新增/编辑界面、同一套校验和同一个 runtime adapter。用户可以在同一协议下创建任意多个连接实例。

## PRODUCT_DECISION

### 用户看到的是连接，不是厂商协议树

主面板和设置页的 Picker/List 显示用户命名的连接：

```text
转写提供商
├── Apple 本地
├── OpenAI 官方
├── 公司 ASR
└── 本地 Whisper
```

“OpenAI”“Groq”“公司内部服务”“自托管 Whisper”如果都实现相同的 OpenAI Audio Transcriptions HTTP contract，就只是四个使用同一 adapter 的配置实例，不应对应四套 UI 或四个 transcriber class。

### 新增和编辑使用同一界面

```text
新增转写提供商
┌────────────────────────────────────┐
│ 名称          公司 ASR              │
│ 协议          OpenAI-compatible HTTP│
│ 快速预设      自定义                 │
│ Base URL      https://asr.example   │
│ Endpoint Path /v1/audio/transcriptions│
│ Model         whisper-large-v3      │
│ API Key       ••••••••••            │
│ Language      zh                     │
│                                    │
│ [高级设置]                          │
│ [测试连接]              [取消] [保存]│
└────────────────────────────────────┘
```

表单行为：

1. 首先选择协议兼容类型。
2. 协议决定显示哪些字段、默认音频格式和 runtime adapter。
3. 预设只填入建议值，之后所有字段仍属于当前连接实例。
4. Save 前执行静态校验；“测试连接”执行真实协议探测。
5. 未保存的 draft 不得影响当前 active provider。

## BYOK AND PROTOCOL COMPATIBILITY

BYOK 与协议兼容是两个独立概念：

- **BYOK**：用户拥有 API Key、账号、配额和账单，Flotis 直接请求用户选择的服务。
- **协议兼容**：目标服务必须实现所选 adapter 要求的请求、音频和响应格式。

GitHub Copilot 的 BYOK 也不是“完全无需 adapter”：官方配置仍指定 provider type、Base URL、API Key 和模型；GitHub 当前把 OpenAI-compatible providers 列入支持范围，并注明该能力处于 public preview：

- https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-for-organization/use-your-own-api-keys
- https://docs.github.com/en/copilot/how-tos/copilot-sdk/setup/backend-services

Flotis 可以采用相同的产品体验，但不能把“兼容 OpenAI Chat API”自动解释为“兼容 OpenAI 语音接口”。

## RECOMMENDED PROTOCOL FAMILIES

| Adapter ID | 用户标签 | 适用场景 | 通用程度 |
|---|---|---|---|
| `apple-on-device` | Apple 设备端 | 本地、无 Key、无网络 | Apple 专属 |
| `openai-audio-transcriptions-http-v1` | OpenAI-compatible HTTP | 录音停止后 multipart 上传 | 推荐的通用 BYOK 主路径 |
| `openai-realtime-transcription-ga` | OpenAI Realtime GA | 实时 partial/final transcription | 仅适用于完整实现 GA Realtime 的端点 |
| `dashscope-paraformer-ws-v1` | DashScope 原生实时协议 | task lifecycle WebSocket | 原生高级 adapter |
| `volcengine-bigasr-ws-v3` | 火山 BigASR 原生协议 | 二进制 WebSocket、资源 ID | 原生高级 adapter |
| `glm-asr-http-sse-v4` | GLM ASR HTTP/SSE | WAV 上传、SSE 响应、服务限制 | 原生高级 adapter |

厂商特有 adapter 仍可存在于内部，但不再各自拥有独立的管理页面。它们在统一表单的“协议”字段或“高级预设”中出现。

## WHY HTTP CAN BE GENERIC BUT REALTIME CANNOT BE ASSUMED

### OpenAI-compatible HTTP transcription

OpenAI Audio Transcriptions 使用：

```text
POST /v1/audio/transcriptions
Content-Type: multipart/form-data

file=<audio>
model=<model-id>
language=<optional>
prompt=<optional>
temperature=<optional>
```

标准响应通常包含 `text`；部分模型可选择 SSE streaming。官方接口支持多种文件格式，并将 model、language、prompt、response format 等作为明确字段：

- https://platform.openai.com/docs/api-reference/audio

这套 request/response contract 边界相对清晰，适合作为 Flotis 第一阶段的通用 BYOK adapter。

### OpenAI Realtime transcription

Realtime 不只是“把 URL 换成 WSS”。完整兼容至少包括：

- `session.update` 与 `session.type = transcription`；
- 嵌套 `session.audio.input` 配置；
- 24 kHz mono PCM；
- `input_audio_buffer.append` / `input_audio_buffer.commit`；
- delta/completed 事件；
- `item_id` / `content_index` 对齐与跨 turn 顺序处理；
- VAD/manual commit 和终态等待。

官方协议说明：

- https://developers.openai.com/api/docs/guides/realtime-transcription

因此 Realtime 必须使用带版本的精确 adapter，例如 `openai-realtime-transcription-ga`。不能因为某个服务自称“OpenAI-compatible”就默认它同时实现 Realtime。

## PROPOSED DATA MODEL

### Connection instance

```json
{
  "id": "uuid",
  "name": "公司 ASR",
  "adapterID": "openai-audio-transcriptions-http-v1",
  "endpoint": {
    "baseURL": "https://asr.example.com",
    "path": "/v1/audio/transcriptions",
    "customEndpointApproved": true
  },
  "model": "whisper-large-v3",
  "language": "zh",
  "authentication": {
    "type": "bearer",
    "apiKeyReference": "keychain-reference"
  },
  "audio": {
    "format": "wav",
    "sampleRate": 16000,
    "channels": 1
  },
  "options": {
    "prompt": null,
    "temperature": null,
    "responseMode": "json"
  }
}
```

API Key 明文不得进入该 JSON；这里只保存 Keychain reference。

### Adapter definition

Adapter 负责：

- 声明 transport、auth scheme 和 endpoint requirements；
- 声明可编辑/固定的模型与音频参数；
- 声明 language、prompt、temperature、partial、SSE、VAD 等能力；
- 对 connection draft 做 normalization/validation；
- 创建 recorder/capture/transcriber；
- 将服务端结果规范化为统一的 partial/final/error/cancel 生命周期。

建议接口概念：

```swift
protocol TranscriptionAdapter {
    var id: String { get }
    var schema: TranscriptionAdapterSchema { get }

    func normalize(_ connection: TranscriptionConnection) -> TranscriptionConnection
    func validate(_ connection: TranscriptionConnection) -> String?
    func makeRuntime(
        connection: TranscriptionConnection,
        credential: String?
    ) throws -> TranscriptionRuntime
}
```

### Preset definition

Preset 与 adapter 分离：

```json
{
  "id": "openai-official-http",
  "displayName": "OpenAI 官方",
  "adapterID": "openai-audio-transcriptions-http-v1",
  "defaults": {
    "baseURL": "https://api.openai.com",
    "path": "/v1/audio/transcriptions",
    "model": "gpt-4o-mini-transcribe"
  }
}
```

选择 preset 后得到普通 connection；后续运行时不再按 preset/vendor 分支。

## UNIFIED FORM FIELDS

### 所有网络连接共有

- 名称
- 协议兼容类型
- 快速预设（可选）
- Base URL / Realtime URL
- Endpoint Path
- Model / Deployment ID
- API Key
- 凭据发送目标 host
- 自定义 host 信任确认
- Test Connection
- Save / Cancel / Clear Key

### 由 adapter 动态控制

- Language
- Prompt / keyword hints
- Temperature
- Audio file format
- Sample rate / channels
- Response format
- JSON 或 SSE response
- Realtime delay/VAD/manual commit
- 上传时长/字节限制
- 厂商原生 resource ID 或专有功能

不支持的字段不显示、不持久化，也不发送空值占位。

## GENERIC HTTP COMPATIBILITY BASELINE

第一阶段建议采用保守 contract：

- HTTPS only；
- Bearer API Key；
- 默认 `/v1/audio/transcriptions`；
- multipart `file` + `model`；
- language 可选；
- prompt/temperature 默认不发送；
- 默认 JSON `{ "text": "..." }` 响应；
- 默认 WAV、PCM16、16 kHz、mono，以提升跨实现可移植性；
- 不跟随携带 Authorization 的 redirect；
- 自定义 host 必须明确确认；
- 失败时不自动把音频发送到其他 provider。

如果服务只兼容 Chat Completions、响应缺少顶层 `text` 字段、拒绝音频格式或字段，就应在 Test Connection 阶段判为不兼容，而不是静默猜测响应结构；顶层 `text` 存在但为空仍是合法协议响应。

## TEST CONNECTION DESIGN

“测试连接”应验证真实 contract，而不是只做 URL ping：

1. 本地检查 HTTPS/WSS、host、path、model 和 Key 是否完整。
2. 可选请求 `/v1/models` 辅助确认认证和模型名，但不能把它当作语音能力证明。
3. 使用程序生成、无用户隐私的短 PCM/WAV 样本请求 transcription endpoint；显式选择 M4A 的 connection 使用匹配的 M4A 样本。
4. 验证 HTTP status、Content-Type 和响应结构。
5. 只显示必要错误摘要，不记录 Authorization、完整响应或用户转写内容；按本次内存中的实际 Key 精确脱敏任意原样回显。
6. 记录最后测试时间、adapter version 和结果；endpoint/model/key boundary 变化后自动失效测试状态。

Realtime 测试还需验证 session ack、append/commit、delta/completed 和 terminal lifecycle；普通 HTTP 测试成功不能证明 Realtime 兼容。当前样本是合成音而非语音质量 fixture，因此合法空 `text` 仍可证明 transport 与响应结构成功，不强制产生非空 transcript。

## SECURITY REQUIREMENTS

- API Key 继续只保存到 Keychain。
- secret boundary 至少包含 adapter ID + scheme + host + port + auth type。
- adapter、host 或 auth type 改变时必须生成新 Keychain reference，不跨服务复用旧 Key。
- 配置先成功持久化，再清理旧 secret；清理失败必须回滚或向用户明确报告。
- UI 始终展示 Key 和音频将发送到的精确 host。
- HTTPS/WSS only；拒绝 userinfo、query、fragment 和歧义 path。
- Authorization-bearing request 不跟随 redirect。
- Test Connection 不使用用户历史录音或真实转写文本。

这些要求应继承当前 `KeychainSecretStore`、custom endpoint approval、secret boundary 和 no-redirect 机制，不得因 BYOK 通用化而弱化。

## CURRENT CODE ALIGNMENT

设计已经落地：

- canonical `TranscriptionConnection` v3 使用嵌套 endpoint/authentication/audio/options/test record；legacy `kind` / `wireProtocol` 只作未编码的迁移兼容计算层。
- 六个稳定、版本化 `TranscriptionAdapterID` 统一注册到 `TranscriptionAdapterRegistry`；controller 只执行 owned-capture、PCM-stream、recorded-file 三类计划，不含厂商 switch。
- `TranscriptionProviderPreset` 与 connection/adapter 分离，只对 draft 做字段填充；用户手改协议字段后 UI 自动回到“自定义”。
- 设置页只有一个 Add Connection 入口，新增与编辑共用 schema-driven editor；同 adapter 支持多个 endpoint/model/key 独立实例，主面板只显示用户命名。
- OpenAI-compatible HTTP 默认 WAV PCM16 16 kHz mono，严格验证 HTTPS、no redirect、multipart、2xx、`application/json` 和顶层 `text`；不猜测嵌套响应。
- OpenAI Realtime 只解析 GA 事件；DashScope、Volcengine、GLM 继续使用各自精确协议，其中 GLM 严格要求 SSE JSON 事件与 `[DONE]`。
- Test Connection 复用 registry/runtime、使用程序生成的无隐私音频，保存 adapter version/fingerprint/安全摘要，不保存 transcript 或响应正文。

## MIGRATION PLAN

已引入 schema v3，并保留 v2/v1 作为只读 migration input。

| 当前 v2 protocol | v3 adapterID | 迁移策略 |
|---|---|---|
| `appleSpeech` | `apple-on-device` | 保留 ID、名称、locale、active 状态 |
| `openAIHTTP` | `openai-audio-transcriptions-http-v1` | 保留 endpoint/model/language/options；host 未变时保留 key reference |
| `openAIRealtime` | `openai-realtime-transcription-ga` | 保留 endpoint/language；固定 GA 音频 contract |
| `dashScopeParaformerRealtime` | `dashscope-paraformer-ws-v1` | 迁移为统一 connection + 原生 adapter |
| `volcengineBigASRRealtime` | `volcengine-bigasr-ws-v3` | 保留 resource ID、two-pass 与 key boundary |
| `glmASRHTTPStream` | `glm-asr-http-sse-v4` | 保留 WAV、prompt、30 秒/25 MiB 限制 |

迁移要求：

- 保留现有 provider UUID、名称和排序；
- 保留有效 active provider；
- adapter + host + auth boundary 未变化时可保留现有 Keychain reference；
- 不得复制、打印或重新编码 API Key 明文；
- 新 snapshot 写入成功前不覆盖 v2；
- 继续保留 last-known-good、corrupt backup 和回滚；
- migration 必须有纯单测，覆盖六个 preset、自定义 provider、active ID 和 secret boundary。

## DELIVERY PHASES

以下四个阶段已在本轮一次性完成；保留分阶段说明作为后续维护边界。

### Phase 1 — BYOK-first HTTP（已完成）

- 引入 connection/adapter/preset 三层概念；
- 统一新增/编辑界面；
- 将 OpenAI HTTP 改为通用 `openai-audio-transcriptions-http-v1`；
- 允许同协议创建多个连接实例；
- 主 Picker 只显示 connection name；
- 原生协议继续工作，但移入高级 adapter/preset。

### Phase 2 — Connection test and capabilities（已完成）

- 加入复用真实 adapter/runtime contract 的 Test Connection；本轮以 fake transport/scripted WebSocket 做自动化验证；
- 区分 required、optional、unsupported fields；
- 保存 adapter version 与最近测试结果；
- endpoint/model/auth boundary 变化后要求重新测试。

### Phase 3 — Realtime BYOK（已完成）

- 将 OpenAI Realtime 明确版本化为 GA adapter；
- 开放符合该 contract 的自定义 WSS endpoint/model；
- 测试 session/commit/event/ordering 全链路；
- 不以 HTTP compatibility 推导 Realtime compatibility。

### Phase 4 — Adapter registry cleanup（已完成）

- 将 DashScope、Volcengine、GLM runtime 注册到统一 adapter registry；
- 从 controller 中移除 vendor switch；
- Provider settings 完全由 adapter schema 驱动；
- 保留现有 session generation、cancel、drain 和 terminal guarantees。

## ACCEPTANCE CRITERIA

### UI

- 所有 provider 在同一个列表和同一个 editor 中新增、修改、删除和设为当前。
- 同一 adapter 可以创建至少两个不同 endpoint/model/key 的 connection。
- 预设只填充字段，不改变 editor 或 runtime type。
- 主面板只显示用户命名的 connection。
- 不支持字段不会出现在表单或持久化数据中。

### Runtime

- controller 只依赖 adapter/runtime interface，不按厂商名称分支。
- OpenAI-compatible HTTP connection 的录音→上传→转写→注入代码路径已接通；本轮以 mock transport 验证请求/响应 contract，未做真实 provider、麦克风或 AX 注入端到端。
- HTTP compatibility 不会错误启用 Realtime。
- adapter switch 保持 session generation、cancel、audio drain 和 terminal wait。

### Data and security

- v2 六个现有 provider 可无损迁移到 v3 connection。
- active provider、用户名称和现有 Keychain reference 在安全边界不变时保留。
- host/adapter/auth 改变时旧 Key 不复用。
- 真实 API Key 不进入 UserDefaults、日志、报告或测试 fixture；自动化只使用明确的 dummy literal 与内存 secret store。
- corrupt data、cleanup failure 与 rollback 路径有自动化测试。

## IMPLEMENTATION_ACCEPTANCE_RESULT

| 范围 | 结果 | 自动化/静态证据 |
|---|---|---|
| 统一列表、Add/Edit editor、connection name Picker | PASS | schema-driven Settings 与 Floating Panel；Add draft/Cancel 不落盘测试 |
| 同 adapter 多 endpoint/model/key | PASS | connection/store 隔离与自定义 HTTP request 测试 |
| preset 只填字段 | PASS | identity/adapter 保留测试；手改字段后 UI 回到“自定义” |
| 六 adapter registry / controller 无厂商 switch | PASS | registry 唯一性、六路径→三类 plan 测试及 controller 静态审计 |
| HTTP / Realtime / GLM 严格协议 | PASS | fake HTTP、scripted Realtime GA、GLM SSE parser 测试 |
| v1/v2→v3 迁移与恢复 | PASS | 六类、自定义实例、顺序、active、reference、v2 LKG、v3 LKG 测试 |
| Keychain 边界与事务 | PASS（逻辑） | 内存 secret store 覆盖轮换、清理失败与回滚；未访问真实 Keychain |
| Test Connection 安全 | PASS | 合成 WAV/M4A/PCM、合法空文本、opaque Key 回显精确脱敏测试 |
| 真实 provider + 麦克风 + AX/`CGEvent` E2E | 未执行 | 用户明确限定仅静态和自动化验证 |

## NON-GOALS

- 不承诺所有自称“OpenAI-compatible”的服务都实现 Audio Transcriptions。
- 不通过宽松猜测把任意 JSON/SSE/WebSocket 响应当成兼容协议。
- 第一阶段不追求任意自定义认证 header；先支持明确的 Bearer contract。
- 不把厂商原生 Realtime 协议硬塞进 OpenAI Realtime adapter。
- 不在连接失败时自动把用户音频发送到另一家服务商。

## UNCERTAINTIES

- 不同 OpenAI-compatible 服务对音频格式、最大文件、prompt、temperature、SSE 和 response format 的支持并不一致，需要 Test Connection 和 adapter capability 明确处理。
- `/v1/models` 能确认认证或模型列表，但通常不能证明具体模型支持 transcription。
- OpenAI Realtime-compatible 第三方实现的 GA 覆盖程度需要逐端点验证，不能仅靠厂商宣传判断。
- 当前连接测试使用约 0.8 秒程序合成音，适合验证协议 transport/结构，不用于判断识别质量；若未来要把“非空转写”作为成功条件，必须改用经过许可且稳定的可识别语音 fixture。
- v3 canonical encoder 不保留 flat legacy fields；旧字段仅在 v1/v2 decode bridge 中使用。
- 真实供应商认证、限流、服务端协议漂移，以及麦克风/AX/`CGEvent` 系统交互，仍需用户提供授权与凭据后另做真机验证，本轮明确不执行。

## VALIDATION_RESULT

本轮实际运行：

- `pwd` → `/Users/vita/Vitemis/Flotis`
- `git rev-parse --show-toplevel` → `/Users/vita/Vitemis/Flotis`
- `xcodegen generate` → 成功生成工程。
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` → `BUILD SUCCEEDED`。
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO test` → `TEST SUCCEEDED`，39 tests、0 failures：Hotkey 5、Transcript 4、Configuration 20、Runtime 10。
- 自动化使用 fake HTTP transport、scripted WebSocket、dummy credential literal 与内存 secret store；未创建、读取或使用真实 API key，未请求真实 provider，未采集麦克风，也未触发 AX/`CGEvent`。
- `git diff --check` → 通过；`git status --short` → 保留未提交工作树，未 add/commit/push，未覆盖或清理 `.DS_Store`、xcuserdata、`CLAUDE.md`、`GEMINI.md` 等非本任务改动。
- 非阻塞提示：`AppleSpeechTranscriber` 的 async-context `NSLock` 会在 Swift 6 模式升级为错误；测试环境另有 XCTest deployment 与 App Intents `linkd` 噪声。本轮 Swift 5 构建和测试均成功。

## NEXT_RECOMMENDED_ACTION

静态与自动化范围已经完成，不应自动继续改业务源码。若用户后续明确提供授权与测试凭据，再按 `docs/TESTING.md` 分别执行真实 provider、真实 Keychain、麦克风、Accessibility/`CGEvent` 真机矩阵；Swift 6 前另开任务处理 `AppleSpeechTranscriber` 的 async-lock 兼容性 warning。
