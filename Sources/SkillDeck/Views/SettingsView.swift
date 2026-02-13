import SwiftUI

/// SettingsView 是应用的设置页面（通过 Cmd+, 打开）
///
/// TabView 在 macOS 上会渲染成系统标准的偏好设置窗口样式（带标签栏）
struct SettingsView: View {

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        // 增加高度以容纳更新状态 UI（从 250 调至 350）
        .frame(width: 450, height: 350)
    }
}

/// 通用设置
struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section("Paths") {
                LabeledContent("Shared Skills") {
                    Text(Constants.sharedSkillsPath)
                        .textSelection(.enabled)  // 允许用户选中复制
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Lock File") {
                    Text(Constants.lockFilePath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// 关于页面（含应用更新检查 UI）
///
/// @Environment(SkillManager.self) 从 View 树中获取 SkillManager 实例。
/// SkillDeckApp 中通过 Settings { ... .environment(skillManager) } 注入。
struct AboutSettingsView: View {

    /// 从 View 环境中获取 SkillManager
    /// @Environment 类似 React 的 useContext 或 Android 的依赖注入
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("SkillDeck")
                .font(.title)
                .fontWeight(.bold)

            Text("Native macOS Agent Skills Manager")
                .foregroundStyle(.secondary)

            // 从 Info.plist 读取版本号，.app bundle 运行时 Bundle.main 包含 Info.plist
            // CFBundleShortVersionString 是用户可见的版本号（如 "1.0.0"）
            // 如果是 swift run 直接运行（无 .app bundle），则回退到 "dev"
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                .font(.caption)
                .foregroundStyle(.tertiary)

            // Link 是 SwiftUI 内置的超链接组件，点击后会调用系统默认浏览器打开 URL
            // 在 macOS 上渲染为蓝色可点击文字，类似 HTML 的 <a> 标签
            Link("GitHub", destination: URL(string: "https://github.com/crossoverjie/SkillDeck")!)
                .font(.caption)

            // Divider 是水平分隔线（类似 HTML 的 <hr>），用于视觉上区分应用信息和更新状态区域
            Divider()
                .padding(.horizontal)

            // 更新状态区域：根据 SkillManager 中的状态显示不同 UI
            updateStatusView
        }
        .padding()
        // .task 在 View 首次出现时自动触发更新检查（受 4 小时间隔限制）
        // 这样用户每次打开设置页面时，如果距上次检查超过 4 小时就会自动检查
        .task {
            await skillManager.checkForAppUpdate()
        }
    }

    /// 更新状态视图：根据 SkillManager 的更新相关状态属性动态显示不同 UI
    ///
    /// @ViewBuilder 允许在计算属性中使用 if-else 返回不同的 View 类型
    /// （Swift 的 View 是强类型的，不同分支返回不同类型时需要 @ViewBuilder 统一包装）
    @ViewBuilder
    private var updateStatusView: some View {
        if skillManager.isCheckingAppUpdate {
            // 检测中状态：显示旋转指示器
            HStack(spacing: 8) {
                // ProgressView() 无参数时显示不确定进度的旋转指示器（spinner）
                // controlSize(.small) 控制大小为小号
                ProgressView()
                    .controlSize(.small)
                Text("Checking for updates...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if skillManager.isDownloadingUpdate {
            // 下载中状态：显示确定进度的进度条
            VStack(spacing: 6) {
                // ProgressView(value:total:) 显示确定进度的水平进度条
                // value 是当前值，total 是最大值（默认 1.0）
                ProgressView(value: skillManager.downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                // 显示百分比（乘 100 并保留整数）
                // Int() 将 Double 截断为整数（类似 Java 的 (int) 强制转换）
                Text("Downloading... \(Int(skillManager.downloadProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()  // 等宽数字字体，避免百分比变化时文字抖动
            }
        } else if let error = skillManager.updateError {
            // 错误状态：显示红色错误信息和重试按钮
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)  // 限制错误信息最多 2 行
                }

                Button("Retry") {
                    Task { await skillManager.checkForAppUpdate(force: true) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if let updateInfo = skillManager.appUpdateInfo {
            // 有可用更新状态：显示新版本号、更新按钮和 GitHub 链接
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    // 使用橙色箭头图标表示有更新可用
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Update available: v\(updateInfo.version)")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                HStack(spacing: 12) {
                    // "Update Now" 按钮触发下载并安装更新
                    // .borderedProminent 是带填充背景的强调按钮样式（类似 Material Design 的 Filled Button）
                    Button("Update Now") {
                        Task { await skillManager.performUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    // "View on GitHub" 链接在浏览器中打开 Release 页面
                    // 使用 Link 组件而非 Button，因为它是外部导航（打开浏览器）
                    if let url = URL(string: updateInfo.htmlUrl) {
                        Link("View on GitHub", destination: url)
                            .font(.caption)
                    }
                }
            }
        } else {
            // 无更新/未检查状态：显示手动检查按钮
            // force: true 忽略 4 小时间隔限制，立即执行检查
            Button("Check for Updates") {
                Task { await skillManager.checkForAppUpdate(force: true) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
