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
    /// not effective). Set on each show. Drives the gear's attention dot.
    var keyboardActive = true
    /// True when a newer version is available. App-level, set by AppDelegate's
    /// update check — deliberately NOT cleared by reset() (it outlives a show).
    var updateAvailable = false

    func reset() {
        showToken     = UUID()
        searchText    = ""
        selectedIndex = 0
    }
}
