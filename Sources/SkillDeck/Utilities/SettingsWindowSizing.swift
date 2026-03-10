import SwiftUI

/// SettingsWindowSizing defines the minimum settings window size based on font size.
///
/// Using an enum as a namespace matches the project's utility style and prevents instantiation.
enum SettingsWindowSizing {
    /// Base dimensions for the settings window at the default font size.
    static let baseWidth: CGFloat = 450
    static let baseHeight: CGFloat = 350
    static let baseFontSize: CGFloat = 13

    /// Calculate the minimum window size for a given font size.
    ///
    /// The size only scales up: values below the base font size clamp to the base dimensions.
    static func minSize(forFontSize fontSize: Double) -> CGSize {
        let size = max(CGFloat(fontSize), baseFontSize)
        let scale = size / baseFontSize
        return CGSize(width: baseWidth * scale, height: baseHeight * scale)
    }
}
