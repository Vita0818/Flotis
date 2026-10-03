import SwiftUI

private enum QuickAskProviderEditorMode: Equatable {
    case add
    case edit(String)
}

private enum QuickAskProviderNoticeKind {
    case information
    case success
    case warning
    case error
}

private struct QuickAskProviderNotice {
    let kind: QuickAskProviderNoticeKind
    let text: String
}

private enum QuickAskProviderTestState: Equatable {
    case idle
    case testing
    case succeeded
    case failed(String)
}

private struct EditableQuickAskModel: Identifiable, Equatable {
    let id: UUID
    var modelID: String
    var displayName: String

    init(id: UUID = UUID(), modelID: String, displayName: String = "") {
        self.id = id
        self.modelID = modelID
        self.displayName = displayName
    }
}

private struct QuickAskProviderSettingsLayout {
    let rawWidth: CGFloat

    private var width: CGFloat { max(rawWidth, 1) }
    var isCompact: Bool { width < 700 }
    var usesColumns: Bool { width >= 760 }
    var horizontalPadding: CGFloat { width < 700 ? 20 : 28 }
    var cardMaxWidth: CGFloat { 820 }
    var providerListWidth: CGFloat { min(220, max(176, width * 0.30)) }
}

private struct QuickAskProviderDisclosure<Label: View, Content: View>: View {
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
                    label.frame(maxWidth: .infinity, alignment: .leading)
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

            if isExpanded { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Quick Ask mirrors the transcription Provider/Models workflow while keeping
/// chat-specific fields and its canonical catalog completely separate.
struct IntatisStyleQuickAskProviderSettingsView: View {
    @ObservedObject var store: QuickAskConfigurationStore
    let client: QuickAskClient
    let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedProviderID: String?
    @State private var editorMode: QuickAskProviderEditorMode?
    @State private var providerName = ""
    @State private var optionsDraft = QuickAskProviderOptions.defaults
    @State private var modelDrafts: [EditableQuickAskModel] = []
    @State private var selectedModelID = ""
    @State private var apiKeyInput = ""
    @State private var notice: QuickAskProviderNotice?
    @State private var saved = false
    @State private var isConnectionExpanded = false
    @State private var isModelsExpanded = false
    @State private var isAdvancedExpanded = false
    @State private var showsDeleteProviderConfirmation = false
    @State private var testState: QuickAskProviderTestState = .idle
    @State private var testGeneration = UUID()
    @State private var testTask: Task<Void, Never>?

    private var providerGroups: [QuickAskProviderGroup] { store.providerGroups }

    private var preferredProviderID: String? {
        FlotisModelSelector(rawValue: store.activeModelSelector)?.providerID
            ?? providerGroups.first?.id
    }

    private var persistedSelectedGroup: QuickAskProviderGroup? {
        guard let selectedProviderID else { return nil }
        return store.providerGroup(id: selectedProviderID)
    }

    private var existingProviderID: String? {
        guard case .edit(let providerID) = editorMode else { return nil }
        return providerID
    }

    private var normalizedModels: [(id: String, name: String)]? {
        var seen = Set<String>()
        let values = modelDrafts.compactMap { model -> (id: String, name: String)? in
            let modelID = model.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlotisModelSelector.isValidModelID(modelID),
                  seen.insert(modelID).inserted else { return nil }
            return (
                id: modelID,
                name: model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard values.count == modelDrafts.count, !values.isEmpty else { return nil }
        return values
    }

    private var selectableModels: [EditableQuickAskModel] {
        var seen = Set<String>()
        return modelDrafts.compactMap { model in
            var value = model
            value.modelID = value.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.modelID.isEmpty, seen.insert(value.modelID).inserted else {
                return nil
            }
            return value
        }
    }

    private var hasSavedAPIKey: Bool {
        existingProviderID.map(store.hasAPIKey(providerID:)) == true
    }

    private var draftMatchesPersistedCredentialBoundary: Bool {
        guard let existingProviderID,
              let persisted = store.providerGroup(id: existingProviderID) else {
            return false
        }
        return persisted.configuration.options.credentialBoundaryIdentifier
            == optionsDraft.credentialBoundaryIdentifier
    }

    private var canClearSavedAPIKey: Bool {
        hasSavedAPIKey && draftMatchesPersistedCredentialBoundary
    }

    private var hasUnsavedDraftChanges: Bool {
        guard editorMode != nil else { return false }
        if editorMode == .add { return true }
        guard let persisted = persistedSelectedGroup else { return true }
        var persistedOptions = persisted.configuration.options
        persistedOptions.apiKey = nil
        let draftModels = modelDrafts.map {
            "\($0.modelID.trimmingCharacters(in: .whitespacesAndNewlines))\u{1f}\($0.displayName.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        let persistedModels = persisted.modelIDs.map { modelID in
            "\(modelID)\u{1f}\(persisted.configuration.models[modelID]?.name ?? "")"
        }
        let persistedSelectedModel = preferredModelID(for: persisted)
        return providerName != persisted.name
            || optionsDraft != persistedOptions
            || draftModels != persistedModels
            || selectedModelID != persistedSelectedModel
            || !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            settingsContent(layout: QuickAskProviderSettingsLayout(rawWidth: proxy.size.width))
        }
        .onAppear {
            selectedProviderID = preferredProviderID
            loadProviderDraft()
        }
        .onChange(of: selectedProviderID) { newProviderID in
            guard editorMode != .add else { return }
            if case .edit(let editingID) = editorMode,
               editingID == newProviderID {
                return
            }
            loadProviderDraft()
        }
        .onChange(of: store.catalog) { _ in
            guard editorMode != .add else { return }
            if selectedProviderID == nil { selectedProviderID = preferredProviderID }
        }
        .onChange(of: isActive) { active in
            if !active { cancelTest(resetState: true) }
        }
        .onDisappear { cancelTest(resetState: true) }
        .alert(
            UIStrings.quickAskDeleteProviderTitle,
            isPresented: $showsDeleteProviderConfirmation
        ) {
            Button(UIStrings.cancel, role: .cancel) {}
            Button(UIStrings.delete, role: .destructive, action: deleteSelectedProvider)
        } message: {
            Text(UIStrings.quickAskDeleteProviderMessage)
        }
    }

    private func settingsContent(layout: QuickAskProviderSettingsLayout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsCard(layout: layout)

                if let notice {
                    providerNotice(notice)
                        .frame(maxWidth: layout.cardMaxWidth, alignment: .leading)
                }

                testSummary.frame(maxWidth: layout.cardMaxWidth, alignment: .leading)
                settingsActions(layout: layout)
                advancedSettings(layout: layout)

                VStack(alignment: .leading, spacing: 8) {
                    Text(UIStrings.quickAskPrivacyNotice)
                    Text(UIStrings.quickAskTestRequestNotice)
                }
                .font(FlotisType.caption(11, .regular))
                .foregroundStyle(FlotisTheme.secondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: layout.cardMaxWidth, alignment: .leading)

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
    private func settingsCard(layout: QuickAskProviderSettingsLayout) -> some View {
        if layout.usesColumns {
            HStack(alignment: .top, spacing: 18) {
                providerList.frame(width: layout.providerListWidth, alignment: .topLeading)
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
                .help(UIStrings.quickAskAddProvider)
            }

            VStack(spacing: 8) {
                ForEach(providerGroups) { group in providerRow(group) }
                if editorMode == .add {
                    providerRowLabel(
                        title: providerName,
                        modelCount: max(1, modelDrafts.count),
                        selected: true
                    )
                }
            }
        }
    }

    private func providerRow(_ group: QuickAskProviderGroup) -> some View {
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
                        selected ? Color.accentColor : FlotisTheme.tertiary(colorScheme)
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
    private func providerDetail(layout: QuickAskProviderSettingsLayout) -> some View {
        if editorMode != nil {
            VStack(alignment: .leading, spacing: 16) {
                inputField(
                    UIStrings.connectionName,
                    text: $providerName,
                    placeholder: "OpenRouter"
                )
                apiKeyField
                activeModelPicker(layout: layout)
                connectionSettings
                modelsSettings(layout: layout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(UIStrings.quickAskAddProviderToConfigure)
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
            SecureField(
                hasSavedAPIKey ? UIStrings.apiKeySavedPlaceholder : UIStrings.quickAskAPIKeyOptional,
                text: $apiKeyInput
            )
            .textFieldStyle(.plain)
            .font(FlotisType.mono(13))
            .foregroundStyle(FlotisTheme.primary(colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .overlay(inputBackground)
        }
    }

    private func activeModelPicker(layout: QuickAskProviderSettingsLayout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(UIStrings.activeModel)
                .font(FlotisType.caption(12, .semibold))
                .foregroundStyle(FlotisTheme.secondary(colorScheme))
            Picker("", selection: $selectedModelID) {
                ForEach(selectableModels) { model in
                    Text(modelTitle(model)).tag(model.modelID)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(selectableModels.isEmpty)
            .frame(maxWidth: layout.usesColumns ? 280 : .infinity, alignment: .leading)
        }
    }

    private var connectionSettings: some View {
        QuickAskProviderDisclosure(
            isExpanded: $isConnectionExpanded,
            accessibilityIdentifier: "settings.quickAsk.connection"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                inputField(
                    UIStrings.baseURL,
                    text: $optionsDraft.baseURL,
                    placeholder: "https://openrouter.ai/api/v1"
                )
                inputField(
                    UIStrings.endpointPath,
                    text: $optionsDraft.path,
                    placeholder: "/chat/completions"
                )

                let runtime = optionsDraft.runtimeConfiguration(modelID: selectedModelID)
                if let host = runtime.destinationHost {
                    Text(UIStrings.quickAskCredentialDestination(host))
                        .font(FlotisType.caption(11, .medium))
                        .foregroundStyle(FlotisTheme.secondary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    if QuickAskEndpointResolver.requiresCustomHostApproval(for: runtime) {
                        Toggle(isOn: $optionsDraft.customEndpointApproved) {
                            Text(UIStrings.quickAskApproveCustomHost)
                                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .toggleStyle(.checkbox)
                        .foregroundStyle(.orange)
                    }
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
            .padding(.top, 10)
        } label: {
            Text(UIStrings.connection)
                .font(FlotisType.body(13, .semibold))
                .foregroundStyle(FlotisTheme.primary(colorScheme))
        }
    }

    private func modelsSettings(layout: QuickAskProviderSettingsLayout) -> some View {
        QuickAskProviderDisclosure(
            isExpanded: $isModelsExpanded,
            accessibilityIdentifier: "settings.quickAsk.models"
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
                        modelDrafts.count >= FlotisConfigurationStore.maximumModelCountPerProvider
                    )
                }

                ForEach($modelDrafts) { model in
                    modelEditorRow(model: model, layout: layout)
                }

                if editorMode != .add {
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            showsDeleteProviderConfirmation = true
                        } label: {
                            Label(UIStrings.deleteProvider, systemImage: "trash")
                                .font(FlotisType.caption(12, .semibold))
                        }
                        .buttonStyle(.borderless)
                    }
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
        model: Binding<EditableQuickAskModel>,
        layout: QuickAskProviderSettingsLayout
    ) -> some View {
        if layout.usesColumns {
            HStack(spacing: 8) {
                inputField(
                    UIStrings.modelID,
                    text: modelIDBinding(model),
                    placeholder: "provider/chat-model"
                )
                inputField(
                    UIStrings.modelDisplayName,
                    text: modelDisplayNameBinding(model),
                    placeholder: UIStrings.quickAskDisplayNamePlaceholder
                )
                removeModelButton(model.wrappedValue.id).padding(.top, 20)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                inputField(
                    UIStrings.modelID,
                    text: modelIDBinding(model),
                    placeholder: "provider/chat-model"
                )
                inputField(
                    UIStrings.modelDisplayName,
                    text: modelDisplayNameBinding(model),
                    placeholder: UIStrings.quickAskDisplayNamePlaceholder
                )
                HStack { Spacer(); removeModelButton(model.wrappedValue.id) }
            }
        }
    }

    private func removeModelButton(_ id: UUID) -> some View {
        Button(action: { removeModel(id) }) {
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
    private func settingsActions(layout: QuickAskProviderSettingsLayout) -> some View {
        if layout.isCompact {
            VStack(alignment: .trailing, spacing: 10) {
                savedLabel.frame(maxWidth: .infinity, alignment: .leading)
                HStack { Spacer(); cancelButton; testButton; saveButton }
            }
            .frame(maxWidth: layout.cardMaxWidth)
        } else {
            HStack { savedLabel; Spacer(); cancelButton; testButton; saveButton }
                .frame(maxWidth: layout.cardMaxWidth)
        }
    }

    @ViewBuilder private var savedLabel: some View {
        if saved, !hasUnsavedDraftChanges {
            Label(UIStrings.saved, systemImage: "checkmark.circle.fill")
                .font(FlotisType.caption(12, .semibold))
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder private var cancelButton: some View {
        if hasUnsavedDraftChanges {
            Button(UIStrings.cancel, action: cancelDraft)
                .font(FlotisType.body(14, .semibold))
                .flotisGlassButton()
        }
    }

    private var testButton: some View {
        Button(action: testDraft) {
            Label(
                testState == .testing ? UIStrings.testingConnection : UIStrings.testProvider,
                systemImage: testState == .testing ? "hourglass" : "checkmark.seal"
            )
            .font(FlotisType.body(14, .semibold))
        }
        .flotisGlassButton()
        .disabled(testState == .testing || !canUseDraft)
        .help(UIStrings.quickAskTestRequestNotice)
    }

    private var saveButton: some View {
        Button(UIStrings.save, action: saveDraft)
            .font(FlotisType.body(14, .semibold))
            .flotisGlassButton(prominent: true)
            .disabled(editorMode == nil || testState == .testing)
    }

    @ViewBuilder private var testSummary: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            Label(UIStrings.testingConnection, systemImage: "hourglass")
                .font(FlotisType.caption(12, .semibold))
                .foregroundStyle(FlotisTheme.secondary(colorScheme))
        case .succeeded:
            Label(UIStrings.connectionTestSucceeded, systemImage: "checkmark.circle.fill")
                .font(FlotisType.caption(12, .semibold))
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(FlotisType.caption(12, .semibold))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func advancedSettings(layout: QuickAskProviderSettingsLayout) -> some View {
        if editorMode != nil {
            VStack(alignment: .leading, spacing: 12) {
                Divider().opacity(0.45)
                QuickAskProviderDisclosure(
                    isExpanded: $isAdvancedExpanded,
                    accessibilityIdentifier: "settings.quickAsk.advanced"
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Text(UIStrings.quickAskTemperature)
                            Slider(value: $optionsDraft.temperature, in: 0 ... 2, step: 0.1)
                            Text(String(format: "%.1f", optionsDraft.temperature))
                                .font(FlotisType.mono(12, .medium))
                                .frame(width: 36, alignment: .trailing)
                        }
                        Stepper(
                            value: $optionsDraft.maxTokens,
                            in: 64 ... 32_768,
                            step: 64
                        ) {
                            Text(UIStrings.quickAskMaxTokens(optionsDraft.maxTokens))
                        }
                        Stepper(
                            value: $optionsDraft.timeoutSeconds,
                            in: 5 ... 600,
                            step: 5
                        ) {
                            Text(UIStrings.quickAskTimeout(optionsDraft.timeoutSeconds))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(UIStrings.quickAskSystemPrompt)
                                .font(FlotisType.caption(12, .semibold))
                                .foregroundStyle(FlotisTheme.secondary(colorScheme))
                            TextEditor(text: $optionsDraft.systemPrompt)
                                .font(FlotisType.body(12, .regular))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 96)
                                .padding(8)
                                .overlay(inputBackground)
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

    private var canUseDraft: Bool {
        guard let modelID = selectableModels.first(where: {
            $0.modelID == selectedModelID
        })?.modelID else { return false }
        return store.draftRuntimeConfiguration(
            existingProviderID: existingProviderID,
            providerName: providerName,
            options: optionsDraft,
            modelID: modelID,
            apiKeyInput: apiKeyInput
        ).validationError() == nil
    }

    private func loadProviderDraft() {
        cancelTest(resetState: true)
        guard let selectedProviderID,
              let group = store.providerGroup(id: selectedProviderID) else {
            if editorMode != .add { resetEditor() }
            return
        }
        editorMode = .edit(selectedProviderID)
        providerName = group.name
        optionsDraft = group.configuration.options
        optionsDraft.apiKey = nil
        modelDrafts = group.modelIDs.map { modelID in
            EditableQuickAskModel(
                modelID: modelID,
                displayName: group.configuration.models[modelID]?.name ?? ""
            )
        }
        selectedModelID = preferredModelID(for: group)
        apiKeyInput = ""
        notice = nil
        saved = false
        isConnectionExpanded = false
        isModelsExpanded = false
        isAdvancedExpanded = false
    }

    private func preferredModelID(for group: QuickAskProviderGroup) -> String {
        if let selector = FlotisModelSelector(rawValue: store.activeModelSelector),
           selector.providerID == group.id,
           group.modelIDs.contains(selector.modelID) {
            return selector.modelID
        }
        return group.modelIDs.first ?? ""
    }

    private func beginAddingProvider() {
        cancelTest(resetState: true)
        selectedProviderID = nil
        editorMode = .add
        providerName = providerGroups.isEmpty
            ? UIStrings.quickAskNewProviderName
            : "\(UIStrings.quickAskNewProviderName) \(providerGroups.count + 1)"
        optionsDraft = .defaults
        modelDrafts = [EditableQuickAskModel(modelID: "")]
        selectedModelID = ""
        apiKeyInput = ""
        notice = nil
        saved = false
        isConnectionExpanded = false
        isModelsExpanded = true
        isAdvancedExpanded = false
    }

    private func cancelDraft() {
        if editorMode == .add { selectedProviderID = preferredProviderID }
        loadProviderDraft()
    }

    private func saveDraft() {
        guard let models = normalizedModels,
              models.contains(where: { $0.id == selectedModelID }) else {
            notice = QuickAskProviderNotice(kind: .error, text: UIStrings.quickAskModelsRequired)
            return
        }
        let oldBoundary = existingProviderID.flatMap {
            store.providerGroup(id: $0)?.configuration.options.credentialBoundaryIdentifier
        }
        let hadSavedKey = existingProviderID.map(store.hasAPIKey(providerID:)) == true
        let submittedReplacementKey = !apiKeyInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let providerID = store.saveProviderGroup(
            existingProviderID: existingProviderID,
            name: providerName,
            options: optionsDraft,
            modelIDs: models.map(\.id),
            modelDisplayNames: Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0.name) }),
            selectedModelID: selectedModelID,
            savingAPIKey: apiKeyInput
        )
        guard let providerID else {
            notice = QuickAskProviderNotice(
                kind: .error,
                text: store.lastError ?? UIStrings.quickAskConfigurationSaveFailed
            )
            return
        }
        let boundaryChanged = oldBoundary != nil
            && oldBoundary != optionsDraft.credentialBoundaryIdentifier
        selectedProviderID = providerID
        editorMode = .edit(providerID)
        loadProviderDraft()
        saved = true
        notice = QuickAskProviderNotice(
            kind: boundaryChanged && hadSavedKey
                && !submittedReplacementKey
                ? .warning
                : .success,
            text: boundaryChanged && hadSavedKey
                && !submittedReplacementKey
                ? UIStrings.quickAskCredentialClearedForNewHost
                : UIStrings.quickAskProviderSaved
        )
    }

    private func deleteSelectedProvider() {
        guard let providerID = existingProviderID else { return }
        guard store.deleteProviderGroup(id: providerID) else {
            notice = QuickAskProviderNotice(
                kind: .error,
                text: store.lastError ?? UIStrings.quickAskProviderNotFound
            )
            return
        }
        selectedProviderID = preferredProviderID
        if selectedProviderID == nil { resetEditor() } else { loadProviderDraft() }
        notice = QuickAskProviderNotice(kind: .success, text: UIStrings.quickAskProviderDeleted)
    }

    private func clearSelectedAPIKey() {
        guard let providerID = existingProviderID else { return }
        guard store.clearAPIKey(providerID: providerID) else {
            notice = QuickAskProviderNotice(
                kind: .error,
                text: store.lastError ?? UIStrings.apiKeyClearFailed
            )
            return
        }
        apiKeyInput = ""
        notice = QuickAskProviderNotice(kind: .success, text: UIStrings.quickAskAPIKeyCleared)
    }

    private func testDraft() {
        guard canUseDraft else {
            notice = QuickAskProviderNotice(kind: .error, text: UIStrings.quickAskConfigurationSaveFailed)
            return
        }
        cancelTest(resetState: false)
        let generation = UUID()
        testGeneration = generation
        testState = .testing
        notice = nil
        let snapshot = store.draftRuntimeConfiguration(
            existingProviderID: existingProviderID,
            providerName: providerName,
            options: optionsDraft,
            modelID: selectedModelID,
            apiKeyInput: apiKeyInput
        )
        testTask = Task {
            let result = await client.testConnection(configuration: snapshot)
            guard !Task.isCancelled, generation == testGeneration else { return }
            store.noteConnectionTest(result)
            switch result.status {
            case .ready:
                testState = .succeeded
            case .missingModel, .connectionFailed, .requestTimeout:
                testState = .failed(result.detail)
            }
            testTask = nil
        }
    }

    private func cancelTest(resetState: Bool) {
        testGeneration = UUID()
        testTask?.cancel()
        testTask = nil
        if resetState { testState = .idle }
    }

    private func addModel() {
        guard modelDrafts.count < FlotisConfigurationStore.maximumModelCountPerProvider else {
            return
        }
        modelDrafts.append(EditableQuickAskModel(modelID: ""))
    }

    private func removeModel(_ id: UUID) {
        guard modelDrafts.count > 1 else { return }
        let removed = modelDrafts.first(where: { $0.id == id })?.modelID
        modelDrafts.removeAll { $0.id == id }
        if selectedModelID == removed || !modelDrafts.contains(where: {
            $0.modelID == selectedModelID
        }) {
            selectedModelID = selectableModels.first?.modelID ?? ""
        }
    }

    private func resetEditor() {
        cancelTest(resetState: true)
        editorMode = nil
        providerName = ""
        optionsDraft = .defaults
        modelDrafts = []
        selectedModelID = ""
        apiKeyInput = ""
        saved = false
        isConnectionExpanded = false
        isModelsExpanded = false
        isAdvancedExpanded = false
    }

    private func modelTitle(_ model: EditableQuickAskModel) -> String {
        let name = model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? model.modelID : name
    }

    private func modelIDBinding(
        _ model: Binding<EditableQuickAskModel>
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
                }
                saved = false
                notice = nil
            }
        )
    }

    private func modelDisplayNameBinding(
        _ model: Binding<EditableQuickAskModel>
    ) -> Binding<String> {
        Binding(
            get: { model.wrappedValue.displayName },
            set: {
                model.wrappedValue.displayName = $0
                saved = false
                notice = nil
            }
        )
    }

    private func providerNotice(_ notice: QuickAskProviderNotice) -> some View {
        Label(notice.text, systemImage: noticeSystemImage(notice.kind))
            .font(FlotisType.caption(12, .medium))
            .foregroundStyle(noticeColor(notice.kind))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func noticeColor(_ kind: QuickAskProviderNoticeKind) -> Color {
        switch kind {
        case .information: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func noticeSystemImage(_ kind: QuickAskProviderNoticeKind) -> String {
        switch kind {
        case .information: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(FlotisTheme.separator(colorScheme), lineWidth: 1)
    }
}
