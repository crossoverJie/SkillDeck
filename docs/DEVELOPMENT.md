# SkillDeck Development Guide

> **Target Audience**: 有 Java / Go / Python 经验，但刚接触 Swift 和 macOS 客户端开发的开发者

---

## Table of Contents

1. [开发环境搭建](#1-开发环境搭建)
2. [项目结构总览](#2-项目结构总览)
3. [构建与运行](#3-构建与运行)
4. [Swift 语法快速入门（对照 Java/Go/Python）](#4-swift-语法快速入门)
5. [SwiftUI 核心概念](#5-swiftui-核心概念)
6. [架构模式：MVVM + @Observable](#6-架构模式)
7. [测试](#7-测试)
8. [调试](#8-调试)
9. [打包与分发](#9-打包与分发)
10. [常见问题](#10-常见问题)

---

## 1. 开发环境搭建

### 必需工具

| 工具 | 版本要求 | 安装方式 |
|------|----------|----------|
| **Xcode** | 15.0+ | Mac App Store 或 [developer.apple.com](https://developer.apple.com/xcode/) |
| **macOS** | 14.0+ (Sonoma) | 系统升级 |
| **Swift** | 5.9+ | 随 Xcode 安装 |
| **Git** | 任意 | 随 Xcode Command Line Tools 安装 |

### 安装步骤

```bash
# 1. 安装 Xcode（如果尚未安装）
# 从 Mac App Store 下载，或者：
xcode-select --install   # 仅安装命令行工具（可以编译但不能用 GUI）

# 2. 验证安装
swift --version           # 应显示 Swift 5.9+
xcodebuild -version       # 应显示 Xcode 15+

# 3. 克隆项目
git clone <repo-url>
cd SkillDeck

# 4. 解析依赖（首次构建时自动执行，也可以手动触发）
swift package resolve
```

### 用 Xcode 打开项目

```bash
# 方式1: 直接打开 Package.swift（推荐）
open Package.swift

# 方式2: 在 Xcode 中 File > Open，选择项目根目录
```

> **注意**: 首次打开时 Xcode 会自动下载依赖（Yams, swift-markdown, swift-collections），可能需要几分钟。进度显示在 Xcode 底部状态栏。

### IDE 选择

| IDE | 优劣 |
|-----|------|
| **Xcode**（推荐） | Apple 官方 IDE，最完整的 SwiftUI 支持，包含 Preview、Instruments、模拟器 |
| **VS Code + Swift Extension** | 轻量，但缺少 SwiftUI Preview 和图形化调试 |
| **Cursor** | 同 VS Code |

---

## 2. 项目结构总览

```
SkillDeck/
├── Package.swift                    # 项目配置（≈ go.mod / pom.xml / pyproject.toml）
├── Sources/
│   └── SkillDeck/
│       ├── App/
│       │   └── SkillDeckApp.swift    # 应用入口（≈ main()）
│       ├── Models/                   # 数据模型（≈ Java POJO / Go struct）
│       │   ├── Agent.swift
│       │   ├── AgentType.swift
│       │   ├── LockEntry.swift
│       │   ├── Skill.swift
│       │   ├── SkillInstallation.swift
│       │   ├── SkillMetadata.swift
│       │   └── SkillScope.swift
│       ├── Services/                 # 业务逻辑层（≈ Service / Repository）
│       │   ├── AgentDetector.swift
│       │   ├── FileSystemWatcher.swift
│       │   ├── LockFileManager.swift
│       │   ├── SkillManager.swift
│       │   ├── SkillMDParser.swift
│       │   ├── SkillScanner.swift
│       │   └── SymlinkManager.swift
│       ├── ViewModels/               # 视图模型（MVVM 中间层）
│       │   ├── DashboardViewModel.swift
│       │   ├── SkillDetailViewModel.swift
│       │   └── SkillEditorViewModel.swift
│       ├── Views/                    # UI 视图层
│       │   ├── ContentView.swift
│       │   ├── SettingsView.swift
│       │   ├── Components/           # 可复用组件
│       │   ├── Dashboard/            # Dashboard 页面
│       │   ├── Detail/               # 详情页面
│       │   ├── Editor/               # 编辑器页面
│       │   └── Sidebar/              # 侧边栏
│       └── Utilities/                # 工具和扩展
│           ├── Constants.swift
│           └── Extensions.swift
├── Tests/
│   └── SkillDeckTests/               # 单元测试
└── docs/
    └── DEVELOPMENT.md                # 本文档
```

### 概念映射

| Swift/macOS 概念 | Java 等价 | Go 等价 | Python 等价 |
|------------------|-----------|---------|-------------|
| `Package.swift` | `pom.xml` / `build.gradle` | `go.mod` | `pyproject.toml` |
| `struct` | Record / POJO | struct | dataclass |
| `class` | class | — | class |
| `enum` | enum（更强大，有关联值） | iota + tagged union | Enum |
| `protocol` | interface | interface | Protocol / ABC |
| `@Observable` | LiveData / StateFlow | — | — |
| `actor` | synchronized class | mutex + struct | — |
| `async/await` | CompletableFuture | goroutine + channel | asyncio |
| `XCTest` | JUnit | testing | pytest |

---

## 3. 构建与运行

### 命令行方式

```bash
# 构建项目
swift build

# 构建 Release 版本（优化编译，更快但编译时间更长）
swift build -c release

# 运行应用
swift run SkillDeck

# 清理构建产物（类似 go clean 或 mvn clean）
swift package clean
```

### Xcode 方式（推荐）

1. **打开项目**: `open Package.swift`
2. **选择目标**: 顶部工具栏选择 `SkillDeck` scheme 和 `My Mac`
3. **运行**: 点击 ▶ 按钮 或 `Cmd + R`
4. **停止**: 点击 ■ 按钮 或 `Cmd + .`

### 快捷键速查

| 操作 | 快捷键 |
|------|--------|
| 运行 | `Cmd + R` |
| 停止 | `Cmd + .` |
| 构建 | `Cmd + B` |
| 测试 | `Cmd + U` |
| 清理 | `Cmd + Shift + K` |
| 打开文件 | `Cmd + Shift + O` |
| 跳转到定义 | `Ctrl + Cmd + J` |
| 查找调用者 | `Ctrl + 1` |
| SwiftUI Preview | `Cmd + Option + P` |

---

## 4. Swift 语法快速入门

### 变量声明

```swift
// let = 不可变（Java final / Go 的默认 / Python 无直接等价）
let name = "SkillDeck"          // 类型推断为 String
let count: Int = 42              // 显式指定类型

// var = 可变
var skills: [Skill] = []         // 可变数组

// Optional: Swift 独有的空安全机制（类似 Java Optional 但更深度集成）
var license: String? = nil       // 可以为 nil
let value = license ?? "Unknown" // ?? 是空值合并运算符（类似 Python 的 or）

// if let 解包 Optional（类似 Go 的 if err != nil 模式）
if let actualLicense = license {
    print(actualLicense)         // 这里 actualLicense 是 String（非 Optional）
}

// guard let 提前返回（推荐用于函数开头的参数验证）
guard let data = loadData() else {
    return  // 必须退出当前作用域
}
// data 在这里是非 Optional 的
```

### 错误处理

```swift
// Swift 错误处理 vs 其他语言：
// Java: try-catch + checked exceptions
// Go:   if err != nil { return err }
// Swift: do-try-catch（类似 Java，但更轻量）

// 定义错误类型
enum ParseError: Error {
    case fileNotFound(URL)
    case invalidFormat(String)
}

// 抛出错误的函数用 throws 标记
func parse(file: URL) throws -> Result {
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw ParseError.fileNotFound(file)
    }
    // ...
}

// 调用方式
do {
    let result = try parse(file: url)
} catch ParseError.fileNotFound(let url) {
    print("File not found: \(url)")
} catch {
    print("Unexpected error: \(error)")
}

// 简写：忽略错误
let result = try? parse(file: url)  // 失败返回 nil
```

### 闭包（Lambda）

```swift
// Swift 闭包 ≈ Java Lambda / Go func literal / Python lambda
// 完整形式
let doubled = numbers.map({ (n: Int) -> Int in
    return n * 2
})

// 简写形式（Swift 类型推断很强）
let doubled = numbers.map { $0 * 2 }  // $0 = 第一个参数

// 尾随闭包：当最后一个参数是闭包时，可以写在括号外
Button("Click") {
    doSomething()  // 这是 action 闭包
}
```

### 协议（Protocol）

```swift
// protocol ≈ Java interface / Go interface
// 但 Swift 的 protocol 可以有默认实现（类似 Java 的 default method）
protocol Displayable {
    var displayName: String { get }
}

// 扩展（extension）可以给已有类型添加协议遵守和方法
// 类似 Go 的方法可以在任意包中定义，或 Kotlin 的扩展函数
extension AgentType: Displayable {
    var displayName: String { /* ... */ }
}
```

### 并发

```swift
// async/await（Swift 5.5+）
func fetchData() async throws -> Data {
    let (data, _) = try await URLSession.shared.data(from: url)
    return data
}

// 并行执行（类似 Go 的 goroutine + WaitGroup）
async let result1 = fetchA()
async let result2 = fetchB()
let (a, b) = await (try result1, try result2)

// Task：创建异步任务（类似 go func(){}）
Task {
    await doSomethingAsync()
}

// actor：线程安全的类（类似 Go 的 struct + sync.Mutex）
actor Counter {
    var count = 0
    func increment() { count += 1 }  // 自动串行化访问
}
```

---

## 5. SwiftUI 核心概念

### View 是声明式的

```swift
// SwiftUI 是声明式 UI 框架（类似 React / Flutter / Jetpack Compose）
// 你描述 UI「应该是什么样」，框架负责更新
struct MyView: View {
    var body: some View {    // body 就是 render 函数
        VStack {             // 垂直布局（类似 CSS flex-direction: column）
            Text("Hello")
            Button("Click") { /* action */ }
        }
    }
}
```

### 状态管理

```swift
// @State：View 内部的私有状态（类似 React 的 useState）
@State private var count = 0

// @Binding：从父组件传递的双向绑定（类似 Vue 的 v-model）
@Binding var isOn: Bool

// @Environment：从 View 树中获取共享对象（类似 React 的 useContext）
@Environment(SkillManager.self) private var skillManager

// @Observable：自动追踪属性变化的类（macOS 14+，替代旧的 ObservableObject）
@Observable
class ViewModel {
    var items: [Item] = []  // 变化时自动通知 UI 更新
}
```

### 常用布局

```swift
// VStack - 垂直排列（CSS: flex-direction: column）
VStack(spacing: 8) { ... }

// HStack - 水平排列（CSS: flex-direction: row）
HStack { ... }

// ZStack - 层叠排列（CSS: position: absolute）
ZStack { ... }

// List - 列表（类似 RecyclerView / UITableView）
List(items) { item in
    Text(item.name)
}

// NavigationSplitView - macOS 三栏布局（类似 Apple Mail）
NavigationSplitView {
    Sidebar()    // 左栏
} content: {
    ItemList()   // 中栏
} detail: {
    ItemDetail() // 右栏
}
```

### Modifier Chain（修饰符链）

```swift
// SwiftUI 使用链式调用设置样式（类似 CSS，但类型安全）
Text("Hello")
    .font(.headline)           // 字体
    .foregroundStyle(.blue)    // 颜色
    .padding()                 // 内边距
    .background(.gray)         // 背景
    .cornerRadius(8)           // 圆角

// 注意：modifier 的顺序很重要！
// padding 在 background 之前 = 背景包含 padding
// padding 在 background 之后 = 背景不包含 padding
```

---

## 6. 架构模式

### MVVM（Model-View-ViewModel）

```
┌─────────┐     observes      ┌──────────────┐     calls      ┌──────────┐
│  View    │ ────────────────► │  ViewModel   │ ─────────────► │  Service │
│(SwiftUI) │ ◄──────────────── │ (@Observable)│ ◄───────────── │  (actor) │
│          │   data binding    │              │    results     │          │
└─────────┘                    └──────────────┘                └──────────┘
```

**类比**：
- **Java/Android**: Activity/Fragment → ViewModel → Repository
- **Go**: Handler → Service → Repository
- **Python**: View → Serializer → Model

### @Observable 工作原理

```swift
@Observable
class SkillManager {
    var skills: [Skill] = []    // 当 skills 改变时，所有读取它的 View 自动刷新
}

// 在 View 中使用
struct DashboardView: View {
    @Environment(SkillManager.self) var manager

    var body: some View {
        List(manager.skills) { skill in   // 当 skills 改变时，List 自动更新
            Text(skill.name)
        }
    }
}
```

### 依赖注入

```swift
// 1. 在 App 入口创建并注入
@main
struct SkillDeckApp: App {
    @State var skillManager = SkillManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(skillManager)    // 注入到 View 树
        }
    }
}

// 2. 在任意子 View 中获取
struct AnyChildView: View {
    @Environment(SkillManager.self) var manager  // 自动获取
}
```

---

## 7. 测试

### 运行测试

```bash
# 运行所有测试
swift test

# 运行特定测试文件
swift test --filter SkillMDParserTests

# 运行特定测试方法
swift test --filter SkillMDParserTests/testParseStandardSkillMD

# 显示详细输出
swift test --verbose

# 在 Xcode 中运行: Cmd + U
```

### 测试框架：XCTest

```swift
import XCTest
@testable import SkillDeck  // @testable 让测试可以访问 internal 成员

final class MyTests: XCTestCase {

    // setUp: 每个测试方法前执行（≈ @Before / TestMain）
    override func setUp() async throws { }

    // tearDown: 每个测试方法后执行（≈ @After）
    override func tearDown() async throws { }

    // 测试方法必须以 test 开头
    func testSomething() throws {
        // 断言方法（≈ JUnit Assert / Go testing.T）
        XCTAssertEqual(1 + 1, 2)
        XCTAssertTrue(condition)
        XCTAssertNil(optionalValue)
        XCTAssertNotNil(optionalValue)
        XCTAssertThrowsError(try riskyOperation())
    }

    // 异步测试
    func testAsync() async throws {
        let result = try await asyncOperation()
        XCTAssertEqual(result, expected)
    }
}
```

### 测试覆盖率

```bash
# 生成覆盖率报告（在 Xcode 中）
# Product > Scheme > Edit Scheme > Test > Options > Code Coverage ✓

# 命令行方式
swift test --enable-code-coverage
# 覆盖率数据在 .build/debug/codecov/ 目录
```

---

## 8. 调试

### Xcode 调试

1. **断点**: 点击代码行号左侧设置断点
2. **LLDB 控制台**: 断点暂停后，在底部控制台输入命令
   ```
   po variable        # 打印对象（≈ Java 的 toString()）
   p expression       # 计算表达式
   bt                 # 打印调用栈
   ```
3. **View Hierarchy**: Debug > View Debugging > Capture View Hierarchy

### print 调试

```swift
// Swift 的 print 可以直接输出任意类型
print("Skills count: \(skills.count)")   // 字符串插值（≈ f-string）
print(skill)                              // 自动调用 description

// dump 输出更详细的结构信息（类似 Python 的 pprint）
dump(skill)
```

### SwiftUI Preview

```swift
// 在 View 文件底部添加 Preview 宏，可以在 Xcode 中实时预览 UI
#Preview {
    SkillRowView(skill: .preview)
        .frame(width: 400)
}
```

---

## 9. 打包与分发

### 方式1: Xcode Archive（推荐）

1. 选择 `Product > Archive`
2. 在 Organizer 中选择 archive
3. 点击 `Distribute App`
4. 选择 `Copy App` 或 `Developer ID` (用于 notarize)

### 方式2: 命令行构建

```bash
# Release 构建
swift build -c release

# 构建产物位置
ls .build/release/SkillDeck
```

### 创建 .app Bundle

Swift Package Manager 生成的是裸可执行文件，要创建 .app bundle 需要额外步骤：

```bash
# 1. 创建 bundle 结构
mkdir -p SkillDeck.app/Contents/MacOS
mkdir -p SkillDeck.app/Contents/Resources

# 2. 复制可执行文件
cp .build/release/SkillDeck SkillDeck.app/Contents/MacOS/

# 3. 创建 Info.plist
cat > SkillDeck.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SkillDeck</string>
    <key>CFBundleIdentifier</key>
    <string>com.skilldeck.app</string>
    <key>CFBundleName</key>
    <string>SkillDeck</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
```

### Notarize（公证）

Apple 要求分发的 macOS 应用必须经过 notarize（公证），否则用户打开时会看到安全警告：

```bash
# 1. 需要 Apple Developer ID（$99/年）
# 2. 创建 Developer ID 签名
codesign --deep --force --sign "Developer ID Application: Your Name" SkillDeck.app

# 3. 创建 DMG
hdiutil create -volname SkillDeck -srcfolder SkillDeck.app -ov SkillDeck.dmg

# 4. 提交 notarize
xcrun notarytool submit SkillDeck.dmg --apple-id your@email.com --team-id XXXX --password @keychain:notarize

# 5. 等待并 staple
xcrun stapler staple SkillDeck.dmg
```

> **开发阶段**: 直接 `swift run` 或 Xcode 运行即可，不需要签名和公证。

### Homebrew Cask（未来分发渠道）

```ruby
# 创建 Cask formula
cask "skilldeck" do
  version "0.1.0"
  sha256 "xxx"
  url "https://github.com/xxx/SkillDeck/releases/download/v#{version}/SkillDeck.dmg"
  name "SkillDeck"
  homepage "https://github.com/xxx/SkillDeck"
  app "SkillDeck.app"
end
```

---

## 10. 常见问题

### Q: `swift build` 报错找不到依赖？

```bash
# 清理并重新解析
swift package clean
swift package resolve
swift build
```

### Q: Xcode 中看不到文件？

Package.swift 的 `Sources/SkillDeck` 目录下的所有 `.swift` 文件会自动包含。确保文件放在正确的路径下。

### Q: 如何添加新的 Swift 文件？

直接在对应目录下创建 `.swift` 文件即可，不需要修改任何配置。Swift Package Manager 会自动发现。

### Q: `@Observable` 报错？

确保 `Package.swift` 中 `platforms` 设置为 `.macOS(.v14)` 以上。`@Observable` 是 macOS 14+ 的新特性。

### Q: SwiftUI Preview 不工作？

1. 确保用 Xcode 打开（不是 VS Code）
2. 文件底部需要有 `#Preview { }` 宏
3. 按 `Cmd + Option + P` 打开 Preview

### Q: 如何查看 SwiftUI 有哪些组件？

- Xcode 中 `Cmd + Shift + L` 打开组件库
- Apple 官方文档: [developer.apple.com/documentation/swiftui](https://developer.apple.com/documentation/swiftui)
- SF Symbols 图标库: 下载 [SF Symbols app](https://developer.apple.com/sf-symbols/)

### Q: struct vs class 怎么选？

| 场景 | 选择 | 原因 |
|------|------|------|
| 数据模型 | `struct` | 值类型，线程安全，Swift 推荐 |
| ViewModel | `class` | `@Observable` 要求引用类型 |
| Service 单例 | `actor` | 线程安全的引用类型 |
| 全局状态 | `class` | 需要共享引用 |

### Q: `some View` 是什么意思？

`some View` 是 Swift 的 opaque return type（不透明返回类型）。意思是「返回某种遵守 View 协议的类型，但调用者不需要知道具体类型」。类似 Java 的 `View<?>` 或 Go 的返回 interface。

---

## 附录：有用的资源

- [Swift Language Guide](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/) - 官方语言文档
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui) - SwiftUI API 文档
- [Hacking with Swift](https://www.hackingwithswift.com/) - 最好的 Swift 学习网站
- [Swift by Sundell](https://www.swiftbysundell.com/) - 高级 Swift 文章
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/macos) - macOS 设计规范
