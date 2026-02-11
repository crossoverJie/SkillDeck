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
        .frame(width: 450, height: 250)
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

/// 关于页面
struct AboutSettingsView: View {
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

            Text("v0.1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}
