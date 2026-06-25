import AppKit
import SwiftUI
import ApplicationServices

/// First-launch wizard, modelled on the Markset onboarding flow: one step on
/// screen at a time with a Back · page-dots · Continue/Done nav bar. Step 1
/// (Accessibility) is gated — you can't continue until the grant is effective.
struct OnboardingView: View {
    @Bindable var settings: AppSettings
    var onDone: () -> Void

    @State private var step = 0
    @State private var axGranted = AXIsProcessTrusted()

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 36)
                .padding(.top, 40)
                .padding(.bottom, 24)

            Divider()

            navBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 520, height: 560)
        // Poll the Accessibility grant so the gate opens the moment it's effective.
        .task {
            while !axGranted {
                try? await Task.sleep(nanoseconds: 500_000_000)
                axGranted = AXIsProcessTrusted()
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:  welcomeStep
        case 1:  shortcutStep
        default: tryItStep
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            if step < totalSteps - 1 {
                Button("Continue") { step += 1 }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdvance)
            } else {
                Button("Get Started") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    /// Step 0 is gated on the Accessibility grant — the rest of the app is dead
    /// without it, so there's no point demoing the shortcut first.
    private var canAdvance: Bool {
        step == 0 ? axGranted : true
    }

    // MARK: - Step 0 · Welcome + Accessibility

    private var welcomeStep: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

            Text("Welcome to ClipHistory")
                .font(.largeTitle.bold())

            Text("Your clipboard history, one keystroke away. There's just one thing to switch on first.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: axGranted ? "checkmark.circle.fill" : "hand.raised.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(axGranted ? .green : .orange)
                    Text("Accessibility access").font(.headline)
                    Spacer()
                    if axGranted {
                        Text("Granted").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                    }
                }
                Text("ClipHistory needs this to detect your shortcut and paste clips into other apps. Click below, then switch ClipHistory on in the list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !axGranted {
                    Button("Open Accessibility Settings…") { requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .padding(.top, 6)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: axGranted)
        }
    }

    // MARK: - Step 1 · Shortcut & Launch

    private var shortcutStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "command")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)

            Text("Your shortcut")
                .font(.title.bold())

            Text("Press this anywhere to open your clipboard history. Change it now if you like, or leave the default.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HotkeyRecorder(hotkey: $settings.hotkey)
                .frame(width: 170, height: 30)
                .padding(.top, 4)

            Toggle("Launch ClipHistory at login", isOn: $settings.launchAtLogin)
                .toggleStyle(.checkbox)
                .padding(.top, 12)
        }
    }

    // MARK: - Step 2 · Try it

    private var tryItStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)

            Text("Give it a go")
                .font(.title.bold())

            Text("Press your shortcut right now to open your clipboard history:")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(settings.hotkey.displayString)
                .font(.system(size: 24, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            Spacer(minLength: 8)

            Text("Change the shortcut, popup position and more any time in **Settings** — the gear button in the popup, or the menu bar icon.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func requestAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
