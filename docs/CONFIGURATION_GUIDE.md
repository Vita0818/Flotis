# Flotis `config.json` 配置教程

本文适用于 Flotis `0.12 (3)` 的 canonical config schema v2。Flotis 使用一个 JSON 文件串联 Provider、共享 endpoint、API key、多个模型、当前模型、对比选择和可配置的全局快捷键：

```text
~/Library/Application Support/Flotis/config.json
```

这个文件包含明文 API key。不要把它提交到 Git、同步到不可信云盘、粘贴到聊天记录或公开 issue。示例中的 `REPLACE_WITH_OPENROUTER_KEY` 必须在本机替换，教程和仓库中不得写入真实 key。

## 最快的 OpenRouter 配置方法

在 Flotis Settings 的“转写”页：

1. 在左侧 **Providers** 点击 `+`，把右侧 **Provider name** 设为 `OpenRouter`，并在 **API key** 输入 OpenRouter key。
2. 展开 **Connection**：Base URL 填 `https://openrouter.ai/api`，Path 填 `/v1/audio/transcriptions`，Request Encoding 选择 `JSON + Base64 audio (OpenRouter)`。
3. 展开 **Models**，点击 **Add model**。每个模型占一行，在 **Model ID** 分别填写：

   ```text
   openai/gpt-4o-mini-transcribe
   openai/gpt-4o-transcribe
   ```

   **Display name** 可留空，也可填写便于辨认的名称；它只影响显示，不改变请求中的 Model ID。
4. 在 **Active model** 选择平时单模型转写要使用的模型。
5. 点击 **Test Provider** 验证当前草稿，再点击 **Save**。endpoint、API key 和请求参数只保存一次，供这个 Provider 下的全部模型共享。
6. 若要并行对比，展开主卡下方的 **Comparison Mode**，勾选这个 Provider 下的 2–4 个已保存且就绪的模型并开启开关。

把 Base URL 改成 `openrouter.ai` 时，界面会自动选择 JSON+Base64；仍建议保存前检查一次。本教程使用 OpenRouter 原生 JSON 形式，在 `input_audio.data` 中发送 Base64 音频。OpenRouter 当前也接受 OpenAI 风格的 multipart 请求，因此需要兼容其他客户端时可以手动切换；Flotis 的默认值只是明确选择 JSON 路径，并不表示 multipart 无效。

## 在界面中修改全局快捷键

打开 Flotis Settings 的“快捷键”页，在唯一的快捷键卡片中点击当前组合键的大号按钮，然后直接按下新组合。可以修改：

- 显示/隐藏悬浮胶囊，默认 `⌘⌥⇧0`；
- 上一个转写结果，默认 `⌥←`；
- 下一个转写结果，默认 `⌥→`。

新组合会立即写入同一个 `config.json` 并重新注册，不需要另点 Save。每项至少要包含一个修饰键，三项不能重复，也不能占用固定的语音快捷键 `⌃⌥A`。每行右侧的恢复按钮可只恢复该项，卡片底部的“恢复默认”会恢复全部三项。上一个/下一个结果仍只在对比审阅中至少有两个成功候选时临时生效。

## 可直接使用的 OpenRouter 完整模板

退出 Flotis 后，将下面内容保存为 `config.json`，再替换 API key：

```json
{
  "$schema": "https://flotis.app/config/v2",
  "schema_version": 2,
  "model": "openrouter/openai/gpt-4o-mini-transcribe",
  "provider_order": [
    "openrouter"
  ],
  "enabled_providers": [
    "openrouter"
  ],
  "comparison": {
    "enabled": true,
    "models": [
      "openrouter/openai/gpt-4o-mini-transcribe",
      "openrouter/openai/gpt-4o-transcribe"
    ]
  },
  "shortcuts": {
    "toggle_panel": {
      "keyCode": 29,
      "modifiers": {
        "command": true,
        "control": false,
        "option": true,
        "shift": true
      }
    },
    "previous_comparison_result": {
      "keyCode": 123,
      "modifiers": {
        "command": false,
        "control": false,
        "option": true,
        "shift": false
      }
    },
    "next_comparison_result": {
      "keyCode": 124,
      "modifiers": {
        "command": false,
        "control": false,
        "option": true,
        "shift": false
      }
    }
  },
  "provider": {
    "openrouter": {
      "name": "OpenRouter",
      "adapter": "openai-audio-transcriptions-http-v1",
      "options": {
        "baseURL": "https://openrouter.ai/api",
        "path": "/v1/audio/transcriptions",
        "apiKey": "REPLACE_WITH_OPENROUTER_KEY",
        "language": "zh",
        "authentication": "bearer",
        "audio": {
          "format": "wav",
          "sampleRate": 16000,
          "channels": 1
        },
        "transcription": {
          "requestEncoding": "json-base64",
          "responseMode": "json"
        }
      },
      "models": {
        "openai/gpt-4o-mini-transcribe": {
          "name": "Fast"
        },
        "openai/gpt-4o-transcribe": {
          "name": "Quality"
        }
      },
      "credentialRevision": 1
    }
  }
}
```

这里的 endpoint、API key、语言、音频参数都属于 `provider.openrouter.options`，只保存一次。两个模型只是同一 Provider 下的两个 route，不需要复制 endpoint 或 key。

## selector 为什么可以包含多个 `/`

Flotis 的 selector 格式是：

```text
<provider-id>/<model-id>
```

解析时只在第一个 `/` 处分割。因此：

```text
openrouter/openai/gpt-4o-mini-transcribe
```

会被解析为：

- Provider ID：`openrouter`
- Model ID：`openai/gpt-4o-mini-transcribe`

Provider ID 本身不能包含 `/`，可使用字母、数字、`-`、`_`、`.`；Model ID 可以继续包含 `/`。不要把 OpenRouter 的完整模型 ID 错误地拆成两个 Provider。

## schema v2 顶层字段

| 字段 | 必填 | 含义与约束 |
|---|---:|---|
| `$schema` | 是 | 固定为 `https://flotis.app/config/v2`。 |
| `schema_version` | 是 | 当前固定为整数 `2`。 |
| `model` | 是 | 默认单模型 route 的完整 selector；没有 Provider 时必须是空字符串。 |
| `provider_order` | 是 | Provider 显示与处理顺序；必须与 `provider` 的键集合完全一致且不能重复。 |
| `enabled_providers` | 是 | 已启用 Provider ID；当前必须与 `provider` 的键集合完全一致。它不是对比模型列表。 |
| `comparison` | 是 | `enabled` 控制对比开关，`models` 保存按展示顺序排列的 0–4 个完整 selector；开启时至少 2 个。 |
| `shortcuts` | 否 | panel 显隐及前后对比导航的全局快捷键；旧 schema v2 文件省略时使用默认值，App 启动加载后会用安全的 read-modify-write 补齐。固定语音快捷键不在这里。 |
| `provider` | 是 | 以语义化 Provider ID 为键的字典；最多 64 个 Provider。 |

JSON 对象本身的文本排列顺序不决定业务顺序；Provider 顺序以 `provider_order` 为准，对比候选顺序以 `comparison.models` 为准。App 保存时会按 pretty-printed、sorted-keys 格式重写文件。

## 单个 Provider 的结构

每个 `provider.<provider-id>` 由共享配置和模型字典组成：

| 字段 | 必填 | 含义 |
|---|---:|---|
| `name` | 是 | Settings 和候选结果中显示的名称。 |
| `adapter` | 是 | 版本化 adapter ID。当前 Settings 只开放 `openai-audio-transcriptions-http-v1`。 |
| `options` | 是 | 这个 Provider 共享的 endpoint、key、语言、音频和请求参数。 |
| `models` | 是 | Model ID 到模型附加配置的字典；至少 1 个、最多 64 个。每个 entry 可选写 `name`，对应 Settings 的 Display name。 |
| `credentialRevision` | 否 | 凭据版本；替换或清除 key 时由 App 递增。 |

常用 `options` 字段：

| 字段 | 含义 |
|---|---|
| `baseURL` | HTTPS 基础地址。OpenRouter 为 `https://openrouter.ai/api`。 |
| `path` | API path，必须以 `/` 开头。OpenRouter 为 `/v1/audio/transcriptions`。 |
| `customEndpointApproved` | 非内建可信 host 时必须显式为 `true`，表示你确认 key 和录音会发往该 host。OpenRouter 不需要。 |
| `apiKey` | 这个 Provider 的共享明文 API key。 |
| `apiKeyReference` | 可选的非机密运行时引用；通常省略，让 App 由 Provider ID 派生。 |
| `language` | 可选转写语言，例如 `zh` 或 `en`。 |
| `authentication` | 目前 OpenAI-compatible HTTP 使用 `bearer`。 |
| `audio` | `format`、`sampleRate`、`channels`。当前对比 route 必须具有相同录音格式。 |
| `transcription` | `requestEncoding`、`responseMode`、`prompt`、`temperature` 等协议参数。 |

`requestEncoding` 目前支持：

- `json-base64`：Flotis 对 OpenRouter 的默认值；请求 JSON 包含 `input_audio.data`、`input_audio.format`、`model`，并按配置加入 `language` / `temperature`。
- `multipart-form-data`：OpenAI 官方端点及传统 OpenAI-compatible 文件上传接口；OpenRouter 当前也支持。该形式可发送 `prompt`、`temperature` 和 `response_format=json`。

Flotis 的 OpenRouter JSON 请求目前不发送 `prompt`，因为官方 JSON 参数表没有把它列为通用字段；OpenRouter 的 multipart 兼容路径会接受但忽略 `prompt`。

## 不启用对比时

保留模型列表，但把对比配置改为：

```json
"comparison": {
  "enabled": false,
  "models": []
}
```

顶层 `model` 仍决定默认使用哪个模型。切换默认模型只需改这个 selector，例如：

```json
"model": "openrouter/openai/gpt-4o-transcribe"
```

## 多 Provider 与同 Provider 多模型可以混合

`comparison.models` 最多保存 4 个 selector，可以同时包含：

- 同一 Provider 的多个模型；
- 不同 Provider 的模型；
- 两者的组合。

例如：

```json
"models": [
  "openrouter/openai/gpt-4o-mini-transcribe",
  "openrouter/openai/gpt-4o-transcribe",
  "internal/whisper-large-v3"
]
```

运行时只录制一份文件，并发交给每个选中的 model route。每个 route 都可能单独计费；失败会单独显示。至少一个 route 成功时，App 会按 `comparison.models` 的顺序自动打开第一个成功结果；这只是稳定默认项，不是质量评分。你可以点击候选，或使用 `shortcuts.previous_comparison_result` / `shortcuts.next_comparison_result` 对应的组合键跳过失败项并循环查看（默认 `⌥←` / `⌥→`），最后按固定语音快捷键 `⌃⌥A` 把当前结果复制到剪贴板并返回小胶囊。当前对比只支持录音文件型 route，并要求它们的格式、采样率和声道一致。

## `shortcuts` 的结构

每个快捷键对象由 Carbon 虚拟 `keyCode` 和四个修饰键布尔值组成：

```json
"toggle_panel": {
  "keyCode": 29,
  "modifiers": {
    "command": true,
    "control": false,
    "option": true,
    "shift": true
  }
}
```

默认 key code 为：数字 `0` = `29`、左方向键 = `123`、右方向键 = `124`。手工编辑时三项必须都包含至少一个修饰键、彼此不同，并且都不能等于固定 voice descriptor `keyCode: 0` + `control: true` + `option: true`。推荐直接在“快捷键”设置中录制，避免手工查虚拟键码。

## 空配置与 Apple Speech

全新安装的合法最小配置是空 catalog：

```json
{
  "$schema": "https://flotis.app/config/v2",
  "schema_version": 2,
  "model": "",
  "provider_order": [],
  "enabled_providers": [],
  "comparison": {
    "enabled": false,
    "models": []
  },
  "shortcuts": {
    "toggle_panel": {
      "keyCode": 29,
      "modifiers": {
        "command": true,
        "control": false,
        "option": true,
        "shift": true
      }
    },
    "previous_comparison_result": {
      "keyCode": 123,
      "modifiers": {
        "command": false,
        "control": false,
        "option": true,
        "shift": false
      }
    },
    "next_comparison_result": {
      "keyCode": 124,
      "modifiers": {
        "command": false,
        "control": false,
        "option": true,
        "shift": false
      }
    }
  },
  "provider": {}
}
```

`config.json` 中不再写入 `apple-on-device`。Provider catalog 为空时，App 仍可把 Apple 设备端识别作为内部、本地 fallback；它不是可配置 Provider，也不能出现在 `provider_order`、`enabled_providers` 或 `comparison.models` 中。

## 安全手工编辑流程

Flotis 不会热加载配置。必须先退出 App，否则运行中的内存快照可能在下次保存时覆盖手工改动。

1. 退出 Flotis。
2. 备份当前文件：

   ```sh
   cp -p "$HOME/Library/Application Support/Flotis/config.json" \
     "$HOME/Library/Application Support/Flotis/config.json.backup"
   ```

3. 编辑并校验 JSON：

   ```sh
   plutil -lint "$HOME/Library/Application Support/Flotis/config.json"
   ```

4. 恢复私有权限：

   ```sh
   chmod 700 "$HOME/Library/Application Support/Flotis"
   chmod 600 "$HOME/Library/Application Support/Flotis/config.json"
   ```

5. 重新启动 Flotis。

App 还会以同目录 `.config.lock` 协调写入。不要把 `config.json` 或 `.config.lock` 换成符号链接。

## 迁移与错误处理

- schema v1 的旧 canonical 文件会自动迁移到 v2；旧 Apple 条目会被移除，网络 Provider、模型、endpoint、key 与可恢复的选择会保留。
- 当 `config.json` 尚不存在时，旧 UserDefaults connection/comparison 与旧 `secrets.json` 只作为一次性只读迁移输入；迁移后不再参与运行时读写。
- canonical 文件一旦存在，旧来源不会覆盖它。
- JSON 损坏、schema 不匹配、Provider/selector 不一致、符号链接、非普通文件、权限所有者异常或文件过大时，App 会拒绝加载和覆盖，而不是静默重置配置。

## 常见错误

- 把两个 OpenRouter 模型写成两个复制了相同 key 的 Provider。正确做法是一个 `openrouter` Provider 下写两个 `models`。
- 把 `openai/gpt-4o-transcribe` 中的 `/` 当作 Provider 分隔符。Flotis 只在 selector 的第一个 `/` 分割。
- 以为 OpenRouter 只能使用一种编码。它当前同时支持 JSON+Base64 和 multipart；本模板与 Flotis 自动默认使用 `json-base64`，若手动切换则应确认服务端和测试结果与所选编码匹配。
- Base URL 写成完整 API URL，同时 Path 又写一次 `/v1/audio/transcriptions`，导致路径重复。
- `comparison.models` 引用了不存在的模型，或开启对比但不足两个 selector。
- 三个可配置快捷键没有修饰键、彼此重复，或占用了固定语音快捷键 `⌃⌥A`。
- 在 App 运行时手工编辑，随后又在 Settings 保存，导致手工版本被旧内存状态覆盖。
- 把真实 API key 写进教程、截图、日志或 Git。

OpenRouter 请求格式参考其官方 Speech-to-Text 文档：<https://openrouter.ai/docs/guides/overview/multimodal/stt>。
