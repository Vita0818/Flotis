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
    static let generalSettings = localized(
        english: "General",
        simplifiedChinese: "概览"
    )
    static let transcriptionSettings = localized(
        english: "Transcription",
        simplifiedChinese: "转写服务"
    )
    static let generalSettingsSubtitle = localized(
        english: "Permission status and the essentials for using Flotis.",
        simplifiedChinese: "查看权限状态与 Flotis 的核心使用方式。"
    )
    static let transcriptionSettingsSubtitle = localized(
        english: "Configure the OpenAI-compatible service used for voice transcription.",
        simplifiedChinese: "配置用于语音转写的 OpenAI 兼容服务。"
    )
    static let commands = localized(english: "Commands", simplifiedChinese: "命令")
    static let speech = localized(english: "Speech", simplifiedChinese: "语音")
    static let transcriptionProviders = localized(
        english: "Transcription Connections",
        simplifiedChinese: "转写连接"
    )
    static let openAICompatible = "OpenAI Compatible"
    static let openAICompatibleNotCurrent = localized(
        english: "Not using OpenAI Compatible",
        simplifiedChinese: "当前未使用 OpenAI Compatible"
    )
    static let noOpenAICompatibleConnections = localized(
        english: "No OpenAI Compatible connection has been added.",
        simplifiedChinese: "尚未添加 OpenAI Compatible 连接。"
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
        english: "Current Connection",
        simplifiedChinese: "当前连接"
    )
    static let connections = localized(english: "Connections", simplifiedChinese: "连接")
    static let basicInformation = localized(
        english: "Basic Information",
        simplifiedChinese: "基本信息"
    )
    static let connectionName = localized(
        english: "Connection Name",
        simplifiedChinese: "连接名称"
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
        english: "Connection Endpoint",
        simplifiedChinese: "连接端点"
    )
    static let addTranscriptionConnection = localized(
        english: "Add Connection",
        simplifiedChinese: "新增连接"
    )
    static let editTranscriptionConnection = localized(
        english: "Edit Connection",
        simplifiedChinese: "编辑连接"
    )
    static let newTranscriptionConnectionName = localized(
        english: "OpenAI Compatible",
        simplifiedChinese: "OpenAI Compatible"
    )
    static let newConnectionDraftHint = localized(
        english: "This connection draft has not been saved. Canceling will not change any existing configuration.",
        simplifiedChinese: "这是未保存的连接草稿；取消不会修改现有配置。"
    )
    static let presetAppliedHint = localized(
        english: "Recommended values have been filled in. You can still adjust every field for this connection.",
        simplifiedChinese: "预设已填入建议值，所有字段仍可按当前连接调整。"
    )
    static let model = localized(english: "Model", simplifiedChinese: "模型")
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
    static let sampleRate = localized(english: "Sample Rate", simplifiedChinese: "采样率")
    static let channels = localized(english: "Channels", simplifiedChinese: "声道数")
    static let temperature = localized(english: "Temperature", simplifiedChinese: "温度")
    static let serverVAD = localized(english: "Server VAD", simplifiedChinese: "服务端 VAD")
    static let apiKey = "API Key"
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
        english: "Select a transcription connection.",
        simplifiedChinese: "选择一个转写连接。"
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
        english: "Press once to start recording, again to stop, and once more to copy the reviewed text and return to the capsule.",
        simplifiedChinese: "按一次开始录音，再按一次停止，确认文字后第三次复制并回到小胶囊。"
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
        english: "Connection",
        simplifiedChinese: "连接"
    )
    static let connectionDetailsDescription = localized(
        english: "Model and HTTPS transcription endpoint.",
        simplifiedChinese: "模型与 HTTPS 转写接口。"
    )
    static let credentials = localized(
        english: "Credentials",
        simplifiedChinese: "凭据"
    )
    static let credentialsDescription = localized(
        english: "The key stays in Flotis local app data and is never written to the connection snapshot.",
        simplifiedChinese: "密钥仅保存在 Flotis 本地应用数据中，不会写入连接配置快照。"
    )
    static let optionalParameters = localized(
        english: "Optional parameters",
        simplifiedChinese: "可选参数"
    )
    static let addConnectionDescription = localized(
        english: "Add one OpenAI-compatible endpoint to start transcribing.",
        simplifiedChinese: "添加一个 OpenAI 兼容接口后即可开始转写。"
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
        english: "Saved. Enter a new value to replace it",
        simplifiedChinese: "已保存，输入新值可覆盖"
    )
    static let apiKeyStoredLocally = localized(
        english: "The API Key is stored locally in Flotis app data.",
        simplifiedChinese: "API Key 由 Flotis 保存在本机应用数据中。"
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
        english: "This connection does not have a saved API Key.",
        simplifiedChinese: "当前连接没有已保存的 API Key。"
    )
    static let apiKeyRequiredForActivation = localized(
        english: "Save an API Key for this connection before setting it as current.",
        simplifiedChinese: "请先保存该连接的 API Key，再设为当前。"
    )
    static let providerSaved = localized(
        english: "Transcription connection saved.",
        simplifiedChinese: "转写连接已保存。"
    )
    static let providerSavedNeedsAPIKey = localized(
        english: "Configuration saved. Enter a new API Key before setting this connection as current.",
        simplifiedChinese: "配置已保存；请录入新的 API Key 后再设为当前。"
    )
    static let providerNotFound = localized(
        english: "Transcription connection not found.",
        simplifiedChinese: "找不到该转写连接。"
    )
    static let keepOneProvider = localized(
        english: "At least one transcription connection is required.",
        simplifiedChinese: "至少需要保留一个转写连接。"
    )
    static let providerConfigSaveFailed = localized(
        english: "Could not save the transcription connection.",
        simplifiedChinese: "转写连接保存失败。"
    )
    static let providerSecretCleanupFailed = localized(
        english: "Could not remove the old API Key. The configuration change was reverted. Try again later.",
        simplifiedChinese: "旧 API Key 清理失败；本次配置变更已撤销，请稍后重试。"
    )
    static let providerDeleteSecretCleanupFailed = localized(
        english: "Could not remove the API Key. The connection was not deleted. Try again later.",
        simplifiedChinese: "API Key 清理失败；提供商删除已撤销，请稍后重试。"
    )
    static let providerConfigRecoveredWithoutOverwrite = localized(
        english: "The transcription provider configuration could not be decoded. A recovery configuration is in use, and the original data was not overwritten.",
        simplifiedChinese: "语音提供商配置无法解码；已使用恢复配置，原始数据未被覆盖。"
    )
    static let providerNameRequired = localized(
        english: "Connection name is required.",
        simplifiedChinese: "连接名称不能为空。"
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
        english: "This connection has not been tested.",
        simplifiedChinese: "尚未测试此连接。"
    )
    static let connectionTestStillValid = localized(
        english: "The most recent connection test still matches the current configuration.",
        simplifiedChinese: "最近一次连接测试仍与当前配置匹配。"
    )
    static let connectionTestInvalidated = localized(
        english: "The configuration or credentials have changed. Test the connection again.",
        simplifiedChinese: "配置或凭据已改变，需要重新测试。"
    )
    static let connectionTestConfigurationInvalid = localized(
        english: "Complete and correct the connection configuration before testing.",
        simplifiedChinese: "请先补全并修正连接配置，再开始测试。"
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
        english: "Press the shortcut; Esc to cancel",
        simplifiedChinese: "按下快捷键，Esc 取消"
    )
    static let transcriptPreviewPlaceholder = localized(
        english: "Transcript preview...",
        simplifiedChinese: "转写预览文本..."
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

    static func additionalShortcutIssues(_ count: Int) -> String {
        localized(
            english: count == 1
                ? " 1 more shortcut issue."
                : " \(count) more shortcut issues.",
            simplifiedChinese: "；另有 \(count) 项快捷键异常。"
        )
    }
}
