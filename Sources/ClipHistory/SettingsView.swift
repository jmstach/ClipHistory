import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store:    ClipboardStore
    var onReopenOnboarding: (() -> Void)?

    @State private var showClearAlert = false

    /// Apps that have ever appeared as a clipboard source, deduplicated by bundle ID.
    private var knownSourceApps: [SourceApp] {
        var seen = Set<String>()
        return store.items
            .compactMap(\.sourceApp)
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                // ── General ────────────────────────────────────────────────
                section(title: "General", icon: "gearshape") {
                    LabeledContent("Launch at Login:") {
                        Toggle("", isOn: $settings.launchAtLogin)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                // ── Shortcut ───────────────────────────────────────────────
                section(title: "Shortcut", icon: "keyboard") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Open popup:") {
                            HotkeyRecorder(hotkey: $settings.hotkey)
                                .frame(width: 150, height: 30)
                        }
                        Text("Click the field, then press any modifier + key combination.\nPress Esc to cancel recording.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // ── History ────────────────────────────────────────────────
                section(title: "History", icon: "clock") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Max items:") {
                            Stepper(
                                "\(settings.maxItems)",
                                value: $settings.maxItems,
                                in: 5...50
                            )
                            .fixedSize()
                        }
                        LabeledContent("Stored now:") {
                            Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        HStack {
                            Spacer()
                            Button("Clear History…", role: .destructive) {
                                showClearAlert = true
                            }
                        }
                    }
                }

                // ── Privacy ────────────────────────────────────────────────
                section(title: "Privacy", icon: "hand.raised") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clipboard changes from excluded apps are never recorded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if knownSourceApps.isEmpty {
                            Text("No apps in history yet.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        } else {
                            ForEach(knownSourceApps, id: \.bundleID) { app in
                                Toggle(isOn: Binding(
                                    get: { settings.excludedBundleIDs.contains(app.bundleID) },
                                    set: { exclude in
                                        if exclude {
                                            settings.excludedBundleIDs.insert(app.bundleID)
                                        } else {
                                            settings.excludedBundleIDs.remove(app.bundleID)
                                        }
                                    }
                                )) {
                                    HStack(spacing: 6) {
                                        if let icon = app.icon {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .frame(width: 14, height: 14)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                        Text(app.name)
                                            .font(.system(size: 12))
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }

                // ── Footer link ────────────────────────────────────────────
                HStack {
                    Spacer()
                    Button {
                        onReopenOnboarding?()
                    } label: {
                        Label("Reopen Setup Guide…", systemImage: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .frame(width: 400, height: 480)
        .alert("Clear clipboard history?", isPresented: $showClearAlert) {
            Button("Clear All", role: .destructive) { store.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(store.items.count) stored items.")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            content()
                .padding(.vertical, 4)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
