import AppKit
import SwiftUI
import ApplicationServices

/// Settings, hand-laid-out to match contemporary Mac app settings (Music, Maps):
/// icon tabs, a centre-equalised form with right-aligned labels and left-aligned
/// controls, left checkboxes indented to the control column, grey pop-up menus,
/// hairline dividers between groups, and no rounded "wells". A flat layout (not a
/// grouped Form) has an intrinsic height, so the window sizes to its content.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store:        ClipboardStore
    var updateChecker: UpdateChecker
    var onReopenOnboarding: (() -> Void)?

    enum Tab: Hashable { case general, history, privacy }

    @State private var tab: Tab = .general
    @State private var showClearAlert       = false
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var checkingUpdate        = false

    private let margin: CGFloat = 20
    private static let noMaximum = 100_000   // "No maximum" maps to a large cap

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Group {
                switch tab {
                case .general: generalTab
                case .history: historyTab
                case .privacy: privacyTab
                }
            }
            .padding(.horizontal, margin)
            .padding(.top, 16)
            .padding(.bottom, margin)
            // Fill the height below the tab bar and top-align, so the tab bar stays
            // pinned at the top and short tabs leave whitespace at the bottom.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Fixed height (sized to the busiest tab) so the tab bar never moves between
        // tabs; lighter tabs simply have whitespace below.
        .frame(width: 480, height: 470)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
        .alert("Clear clipboard history?", isPresented: $showClearAlert) {
            Button("Clear All", role: .destructive) { store.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(store.items.count) stored items.")
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 6) {
            tabButton(.general, "General", "gearshape")
            tabButton(.history, "History", "clock")
            tabButton(.privacy, "Privacy", "hand.raised")
        }
        .frame(maxWidth: .infinity)   // centre the tabs
        .padding(.top, 10)            // close to the top, clear of the title row
        .padding(.bottom, 10)
    }

    private func tabButton(_ t: Tab, _ title: String, _ icon: String) -> some View {
        Button { tab = t } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17, weight: .regular))
                Text(title).font(.system(size: 11))
            }
            .frame(width: 68, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tab == t ? Color.primary.opacity(0.1) : .clear)
            )
            .foregroundStyle(tab == t ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(spacing: 0) {
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Launch at login").gridColumnAlignment(.trailing)
                    Toggle("", isOn: $settings.launchAtLogin)
                        .toggleStyle(.checkbox).labelsHidden()
                        .gridColumnAlignment(.leading)
                }
                GridRow {
                    Text("Popup position")
                    Picker("", selection: $settings.popupPlacement) {
                        ForEach(PopupPlacement.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                GridRow {
                    Text("Hide menu bar icon")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Toggle("", isOn: $settings.hideMenuBarIcon).toggleStyle(.checkbox).labelsHidden()
                        description("With the icon hidden, open Settings from the gear button in the popup.")
                    }
                }

                gridDivider()
                GridRow {
                    Text("Open popup")
                    VStack(alignment: .leading, spacing: 4) {
                        HotkeyRecorder(hotkey: $settings.hotkey).frame(width: 150, height: 24)
                        description("↵ pastes with formatting,\n⇧↵ as plain text.")
                    }
                    // The recorder is an NSView with no text baseline, so pin the
                    // group's baseline near the box centre to line up with the label.
                    .alignmentGuide(.firstTextBaseline) { _ in 16 }
                }

                gridDivider()
                GridRow {
                    Text("Keyboard navigation")
                    VStack(alignment: .leading, spacing: 4) {
                        accessibilityControl
                        description("Required for arrow keys, search and Return inside the popup.")
                    }
                }

                gridDivider()
                GridRow {
                    Text("Version")
                    HStack(spacing: 10) {
                        Text(appVersion).foregroundStyle(.secondary)
                        Button(checkingUpdate ? "Checking…" : "Check for Updates") {
                            Task { checkingUpdate = true; await updateChecker.check(); checkingUpdate = false }
                        }
                        .disabled(checkingUpdate)
                        if let update = updateChecker.available {
                            Button("Download \(update.version)") { NSWorkspace.shared.open(update.downloadURL) }
                                .buttonStyle(.borderedProminent)
                            if let notes = update.notesURL { Link("Release notes", destination: notes) }
                        }
                    }
                }
            }

            Spacer(minLength: 16)   // pin the bottom buttons to the window bottom
            Divider().padding(.bottom, 16)
            HStack {
                Button("Restart Setup Guide…") { onReopenOnboarding?() }
                Spacer()
                Button("Quit ClipHistory") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - History

    private var historyTab: some View {
        VStack(spacing: 0) {
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Maximum items").gridColumnAlignment(.trailing)
                    Picker("", selection: $settings.maxItems) {
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("150").tag(150)
                        Text("No maximum").tag(Self.noMaximum)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .gridColumnAlignment(.leading)
                }
                GridRow {
                    Text("")
                    description("Oldest unpinned clips are trimmed once the limit is reached.")
                }
                GridRow {
                    Text("Stored clips")
                    Text("\(store.items.count)").foregroundStyle(.secondary)
                }

                gridDivider()
                GridRow {
                    Text("")
                    VStack(alignment: .leading, spacing: 4) {
                        Button("Clear All History…", role: .destructive) { showClearAlert = true }
                        description("Permanently removes every stored clip.")
                    }
                }
            }
        }
    }

    // MARK: - Privacy

    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            description("Sensitive content and password managers are always ignored. Uncheck an app to stop capturing what it copies.")

            Text("Monitored apps")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 14)
                .padding(.bottom, 8)

            if knownSourceApps.isEmpty {
                Text("Apps appear here after they’ve copied something.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                appsTable
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Bordered, alternating-row table — checkbox · icon · name. Checked = monitored.
    private var appsTable: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(knownSourceApps.indices, id: \.self) { i in
                    let app = knownSourceApps[i]
                    HStack(spacing: 10) {
                        Toggle("", isOn: monitorBinding(app)).toggleStyle(.checkbox).labelsHidden()
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                        }
                        Text(app.name)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(i.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
                }
            }
        }
        .frame(height: 220)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Building blocks

    // A divider spanning both grid columns, with breathing room above/below.
    private func gridDivider() -> some View {
        GridRow {
            Divider().gridCellColumns(2).padding(.vertical, 6)
        }
    }

    private func description(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var accessibilityControl: some View {
        if accessibilityGranted {
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        } else {
            Button("Grant Access…") { requestAccessibility() }
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var knownSourceApps: [SourceApp] {
        var seen = Set<String>()
        return store.items
            .compactMap(\.sourceApp)
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Checked = monitored (captured); unchecked = excluded.
    private func monitorBinding(_ app: SourceApp) -> Binding<Bool> {
        Binding(
            get: { !settings.excludedBundleIDs.contains(app.bundleID) },
            set: { monitored in
                if monitored { settings.excludedBundleIDs.remove(app.bundleID) }
                else         { settings.excludedBundleIDs.insert(app.bundleID) }
            }
        )
    }

    private func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Visual Effect View helper
//
// Still used by OnboardingView for its window background.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
