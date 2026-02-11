// swift-tools-version: 5.9
// SkillDeck — Native macOS Agent Skills Manager
// 这是 Swift Package Manager 的项目配置文件，类似于 Go 的 go.mod 或 Python 的 pyproject.toml

import PackageDescription

let package = Package(
    name: "SkillDeck",

    // 指定最低运行平台：macOS 14 (Sonoma)，因为我们使用了 @Observable 宏（macOS 14+ 新特性）
    platforms: [.macOS(.v14)],

    // 外部依赖，类似 Go modules 或 pip install
    dependencies: [
        // Yams: Swift 的 YAML 解析库，用于解析 SKILL.md 的 frontmatter
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),

        // Apple 官方的 Markdown 解析库，用于渲染 SKILL.md 的正文部分
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.7.3"),

        // Apple 官方的集合扩展库，提供 OrderedDictionary 等高级数据结构
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    ],

    targets: [
        // 主应用 target（可执行文件），类似 Go 的 main package
        .executableTarget(
            name: "SkillDeck",
            dependencies: [
                "Yams",
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Collections", package: "swift-collections"),
            ],
            path: "Sources/SkillDeck"
        ),

        // 单元测试 target，类似 Go 的 _test.go 文件
        .testTarget(
            name: "SkillDeckTests",
            dependencies: ["SkillDeck"],
            path: "Tests/SkillDeckTests"
        ),
    ]
)
