import Combine
import Foundation

enum ConfigurableHotkey: String, CaseIterable, Identifiable {
    case togglePanel
    case previousComparisonResult
    case nextComparisonResult

    var id: String { rawValue }

    var defaultDescriptor: KeyboardShortcutDescriptor {
        switch self {
        case .togglePanel:
            return .togglePanel
        case .previousComparisonResult:
            return .previousComparisonResult
        case .nextComparisonResult:
            return .nextComparisonResult
        }
    }

    var displayName: String {
        switch self {
        case .togglePanel:
            return UIStrings.showHideFloatingPanel
        case .previousComparisonResult:
            return UIStrings.previousComparisonResult
        case .nextComparisonResult:
            return UIStrings.nextComparisonResult
        }
    }
}

struct FlotisHotkeyConfiguration: Codable, Equatable {
    var togglePanel: KeyboardShortcutDescriptor
    var previousComparisonResult: KeyboardShortcutDescriptor
    var nextComparisonResult: KeyboardShortcutDescriptor

    static let defaults = FlotisHotkeyConfiguration(
        togglePanel: .togglePanel,
        previousComparisonResult: .previousComparisonResult,
        nextComparisonResult: .nextComparisonResult
    )

    init(
        togglePanel: KeyboardShortcutDescriptor,
        previousComparisonResult: KeyboardShortcutDescriptor,
        nextComparisonResult: KeyboardShortcutDescriptor
    ) {
        self.togglePanel = togglePanel
        self.previousComparisonResult = previousComparisonResult
        self.nextComparisonResult = nextComparisonResult
    }

    private enum CodingKeys: String, CodingKey {
        case togglePanel = "toggle_panel"
        case previousComparisonResult = "previous_comparison_result"
        case nextComparisonResult = "next_comparison_result"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        togglePanel = try container.decodeIfPresent(
            KeyboardShortcutDescriptor.self,
            forKey: .togglePanel
        ) ?? Self.defaults.togglePanel
        previousComparisonResult = try container.decodeIfPresent(
            KeyboardShortcutDescriptor.self,
            forKey: .previousComparisonResult
        ) ?? Self.defaults.previousComparisonResult
        nextComparisonResult = try container.decodeIfPresent(
            KeyboardShortcutDescriptor.self,
            forKey: .nextComparisonResult
        ) ?? Self.defaults.nextComparisonResult
    }

    subscript(hotkey: ConfigurableHotkey) -> KeyboardShortcutDescriptor {
        get {
            switch hotkey {
            case .togglePanel:
                return togglePanel
            case .previousComparisonResult:
                return previousComparisonResult
            case .nextComparisonResult:
                return nextComparisonResult
            }
        }
        set {
            switch hotkey {
            case .togglePanel:
                togglePanel = newValue
            case .previousComparisonResult:
                previousComparisonResult = newValue
            case .nextComparisonResult:
                nextComparisonResult = newValue
            }
        }
    }

    var isValid: Bool {
        let descriptors = ConfigurableHotkey.allCases.map { self[$0] }
        return descriptors.allSatisfy(\.modifiers.hasAnyModifier)
            && !descriptors.contains(.toggleVoice)
            && Set(descriptors).count == descriptors.count
    }
}

final class HotkeyConfigurationStore: ObservableObject {
    static let shared = HotkeyConfigurationStore()

    @Published private(set) var configuration: FlotisHotkeyConfiguration
    @Published private(set) var lastError: String?

    private let configurationStore: FlotisConfigurationStore

    init(configurationStore: FlotisConfigurationStore = .shared) {
        self.configurationStore = configurationStore

        switch configurationStore.load() {
        case .loaded(let document):
            configuration = document.shortcuts ?? .defaults
            lastError = nil
            if document.shortcuts == nil {
                let initialConfiguration = configuration
                let didSave = configurationStore.update { document in
                    document.replaceShortcuts(initialConfiguration)
                }
                if !didSave {
                    lastError = UIStrings.hotkeyConfigurationSaveFailed
                }
            }
        case .missing:
            configuration = .defaults
            let initialConfiguration = configuration
            let didSave = configurationStore.update { document in
                document.replaceShortcuts(initialConfiguration)
            }
            lastError = didSave ? nil : UIStrings.hotkeyConfigurationSaveFailed
        case .unavailable:
            configuration = .defaults
            lastError = UIStrings.hotkeyConfigurationUnavailable
        }
    }

    func validationError(
        for descriptor: KeyboardShortcutDescriptor,
        hotkey: ConfigurableHotkey
    ) -> String? {
        guard descriptor.modifiers.hasAnyModifier else {
            return UIStrings.hotkeyRequiresModifier
        }

        if descriptor == .toggleVoice {
            return UIStrings.hotkeyConflictsWithVoiceInput
        }

        if let conflictingHotkey = ConfigurableHotkey.allCases.first(where: {
            $0 != hotkey && configuration[$0] == descriptor
        }) {
            return UIStrings.hotkeyAlreadyUsed(by: conflictingHotkey.displayName)
        }

        return nil
    }

    @discardableResult
    func setShortcut(
        _ descriptor: KeyboardShortcutDescriptor,
        for hotkey: ConfigurableHotkey
    ) -> Bool {
        if let message = validationError(for: descriptor, hotkey: hotkey) {
            lastError = message
            return false
        }

        var updated = configuration
        updated[hotkey] = descriptor
        return persist(updated)
    }

    @discardableResult
    func resetShortcut(_ hotkey: ConfigurableHotkey) -> Bool {
        setShortcut(hotkey.defaultDescriptor, for: hotkey)
    }

    @discardableResult
    func resetToDefaults() -> Bool {
        persist(.defaults)
    }

    @discardableResult
    private func persist(_ candidate: FlotisHotkeyConfiguration) -> Bool {
        guard candidate.isValid else {
            lastError = UIStrings.hotkeyConfigurationInvalid
            return false
        }

        let didSave = configurationStore.update { document in
            document.replaceShortcuts(candidate)
        }
        guard didSave else {
            lastError = UIStrings.hotkeyConfigurationSaveFailed
            return false
        }

        configuration = candidate
        lastError = nil
        return true
    }
}
