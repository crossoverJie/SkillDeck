import SwiftUI

private struct AppFontFamilyKey: EnvironmentKey {
    static let defaultValue = FontSettings.systemFontFamily
}

private struct AppFontBaseSizeKey: EnvironmentKey {
    static let defaultValue = FontSettings.defaultFontSize
}

extension EnvironmentValues {
    var appFontFamily: String {
        get { self[AppFontFamilyKey.self] }
        set { self[AppFontFamilyKey.self] = newValue }
    }

    var appFontBaseSize: Double {
        get { self[AppFontBaseSizeKey.self] }
        set { self[AppFontBaseSizeKey.self] = newValue }
    }
}

private struct AppFontStyleModifier: ViewModifier {
    @Environment(\.appFontFamily) private var family
    @Environment(\.appFontBaseSize) private var baseSize

    let textStyle: Font.TextStyle
    let design: Font.Design?

    func body(content: Content) -> some View {
        content.font(FontSettings.font(family: family, baseSize: baseSize, textStyle: textStyle, design: design))
    }
}

extension View {
    func appFont(_ textStyle: Font.TextStyle, design: Font.Design? = nil) -> some View {
        modifier(AppFontStyleModifier(textStyle: textStyle, design: design))
    }
}
