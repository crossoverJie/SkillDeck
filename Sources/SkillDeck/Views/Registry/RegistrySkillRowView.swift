import SwiftUI

/// RegistrySkillRowView displays a single skill from the skills.sh registry
///
/// Shows: skill name, source repo, install count, daily change (if available), and install button.
/// Layout follows the existing SkillRowView/SkillInstallView patterns for visual consistency.
///
/// `let` properties make this a stateless, reusable component — all data flows in from the parent.
/// The `onInstall` closure enables the parent to handle the install action (Callback pattern,
/// similar to Java's OnClickListener or React's onClick prop).
struct RegistrySkillRowView: View {

    /// Skill data from the registry
    let skill: RegistrySkill

    /// Whether this skill is already installed locally
    let isInstalled: Bool

    /// Closure called when user clicks the "Install" button
    /// `() -> Void` is a function type that takes no arguments and returns nothing
    /// — similar to Java's Runnable or Go's func()
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Skill info (left side)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.headline)
                        // lineLimit(1) ensures name doesn't wrap to multiple lines
                        .lineLimit(1)

                    // "Installed" badge — matches the existing SkillInstallView pattern
                    // (green capsule with "Installed" text)
                    if isInstalled {
                        Text("Installed")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            // clipShape crops view to capsule shape (pill-shaped rounded rectangle)
                            .clipShape(Capsule())
                    }
                }

                // Source repo label with link icon
                // Label combines an icon and text — macOS native component
                // systemImage refers to SF Symbols (Apple's icon library)
                Label(skill.source, systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Install count + daily change (right side)
            VStack(alignment: .trailing, spacing: 2) {
                // Formatted install count (e.g., "135.6K")
                Text(skill.formattedInstalls)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    // monospacedDigit prevents numbers from shifting when values change
                    // (each digit occupies the same width, like tabular figures in typography)
                    .monospacedDigit()

                Text("installs")
                    .font(.caption2)
                    // .tertiary is lighter than .secondary — used for least important text
                    .foregroundStyle(.tertiary)

                // Show daily change delta if available (from hot/trending data)
                // `if let` unwraps optional — only shown when `change` is non-nil and non-zero
                if let change = skill.change, change != 0 {
                    HStack(spacing: 2) {
                        // Up arrow icon for positive change
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                        Text("+\(change)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.green)
                }
            }

            // Install button
            Button("Install") {
                onInstall()
            }
            // .bordered gives the button a visible border (macOS standard secondary button style)
            .buttonStyle(.bordered)
            // .controlSize(.small) makes the button compact — appropriate for list rows
            .controlSize(.small)
            // Disabled when skill is already installed (prevents duplicate installs)
            .disabled(isInstalled)
        }
        .padding(.vertical, 4)
    }
}
