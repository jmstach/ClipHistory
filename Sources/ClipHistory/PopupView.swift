import SwiftUI

struct PopupView: View {
    let store:     ClipboardStore
    @Bindable var settings: AppSettings
    @Bindable var state: PopupState
    let onSelect:  (ClipItem) -> Void
    let onDismiss: () -> Void

    var filtered: [ClipItem] {
        // Access store.items, settings.hideImages and state.searchText directly
        // so SwiftUI's @Observable tracker registers all three dependencies.
        var result = store.items
        if settings.hideImages { result = result.filter { !$0.isImage } }
        let q = state.searchText
        guard !q.isEmpty else { return result }
        return result.filter {
            $0.preview.localizedCaseInsensitiveContains(q) ||
            ($0.sourceApp?.name.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    /// True once the user has clicked on the search bar area.
    @State private var searchFocused = false
    /// Drives the blink animation — toggled by `onChange(of: searchFocused)`.
    @State private var cursorPhase   = false
    /// Last recorded hover position. Hover activates after the mouse moves
    /// at least 6 pts from its initial entry point, so mousing over the popup
    /// while it opens doesn't immediately change the selection.
    @State private var lastHoverPt: CGPoint? = nil
    @State private var hoverEnabled         = false

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.12)
            itemList
                .onContinuousHover { phase in
                    guard case .active(let pt) = phase else { return }
                    if let last = lastHoverPt {
                        // Enable hover once the mouse moves ≥ 6 pts in any direction.
                        if !hoverEnabled {
                            let dx = pt.x - last.x, dy = pt.y - last.y
                            if dx*dx + dy*dy >= 36 { hoverEnabled = true }
                        }
                    } else {
                        lastHoverPt = pt
                    }
                }
            hintsBar
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
        .onChange(of: state.searchText) { _, _ in state.selectedIndex = 0 }
        // Reset state every time the popup is freshly opened
        .onChange(of: state.showToken) { _, _ in
            searchFocused = false
            cursorPhase   = false
            resetHoverState()
        }
        .onAppear { resetHoverState() }
    }

    private func resetHoverState() {
        lastHoverPt  = nil
        hoverEnabled = false
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(searchFocused ? Color.accentColor : Color.secondary)

            ZStack(alignment: .leading) {
                if state.searchText.isEmpty {
                    Text("Search clipboard…")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.primary.opacity(0.28))
                }
                HStack(spacing: 1) {
                    Text(state.searchText.isEmpty ? "" : state.searchText)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.primary)
                    // Blinking caret — only after the user clicks the search bar
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 1.5, height: 14)
                        .opacity(searchFocused && cursorPhase ? 1 : 0)
                        .animation(
                            searchFocused
                                ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                                : .default,
                            value: cursorPhase
                        )
                        .onChange(of: searchFocused) { _, focused in
                            cursorPhase = focused   // kick off the repeat when focused
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !state.searchText.isEmpty {
                Button { state.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // Hide-images toggle — lives at the top so it's always reachable
            Divider().frame(height: 14).opacity(0.4)
            Toggle(isOn: $settings.hideImages) {
                Image(systemName: settings.hideImages ? "photo.slash" : "photo")
                    .font(.system(size: 11))
                    .foregroundStyle(settings.hideImages ? Color.accentColor : Color.secondary)
            }
            .toggleStyle(.checkbox)
            .controlSize(.mini)
            .help(settings.hideImages ? "Show images" : "Hide images")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Clicking anywhere in the bar activates the cursor
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    // MARK: - Item list

    @ViewBuilder
    private var itemList: some View {
        if filtered.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: store.items.isEmpty ? "clipboard" : "magnifyingglass")
                    .font(.system(size: 26, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
                Text(store.items.isEmpty ? "Nothing copied yet" : "No matches")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, item in
                            itemRow(item, index: idx)
                                .id(item.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: state.selectedIndex) { _, newIdx in
                    if let item = filtered[safe: newIdx] {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo(item.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func itemRow(_ item: ClipItem, index: Int) -> some View {
        let selected = index == state.selectedIndex
        return Button { onSelect(item) } label: {
            HStack(alignment: .center, spacing: 0) {

                // Selection bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(selected ? Color.accentColor : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .padding(.trailing, 9)

                // Content area
                rowContent(for: item, selected: selected)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)

                // Pin button — always visible when pinned, fades in on hover
                Button {
                    store.togglePin(id: item.id)
                } label: {
                    Image(systemName: item.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(item.pinned ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .opacity(item.pinned || selected ? 1 : 0)
                .padding(.trailing, 6)

                // Source-app icon + age stamp
                VStack(alignment: .trailing, spacing: 3) {
                    if let icon = item.sourceApp?.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 13, height: 13)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(shortAge(item.date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.quaternary)
                }
                .fixedSize()
            }
            .padding(.leading, 8)
            .padding(.trailing, 11)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { if $0 && hoverEnabled { state.selectedIndex = index } }
    }

    // MARK: - Per-kind content

    @ViewBuilder
    private func rowContent(for item: ClipItem, selected: Bool) -> some View {
        switch item.content {

        case .text(let text):
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 12.5))
                .lineLimit(2)
                .truncationMode(.tail)
                .foregroundStyle(
                    selected
                    ? AnyShapeStyle(.primary)
                    : AnyShapeStyle(Color.primary.opacity(0.85))
                )

        case .image(let data):
            HStack(spacing: 10) {
                if let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 54, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Image")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                    if let app = item.sourceApp {
                        Text("from \(app.name)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Keyboard hints footer

    private var hintsBar: some View {
        HStack(spacing: 12) {
            hintChip(key: "↑↓", label: "navigate")
            hintChip(key: "↵",  label: "paste")
            hintChip(key: "esc", label: "close")
            Spacer()
            if !filtered.isEmpty {
                Text("\(filtered.count) item\(filtered.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.10) }
    }

    private func hintChip(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Static age string

    private func shortAge(_ date: Date) -> String {
        let s = max(0, Int(Date.now.timeIntervalSince(date)))
        switch s {
        case ..<5:      return "now"
        case ..<60:     return "\(s)s"
        case ..<3600:   return "\(s / 60)m"
        case ..<86400:  return "\(s / 3600)h"
        case ..<604800: return "\(s / 86400)d"
        default:        return "\(s / 604800)w"
        }
    }
}

// MARK: - Helpers

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
