import SwiftUI

// MARK: - Date Formatting Extension

extension String {
    /// 将 ISO 8601 时间字符串转为可读格式
    /// 例如 "2026-02-07T08:07:27.280Z" → "Feb 7, 2026"
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
    /// 获取 ~ 缩写的路径显示（更短更友好）
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
    /// 条件修饰器：类似三元表达式，但用于 SwiftUI modifier chain
    /// 用法：.if(condition) { view in view.foregroundColor(.red) }
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
