import Foundation

enum AppLanguage: Equatable {
    case simplifiedChinese
    case english

    static let current = resolve(preferredLanguages: Locale.preferredLanguages)

    static func resolve(preferredLanguages: [String]) -> AppLanguage {
        guard let preferredLanguage = preferredLanguages.first else {
            return .english
        }

        let components = preferredLanguage
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
            .split(separator: "-")
            .map(String.init)

        guard components.first == "zh" else {
            return .english
        }
        if components.contains("hant")
            || components.contains("tw")
            || components.contains("hk")
            || components.contains("mo") {
            return .english
        }
        if components.contains("hans")
            || components.contains("cn")
            || components.contains("sg")
            || components.contains("my") {
            return .simplifiedChinese
        }

        return .english
    }

    var locale: Locale {
        switch self {
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        case .english:
            return Locale(identifier: "en")
        }
    }

    func localized(english: String, simplifiedChinese: String) -> String {
        switch self {
        case .simplifiedChinese:
            return simplifiedChinese
        case .english:
            return english
        }
    }
}

enum UIStrings {
    static func localized(english: String, simplifiedChinese: String) -> String {
        AppLanguage.current.localized(
            english: english,
            simplifiedChinese: simplifiedChinese
        )
    }

    static let settings = localized(english: "Settings", simplifiedChinese: "设置")
    static let settingsSubtitle = localized(
        english: "Voice input, permissions, and OpenAI Compatible",
        simplifiedChinese: "语音输入、权限与 OpenAI Compatible"
    )
    static let shortcutSettings = localized(
        english: "Shortcuts",
        simplifiedChinese: "快捷键"
    )
    static let transcriptionSettings = localized(
        english: "Transcription",
        simplifiedChinese: "转写服务"
    )
    static let transcriptionSettingsSubtitle = localized(
        english: "Configure providers with multiple models and compare selected model routes.",
        simplifiedChinese: "配置支持多模型的 Provider，并对比选中的模型路由。"
    )
    static let commands = localized(english: "Commands", simplifiedChinese: "命令")
    static let speech = localized(english: "Speech", simplifiedChinese: "语音")
    static let transcriptionProviders = localized(
        english: "Transcription Providers",
        simplifiedChinese: "转写 Provider"
    )
    static let openAICompatible = "OpenAI Compatible"
    static let openAICompatibleNotCurrent = localized(
        english: "Not using OpenAI Compatible",
        simplifiedChinese: "当前未使用 OpenAI Compatible"
    )
    static let noOpenAICompatibleConnections = localized(
        english: "No OpenAI Compatible provider has been added.",
        simplifiedChinese: "尚未添加 OpenAI Compatible Provider。"
    )
    static let comparisonMode = localized(
        english: "Compare multiple results",
        simplifiedChinese: "多模型对比"
    )
    static let comparisonModeDescription = localized(
        english: "Record once, send the same audio to every selected route, then review the first result or switch with your comparison shortcuts.",
        simplifiedChinese: "只录音一次，把同一份音频交给所有所选路由；默认打开第一个结果，也可用自定义的对比快捷键切换。"
    )
    static let comparisonPrivacyWarning = localized(
        english: "Each selected service receives the recording and may charge for one transcription request.",
        simplifiedChinese: "每个所选服务都会收到本次录音，并可能分别产生一次转写费用。"
    )
    static let comparisonConnections = localized(
        english: "Model routes to compare",
        simplifiedChinese: "参与对比的模型路由"
    )
    static let previousComparisonResult = localized(
        english: "Previous transcription result",
        simplifiedChinese: "上一个转写结果"
    )
    static let nextComparisonResult = localized(
        english: "Next transcription result",
        simplifiedChinese: "下一个转写结果"
    )
    static let editConnection = localized(
        english: "Provider to edit",
        simplifiedChinese: "正在编辑的 Provider"
    )
    static let addAnotherConnection = localized(
        english: "Add another provider",
        simplifiedChinese: "再添加一个 Provider"
    )
    static let newConnection = localized(
        english: "New provider",
        simplifiedChinese: "新 Provider"
    )
    static let connectionNotReady = localized(
        english: "Not ready",
        simplifiedChinese: "尚未就绪"
    )
    static let back = localized(english: "Back", simplifiedChinese: "返回")
    static let done = localized(english: "Done", simplifiedChinese: "完成")
    static let close = localized(english: "Close", simplifiedChinese: "关闭")
    static let quitFlotis = localized(
        english: "Quit Flotis",
        simplifiedChinese: "退出 Flotis"
    )
    static let add = localized(english: "Add", simplifiedChinese: "新增")
    static let delete = localized(english: "Delete", simplifiedChinese: "删除")
    static let save = localized(english: "Save", simplifiedChinese: "保存")
    static let cancel = localized(english: "Cancel", simplifiedChinese: "取消")
    static let copyText = localized(english: "Copy text", simplifiedChinese: "复制文字")
    static let copyAndReturn = localized(
        english: "Copy and return",
        simplifiedChinese: "复制并返回"
    )
    static let resetDefaults = localized(
        english: "Restore Defaults",
        simplifiedChinese: "恢复默认"
    )
    static let enabled = localized(english: "Enabled", simplifiedChinese: "启用")
    static let expanded = localized(english: "Expanded", simplifiedChinese: "已展开")
    static let collapsed = localized(english: "Collapsed", simplifiedChinese: "已折叠")
    static let shortcut = localized(english: "Shortcut", simplifiedChinese: "快捷键")
    static let recordShortcut = localized(
        english: "Record Shortcut",
        simplifiedChinese: "录制快捷键"
    )
    static let recordingShortcut = localized(
        english: "Recording...",
        simplifiedChinese: "正在录制..."
    )
    static let clear = localized(english: "Clear", simplifiedChinese: "清除")
    static let title = localized(english: "Title", simplifiedChinese: "标题")
    static let content = localized(english: "Content", simplifiedChinese: "内容")
    static let prompt = localized(english: "Prompt", simplifiedChinese: "短语")
    static let provider = localized(english: "Provider", simplifiedChinese: "提供商")
    static let providerKind = localized(
        english: "Provider Type",
        simplifiedChinese: "提供商类型"
    )
    static let providerWireProtocol = localized(
        english: "Wire Protocol",
        simplifiedChinese: "接口协议"
    )
    static let providerName = localized(
        english: "Provider Name",
        simplifiedChinese: "提供商名称"
    )
    static let currentProvider = localized(
        english: "Current Model Route",
        simplifiedChinese: "当前模型路由"
    )
    static let connections = localized(english: "Providers", simplifiedChinese: "Provider")
    static let basicInformation = localized(
        english: "Basic Information",
        simplifiedChinese: "基本信息"
    )
    static let connectionName = localized(
        english: "Provider name",
        simplifiedChinese: "Provider 名称"
    )
    static let protocolCompatibilityType = localized(
        english: "Protocol Compatibility",
        simplifiedChinese: "协议兼容类型"
    )
    static let quickPreset = localized(
        english: "Quick Preset",
        simplifiedChinese: "快速预设"
    )
    static let customPreset = localized(english: "Custom", simplifiedChinese: "自定义")
    static let recommendedAdapters = localized(
        english: "Recommended Adapters",
        simplifiedChinese: "推荐协议"
    )
    static let advancedNativeAdapters = localized(
        english: "Advanced Native Adapters",
        simplifiedChinese: "高级原生适配器"
    )
    static let advancedSettings = localized(
        english: "Advanced Settings",
        simplifiedChinese: "高级设置"
    )
    static let connectionEndpoint = localized(
        english: "Provider Endpoint",
        simplifiedChinese: "Provider 端点"
    )
    static let addTranscriptionConnection = localized(
        english: "Add Provider",
        simplifiedChinese: "新增 Provider"
    )
    static let editTranscriptionConnection = localized(
        english: "Edit Provider",
        simplifiedChinese: "编辑 Provider"
    )
    static let newTranscriptionConnectionName = localized(
        english: "OpenAI Compatible",
        simplifiedChinese: "OpenAI Compatible"
    )
    static let newConnectionDraftHint = localized(
        english: "This provider draft has not been saved. Canceling will not change any existing configuration.",
        simplifiedChinese: "这是未保存的 Provider 草稿；取消不会修改现有配置。"
    )
    static let presetAppliedHint = localized(
        english: "Recommended values have been filled in. You can still adjust every field for this provider.",
        simplifiedChinese: "预设已填入建议值，所有字段仍可按当前 Provider 调整。"
    )
    static let model = localized(english: "Model", simplifiedChinese: "模型")
    static let models = localized(english: "Models", simplifiedChinese: "模型列表")
    static let modelsLowercase = localized(english: "models", simplifiedChinese: "个模型")
    static let currentModel = localized(
        english: "Current model",
        simplifiedChinese: "当前模型"
    )
    static let activeModel = localized(
        english: "Active model",
        simplifiedChinese: "当前模型"
    )
    static let modelID = localized(
        english: "Model ID",
        simplifiedChinese: "模型 ID"
    )
    static let modelDisplayName = localized(
        english: "Display name",
        simplifiedChinese: "显示名称"
    )
    static let addModel = localized(
        english: "Add model",
        simplifiedChinese: "新增模型"
    )
    static let removeModel = localized(
        english: "Remove model",
        simplifiedChinese: "移除模型"
    )
    static let connection = localized(
        english: "Connection",
        simplifiedChinese: "连接"
    )
    static let saved = localized(
        english: "Saved",
        simplifiedChinese: "已保存"
    )
    static let deleteProvider = localized(
        english: "Delete provider",
        simplifiedChinese: "删除 Provider"
    )
    static let deleteProviderTitle = localized(
        english: "Delete this provider?",
        simplifiedChinese: "删除这个 Provider？"
    )
    static let deleteProviderMessage = localized(
        english: "Its models and shared API key will be removed from Flotis config.json.",
        simplifiedChinese: "它的模型和共享 API Key 将从 Flotis config.json 中移除。"
    )
    static let providerDeleteFailed = localized(
        english: "Could not delete the provider.",
        simplifiedChinese: "无法删除这个 Provider。"
    )
    static let addProviderToConfigureModels = localized(
        english: "Add a provider to configure models.",
        simplifiedChinese: "新增一个 Provider 后即可配置模型。"
    )
    static let modelsOnePerLine = localized(
        english: "Enter one model ID per line. IDs may contain '/', for example openai/gpt-4o-mini-transcribe.",
        simplifiedChinese: "每行填写一个模型 ID；ID 可以包含“/”，例如 openai/gpt-4o-mini-transcribe。"
    )
    static let modelsRequired = localized(
        english: "Add at least one valid model and choose the current model.",
        simplifiedChinese: "请至少添加一个有效模型，并选择当前模型。"
    )
    static let language = localized(english: "Language", simplifiedChinese: "语言")
    static let endpoint = localized(english: "Endpoint", simplifiedChinese: "接口地址")
    static let baseURL = localized(english: "Base URL", simplifiedChinese: "基础地址")
    static let endpointPath = localized(
        english: "Endpoint Path",
        simplifiedChinese: "接口路径"
    )
    static let realtimeURL = localized(
        english: "Realtime URL",
        simplifiedChinese: "实时地址"
    )
    static let realtimePath = localized(
        english: "Realtime Endpoint Path",
        simplifiedChinese: "实时接口路径"
    )
    static let inputAudioFormat = localized(
        english: "Input Audio Format",
        simplifiedChinese: "输入音频格式"
    )
    static let responseMode = localized(
        english: "Response Mode",
        simplifiedChinese: "响应模式"
    )
    static let responseModeJSON = "JSON"
    static let responseModeSSE = "Server-Sent Events"
    static let requestEncoding = localized(
        english: "Request encoding",
        simplifiedChinese: "请求编码"
    )
    static let requestEncodingMultipart = localized(
        english: "Multipart file upload (OpenAI compatible)",
        simplifiedChinese: "Multipart 文件上传（OpenAI 兼容）"
    )
    static let requestEncodingJSONBase64 = localized(
        english: "JSON + Base64 audio (OpenRouter)",
        simplifiedChinese: "JSON + Base64 音频（OpenRouter）"
    )
    static let sampleRate = localized(english: "Sample Rate", simplifiedChinese: "采样率")
    static let channels = localized(english: "Channels", simplifiedChinese: "声道数")
    static let temperature = localized(english: "Temperature", simplifiedChinese: "温度")
    static let serverVAD = localized(english: "Server VAD", simplifiedChinese: "服务端 VAD")
    static let apiKey = "API key"
    static let saveAPIKey = localized(
        english: "Save API Key",
        simplifiedChinese: "保存 API Key"
    )
    static let clearAPIKey = localized(
        english: "Clear API Key",
        simplifiedChinese: "清除 API Key"
    )
    static let microphone = localized(english: "Microphone", simplifiedChinese: "麦克风")
    static let accessibility = localized(
        english: "Accessibility",
        simplifiedChinese: "辅助功能"
    )
    static let speechRecognition = localized(
        english: "Speech Recognition",
        simplifiedChinese: "语音识别"
    )
    static let permissions = localized(english: "Permissions", simplifiedChinese: "权限")
    static let openSettings = localized(
        english: "Open Settings",
        simplifiedChinese: "打开设置"
    )
    static let noShortcut = localized(
        english: "No Shortcut",
        simplifiedChinese: "无快捷键"
    )
    static let none = localized(english: "None", simplifiedChinese: "无")
    static let untitledCommand = localized(
        english: "Untitled Command",
        simplifiedChinese: "未命名命令"
    )
    static let selectCommandToEdit = localized(
        english: "Select a command to edit.",
        simplifiedChinese: "选择一个命令进行编辑。"
    )
    static let selectProviderToEdit = localized(
        english: "Select a transcription provider.",
        simplifiedChinese: "选择一个转写 Provider。"
    )
    static let noEnabledCommands = localized(
        english: "No Enabled Commands",
        simplifiedChinese: "暂无启用命令"
    )
    static let setAsCurrent = localized(
        english: "Set as Current",
        simplifiedChinese: "设为当前"
    )
    static let moveUp = localized(english: "Move Up", simplifiedChinese: "上移")
    static let moveDown = localized(english: "Move Down", simplifiedChinese: "下移")
    static let status = localized(english: "Status", simplifiedChinese: "状态")
    static let configured = localized(english: "Configured", simplifiedChinese: "已配置")
    static let notConfigured = localized(
        english: "Not Configured",
        simplifiedChinese: "未配置"
    )
    static let managedByMacOS = localized(
        english: "Managed by macOS",
        simplifiedChinese: "由 macOS 管理"
    )
    static let enabledStatus = localized(english: "Enabled", simplifiedChinese: "已启用")
    static let disabledStatus = localized(english: "Disabled", simplifiedChinese: "未启用")
    static let accessibilityReadyDescription = localized(
        english: "Flotis can securely send the reviewed text to the app where recording started.",
        simplifiedChinese: "Flotis 可以把确认后的文字安全输入到开始录音时的 App。"
    )
    static let accessibilityRequiredDescription = localized(
        english: "Allow Flotis in Privacy & Security → Accessibility. This permission is required only for the final Command-V event.",
        simplifiedChinese: "请在“隐私与安全性 → 辅助功能”中允许 Flotis；该权限仅用于最后发送 Command-V。"
    )
    static let grantAccessibility = localized(
        english: "Grant Access",
        simplifiedChinese: "开启权限"
    )
    static let checkAgain = localized(
        english: "Check Again",
        simplifiedChinese: "重新检查"
    )
    static let voiceShortcutTitle = localized(
        english: "Voice shortcut",
        simplifiedChinese: "语音快捷键"
    )
    static let voiceShortcutDescription = localized(
        english: "Press once to record and again to stop. With multiple results, use the comparison shortcuts below, then press once more to copy and return.",
        simplifiedChinese: "按一次录音，再按一次停止。出现多个结果时可使用下方的对比快捷键切换，再按一次即可复制并返回。"
    )
    static let globalHotkeys = localized(
        english: "Global shortcuts",
        simplifiedChinese: "全局快捷键"
    )
    static let togglePanelShortcutDescription = localized(
        english: "Show or hide the floating capsule from any app.",
        simplifiedChinese: "在任意 App 中显示或隐藏悬浮胶囊。"
    )
    static let previousComparisonShortcutDescription = localized(
        english: "While comparing transcripts, open the previous successful result.",
        simplifiedChinese: "对比转写结果时，打开上一个成功结果。"
    )
    static let nextComparisonShortcutDescription = localized(
        english: "While comparing transcripts, open the next successful result.",
        simplifiedChinese: "对比转写结果时，打开下一个成功结果。"
    )
    static let comparisonShortcutAvailability = localized(
        english: "Comparison shortcuts are active only while at least two successful results are open.",
        simplifiedChinese: "只有在对比审阅中至少有两个成功结果时，对比快捷键才会临时生效。"
    )
    static let clickToRecordShortcut = localized(
        english: "Click to record a new shortcut",
        simplifiedChinese: "点击录制新的快捷键"
    )
    static let resetThisShortcut = localized(
        english: "Restore this shortcut",
        simplifiedChinese: "恢复这一项的默认快捷键"
    )
    static let hotkeyRequiresModifier = localized(
        english: "A global shortcut must include at least one modifier key.",
        simplifiedChinese: "全局快捷键至少需要一个修饰键。"
    )
    static let hotkeyConfigurationInvalid = localized(
        english: "The shortcut configuration is invalid.",
        simplifiedChinese: "快捷键配置无效。"
    )
    static let hotkeyConfigurationSaveFailed = localized(
        english: "Could not save the shortcut configuration to config.json.",
        simplifiedChinese: "无法将快捷键配置保存到 config.json。"
    )
    static let hotkeyConfigurationUnavailable = localized(
        english: "config.json is unavailable, so the default shortcuts are being used without overwriting the file.",
        simplifiedChinese: "config.json 当前不可用，因此暂时使用默认快捷键，并且不会覆盖原文件。"
    )
    static let floatingPanelTitle = localized(
        english: "Floating capsule",
        simplifiedChinese: "悬浮胶囊"
    )
    static let floatingPanelDragDescription = localized(
        english: "Drag any empty area of the capsule. Its position is preserved while the capsule changes size.",
        simplifiedChinese: "拖动胶囊任意空白处；胶囊切换尺寸时会保留当前位置。"
    )
    static let connectionDetails = localized(
        english: "Provider and models",
        simplifiedChinese: "Provider 与模型"
    )
    static let connectionDetailsDescription = localized(
        english: "One shared HTTPS endpoint and one or more models.",
        simplifiedChinese: "一个共享的 HTTPS 接口，以及一个或多个模型。"
    )
    static let credentials = localized(
        english: "Credentials",
        simplifiedChinese: "凭据"
    )
    static let credentialsDescription = localized(
        english: "This provider stores one shared key in Flotis config.json for all of its models.",
        simplifiedChinese: "该 Provider 的所有模型共用一个密钥，并统一保存在 Flotis 的 config.json 中。"
    )
    static let optionalParameters = localized(
        english: "Optional parameters",
        simplifiedChinese: "可选参数"
    )
    static let addConnectionDescription = localized(
        english: "Add an OpenAI-compatible provider, then list every model that should share its endpoint and key.",
        simplifiedChinese: "添加一个 OpenAI 兼容 Provider，再列出共享该接口和密钥的全部模型。"
    )
    static let customRealtime = localized(
        english: "Custom Realtime Transcription",
        simplifiedChinese: "自定义实时转写"
    )
    static let customHTTP = localized(
        english: "Custom HTTP Transcription",
        simplifiedChinese: "自定义 HTTP 转写"
    )
    static let qwenParaformerRealtime = localized(
        english: "Qwen/DashScope Paraformer Realtime Transcription",
        simplifiedChinese: "Qwen/百炼 Paraformer 实时转写"
    )
    static let volcengineBigASRRealtime = localized(
        english: "Volcengine Doubao Streaming Speech Recognition",
        simplifiedChinese: "火山豆包流式语音识别"
    )
    static let glmASRHTTPStream = localized(
        english: "GLM-ASR Streaming HTTP Transcription",
        simplifiedChinese: "GLM-ASR 流式 HTTP 转写"
    )
    static let appleSpeech = localized(
        english: "Apple Speech Recognition",
        simplifiedChinese: "Apple 语音识别"
    )
    static let realtime = localized(english: "Realtime", simplifiedChinese: "实时")
    static let httpTranscription = localized(
        english: "HTTP Transcription",
        simplifiedChinese: "HTTP 转写"
    )
    static let realtimeTranscription = localized(
        english: "Realtime Transcription",
        simplifiedChinese: "实时转写"
    )
    static let httpTranscriptionSection = httpTranscription
    static let realtimeStreamingSection = realtimeTranscription
    static let apiKeySavedPlaceholder = localized(
        english: "Using provider config; enter key to replace",
        simplifiedChinese: "使用 Provider 配置；输入新 Key 可覆盖"
    )
    static let apiKeyStoredLocally = localized(
        english: "The API Key is stored in the local Flotis config.json file.",
        simplifiedChinese: "API Key 已保存在本机 Flotis config.json 文件中。"
    )
    static let apiKeySaved = localized(
        english: "API Key saved.",
        simplifiedChinese: "API Key 已保存。"
    )
    static let apiKeySaveFailed = localized(
        english: "Could not save the API Key.",
        simplifiedChinese: "API Key 保存失败。"
    )
    static let apiKeyCleared = localized(
        english: "API Key removed from local storage.",
        simplifiedChinese: "API Key 已从本地存储清除。"
    )
    static let apiKeyClearFailed = localized(
        english: "Could not remove the API Key.",
        simplifiedChinese: "API Key 清除失败。"
    )
    static let apiKeyNotSaved = localized(
        english: "This provider does not have a saved API Key.",
        simplifiedChinese: "当前 Provider 没有已保存的 API Key。"
    )
    static let apiKeyRequiredForActivation = localized(
        english: "Save an API Key for this provider before setting one of its models as current.",
        simplifiedChinese: "请先保存该 Provider 的 API Key，再把其中一个模型设为当前。"
    )
    static let providerSaved = localized(
        english: "Transcription provider and models saved.",
        simplifiedChinese: "转写 Provider 与模型已保存。"
    )
    static let providerSavedNeedsAPIKey = localized(
        english: "Configuration saved. Enter a new API Key before using this provider's models.",
        simplifiedChinese: "配置已保存；请录入新的 API Key 后再使用该 Provider 的模型。"
    )
    static let providerNotFound = localized(
        english: "Transcription provider or model route not found.",
        simplifiedChinese: "找不到该转写 Provider 或模型路由。"
    )
    static let keepOneProvider = localized(
        english: "At least one transcription provider is required.",
        simplifiedChinese: "至少需要保留一个转写 Provider。"
    )
    static let providerConfigSaveFailed = localized(
        english: "Could not save the transcription provider.",
        simplifiedChinese: "转写 Provider 保存失败。"
    )
    static let providerSecretCleanupFailed = localized(
        english: "Could not remove the old API Key. The configuration change was reverted. Try again later.",
        simplifiedChinese: "旧 API Key 清理失败；本次配置变更已撤销，请稍后重试。"
    )
    static let providerDeleteSecretCleanupFailed = localized(
        english: "Could not remove the API Key. The provider was not deleted. Try again later.",
        simplifiedChinese: "API Key 清理失败；提供商删除已撤销，请稍后重试。"
    )
    static let providerConfigRecoveredWithoutOverwrite = localized(
        english: "The transcription provider configuration could not be decoded. A recovery configuration is in use, and the original data was not overwritten.",
        simplifiedChinese: "语音提供商配置无法解码；已使用恢复配置，原始数据未被覆盖。"
    )
    static let providerNameRequired = localized(
        english: "Provider name is required.",
        simplifiedChinese: "Provider 名称不能为空。"
    )
    static let providerModelRequired = localized(
        english: "Model name is required.",
        simplifiedChinese: "模型名称不能为空。"
    )
    static let secureWebSocketRequired = localized(
        english: "The Realtime URL must be a valid WSS URL and must not contain a username or password.",
        simplifiedChinese: "实时地址必须是有效的 WSS 地址，且不能包含用户名或密码。"
    )
    static let secureHTTPRequired = localized(
        english: "The Base URL must be a valid HTTPS URL and must not contain a username or password.",
        simplifiedChinese: "基础地址必须是有效的 HTTPS 地址，且不能包含用户名或密码。"
    )
    static let endpointPathInvalid = localized(
        english: "The endpoint path must start with a single / and must not contain a query, fragment, backslash, or full URL.",
        simplifiedChinese: "接口路径必须以单个 / 开头，且不能包含查询、片段、反斜杠或完整 URL。"
    )
    static let customEndpointConfirmationRequired = localized(
        english: "Confirm the custom service address. Credentials and audio will be sent to this host.",
        simplifiedChinese: "请确认自定义服务地址；凭据和音频会发送到该主机。"
    )
    static let temperatureRangeError = localized(
        english: "Temperature must be between 0 and 1.",
        simplifiedChinese: "温度必须在 0 到 1 之间。"
    )
    static let audioParametersInvalid = localized(
        english: "The audio parameters are not compatible with the selected protocol.",
        simplifiedChinese: "音频参数与所选接口协议不兼容。"
    )
    static let volcengineResourceIDInvalid = localized(
        english: "The Volcengine Resource ID must match volc.*.sauc.*, for example volc.seedasr.sauc.duration.",
        simplifiedChinese: "火山资源 ID 必须使用 volc.*.sauc.* 形式，例如 volc.seedasr.sauc.duration。"
    )
    static let volcengineModelNameInvalid = localized(
        english: "model_name must be bigmodel for the Volcengine bidirectional streaming API.",
        simplifiedChinese: "火山双向流式接口的 model_name 必须为 bigmodel。"
    )
    static let audioParameters = localized(
        english: "Fixed Audio Parameters",
        simplifiedChinese: "固定音频参数"
    )
    static let volcengineResourceID = localized(
        english: "Resource ID",
        simplifiedChinese: "资源 ID"
    )
    static let volcengineModelName = localized(
        english: "Model Name",
        simplifiedChinese: "模型名称"
    )
    static let volcengineTwoPassRecognition = localized(
        english: "Enable Two-Pass Recognition (Non-VAD)",
        simplifiedChinese: "启用二遍识别（非 VAD）"
    )
    static let credentialDestination = localized(
        english: "Credential Destination",
        simplifiedChinese: "凭据发送目标"
    )
    static let credentialDestinationFormat = localized(
        english: "The API Key and voice data will be sent to %@.",
        simplifiedChinese: "API Key 与语音数据将发送到 %@。"
    )
    static let confirmCustomEndpoint = localized(
        english: "I trust this custom host",
        simplifiedChinese: "我确认信任这个自定义主机"
    )
    static let protocolChangeClearsAPIKey = localized(
        english: "The protocol has changed. Saving will remove the old API Key, which will not be reused across services.",
        simplifiedChinese: "接口协议已切换；保存时会清除旧 API Key，且不会跨服务复用。"
    )
    static let adapterChangeClearsAPIKey = localized(
        english: "The protocol adapter has changed. Saving will remove the old API Key, which will not be reused across services.",
        simplifiedChinese: "协议适配器已切换；保存时会清除旧 API Key，且不会跨服务复用。"
    )
    static let adapterChangedHint = localized(
        english: "The protocol adapter has changed. The form now shows the fields supported by this adapter.",
        simplifiedChinese: "协议适配器已切换，表单已更新为该协议支持的字段。"
    )
    static let connectionTest = localized(
        english: "Connection Test",
        simplifiedChinese: "连接测试"
    )
    static let testConnection = localized(
        english: "Test Connection",
        simplifiedChinese: "测试连接"
    )
    static let testProvider = localized(
        english: "Test Provider",
        simplifiedChinese: "测试 Provider"
    )
    static let cancelConnectionTest = localized(
        english: "Cancel Test",
        simplifiedChinese: "取消测试"
    )
    static let testingConnection = localized(
        english: "Verifying the live transcription protocol...",
        simplifiedChinese: "正在验证真实转写协议..."
    )
    static let connectionTestSucceeded = localized(
        english: "Connection, audio transfer, and response structure verified.",
        simplifiedChinese: "连接、音频传输与响应结构验证成功。"
    )
    static let connectionTestFailedFormat = localized(
        english: "Test failed: %@",
        simplifiedChinese: "测试失败：%@"
    )
    static let connectionTestUnknownFailure = localized(
        english: "Connection or protocol verification failed.",
        simplifiedChinese: "连接或协议验证失败。"
    )
    static let lastConnectionTest = localized(
        english: "Last Test",
        simplifiedChinese: "上次测试"
    )
    static let adapterVersion = localized(
        english: "Adapter Version",
        simplifiedChinese: "适配器版本"
    )
    static let connectionNotTested = localized(
        english: "This model route has not been tested.",
        simplifiedChinese: "尚未测试此模型路由。"
    )
    static let connectionTestStillValid = localized(
        english: "The most recent route test still matches the current configuration.",
        simplifiedChinese: "最近一次路由测试仍与当前配置匹配。"
    )
    static let connectionTestInvalidated = localized(
        english: "The provider, model, or credentials changed. Test this route again.",
        simplifiedChinese: "Provider、模型或凭据已改变，需要重新测试此路由。"
    )
    static let connectionTestConfigurationInvalid = localized(
        english: "Complete and correct the provider and model configuration before testing.",
        simplifiedChinese: "请先补全并修正 Provider 与模型配置，再开始测试。"
    )
    static let connectionTestPrivacyNote = localized(
        english: "The test uses a short, privacy-safe audio clip built into the app. It never uses your previous recordings.",
        simplifiedChinese: "测试使用应用内置的无隐私短音频，不会使用你的历史录音。"
    )
    static let openAIRealtimeManualCommit = localized(
        english: "OpenAI Realtime uses 24 kHz mono PCM and commits manually when recording stops. Server VAD is disabled.",
        simplifiedChinese: "OpenAI Realtime 使用 24 kHz 单声道 PCM，并在停止时手动提交；不启用 server VAD。"
    )
    static let glmUploadLimits = localized(
        english: "GLM-ASR uploads after recording: WAV/MP3 only, up to 25 MB and 30 seconds. stream=true only streams the response.",
        simplifiedChinese: "GLM-ASR 是录音后上传：仅 WAV/MP3，文件不超过 25 MB、音频不超过 30 秒；stream=true 只表示响应流式。"
    )
    static let accessibilityPastePermission = localized(
        english: "Accessibility permission is required to paste into other apps",
        simplifiedChinese: "需要开启辅助功能权限以粘贴到其他 App"
    )
    static let pasteFailed = localized(
        english: "Paste failed. Accessibility permission may be missing.",
        simplifiedChinese: "粘贴失败，可能没有权限。"
    )
    static let shortcutCaptureHint = localized(
        english: "Press keys",
        simplifiedChinese: "按下组合键"
    )
    static let transcriptPreviewPlaceholder = localized(
        english: "Transcript preview...",
        simplifiedChinese: "转写预览文本..."
    )
    static let comparisonResultFailed = localized(
        english: "Failed",
        simplifiedChinese: "失败"
    )
    static let comparisonResultReady = localized(
        english: "Ready",
        simplifiedChinese: "已完成"
    )
    static let requestingPermission = localized(
        english: "Requesting permission...",
        simplifiedChinese: "正在请求权限..."
    )
    static let connecting = localized(
        english: "Connecting...",
        simplifiedChinese: "正在连接..."
    )
    static let dictating = localized(
        english: "Listening...",
        simplifiedChinese: "正在听写..."
    )
    static let comparisonListening = localized(
        english: "Recording once for all selected models...",
        simplifiedChinese: "正在为所有所选模型录制同一份音频..."
    )
    static let realtimeTranscribing = localized(
        english: "Transcribing in real time...",
        simplifiedChinese: "实时转写中..."
    )
    static let stopping = localized(
        english: "Stopping...",
        simplifiedChinese: "正在停止..."
    )
    static let transcribing = localized(
        english: "Transcribing...",
        simplifiedChinese: "正在转写..."
    )
    static let comparisonTranscribing = localized(
        english: "Transcribing with the selected models...",
        simplifiedChinese: "所选模型正在并行转写..."
    )
    static let reviewing = localized(
        english: "Ready to Review",
        simplifiedChinese: "等待确认"
    )
    static let recording = localized(english: "Recording", simplifiedChinese: "正在录音")
    static let reviewTranscript = localized(
        english: "Review Transcript",
        simplifiedChinese: "检查转写文字"
    )
    static let reviewThenInsert = localized(
        english: "Edit the transcript, then press the shortcut to insert",
        simplifiedChinese: "可以直接修改，再按快捷键输入"
    )
    static let insertText = localized(english: "Insert", simplifiedChinese: "输入")
    static let hotkeyCancelsCurrentOperation = localized(
        english: "Press the shortcut again to cancel",
        simplifiedChinese: "再按快捷键可取消当前操作"
    )
    static let verifyingTarget = localized(
        english: "Verifying target input location",
        simplifiedChinese: "正在确认目标输入位置"
    )
    static let emptyTranscript = localized(
        english: "There is no transcript to copy.",
        simplifiedChinese: "没有可复制的转写文字。"
    )
    static let comparisonNeedsTwoConnections = localized(
        english: "Select at least two model routes before enabling comparison mode.",
        simplifiedChinese: "请至少选择两个模型路由，再启用多模型对比。"
    )
    static let comparisonNeedsTwoReadyConnections = localized(
        english: "Comparison mode needs at least two saved and available model routes.",
        simplifiedChinese: "多模型对比至少需要两个已经保存且可用的模型路由。"
    )
    static let comparisonConnectionLimit = localized(
        english: "Comparison mode supports up to four model routes.",
        simplifiedChinese: "多模型对比最多支持四个模型路由。"
    )
    static let comparisonSupportsRecordedFileOnly = localized(
        english: "This first comparison version supports recorded-file model routes only.",
        simplifiedChinese: "当前第一版对比功能仅支持录音文件型模型路由。"
    )
    static let comparisonAudioFormatsMustMatch = localized(
        english: "All comparison routes must use the same recording format, sample rate, and channel count.",
        simplifiedChinese: "参与对比的模型路由必须使用相同的录音格式、采样率和声道数。"
    )
    static let comparisonRecordingDidNotStart = localized(
        english: "The shared comparison recording did not start correctly.",
        simplifiedChinese: "用于多模型对比的共享录音未正确启动。"
    )
    static let recordingFileUnavailable = localized(
        english: "Could not create a readable recording file.",
        simplifiedChinese: "无法生成可读取的录音文件。"
    )
    static let allComparisonConnectionsFailed = localized(
        english: "All selected transcription model routes failed.",
        simplifiedChinese: "所有所选转写模型路由都失败了。"
    )
    static let comparisonPreferencesUnavailable = localized(
        english: "The saved comparison settings could not be read. Comparison mode was turned off without overwriting them.",
        simplifiedChinese: "已保存的对比设置无法读取；对比模式已关闭，原数据未被覆盖。"
    )
    static let comparisonPreferencesSaveFailed = localized(
        english: "Could not save the comparison settings.",
        simplifiedChinese: "无法保存多模型对比设置。"
    )
    static let localDevice = localized(
        english: "On this Mac",
        simplifiedChinese: "本机"
    )
    static let copyReviewedTranscriptFailed = localized(
        english: "Flotis could not copy the reviewed text. It was preserved so you can try again.",
        simplifiedChinese: "Flotis 无法复制确认后的文字；文字已保留，可以重试。"
    )
    static let reviewInjectionFailed = localized(
        english: "Insert failed. Your text was preserved. Check the target input location and Accessibility permission, then try again.",
        simplifiedChinese: "输入失败，文字已保留；请确认目标输入位置和辅助功能权限后重试。"
    )
    static let injectionAccessibilityMissing = localized(
        english: "Accessibility is not enabled for this Flotis build. Your text was preserved.",
        simplifiedChinese: "当前 Flotis 构建尚未获得辅助功能权限，文字已保留。"
    )
    static let injectionTargetUnavailable = localized(
        english: "The app where recording started is no longer available. Your text was preserved.",
        simplifiedChinese: "开始录音时的目标 App 已不可用，文字已保留。"
    )
    static let injectionBusy = localized(
        english: "Another insert is still finishing. Try again in a moment.",
        simplifiedChinese: "上一次输入仍在收尾，请稍后重试。"
    )
    static let injectionClipboardUnavailable = localized(
        english: "The current clipboard could not be copied safely. It was left unchanged.",
        simplifiedChinese: "无法安全备份当前剪贴板，已保持原内容不变。"
    )
    static let injectionClipboardChanged = localized(
        english: "The clipboard changed during insertion, so Flotis stopped safely.",
        simplifiedChinese: "输入期间剪贴板发生变化，Flotis 已安全停止。"
    )
    static let injectionClipboardWriteFailed = localized(
        english: "Flotis could not place the reviewed text on the clipboard.",
        simplifiedChinese: "Flotis 无法把确认后的文字写入剪贴板。"
    )
    static let injectionTargetActivationFailed = localized(
        english: "The original app did not regain keyboard focus in time. Your text was preserved.",
        simplifiedChinese: "原目标 App 未能及时恢复键盘焦点，文字已保留。"
    )
    static let injectionShortcutReleaseTimedOut = localized(
        english: "Release the voice shortcut before inserting, then try again.",
        simplifiedChinese: "请先完全松开语音快捷键，再重试输入。"
    )
    static let injectionOperationExpired = localized(
        english: "The insert request expired before it was safe to continue. Try again.",
        simplifiedChinese: "输入请求在安全核验完成前已过期，请重试。"
    )
    static let injectionEventFailed = localized(
        english: "macOS could not create the paste event. Your text was preserved.",
        simplifiedChinese: "macOS 无法创建粘贴事件，文字已保留。"
    )
    static let injectionClipboardRestoreFailed = localized(
        english: "Text was sent, but the previous clipboard could not be restored.",
        simplifiedChinese: "文字已发送，但此前的剪贴板内容未能恢复。"
    )
    static let injecting = localized(
        english: "Inserting...",
        simplifiedChinese: "正在注入..."
    )
    static let failed = localized(english: "Failed", simplifiedChinese: "失败")
    static let retry = localized(english: "Retry", simplifiedChinese: "重试")
    static let start = localized(english: "Start", simplifiedChinese: "开始")
    static let stop = localized(english: "Stop", simplifiedChinese: "停止")
    static let requestInProgress = localized(
        english: "Request in Progress",
        simplifiedChinese: "请求中"
    )
    static let connectingShort = localized(
        english: "Connecting",
        simplifiedChinese: "连接中"
    )
    static let stoppingShort = localized(english: "Stopping", simplifiedChinese: "停止中")
    static let transcribingShort = localized(
        english: "Transcribing",
        simplifiedChinese: "转写中"
    )
    static let injectingShort = localized(english: "Inserting", simplifiedChinese: "注入中")
    static let uploading = localized(
        english: "Uploading...",
        simplifiedChinese: "上传中..."
    )
    static let speechBusy = localized(
        english: "Voice input is busy.",
        simplifiedChinese: "语音输入正在处理中。"
    )

    static let externalProvider = localized(
        english: "External Provider",
        simplifiedChinese: "外部提供商"
    )
    static let idle = localized(english: "Idle", simplifiedChinese: "空闲")
    static let showHideFloatingPanel = localized(
        english: "Show/Hide Floating Panel",
        simplifiedChinese: "显示/隐藏浮窗"
    )
    static let voiceInput = localized(english: "Voice Input", simplifiedChinese: "语音输入")
    static let space = localized(english: "Space", simplifiedChinese: "空格")

    static func hotkeyAlreadyUsed(by displayName: String) -> String {
        localized(
            english: "This shortcut is already used by \(displayName).",
            simplifiedChinese: "该快捷键已被“\(displayName)”使用。"
        )
    }

    static func pressAgainToInsert(shortcut: String) -> String {
        localized(
            english: "Press \(shortcut) again to insert",
            simplifiedChinese: "\(shortcut) 再按输入"
        )
    }

    static func pressToStartRecording(shortcut: String) -> String {
        localized(
            english: "Press \(shortcut) to start recording",
            simplifiedChinese: "按 \(shortcut) 开始录音"
        )
    }

    static func pressAgainToStop(shortcut: String) -> String {
        localized(
            english: "Press \(shortcut) again to stop",
            simplifiedChinese: "再按 \(shortcut) 停止"
        )
    }

    static func failed(message: String) -> String {
        localized(
            english: "Failed: \(message)",
            simplifiedChinese: "失败：\(message)"
        )
    }

    static func recordingSecondsRemaining(_ seconds: Int) -> String {
        localized(
            english: seconds == 1
                ? "Recording — 1 second remaining"
                : "Recording — \(seconds) seconds remaining",
            simplifiedChinese: "正在录音，剩余 \(seconds) 秒"
        )
    }

    static func recordingExceedsUploadLimit(megabytes: Int) -> String {
        localized(
            english: "The recording exceeds \(megabytes) MB and was not sent.",
            simplifiedChinese: "录音超过 \(megabytes) MB，未发送。"
        )
    }

    static func comparisonConnectionError(
        connectionName: String,
        message: String
    ) -> String {
        localized(
            english: "\(connectionName): \(message)",
            simplifiedChinese: "\(connectionName)：\(message)"
        )
    }

    static func providerModelCount(_ count: Int) -> String {
        localized(
            english: count == 1 ? "1 model" : "\(count) models",
            simplifiedChinese: "\(count) 个模型"
        )
    }

    static func comparisonSelectedCount(_ count: Int) -> String {
        localized(
            english: "\(count) of \(TranscriptionComparisonStore.maximumConnectionCount) selected",
            simplifiedChinese: "已选择 \(count)/\(TranscriptionComparisonStore.maximumConnectionCount)"
        )
    }

    static func comparisonElapsed(milliseconds: Int) -> String {
        let seconds = Double(max(0, milliseconds)) / 1_000
        return localized(
            english: String(format: "%.1fs", seconds),
            simplifiedChinese: String(format: "%.1f 秒", seconds)
        )
    }

    static func recordingElapsed(seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func additionalShortcutIssues(_ count: Int) -> String {
        localized(
            english: count == 1
                ? " 1 more shortcut issue."
                : " \(count) more shortcut issues.",
            simplifiedChinese: "；另有 \(count) 项快捷键异常。"
        )
    }
}
