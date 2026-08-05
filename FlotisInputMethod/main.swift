import AppKit
import InputMethodKit

let application = NSApplication.shared

guard let connectionName = Bundle.main.object(
    forInfoDictionaryKey: "InputMethodConnectionName"
) as? String,
    !connectionName.isEmpty
else {
    fatalError("FlotisInputMethod is missing InputMethodConnectionName")
}

guard let bundleIdentifier = Bundle.main.bundleIdentifier,
      !bundleIdentifier.isEmpty
else {
    fatalError("FlotisInputMethod is missing CFBundleIdentifier")
}

let inputMethodServer = IMKServer(
    name: connectionName,
    bundleIdentifier: bundleIdentifier
)

withExtendedLifetime(inputMethodServer) {
    application.run()
}
