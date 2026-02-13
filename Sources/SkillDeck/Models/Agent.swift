import Foundation

/// Agent represents an installed AI code assistant instance
/// Using struct (value type) instead of class (reference type), which is a Swift best practice
/// Value types are copied on assignment, avoiding concurrency issues with shared state (similar to Go's pass-by-value)
struct Agent: Identifiable, Hashable {
    let type: AgentType
    let isInstalled: Bool           // Whether the CLI tool exists
    let configDirectoryExists: Bool // Whether the configuration directory exists
    let skillsDirectoryExists: Bool // Whether the skills directory exists
    let skillCount: Int             // Number of skills under this Agent

    // Identifiable protocol: SwiftUI uses id to track each element in a list
    var id: String { type.id }
    var displayName: String { type.displayName }
}
