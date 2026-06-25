import Foundation
import AppKit
import Observation
import ServiceManagement

/// Where the popup appears when opened.
enum PopupPlacement: String, CaseIterable, Codable {
    case cursor, centre, topCentre, bottomCentre, bottomTray

    var label: String {
        switch self {
        case .cursor:       return "At cursor"
        case .centre:       return "Centre"
        case .topCentre:    return "Top centre"
        case .bottomCentre: return "Bottom centre"
        case .bottomTray:   return "Bottom tray"
        }
    }
}

@Observable
final class AppSettings {

    // MARK: - Stored properties

    var hotkey: HotkeyShortcut = .default {
        didSet { save(); onHotkeyChanged?(hotkey) }
    }

    var maxItems: Int = 150 {   // "Plenty"
        didSet { save(); onMaxItemsChanged?(maxItems) }
    }

    var launchAtLogin: Bool = false {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }

    /// Hide image items from the popup list.
    var hideImages: Bool = false {
        didSet { save() }
    }

    /// Where the popup spawns when opened.
    var popupPlacement: PopupPlacement = .bottomTray {
        didSet { save() }
    }

    /// Hide the menu bar status item. Settings is still reachable via the gear
    /// button in the popup, so the app stays controllable without the icon.
    /// Defaults to visible — onboarding also forces it on so new users always
    /// have a discoverable entry point; hiding is an explicit opt-in.
    var hideMenuBarIcon: Bool = false {
        didSet {
            guard hideMenuBarIcon != oldValue else { return }
            save()
            onMenuBarVisibilityChanged?(hideMenuBarIcon)
        }
    }

    /// Bundle IDs of apps whose clipboard changes are silently ignored.
    var excludedBundleIDs: Set<String> = [] {
        didSet { save() }
    }

    // MARK: - Callbacks (set by AppDelegate)

    var onHotkeyChanged:   ((HotkeyShortcut) -> Void)?
    var onMaxItemsChanged: ((Int) -> Void)?
    var onMenuBarVisibilityChanged: ((Bool) -> Void)?

    // MARK: - Init

    init() { load() }

    // MARK: - Persistence

    private enum Keys {
        static let hotkey            = "hotkey"
        static let maxItems          = "maxItems"
        static let hideImages        = "hideImages"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let popupPlacement    = "popupPlacement"
        static let hideMenuBarIcon   = "hideMenuBarIcon"
    }

    private func load() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Keys.hotkey),
           let saved = try? JSONDecoder().decode(HotkeyShortcut.self, from: data) {
            hotkey = saved
        }
        let n = d.integer(forKey: Keys.maxItems)
        if n >= 5 { maxItems = n }

        hideImages = d.bool(forKey: Keys.hideImages)
        if let ids = d.stringArray(forKey: Keys.excludedBundleIDs) {
            excludedBundleIDs = Set(ids)
        }
        if let raw = d.string(forKey: Keys.popupPlacement),
           let placement = PopupPlacement(rawValue: raw) {
            popupPlacement = placement
        }
        // Only override the default if a value was actually stored (bool returns
        // false for an absent key, which would mask the hidden-by-default).
        if d.object(forKey: Keys.hideMenuBarIcon) != nil {
            hideMenuBarIcon = d.bool(forKey: Keys.hideMenuBarIcon)
        }

        // Read ground-truth from the OS — don't call SMAppService again if it
        // already matches (guard in didSet prevents the redundant call).
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(hotkey) {
            d.set(data, forKey: Keys.hotkey)
        }
        d.set(maxItems,              forKey: Keys.maxItems)
        d.set(hideImages,            forKey: Keys.hideImages)
        d.set(Array(excludedBundleIDs), forKey: Keys.excludedBundleIDs)
        d.set(popupPlacement.rawValue, forKey: Keys.popupPlacement)
        d.set(hideMenuBarIcon,         forKey: Keys.hideMenuBarIcon)
    }

    // MARK: - Launch at Login

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // SMAppService throws if the state is already what we asked for,
            // or if it needs user approval — both are non-fatal.
            NSLog("ClipHistory: launch-at-login update: \(error.localizedDescription)")
        }
    }
}
