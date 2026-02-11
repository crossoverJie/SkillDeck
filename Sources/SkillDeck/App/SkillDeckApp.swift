import SwiftUI
import AppKit

/// AppDelegate 处理应用级别的生命周期事件
/// 在 SwiftUI 应用中，通过 @NSApplicationDelegateAdaptor 桥接使用
/// 这里主要解决一个问题：通过 `swift run` 命令行启动时，
/// macOS 不会自动把应用窗口带到前台（因为它不是 .app bundle）
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // setActivationPolicy(.regular) 告诉 macOS：这是一个正常的 GUI 应用
        // 没有这一行的话，通过命令行启动的裸可执行文件会被当作「后台进程」，
        // 不会在 Dock 显示图标，也不会创建窗口
        // .regular = 普通 GUI 应用（有 Dock 图标、菜单栏）
        // .accessory = 辅助应用（只在菜单栏，无 Dock 图标）
        // .prohibited = 纯后台进程（无 UI）
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 将应用激活到前台，确保窗口可见
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// @main 标记应用的入口点（类似 Java 的 public static void main 或 Go 的 func main()）
///
/// SwiftUI 的 App 协议定义了整个应用的结构：
/// - body 属性返回应用的 Scene（窗口）
/// - WindowGroup 创建一个可以多窗口的场景（macOS 支持多窗口）
///
/// @State 是 SwiftUI 的状态管理属性包装器：
/// - 当 @State 标记的值改变时，SwiftUI 会自动重新渲染相关的 View
/// - 类似 React 的 useState 或 Vue 的 ref()
@main
struct SkillDeckApp: App {

    /// SkillManager 是应用的核心状态管理器
    /// 使用 @State 让 SwiftUI 管理它的生命周期
    @State private var skillManager = SkillManager()

    /// NSApplicationDelegateAdaptor 桥接了 SwiftUI 和传统的 AppKit 生命周期
    /// 通过 AppDelegate 我们可以在应用启动时执行 AppKit 级别的操作
    /// 这里用它解决命令行启动时窗口不自动激活的问题
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // WindowGroup 创建主窗口
        WindowGroup {
            ContentView()
                // .environment 将 skillManager 注入到整个 View 树中
                // 所有子 View 都可以通过 @Environment 访问它
                // 类似 React 的 Context Provider 或 Android 的依赖注入
                .environment(skillManager)
        }
        // 设置窗口的默认大小
        .defaultSize(width: 1000, height: 700)

        // Settings 场景：macOS 应用的「偏好设置」窗口
        // 用户可以通过 Cmd+, 打开
        Settings {
            SettingsView()
        }
    }
}
