# ClipHistory

A lightweight, native macOS clipboard manager. Lives in your menu bar, pops up instantly with a hotkey, and lets you paste anything you copied — text or images.

![CI](https://github.com/weiykong/ClipHistory/actions/workflows/ci.yml/badge.svg)
![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

- **Instant popup** — press a customisable hotkey (default `⌥V`) anywhere, get your clipboard history
- **Text & images** — captures plain text, rich text, screenshots, and images copied from Finder or browsers
- **Search** — type to filter as you go; click the search bar to activate the cursor
- **Pin / favourite** — pin items so they stay at the top and are never evicted
- **Hide images** — toggle in the popup to show text-only when needed
- **Source app icons** — see which app each item was copied from
- **Exclude apps** — block specific apps (e.g. password managers) from being recorded
- **Launch at Login** — optional, configured in Settings
- **Persisted history** — clipboard history survives restarts (stored locally in `~/Library/Application Support/ClipHistory/`)
- **Lightweight** — ~1 MB binary, no Electron, no background web process, pure SwiftUI

---

## Requirements

- macOS 14 Sonoma or later
- Accessibility permission (required for the global hotkey and keyboard intercept)

---

## Installation

### Download (pre-built)

Download the latest `.dmg` from the [Releases](../../releases) page, open it, and drag **ClipHistory.app** to `/Applications`.

> **First launch:** macOS will show a Gatekeeper warning because the app is not notarised.  
> Right-click → **Open** → **Open** to bypass it once, or run:
> ```bash
> xattr -d com.apple.quarantine /Applications/ClipHistory.app
> ```

### Build from source

```bash
git clone https://github.com/weiykong/ClipHistory.git
cd ClipHistory
bash scripts/build-dmg.sh
# → dist/ClipHistory.dmg
```

Requires Xcode Command Line Tools (`xcode-select --install`).

---

## Usage

| Action | How |
|---|---|
| Open popup | `⌥V` (customisable in Settings) |
| Navigate items | `↑` / `↓` |
| Paste selected item | `↵` |
| Search / filter | Just start typing after clicking the search bar |
| Pin an item | Click the `pin` icon on the row (visible on hover) |
| Hide images | Check the `photo` toggle in the popup header |
| Close popup | `Esc` or click outside |
| Settings | Click the menu bar icon → **Settings…** |

---

## Settings

Open via the menu bar icon → **Settings…**

- **General** — Launch at Login toggle
- **Shortcut** — Record any modifier + key combination as the popup hotkey
- **History** — Max items stored (5–50); Clear History button
- **Privacy** — Exclude specific apps from clipboard capture

---

## Architecture

Pure Swift, no dependencies, Swift Package Manager executable target.

```
Sources/ClipHistory/
├── main.swift                  # NSApplication entry point
├── AppDelegate.swift           # Menu bar, hotkey registration, clipboard polling timer
├── AppSettings.swift           # @Observable settings, UserDefaults persistence
├── ClipboardStore.swift        # Clipboard items, polling, image thumbnailing
├── PopupWindowController.swift # NSPanel + CGEventTap (keyboard intercept)
├── PopupView.swift             # SwiftUI popup UI
├── PopupState.swift            # Shared search/selection state
├── SettingsView.swift          # SwiftUI settings window
├── OnboardingView.swift        # First-launch onboarding
├── HotkeyShortcut.swift        # Hotkey model + Carbon registration
├── HotkeyRecorderView.swift    # NSViewRepresentable hotkey recorder
└── MenuBarIcon.swift           # Programmatic menu bar icon
```

**Key design decisions:**

- **`NSPanel` with `.nonactivatingPanel`** — the popup appears as key window (so SwiftUI buttons receive clicks) but never activates the app, so the previously focused app keeps its text cursor. Cmd+V is simulated after paste via `CGEvent`.
- **`CGEventTap` at session level** — intercepts keyboard events while the popup is visible, routing them to search / navigation without stealing focus from App A.
- **`@Observable` + `@Bindable`** — SwiftUI observation throughout; no `@StateObject` / `@ObservedObject`.
- **Image thumbnailing** — clipboard images are downscaled to ≤480 px PNG on capture using `NSImage(size:flipped:drawingHandler:)` to handle lazy clipboard NSImages that report `size=(0,0)` until rendered.

---

## Contributing

Issues and PRs welcome. Please open an issue before starting large changes.

---

## License

MIT — see [LICENSE](LICENSE).
