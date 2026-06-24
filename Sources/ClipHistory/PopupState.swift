import Foundation
import Observation

/// Shared mutable state between PopupWindowController and PopupView.
/// Lives in the controller; the view observes it via @Bindable.
@Observable
final class PopupState {
    /// Bumped every time the popup opens — SwiftUI uses this to re-focus the search field.
    var showToken    = UUID()
    var searchText   = ""
    var selectedIndex = 0
    /// False when the keyboard CGEventTap could not be installed (Accessibility
    /// not effective) — drives the in-popup banner. Set on each show.
    var keyboardActive = true

    func reset() {
        showToken     = UUID()
        searchText    = ""
        selectedIndex = 0
    }
}
