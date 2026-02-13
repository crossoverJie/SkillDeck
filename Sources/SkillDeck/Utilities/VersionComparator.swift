import Foundation

/// VersionComparator 是版本号比较的工具枚举（命名空间模式）
///
/// 使用 enum 而非 struct/class 作为命名空间，因为没有 case 的 enum 无法被实例化，
/// 只能通过静态方法访问，语义上更清晰（类似 Java 的 final class + private constructor）。
/// 与 Constants.swift 中的 Constants 枚举保持一致的命名空间模式。
///
/// 支持语义化版本（Semantic Versioning）的解析和比较：
/// - 格式：major.minor.patch（如 "1.2.3"）
/// - 可选 "v" 前缀（如 "v1.2.3"）
/// - 忽略预发布后缀（如 "1.2.3-beta" 中的 "-beta"）
enum VersionComparator {

    /// 将版本字符串解析为整数数组
    ///
    /// 解析规则：
    /// 1. 去掉 "v" 前缀（如 "v1.2.3" → "1.2.3"）
    /// 2. 去掉预发布后缀（如 "1.2.3-beta" → "1.2.3"，用 "-" 分割取第一段）
    /// 3. 按 "." 分割并转为 Int 数组（非数字部分忽略）
    ///
    /// - Parameter version: 版本字符串（如 "v1.2.3-beta"）
    /// - Returns: 整数数组（如 [1, 2, 3]），无法解析的部分被忽略
    ///
    /// 示例：
    /// - "1.2.3" → [1, 2, 3]
    /// - "v2.0" → [2, 0]
    /// - "1.0.0-beta.1" → [1, 0, 0]
    /// - "dev" → []
    static func parse(_ version: String) -> [Int] {
        // Swift 的 String 操作链式调用（类似 Java 的 String 方法链或 Python 的 str 方法）
        var cleaned = version

        // hasPrefix 检查字符串前缀（类似 Java 的 startsWith）
        // dropFirst() 返回去掉第一个字符的 Substring（类似 Python 的 s[1:]）
        // String() 将 Substring 转为 String（Swift 的 Substring 和 String 是不同类型）
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned = String(cleaned.dropFirst())
        }

        // split(separator:) 类似 Java 的 split() 或 Go 的 strings.Split()
        // maxSplits: 1 表示只分割第一个 "-"（保留后续可能出现的 "-"）
        // 这样 "1.0.0-beta.1" 会分割成 ["1.0.0", "beta.1"]
        if let dashIndex = cleaned.firstIndex(of: "-") {
            cleaned = String(cleaned[cleaned.startIndex..<dashIndex])
        }

        // compactMap 类似 Java Stream 的 filter+map 组合：
        // 对每个元素执行 Int($0) 转换，自动过滤掉转换失败（返回 nil）的元素
        // 例如 "1.2.abc" 中的 "abc" 会被 Int() 返回 nil，从而被 compactMap 丢弃
        return cleaned.split(separator: ".").compactMap { Int($0) }
    }

    /// 比较两个版本号，判断 latest 是否比 current 更新
    ///
    /// 逐段比较 major → minor → patch，第一个不相等的段决定结果。
    /// 如果一个版本段数少于另一个，缺失的段视为 0（例如 "1.2" 等价于 "1.2.0"）。
    ///
    /// - Parameters:
    ///   - current: 当前已安装的版本（如 "1.0.0"）
    ///   - latest: 远程最新的版本（如 "1.1.0"）
    /// - Returns: 如果 latest 版本更新则返回 true
    ///
    /// 示例：
    /// - isNewer(current: "1.0.0", latest: "1.0.1") → true（patch 更新）
    /// - isNewer(current: "1.0.0", latest: "1.0.0") → false（相同版本）
    /// - isNewer(current: "2.0.0", latest: "1.9.9") → false（当前更新）
    static func isNewer(current: String, latest: String) -> Bool {
        let currentParts = parse(current)
        let latestParts = parse(latest)

        // 取两个版本号段数的最大值作为比较长度
        // max() 是 Swift 全局函数（类似 Math.max）
        let count = max(currentParts.count, latestParts.count)

        for i in 0..<count {
            // 如果某个版本号段数不足，用 0 补齐
            // 例如 "1.2" 的第 3 段视为 0，与 "1.2.0" 等价
            // 三元运算符与 Java/Go/Python 的写法一致
            let c = i < currentParts.count ? currentParts[i] : 0
            let l = i < latestParts.count ? latestParts[i] : 0

            if l > c { return true }   // latest 的某一段更大，说明有更新
            if l < c { return false }  // latest 的某一段更小，说明是旧版本
            // l == c 则继续比较下一段
        }

        // 所有段都相等，版本相同，不算更新
        return false
    }
}
