import Combine
import Foundation

final class AppState: ObservableObject {
    @Published var hasAccessibilityPermission: Bool = false
    @Published var isPanelVisible: Bool = true
    @Published var pasteError: String? = nil
    
    func checkAccessibility() {
        self.hasAccessibilityPermission = AccessibilityPermission.check()
    }
}
