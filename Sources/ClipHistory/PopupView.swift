import SwiftUI

struct PopupView: View {
    let store:     ClipboardStore
    @Bindable var settings: AppSettings
    @Bindable var state: PopupState
    let onSelect:  (ClipItem) -> Void
    let onDismiss: () -> Void

    // Single source of truth for filtering — same call the window controller
    // uses, so selection indices always agree between view and key handling.
    // Reading state.searchText / settings.hideImages here (and store.items
    // inside the store method) registers all three @Observable dependencies.
    var filtered: [ClipItem] {
        store.filtered(query: state.searchText, showImages: !settings.hideImages)
    }

    @State private var searchFocused = false
    @State private var cursorPhase   = false
    @State private var lastHoverPt: CGPoint? = nil
    @State private var hoverEnabled         = false

    var body: some View {
        VStack(spacing: 0) {
            header
            itemList
                .onContinuousHover { phase in
                    guard case .active(let pt) = phase else { return }
                    if let last = lastHoverPt {
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
        .background {
            RoundedRectangle(cornerRadius: AppTheme.panelRadius)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 32, y: 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius))
        .onChange(of: state.searchText) { _, _ in state.selectedIndex = 0 }
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

    // MARK: - Header

    private var header: some View {
        searchField
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(searchFocused ? Color.accentColor : Color.primary.opacity(0.3))
                .scaleEffect(searchFocused ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: searchFocused)

            ZStack(alignment: .leading) {
                if state.searchText.isEmpty {
                    Text("Search history...")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.25))
                }

                HStack(spacing: 1) {
                    Text(state.searchText.isEmpty ? "" : state.searchText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.9))

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 16)
                        .opacity(searchFocused && cursorPhase ? 1 : 0)
                        .animation(
                            searchFocused
                                ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                                : .default,
                            value: cursorPhase
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !state.searchText.isEmpty {
                Button { state.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary.opacity(0.2))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    // MARK: - Item list

    @ViewBuilder
    private var itemList: some View {
        if filtered.isEmpty {
            emptyState
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    .fill(AppTheme.softFill)
                    .frame(width: 44, height: 44)
                Image(systemName: store.items.isEmpty ? "clipboard" : "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text(store.items.isEmpty ? "Nothing copied yet" : "No matches")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.82))
                Text(store.items.isEmpty ? "Your recent clips will appear here." : "Try a different search or show images.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    // MARK: - Row

    private func itemRow(_ item: ClipItem, index: Int) -> some View {
        let selected = index == state.selectedIndex
        return Button { onSelect(item) } label: {
            HStack(alignment: .center, spacing: 12) {
                appIconView(item, selected: selected)

                rowContent(for: item, selected: selected)
                    .frame(maxWidth: .infinity, alignment: .leading)

                trailingMeta(for: item, selected: selected)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.rowRadius)
                    .fill(selected ? Color.primary.opacity(0.06) : Color.clear)
            }
            // Fast easeOut instead of a spring: when the cursor sweeps across
            // several rows the highlight must keep up, not bounce behind it.
            .animation(.easeOut(duration: 0.1), value: selected)
        }
        .buttonStyle(.plain)
        .onHover { if $0 && hoverEnabled { state.selectedIndex = index } }
    }

    @ViewBuilder
    private func appIconView(_ item: ClipItem, selected: Bool) -> some View {
        Group {
            if let icon = item.sourceApp?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: item.isImage ? "photo" : "doc.text")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.4))
                    }
            }
        }
    }

    @ViewBuilder
    private func rowContent(for item: ClipItem, selected: Bool) -> some View {
        switch item.content {

        case .text(let text):
            VStack(alignment: .leading, spacing: 2) {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary.opacity(selected ? 1 : 0.85))

                if let app = item.sourceApp {
                    Text(app.name)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }

        case .image:
            HStack(spacing: 10) {
                if let img = store.cachedImage(for: item) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.primary.opacity(0.05), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Image")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.9))
                    if let app = item.sourceApp {
                        Text(app.name)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
            }
        }
    }

    private func trailingMeta(for item: ClipItem, selected: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if item.pinned || selected {
                HStack(spacing: 4) {
                    Button {
                        store.remove(id: item.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.red.opacity(0.4))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.togglePin(id: item.id)
                    } label: {
                        Image(systemName: item.pinned ? "pin.fill" : "pin")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(item.pinned ? Color.accentColor : Color.primary.opacity(0.2))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.scale.combined(with: .opacity))
            }

            Text(shortAge(item.date))
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.2))
        }
        .frame(width: 44, alignment: .trailing)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: selected)
    }

    // MARK: - Hints bar

    private var hintsBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                hintChip(key: "↑↓", label: "navigate")
                hintChip(key: "↵",  label: "paste")
                hintChip(key: "⇧↵", label: "plain")
                Spacer()
            }
            HStack(spacing: 12) {
                hintChip(key: "⌘P", label: "pin")
                hintChip(key: "⌘⌫", label: "delete")
                hintChip(key: "esc", label: "close")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func hintChip(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.6))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.5))
        }
    }

    // MARK: - Age string

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
