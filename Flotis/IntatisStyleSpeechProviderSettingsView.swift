import AppKit
import SwiftUI

private enum ProviderModelEditorMode: Equatable {
    case add
    case edit(String)
}

private enum ProviderModelNoticeKind {
    case information
    case success
    case warning
    case error
}

private struct ProviderModelNotice {
    let kind: ProviderModelNoticeKind
    let text: String
}

private enum ProviderModelConnectionTestState: Equatable {
    case idle
    case testing
    case succeeded
    case failed(String)
}

private struct EditableProviderModel: Identifiable, Equatable {
    let id: UUID
    var modelID: String
    var displayName: String

    init(
        id: UUID = UUID(),
        modelID: String,
        displayName: String = ""
    ) {
        self.id = id
        self.modelID = modelID
        self.displayName = displayName
    }
}

private struct ProviderModelSettingsLayout {
    let rawWidth: CGFloat

    private var width: CGFloat { max(rawWidth, 1) }
    var isCompact: Bool { width < 700 }
    var usesColumns: Bool { width >= 760 }
    var horizontalPadding: CGFloat { width < 700 ? 20 : 28 }
    var cardMaxWidth: CGFloat { 820 }

    var providerListWidth: CGFloat {
        min(220, max(176, width * 0.30))
    }
}

private struct ProviderSettingsDisclosure<Label: View, Content: View>: View {
    @Binding var isExpanded: Bool

    let accessibilityIdentifier: String
    let label: Label
    let content: Content

    init(
        isExpanded: Binding<Bool>,
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        _isExpanded = isExpanded
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
        self.label = label()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    label
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityValue(isExpanded ? UIStrings.expanded : UIStrings.collapsed)

            if isExpanded {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The transcription catalog intentionally mirrors Intatis' Settings model
/// editor: providers on the left, shared provider fields on the right, then
/// collapsible Connection and Models sections. Flotis-only comparison and
/// transcription parameters remain below that primary card so they do not
/// distort the shared provider/model hierarchy.
struct IntatisStyleSpeechProviderSettingsView: View {
    @ObservedObject var providerStore: SpeechProviderStore
    @ObservedObject var comparisonStore: TranscriptionComparisonStore
    let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedProviderID: String?
    @State private var providerDraft: SpeechProviderConfig?
    @State private var editorMode: ProviderModelEditorMode?
    @State private var modelDrafts: [EditableProviderModel] = []
    @State private var selectedModelID = ""
    @State private var apiKeyInput = ""
    @State private var notice: ProviderModelNotice?
    @State private var saved = false
    @State private var isConnectionExpanded = false
    @State private var isModelsExpanded = false
    @State private var isComparisonExpanded = false
    @State private var isAdvancedExpanded = false
    @State private var showsDeleteProviderConfirmation = false
    @State private var connectionTestState: ProviderModelConnectionTestState = .idle
    @State private var connectionTestGeneration = UUID()
    @State private var connectionTestTask: Task<Void, Never>?

    private let visibleAdapterID: TranscriptionAdapterID =
        .openAIAudioTranscriptionsHTTPV1

    private var visibleProviderGroups: [SpeechProviderGroup] {
        providerStore.providerGroups.filter { $0.adapterID == visibleAdapterID }
    }

    private var visibleRoutes: [SpeechProviderConfig] {
        providerStore.providers.filter { $0.adapterID == visibleAdapterID }
    }

    private var preferredVisibleProviderID: String? {
        if let active = visibleRoutes.first(where: {
            $0.id == providerStore.activeProviderID
        })?.configurationProviderID {
            return active
        }
        return visibleProviderGroups.first?.id
    }

    private var persistedSelectedGroup: SpeechProviderGroup? {
        guard let selectedProviderID else { return nil }
        return providerStore.providerGroup(id: selectedProviderID)
    }

    private var persistedSelectedProvider: SpeechProviderConfig? {
        guard let group = persistedSelectedGroup else { return nil }
        if group.modelIDs.contains(selectedModelID) {
            return group.connection(modelID: selectedModelID)
        }
        return group.modelIDs.first.flatMap(group.connection)
    }

    private var normalizedModelDrafts: [(id: String, name: String)]? {
        var seen = Set<String>()
        var values: [(id: String, name: String)] = []
        for model in modelDrafts {
            let modelID = model.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlotisModelSelector.isValidModelID(modelID),
                  seen.insert(modelID).inserted else {
                return nil
            }
            values.append((
                id: modelID,
                name: model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return values.isEmpty ? nil : values
    }

    private var selectableModels: [EditableProviderModel] {
        var seen = Set<String>()
        return modelDrafts.compactMap { model in
            var normalized = model
            normalized.modelID = model.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.modelID.isEmpty,
                  seen.insert(normalized.modelID).inserted else { return nil }
            return normalized
        }
    }

    private var hasUnsavedDraftChanges: Bool {
        guard let providerDraft else { return false }
        if editorMode == .add { return true }
        guard let persistedSelectedProvider,
              let persistedSelectedGroup else { return true }

        let draftModels = modelDrafts.map {
            "\($0.modelID.trimmingCharacters(in: .whitespacesAndNewlines))\u{1f}\($0.displayName.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        let persistedModels = persistedSelectedGroup.modelIDs.map { modelID in
            let displayName = persistedSelectedGroup.configuration.models[modelID]?.name ?? ""
            return "\(modelID)\u{1f}\(displayName)"
        }
        return providerDraft != persistedSelectedProvider
            || draftModels != persistedModels
            || !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedComparisonCount: Int {
        comparisonStore.selectedModelSelectors.count
    }

    var body: some View {
        GeometryReader { proxy in
            settingsContent(
                layout: ProviderModelSettingsLayout(rawWidth: proxy.size.width)
            )
        }
        .onAppear {
            reconcileComparisonModels()
            selectedProviderID = preferredVisibleProviderID
            loadProviderDraft()
        }
        .onChange(of: selectedProviderID) { newProviderID in
            guard let newProviderID else { return }
            if case .edit(let editingID) = editorMode,
               editingID == newProviderID,
               providerDraft?.configurationProviderID == newProviderID {
                return
            }
            apiKeyInput = ""
            notice = nil
            saved = false
            loadProviderDraft()
        }
        .onChange(of: providerStore.availableModelSelectors) { _ in
            reconcileComparisonModels()
        }
        .onChange(of: isActive) { newValue in
            if !newValue {
                cancelConnectionTest(resetState: true)
            }
        }
        .onDisappear {
            cancelConnectionTest(resetState: true)
        }
        .alert(
            UIStrings.deleteProviderTitle,
            isPresented: $showsDeleteProviderConfirmation
        ) {
            Button(UIStrings.cancel, role: .cancel) {}
            Button(UIStrings.delete, role: .destructive) {
                deleteSelectedProvider()
            }
        } message: {
            Text(UIStrings.deleteProviderMessage)
        }
    }

    private func settingsContent(
        layout: ProviderModelSettingsLayout
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsCard(layout: layout)

                if let notice {
                    providerNotice(notice)
                        .frame(maxWidth: layout.cardMaxWidth, alignment: .leading)
                }

                connectionTestSummary
                    .frame(maxWidth: layout.cardMaxWidth, alignment: .leading)

                settingsActions(layout: layout)

                comparisonSettings(layout: layout)

                advancedSettings(layout: layout)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.bottom, 30)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func settingsCard(
        layout: ProviderModelSettingsLayout
    ) -> some View {
        if layout.usesColumns {
            HStack(alignment: .top, spacing: 18) {
                providerList
                    .frame(width: layout.providerListWidth, alignment: .topLeading)
                Divider().opacity(0.45)
                providerDetail(layout: layout)
            }
            .padding(22)
            .flotisContentSurface(cornerRadius: 24)
            .frame(maxWidth: layout.cardMaxWidth, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                providerList
                Divider().opacity(0.45)
                providerDetail(layout: layout)
            }
            .padding(18)
            .flotisContentSurface(cornerRadius: 20)
            .frame(maxWidth: layout.cardMaxWidth, alignment: .leading)
        }
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(UIStrings.connections)
                    .font(FlotisType.caption(12, .semibold))
                    .foregroundStyle(FlotisTheme.secondary(colorScheme))
                Spacer()
                Button(action: beginAddingProvider) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(hasUnsavedDraftChanges)
                .help(UIStrings.addTranscriptionConnection)
            }

            VStack(spacing: 8) {
                ForEach(visibleProviderGroups) { group in
                    providerRow(group)
                }
                if editorMode == .add, let providerDraft {
                    providerDraftRow(providerDraft)
                }
            }
        }
    }

    private func providerRow(_ group: SpeechProviderGroup) -> some View {
        let selected = editorMode != .add && group.id == selectedProviderID
        return Button {
            selectedProviderID = group.id
        } label: {
            providerRowLabel(
                title: group.name,
                modelCount: group.modelIDs.count,
                selected: selected
            )
        }
        .buttonStyle(.plain)
        .disabled(hasUnsavedDraftChanges && !selected)
    }

    private func providerDraftRow(_ provider: SpeechProviderConfig) -> some View {
        providerRowLabel(
            title: provider.name,
            modelCount: max(1, modelDrafts.count),
            selected: true
        )
    }

    private func providerRowLabel(
        title: String,
        modelCount: Int,
        selected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        selected
                            ? Color.accentColor
                            : FlotisTheme.tertiary(colorScheme)
                    )
                Text(title.isEmpty ? UIStrings.newConnection : title)
                    .font(FlotisType.body(13, .semibold))
                    .foregroundStyle(FlotisTheme.primary(colorScheme))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(UIStrings.providerModelCount(modelCount))
                .font(FlotisType.caption(11, .regular))
                .foregroundStyle(FlotisTheme.secondary(colorScheme))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    selected
                        ? Color.accentColor.opacity(0.72)
                        : FlotisTheme.separator(colorScheme),
                    lineWidth: 1
                )
        }
    }

    @ViewBuilder
    private func providerDetail(
        layout: ProviderModelSettingsLayout
    ) -> some View {
        if providerDraftBinding != nil {
            VStack(alignment: .leading, spacing: 16) {
                inputField(
                    UIStrings.connectionName,
                    text: providerNameBinding,
                    placeholder: "OpenRouter"
                )

                apiKeyField

                activeModelPicker(layout: layout)

                connectionSettings

                modelsSettings(layout: layout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(UIStrings.addProviderToConfigureModels)
                .font(FlotisType.body(14))
                .foregroundStyle(FlotisTheme.secondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(UIStrings.apiKey)
                .font(FlotisType.caption(12, .semibold))
                .foregroundStyle(FlotisTheme.secondary(colorScheme))

            HStack(spacing: 8) {
                SecureField(
                    hasSavedAPIKeyForDraft
                        ? UIStrings.apiKeySavedPlaceholder
                        : UIStrings.apiKey,
                    text: apiKeyBinding
                )
                .textFieldStyle(.plain)
                .font(FlotisType.mono(13))
                .foregroundStyle(FlotisTheme.primary(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .overlay(inputBackground)
            }
        }
    }

    private func activeModelPicker(
        layout: ProviderModelSettingsLayout
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(UIStrings.activeModel)
                .font(FlotisType.caption(12, .semibold))
                .foregroundStyle(FlotisTheme.secondary(colorScheme))

            Picker("", selection: selectedModelBinding) {
                ForEach(selectableModels) { model in
                    Text(modelTitle(model)).tag(model.modelID)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(selectableModels.isEmpty)
            .frame(
                maxWidth: layout.usesColumns ? 280 : .infinity,
                alignment: .leading
            )
        }
    }

    private var connectionSettings: some View {
        ProviderSettingsDisclosure(
            isExpanded: $isConnectionExpanded,
            accessibilityIdentifier: "settings.provider.connection"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                inputField(
                    UIStrings.baseURL,
                    text: baseURLBinding,
                    placeholder: "https://openrouter.ai/api"
                )
                inputField(
                    UIStrings.endpointPath,
                    text: endpointPathBinding,
                    placeholder: "/v1/audio/transcriptions"
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(UIStrings.requestEncoding)
                        .font(FlotisType.caption(12, .semibold))
                        .foregroundStyle(FlotisTheme.secondary(colorScheme))
                    Picker(
                        UIStrings.requestEncoding,
                        selection: requestEncodingBinding
                    ) {
                        Text(UIStrings.requestEncodingMultipart)
                            .tag(TranscriptionRequestEncoding.multipartFormData)
                        Text(UIStrings.requestEncodingJSONBase64)
                            .tag(TranscriptionRequestEncoding.jsonBase64)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if let providerDraft,
                   let host = providerDraft.credentialDestinationIdentifier {
                    Text(String(format: UIStrings.credentialDestinationFormat, host))
                        .font(FlotisType.caption(11, .medium))
                        .foregroundStyle(FlotisTheme.secondary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    if !providerDraft.usesTrustedEndpoint {
                        Toggle(isOn: customEndpointApprovalBinding) {
                            Text(UIStrings.confirmCustomEndpoint)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: 40,
                                    alignment: .leading
                                )
                                .contentShape(Rectangle())
                        }
                        .toggleStyle(.checkbox)
                        .foregroundStyle(.orange)
                    }

                    if canClearSavedAPIKey {
                        HStack {
                            Spacer()
                            Button(
                                UIStrings.clearAPIKey,
                                role: .destructive,
                                action: clearSelectedAPIKey
                            )
                            .buttonStyle(.borderless)
                            .font(FlotisType.caption(12, .semibold))
                        }
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Text(UIStrings.connection)
                .font(FlotisType.body(13, .semibold))
                .foregroundStyle(FlotisTheme.primary(colorScheme))
        }
    }

    private func modelsSettings(
        layout: ProviderModelSettingsLayout
    ) -> some View {
        ProviderSettingsDisclosure(
            isExpanded: $isModelsExpanded,
            accessibilityIdentifier: "settings.provider.models"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    Button(action: addModel) {
                        Label(UIStrings.addModel, systemImage: "plus")
                            .font(FlotisType.caption(12, .semibold))
                            .padding(.horizontal, 8)
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        modelDrafts.count
                            >= FlotisConfigurationStore.maximumModelCountPerProvider
                    )
                }

                ForEach($modelDrafts) { model in
                    modelEditorRow(model: model, layout: layout)
                }

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showsDeleteProviderConfirmation = true
                    } label: {
                        Label(UIStrings.deleteProvider, systemImage: "trash")
                            .font(FlotisType.caption(12, .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(
                        editorMode == .add || visibleProviderGroups.count <= 1
                    )
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Text(UIStrings.models)
                    .font(FlotisType.body(13, .semibold))
                    .foregroundStyle(FlotisTheme.primary(colorScheme))
                Spacer()
                Text("\(modelDrafts.count)")
                    .font(FlotisType.caption(12, .medium))
                    .foregroundStyle(FlotisTheme.secondary(colorScheme))
            }
        }
    }

    @ViewBuilder
    private func modelEditorRow(
        model: Binding<EditableProviderModel>,
        layout: ProviderModelSettingsLayout
    ) -> some View {
        if layout.usesColumns {
            HStack(spacing: 8) {
                inputField(
                    UIStrings.modelID,
                    text: modelIDBinding(model),
                    placeholder: "openai/gpt-4o-mini-transcribe"
                )
                inputField(
                    UIStrings.modelDisplayName,
                    text: modelDisplayNameBinding(model),
                    placeholder: "GPT-4o mini transcribe"
                )
                removeModelButton(model.wrappedValue.id)
                    .padding(.top, 20)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                inputField(
                    UIStrings.modelID,
                    text: modelIDBinding(model),
                    placeholder: "openai/gpt-4o-mini-transcribe"
                )
                inputField(
                    UIStrings.modelDisplayName,
                    text: modelDisplayNameBinding(model),
                    placeholder: "GPT-4o mini transcribe"
                )
                HStack {
                    Spacer()
                    removeModelButton(model.wrappedValue.id)
                }
            }
        }
    }

    private func removeModelButton(_ modelID: UUID) -> some View {
        Button(action: { removeModel(modelID) }) {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FlotisTheme.tertiary(colorScheme))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(modelDrafts.count == 1)
        .help(UIStrings.removeModel)
    }

    @ViewBuilder
    private func settingsActions(
        layout: ProviderModelSettingsLayout
    ) -> some View {
        if layout.isCompact {
            VStack(alignment: .trailing, spacing: 10) {
                savedLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer(minLength: 0)
                    cancelButton
                    testProviderButton
                    saveButton
                }
            }
            .frame(maxWidth: layout.cardMaxWidth)
        } else {
            HStack {
                savedLabel
                Spacer()
                cancelButton
                testProviderButton
                saveButton
            }
            .frame(maxWidth: layout.cardMaxWidth)
        }
    }

    @ViewBuilder
    private var savedLabel: some View {
        if saved {
            Label(UIStrings.saved, systemImage: "checkmark.circle.fill")
                .font(FlotisType.caption(12, .semibold))
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var cancelButton: some View {
        if providerDraft != nil, hasUnsavedDraftChanges {
            Button(UIStrings.cancel, action: cancelProviderDraft)
                .font(FlotisType.body(14, .semibold))
                .flotisGlassButton()
        }
    }

    private var testProviderButton: some View {
        Button(action: testProviderDraft) {
            Label(
                isTestingConnection
                    ? UIStrings.testingConnection
                    : UIStrings.testProvider,
                systemImage: isTestingConnection ? "hourglass" : "checkmark.seal"
            )
            .font(FlotisType.body(14, .semibold))
            .foregroundStyle(.primary)
        }
        .flotisGlassButton()
        .disabled(isTestingConnection || !canTestDraftConnection)
        .help(UIStrings.connectionTestPrivacyNote)
    }

    private var saveButton: some View {
        Button(UIStrings.save, action: saveProviderDraft)
            .font(FlotisType.body(14, .semibold))
            .foregroundStyle(.primary)
            .flotisGlassButton(prominent: true)
            .disabled(providerDraft == nil || isTestingConnection)
    }

    @ViewBuilder
    private var connectionTestSummary: some View {
        switch connectionTestState {
        case .idle:
            if let providerDraft,
               let record = providerDraft.lastConnectionTest {
                Label(
                    providerDraft.isConnectionTestCurrent
                        ? (record.outcome == .succeeded
                            ? UIStrings.connectionTestStillValid
                            : String(
                                format: UIStrings.connectionTestFailedFormat,
                                record.safeSummary
                            ))
                        : UIStrings.connectionTestInvalidated,
                    systemImage: record.outcome == .succeeded
                        && providerDraft.isConnectionTestCurrent
                        ? "checkmark.circle.fill"
                        : "arrow.triangle.2.circlepath"
                )
                .font(FlotisType.caption(12, .semibold))
                .foregroundStyle(
                    record.outcome == .succeeded
                        && providerDraft.isConnectionTestCurrent
                        ? Color.green
                        : FlotisTheme.secondary(colorScheme)
                )
            }
        case .testing:
            Label(UIStrings.testingConnection, systemImage: "hourglass")
                .font(FlotisType.caption(12, .semibold))
                .foregroundStyle(FlotisTheme.secondary(colorScheme))
        case .succeeded:
            Label(
                UIStrings.connectionTestSucceeded,
                systemImage: "checkmark.circle.fill"
            )
            .font(FlotisType.caption(12, .semibold))
            .foregroundStyle(.green)
        case .failed(let summary):
            Label(
                String(format: UIStrings.connectionTestFailedFormat, summary),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(FlotisType.caption(12, .semibold))
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func comparisonSettings(
        layout: ProviderModelSettingsLayout
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().opacity(0.45)

            ProviderSettingsDisclosure(
                isExpanded: $isComparisonExpanded,
                accessibilityIdentifier: "settings.provider.comparison"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        isOn: Binding(
                            get: { comparisonStore.isEnabled },
                            set: { _ = comparisonStore.setEnabled($0) }
                        )
                    ) {
                        HStack(spacing: 10) {
                            Text(UIStrings.enabled)
                                .font(FlotisType.body(13, .medium))
                            Spacer(minLength: 12)
                            Text(UIStrings.comparisonSelectedCount(selectedComparisonCount))
                                .font(FlotisType.mono(10, .medium))
                                .foregroundStyle(FlotisTheme.secondary(colorScheme))
                        }
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .toggleStyle(.switch)
                    .disabled(
                        !comparisonStore.isEnabled
                            && selectedComparisonCount < 2
                    )

                    Text(UIStrings.comparisonModeDescription)
                        .font(FlotisType.caption(12, .regular))
                        .foregroundStyle(FlotisTheme.secondary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(visibleRoutes) { provider in
                            comparisonRouteToggle(provider)
                        }
                    }

                    Label(
                        UIStrings.comparisonPrivacyWarning,
                        systemImage: "exclamationmark.shield"
                    )
                    .font(FlotisType.caption(11, .regular))
                    .foregroundStyle(FlotisTheme.secondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                    if let lastError = comparisonStore.lastError {
                        Text(lastError)
                            .font(FlotisType.caption(11, .medium))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 12)
            } label: {
                HStack {
                    Label(UIStrings.comparisonMode, systemImage: "square.stack.3d.up")
                        .font(FlotisType.body(14, .semibold))
                        .foregroundStyle(FlotisTheme.primary(colorScheme))
                    Spacer()
                    Text("\(selectedComparisonCount)")
                        .font(FlotisType.caption(12, .medium))
                        .foregroundStyle(FlotisTheme.secondary(colorScheme))
                }
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: layout.cardMaxWidth, alignment: .leading)
    }

    private func comparisonRouteToggle(
        _ provider: SpeechProviderConfig
    ) -> some View {
        let selector = provider.configurationModelSelector ?? ""
        let selected = comparisonStore.isSelected(selector)
        let ready = providerStore.isProviderReady(provider)
        let limitReached = selectedComparisonCount
            >= TranscriptionComparisonStore.maximumConnectionCount

        return Button {
            _ = comparisonStore.setModel(selector, selected: !selected)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayNameForUI)
                        .font(FlotisType.body(12, .semibold))
                        .lineLimit(1)
                    Text(ready ? displayName(for: provider) : UIStrings.connectionNotReady)
                        .font(FlotisType.mono(10, .regular))
                        .foregroundStyle(ready ? Color.secondary : Color.orange)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        selected
                            ? Color.accentColor.opacity(0.72)
                            : FlotisTheme.separator(colorScheme),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled((!ready && !selected) || (!selected && limitReached))
        .accessibilityLabel(provider.displayNameForUI)
        .accessibilityValue(selected ? UIStrings.enabledStatus : UIStrings.disabledStatus)
    }

    @ViewBuilder
    private func advancedSettings(
        layout: ProviderModelSettingsLayout
    ) -> some View {
        if hasAdvancedSettings {
            VStack(alignment: .leading, spacing: 12) {
                Divider().opacity(0.45)

                ProviderSettingsDisclosure(
                    isExpanded: $isAdvancedExpanded,
                    accessibilityIdentifier: "settings.provider.advanced"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        if providerDraft?.protocolSchema.supportsLanguage == true {
                            inputField(
                                UIStrings.language,
                                text: optionalStringBinding(\.language),
                                placeholder: "en"
                            )
                        }

                        if providerDraft?.protocolSchema.supportsPrompt == true {
                            inputField(
                                UIStrings.prompt,
                                text: optionalStringBinding(\.prompt),
                                placeholder: UIStrings.prompt
                            )
                        }

                        if providerDraft?.protocolSchema.supportsTemperature == true {
                            inputField(
                                UIStrings.temperature,
                                text: doubleBinding(\.temperature),
                                placeholder: "0"
                            )
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    Label(UIStrings.advancedSettings, systemImage: "slider.horizontal.3")
                        .font(FlotisType.body(14, .semibold))
                        .foregroundStyle(FlotisTheme.primary(colorScheme))
                }
            }
            .padding(.top, 2)
            .frame(maxWidth: layout.cardMaxWidth, alignment: .leading)
        }
    }

    private var hasAdvancedSettings: Bool {
        guard let providerDraft else { return false }
        return providerDraft.protocolSchema.supportsLanguage
            || providerDraft.protocolSchema.supportsPrompt
            || providerDraft.protocolSchema.supportsTemperature
    }

    private func providerNotice(_ notice: ProviderModelNotice) -> some View {
        Label {
            Text(notice.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: noticeSystemImage(notice.kind))
        }
        .font(FlotisType.caption(12, .medium))
        .foregroundStyle(noticeColor(notice.kind))
    }

    private func noticeColor(_ kind: ProviderModelNoticeKind) -> Color {
        switch kind {
        case .information:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func noticeSystemImage(_ kind: ProviderModelNoticeKind) -> String {
        switch kind {
        case .information:
            return "info.circle"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private var providerDraftBinding: Binding<SpeechProviderConfig>? {
        guard let providerDraft else { return nil }
        return Binding(
            get: { self.providerDraft ?? providerDraft },
            set: {
                self.providerDraft = $0
                markDraftChanged()
            }
        )
    }

    private var draftMatchesPersistedSecretBoundary: Bool {
        guard let providerDraft,
              let persistedSelectedProvider else { return false }
        return providerDraft.secretBoundaryIdentifier
            == persistedSelectedProvider.secretBoundaryIdentifier
    }

    private var hasSavedAPIKeyForDraft: Bool {
        guard draftMatchesPersistedSecretBoundary,
              let persistedSelectedProvider else { return false }
        return providerStore.hasAPIKey(for: persistedSelectedProvider)
    }

    private var canClearSavedAPIKey: Bool {
        hasSavedAPIKeyForDraft && draftMatchesPersistedSecretBoundary
    }

    private var canTestDraftConnection: Bool {
        guard var candidate = providerDraft,
              let selectedModel = selectableModels.first(where: {
                  $0.modelID == selectedModelID
              }) else { return false }
        candidate.model = selectedModel.modelID
        guard candidate.configurationValidationError() == nil else { return false }
        if candidate.protocolSchema.requiresAPIKey {
            let hasDraftKey = !apiKeyInput
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            return hasDraftKey || hasSavedAPIKeyForDraft
        }
        return true
    }

    private var isTestingConnection: Bool {
        connectionTestState == .testing
    }

    private func loadProviderDraft() {
        cancelConnectionTest(resetState: true)
        guard let selectedProviderID,
              let group = providerStore.providerGroup(id: selectedProviderID),
              !group.modelIDs.isEmpty else {
            providerDraft = nil
            editorMode = nil
            modelDrafts = []
            selectedModelID = ""
            apiKeyInput = ""
            isConnectionExpanded = false
            isModelsExpanded = false
            return
        }

        let activeSelector = FlotisModelSelector(
            rawValue: providerStore.activeModelSelector
        )
        let preferredModelID = activeSelector?.providerID == selectedProviderID
            && group.modelIDs.contains(activeSelector?.modelID ?? "")
            ? activeSelector!.modelID
            : group.modelIDs[0]

        selectedModelID = preferredModelID
        modelDrafts = group.modelIDs.map { modelID in
            EditableProviderModel(
                modelID: modelID,
                displayName: group.configuration.models[modelID]?.name ?? ""
            )
        }
        providerDraft = group.connection(modelID: preferredModelID)
        editorMode = .edit(selectedProviderID)
        apiKeyInput = ""
        isConnectionExpanded = false
        isModelsExpanded = false
    }

    private func beginAddingProvider() {
        guard !hasUnsavedDraftChanges else { return }
        cancelConnectionTest(resetState: true)
        var draft = providerStore.makeNewConnection(adapterID: visibleAdapterID)
        let baseName = UIStrings.newTranscriptionConnectionName
        draft.name = visibleProviderGroups.isEmpty
            ? baseName
            : "\(baseName) \(visibleProviderGroups.count + 1)"
        draft.lastConnectionTest = nil

        selectedProviderID = nil
        providerDraft = draft
        editorMode = .add
        selectedModelID = draft.model
        modelDrafts = [EditableProviderModel(modelID: draft.model)]
        apiKeyInput = ""
        notice = nil
        saved = false
        isConnectionExpanded = false
        isModelsExpanded = false
    }

    private func cancelProviderDraft() {
        notice = nil
        saved = false
        if editorMode == .add {
            selectedProviderID = preferredVisibleProviderID
        }
        loadProviderDraft()
    }

    private func saveProviderDraft() {
        guard var providerDraft,
              let normalizedModels = normalizedModelDrafts,
              normalizedModels.contains(where: { $0.id == selectedModelID }) else {
            saved = false
            notice = ProviderModelNotice(kind: .error, text: UIStrings.modelsRequired)
            return
        }

        providerDraft.model = selectedModelID
        let candidate = providerDraft.normalizedForProtocol()
        if let error = candidate.configurationValidationError() {
            saved = false
            notice = ProviderModelNotice(kind: .error, text: error)
            return
        }

        let trimmedAPIKey = apiKeyInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = trimmedAPIKey.isEmpty ? nil : trimmedAPIKey
        let existingProviderID: String?
        switch editorMode {
        case .add:
            existingProviderID = nil
        case .edit(let providerID):
            existingProviderID = providerID
        case nil:
            return
        }

        let displayNames = Dictionary(
            uniqueKeysWithValues: normalizedModels.map { ($0.id, $0.name) }
        )
        guard let persistedProviderID = providerStore.saveProviderGroup(
            existingProviderID: existingProviderID,
            draft: candidate,
            modelIDs: normalizedModels.map(\.id),
            selectedModelID: selectedModelID,
            modelDisplayNames: displayNames,
            savingAPIKey: apiKey
        ) else {
            saved = false
            notice = ProviderModelNotice(
                kind: .error,
                text: providerStore.lastError ?? UIStrings.providerConfigSaveFailed
            )
            return
        }

        selectedProviderID = persistedProviderID
        editorMode = .edit(persistedProviderID)
        apiKeyInput = ""
        reconcileComparisonModels()
        loadProviderDraft()
        saved = true

        if let persistedSelectedProvider,
           persistedSelectedProvider.protocolSchema.requiresAPIKey,
           !providerStore.hasAPIKey(for: persistedSelectedProvider) {
            notice = ProviderModelNotice(
                kind: .warning,
                text: UIStrings.providerSavedNeedsAPIKey
            )
        } else {
            notice = nil
        }
    }

    private func deleteSelectedProvider() {
        guard case .edit(let providerID) = editorMode else { return }
        cancelConnectionTest(resetState: true)
        guard providerStore.deleteProviderGroup(id: providerID) else {
            notice = ProviderModelNotice(
                kind: .error,
                text: providerStore.lastError ?? UIStrings.providerDeleteFailed
            )
            return
        }

        reconcileComparisonModels()
        selectedProviderID = preferredVisibleProviderID
        notice = nil
        saved = false
        loadProviderDraft()
    }

    private func clearSelectedAPIKey() {
        guard editorMode != .add,
              let persistedSelectedProvider else { return }
        guard providerStore.clearAPIKey(for: persistedSelectedProvider.id) else {
            notice = ProviderModelNotice(
                kind: .error,
                text: providerStore.lastError ?? UIStrings.apiKeyClearFailed
            )
            return
        }
        apiKeyInput = ""
        loadProviderDraft()
        notice = ProviderModelNotice(kind: .success, text: UIStrings.apiKeyCleared)
        saved = true
    }

    private func testProviderDraft() {
        guard var candidate = providerDraft?.normalizedForProtocol(),
              canTestDraftConnection else {
            notice = ProviderModelNotice(
                kind: .error,
                text: UIStrings.connectionTestConfigurationInvalid
            )
            return
        }

        candidate.model = selectedModelID
        cancelConnectionTest(resetState: false)
        let generation = UUID()
        connectionTestGeneration = generation
        connectionTestState = .testing
        notice = nil
        let trimmedAPIKey = apiKeyInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = trimmedAPIKey.isEmpty ? nil : trimmedAPIKey
        if apiKey != nil {
            candidate.credentialRevision =
                (persistedSelectedProvider?.credentialRevision ?? 0) + 1
            candidate.lastConnectionTest = nil
        }

        connectionTestTask = Task { @MainActor in
            do {
                let tester = TranscriptionConnectionTester(
                    secretLoader: { providerStore.load(for: $0) }
                )
                let record = try await tester.test(
                    connection: candidate,
                    apiKey: apiKey
                )
                guard !Task.isCancelled,
                      connectionTestGeneration == generation,
                      providerDraft?.id == candidate.id else { return }
                providerDraft?.credentialRevision = candidate.credentialRevision
                providerDraft?.lastConnectionTest = record
                switch record.outcome {
                case .succeeded:
                    connectionTestState = .succeeded
                case .failed:
                    connectionTestState = .failed(record.safeSummary)
                }
                connectionTestTask = nil
            } catch is CancellationError {
                guard connectionTestGeneration == generation else { return }
                connectionTestState = .idle
                connectionTestTask = nil
            } catch {
                guard !Task.isCancelled,
                      connectionTestGeneration == generation,
                      providerDraft?.id == candidate.id else { return }
                var testedCandidate = candidate
                testedCandidate.recordConnectionTest(
                    outcome: .failed,
                    safeSummary: error.localizedDescription
                )
                providerDraft?.credentialRevision = testedCandidate.credentialRevision
                providerDraft?.lastConnectionTest = testedCandidate.lastConnectionTest
                connectionTestState = .failed(
                    testedCandidate.lastConnectionTest?.safeSummary
                        ?? UIStrings.connectionTestUnknownFailure
                )
                connectionTestTask = nil
            }
        }
    }

    private func cancelConnectionTest(resetState: Bool) {
        connectionTestGeneration = UUID()
        connectionTestTask?.cancel()
        connectionTestTask = nil
        if resetState {
            connectionTestState = .idle
        }
    }

    private func reconcileComparisonModels() {
        comparisonStore.reconcileAvailableModelSelectors(
            providerStore.availableModelSelectors
        )
    }

    private func addModel() {
        guard modelDrafts.count
                < FlotisConfigurationStore.maximumModelCountPerProvider else {
            return
        }
        let defaultModel = providerDraft?.protocolSchema.defaultModel
            ?? "gpt-4o-mini-transcribe"
        let existing = Set(modelDrafts.map {
            $0.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        var candidate = existing.contains(defaultModel) ? "model-id" : defaultModel
        var suffix = 2
        while existing.contains(candidate) {
            candidate = "model-id-\(suffix)"
            suffix += 1
        }
        modelDrafts.append(EditableProviderModel(modelID: candidate))
        selectedModelID = candidate
        providerDraft?.model = candidate
        markDraftChanged()
    }

    private func removeModel(_ id: UUID) {
        guard modelDrafts.count > 1,
              let index = modelDrafts.firstIndex(where: { $0.id == id }) else {
            return
        }
        let removedModelID = modelDrafts[index].modelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        modelDrafts.remove(at: index)
        if selectedModelID == removedModelID {
            selectedModelID = modelDrafts[0].modelID
                .trimmingCharacters(in: .whitespacesAndNewlines)
            providerDraft?.model = selectedModelID
        }
        markDraftChanged()
    }

    private func modelTitle(_ model: EditableProviderModel) -> String {
        let displayName = model.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return displayName.isEmpty ? model.modelID : displayName
    }

    private func displayName(for provider: SpeechProviderConfig) -> String {
        guard let selectorRaw = provider.configurationModelSelector,
              let selector = FlotisModelSelector(rawValue: selectorRaw),
              let group = providerStore.providerGroup(id: selector.providerID),
              let name = group.configuration.models[selector.modelID]?.name,
              !name.isEmpty else {
            return provider.model
        }
        return name
    }

    private func markDraftChanged() {
        saved = false
        if notice?.kind == .success {
            notice = nil
        }
        cancelConnectionTest(resetState: true)
    }

    @ViewBuilder
    private func inputField(
        _ label: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(FlotisType.caption(12, .semibold))
                .foregroundStyle(FlotisTheme.secondary(colorScheme))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(FlotisType.mono(13))
                .foregroundStyle(FlotisTheme.primary(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .overlay(inputBackground)
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(FlotisTheme.separator(colorScheme), lineWidth: 1)
    }

    private var providerNameBinding: Binding<String> {
        Binding(
            get: { providerDraft?.name ?? "" },
            set: {
                providerDraft?.name = $0
                markDraftChanged()
            }
        )
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { apiKeyInput },
            set: {
                apiKeyInput = $0
                markDraftChanged()
            }
        )
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { selectedModelID },
            set: {
                selectedModelID = $0
                providerDraft?.model = $0
                markDraftChanged()
            }
        )
    }

    private func modelIDBinding(
        _ model: Binding<EditableProviderModel>
    ) -> Binding<String> {
        Binding(
            get: { model.wrappedValue.modelID },
            set: { newValue in
                let oldValue = model.wrappedValue.modelID
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                model.wrappedValue.modelID = newValue
                if selectedModelID == oldValue {
                    selectedModelID = newValue
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    providerDraft?.model = selectedModelID
                }
                markDraftChanged()
            }
        )
    }

    private func modelDisplayNameBinding(
        _ model: Binding<EditableProviderModel>
    ) -> Binding<String> {
        Binding(
            get: { model.wrappedValue.displayName },
            set: {
                model.wrappedValue.displayName = $0
                markDraftChanged()
            }
        )
    }

    private var endpointPathBinding: Binding<String> {
        Binding(
            get: { providerDraft?.endpointPath ?? "" },
            set: {
                providerDraft?.endpointPath = $0
                markDraftChanged()
            }
        )
    }

    private var baseURLBinding: Binding<String> {
        Binding(
            get: { providerDraft?.baseURL ?? "" },
            set: { newValue in
                let oldHost = providerDraft?.credentialDestinationIdentifier
                providerDraft?.baseURL = newValue
                if providerDraft?.credentialDestinationIdentifier != oldHost {
                    providerDraft?.isCustomEndpointApproved = false
                }
                if isOpenRouterHost(providerDraft?.credentialDestinationIdentifier) {
                    providerDraft?.requestEncoding = .jsonBase64
                }
                markDraftChanged()
            }
        )
    }

    private var requestEncodingBinding: Binding<TranscriptionRequestEncoding> {
        Binding(
            get: { providerDraft?.requestEncoding ?? .multipartFormData },
            set: {
                providerDraft?.requestEncoding = $0
                markDraftChanged()
            }
        )
    }

    private var customEndpointApprovalBinding: Binding<Bool> {
        Binding(
            get: { providerDraft?.isCustomEndpointApproved ?? false },
            set: {
                providerDraft?.isCustomEndpointApproved = $0
                markDraftChanged()
            }
        )
    }

    private func optionalStringBinding(
        _ keyPath: WritableKeyPath<SpeechProviderConfig, String?>
    ) -> Binding<String> {
        Binding(
            get: { providerDraft?[keyPath: keyPath] ?? "" },
            set: {
                providerDraft?[keyPath: keyPath] = $0.isEmpty ? nil : $0
                markDraftChanged()
            }
        )
    }

    private func doubleBinding(
        _ keyPath: WritableKeyPath<SpeechProviderConfig, Double?>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = providerDraft?[keyPath: keyPath] else { return "" }
                return "\(value)"
            },
            set: {
                providerDraft?[keyPath: keyPath] = Double($0)
                markDraftChanged()
            }
        )
    }

    private func isOpenRouterHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "openrouter.ai" || host.hasSuffix(".openrouter.ai")
    }
}
