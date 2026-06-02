import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store:    ClipboardStore
    var onReopenOnboarding: (() -> Void)?

    @State private var showClearAlert = false

    private var knownSourceApps: [SourceApp] {
        var seen = Set<String>()
        return store.items
            .compactMap(\.sourceApp)
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                generalSection
                shortcutSection
                historySection
                privacySection
                footerLink
            }
            .padding(24)
        }
        .frame(width: 420, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Clear clipboard history?", isPresented: $showClearAlert) {
            Button("Clear All", role: .destructive) { store.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(store.items.count) stored items.")
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        SettingsSection(title: "General", icon: "gearshape.fill") {
            SettingsRow(label: "Launch at Login", hint: "Start ClipHistory automatically when you log in") {
                Toggle("", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    private var shortcutSection: some View {
        SettingsSection(title: "Shortcut", icon: "keyboard.fill") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRow(label: "Open Popup") {
                    HotkeyRecorder(hotkey: $settings.hotkey)
                        .frame(width: 150, height: 28)
                }
                Text("Click the field, then press a modifier + key combination. Press Esc to cancel.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
        }
    }

    private var historySection: some View {
        SettingsSection(title: "History", icon: "clock.fill") {
            VStack(spacing: 0) {
                SettingsRow(label: "Max Items") {
                    HStack(spacing: 8) {
                        Text("\(settings.maxItems)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(minWidth: 28, alignment: .trailing)
                        Stepper("", value: $settings.maxItems, in: 5...200)
                            .labelsHidden()
                    }
                }
                Divider().padding(.horizontal, 14)
                SettingsRow(label: "Stored Now") {
                    Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Divider().padding(.horizontal, 14)
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showClearAlert = true
                    } label: {
                        Label("Clear History", systemImage: "trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacy", icon: "hand.raised.fill") {
            VStack(alignment: .leading, spacing: 0) {
                Text("Clipboard changes from excluded apps are never recorded.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                if knownSourceApps.isEmpty {
                    HStack {
                        Spacer()
                        Text("No apps in history yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(.quaternary)
                            .padding(.vertical, 14)
                        Spacer()
                    }
                } else {
                    ForEach(Array(knownSourceApps.enumerated()), id: \.element.bundleID) { i, app in
                        if i > 0 { Divider().padding(.leading, 44) }
                        appExcludeRow(app)
                    }
                }
            }
        }
    }

    private func appExcludeRow(_ app: SourceApp) -> some View {
        let excluded = settings.excludedBundleIDs.contains(app.bundleID)
        return HStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 20, height: 20)
            }
            Text(app.name)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { excluded },
                set: { on in
                    if on { settings.excludedBundleIDs.insert(app.bundleID) }
                    else  { settings.excludedBundleIDs.remove(app.bundleID) }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var footerLink: some View {
        Button {
            onReopenOnboarding?()
        } label: {
            Label("Reopen Setup Guide", systemImage: "arrow.clockwise")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable section container

private struct SettingsSection<Content: View>: View {
    let title:   String
    let icon:    String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)

            // Card
            VStack(spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
        }
    }
}

// MARK: - Single labeled row

private struct SettingsRow<Trailing: View>: View {
    let label: String
    var hint:  String? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
