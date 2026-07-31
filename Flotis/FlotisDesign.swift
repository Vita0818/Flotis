import AppKit
import SwiftUI

// MARK: - Dynamic system palette

enum FlotisTheme {
    static func primary(_: ColorScheme) -> Color { .primary }
    static func secondary(_: ColorScheme) -> Color { .secondary }
    static func tertiary(_: ColorScheme) -> Color { .secondary.opacity(0.72) }

    /// Flotis keeps its main actions monochrome. Semantic state colors remain
    /// reserved for recording, warnings, success, and failure.
    static func action(_: ColorScheme) -> Color { .primary }

    static func separator(_: ColorScheme) -> Color {
        Color(nsColor: .separatorColor)
    }
}

// MARK: - System canvas

struct FlotisSystemCanvas: View {
    @ViewBuilder var body: some View {
        if #available(macOS 14.0, *) {
            Rectangle().fill(.windowBackground)
        } else {
            FlotisLegacyWindowBackground()
        }
    }
}

private struct FlotisLegacyWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .windowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Typography

enum FlotisType {
    static func brand(
        _ size: CGFloat = 30,
        _ weight: Font.Weight = .semibold
    ) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func largeTitle(
        for text: String,
        _ size: CGFloat = 30,
        _ weight: Font.Weight = .semibold
    ) -> Font {
        displayFont(for: text, size: size, weight: weight)
    }

    static func title(
        for text: String,
        _ size: CGFloat = 20,
        _ weight: Font.Weight = .semibold
    ) -> Font {
        displayFont(for: text, size: size, weight: weight)
    }

    static func headline(
        _ size: CGFloat = 16,
        _ weight: Font.Weight = .semibold
    ) -> Font {
        .system(size: size, weight: weight)
    }

    static func body(
        _ size: CGFloat = 14,
        _ weight: Font.Weight = .regular
    ) -> Font {
        .system(size: size, weight: weight)
    }

    static func caption(
        _ size: CGFloat = 12,
        _ weight: Font.Weight = .medium
    ) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(
        _ size: CGFloat = 13,
        _ weight: Font.Weight = .regular
    ) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static func displayFont(
        for text: String,
        size: CGFloat,
        weight: Font.Weight
    ) -> Font {
        .system(
            size: size,
            weight: weight,
            design: containsChineseText(text) ? .default : .serif
        )
    }

    private static func containsChineseText(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x2FDF,
                 0x3000...0x303F,
                 0x31C0...0x31EF,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x20000...0x2FA1F:
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Native content and control surfaces

private struct FlotisContentSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(.regularMaterial, in: shape)
            .overlay {
                shape.stroke(FlotisTheme.separator(colorScheme), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct FlotisLiquidGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let isInteractive: Bool

    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(
                isInteractive ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(.regularMaterial, in: shape)
            .overlay {
                shape.stroke(FlotisTheme.separator(colorScheme), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct FlotisGlassButtonModifier: ViewModifier {
    let isProminent: Bool

    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if isProminent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    @ViewBuilder private func fallback(_ content: Content) -> some View {
        if isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct FlotisCircularButtonBorderModifier: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.buttonBorderShape(.circle)
        } else {
            content.buttonBorderShape(.roundedRectangle)
        }
    }
}

extension View {
    func flotisContentSurface(cornerRadius: CGFloat = 22) -> some View {
        modifier(FlotisContentSurfaceModifier(cornerRadius: cornerRadius))
    }

    func flotisLiquidGlass(
        cornerRadius: CGFloat = 18,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            FlotisLiquidGlassModifier(
                cornerRadius: cornerRadius,
                isInteractive: isInteractive
            )
        )
    }

    func flotisGlassButton(prominent: Bool = false) -> some View {
        modifier(FlotisGlassButtonModifier(isProminent: prominent))
    }

    func flotisCircularButtonBorder() -> some View {
        modifier(FlotisCircularButtonBorderModifier())
    }
}

// MARK: - Shared settings composition

struct FlotisPageHeader: View {
    let title: String
    var subtitle: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FlotisType.largeTitle(for: title))
                .foregroundStyle(FlotisTheme.primary(colorScheme))

            if let subtitle {
                Text(subtitle)
                    .font(FlotisType.caption(13))
                    .foregroundStyle(FlotisTheme.secondary(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FlotisSettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: Content

    init(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(FlotisType.headline())

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flotisContentSurface(cornerRadius: 18)
    }
}
