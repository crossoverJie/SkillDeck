import SwiftUI

// MARK: - Date Formatting Extension

extension String {
    /// Converts ISO 8601 timestamp string to a human-readable format
    /// Example: "2026-02-07T08:07:27.280Z" → "Feb 7, 2026"
    var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: self) else { return self }
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

// MARK: - URL Extension

extension URL {
    /// Gets the tilde-abbreviated path display (shorter and more user-friendly)
    var tildeAbbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - View Extension

extension View {
    /// Conditional modifier: similar to a ternary expression, but for SwiftUI modifier chains
    /// Usage: .if(condition) { view in view.foregroundColor(.red) }
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
