import SwiftUI
import AppKit

struct OnboardingView: View {
    @Bindable var settings: AppSettings
    /// Called when the user completes or dismisses onboarding.
    var onDone: () -> Void

    @State private var axGranted = AXIsProcessTrusted()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15)
            steps
            Divider().opacity(0.15)
            footer
        }
        .frame(width: 440)
        // Poll Accessibility status every 0.5 s until granted
        .task {
            while !axGranted {
                try? await Task.sleep(nanoseconds: 500_000_000)
                axGranted = AXIsProcessTrusted()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to ClipHistory")
                    .font(.system(size: 17, weight: .semibold))
                Text("A quick one-time setup and you're good to go.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    // MARK: - Setup steps

    private var steps: some View {
        VStack(spacing: 12) {
            accessibilityCard
            launchAtLoginCard
            shortcutCard
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    // ── Accessibility ────────────────────────────────────────────────────────

    private var accessibilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Label {
                    Text("Accessibility Access")
                        .font(.system(size: 13, weight: .semibold))
                } icon: {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(axGranted ? .green : .orange)
                }

                Spacer()

                // Live status badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(axGranted ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(axGranted ? "Granted" : "Required")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(axGranted ? .green : .orange)
                }
                .animation(.easeInOut(duration: 0.2), value: axGranted)
            }

            Text("ClipHistory needs Accessibility permission to paste items into other apps when you select from your clipboard history.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !axGranted {
                Button {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                } label: {
                    Label("Open System Settings", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Label("All set — ClipHistory can paste into any app.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(axGranted
                      ? Color.green.opacity(0.06)
                      : Color.orange.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(axGranted
                              ? Color.green.opacity(0.25)
                              : Color.orange.opacity(0.25),
                              lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: axGranted)
    }

    // ── Launch at Login ──────────────────────────────────────────────────────

    private var launchAtLoginCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("Launch at Login")
                        .font(.system(size: 13, weight: .semibold))
                } icon: {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .foregroundStyle(.blue)
                }
                Text("Start ClipHistory automatically when you log in to your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    // ── Shortcut reminder ────────────────────────────────────────────────────

    private var shortcutCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("Your Shortcut")
                        .font(.system(size: 13, weight: .semibold))
                } icon: {
                    Image(systemName: "command.circle.fill")
                        .foregroundStyle(.purple)
                }
                Text("Press \(settings.hotkey.displayString) anywhere to instantly open your clipboard history. You can change this in Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if !axGranted {
                Text("You can grant Accessibility access at any time in System Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("You're all set. Enjoy ClipHistory!")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Get Started") { onDone() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}
