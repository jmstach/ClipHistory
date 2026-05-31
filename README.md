<div align="center">

<img src="docs/icon.png" width="128" height="128" alt="ClipHistory icon" />

# ClipHistory

**A lightweight, native macOS clipboard manager.**  
One hotkey. Instant popup. Text and images. No subscription.

[![CI](https://github.com/weiykong/ClipHistory/actions/workflows/ci.yml/badge.svg)](https://github.com/weiykong/ClipHistory/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)](https://github.com/weiykong/ClipHistory/releases/latest)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![MIT License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[**Download for Mac**](https://github.com/weiykong/ClipHistory/releases/latest/download/ClipHistory.dmg) · [Website](https://weiykong.github.io/ClipHistory) · [Releases](https://github.com/weiykong/ClipHistory/releases)

</div>

---

## What it looks like

> *Add a screenshot or GIF here — drag an image into this edit field on GitHub*
>
> ![ClipHistory popup](docs/screenshot.png)

---

## Why ClipHistory?

| | ClipHistory | Maccy | Paste | Raycast |
|---|:---:|:---:|:---:|:---:|
| Free | ✅ | ✅ | ❌ $3.99/mo | ✅ |
| Images | ✅ | ❌ | ✅ | ✅ |
| Native Swift (no Electron) | ✅ | ✅ | ✅ | ❌ |
| Pin items | ✅ | ❌ | ✅ | ❌ |
| Per-app exclusions | ✅ | ✅ | ❌ | ❌ |
| Open source | ✅ | ✅ | ❌ | ❌ |
| App size | ~1 MB | ~5 MB | ~30 MB | ~90 MB |

---

## Features

- **⚡ Instant popup** — press `⌥V` from any app, your clipboard history appears at the cursor
- **🖼 Text & images** — captures plain text, screenshots, images from Finder, browsers, Preview
- **🔍 Search** — type to filter instantly; searches content and source app name
- **📌 Pin favourites** — pinned items float to the top and are never evicted by newer copies
- **🔒 Privacy controls** — exclude apps (e.g. 1Password) so sensitive data is never recorded
- **👁 Hide images toggle** — one click in the popup to go text-only
- **🏷 Source app icons** — see at a glance which app each item came from
- **🪶 Truly lightweight** — ~1 MB, pure SwiftUI, no background web process, no telemetry

---

## Install

### Download (recommended)

1. [**Download ClipHistory.dmg**](https://github.com/weiykong/ClipHistory/releases/latest/download/ClipHistory.dmg)
2. Open the DMG and drag **ClipHistory.app** to `/Applications`
3. Right-click → **Open** on first launch *(Gatekeeper prompt — one time only)*
4. Grant **Accessibility** permission when the onboarding screen asks

> Or bypass Gatekeeper from the terminal:
> ```bash
> xattr -d com.apple.quarantine /Applications/ClipHistory.app
> ```

**Requires macOS 14 Sonoma or later.**

### Build from source

```bash
git clone https://github.com/weiykong/ClipHistory.git
cd ClipHistory
bash scripts/build-dmg.sh   # → dist/ClipHistory.dmg
```

Requires Xcode Command Line Tools: `xcode-select --install`

---

## Usage

| Action | Shortcut |
|---|---|
| Open popup | `⌥V` *(customisable in Settings)* |
| Navigate | `↑` / `↓` |
| Paste selected | `↵` |
| Search | Click the search bar, then type |
| Pin / unpin item | Click the `pin` icon on the row |
| Hide images | `photo` toggle in the popup header |
| Close | `Esc` or click outside |
| Settings | Menu bar icon → **Settings…** |

---

## Architecture

Zero dependencies. Swift Package Manager executable target.

```
Sources/ClipHistory/
├── main.swift                  # NSApplication entry point
├── AppDelegate.swift           # Menu bar, hotkey, clipboard polling timer
├── AppSettings.swift           # @Observable settings + UserDefaults persistence
├── ClipboardStore.swift        # Item store, polling, PNG thumbnailing
├── PopupWindowController.swift # NSPanel + CGEventTap keyboard intercept
├── PopupView.swift             # SwiftUI popup UI
├── PopupState.swift            # Shared search / selection state
├── SettingsView.swift          # SwiftUI settings window
├── OnboardingView.swift        # First-launch setup guide
├── HotkeyShortcut.swift        # Hotkey model + Carbon registration
├── HotkeyRecorderView.swift    # NSViewRepresentable hotkey recorder
└── MenuBarIcon.swift           # Programmatic SF Symbol menu bar icon
```

<details>
<summary><strong>Key design decisions</strong></summary>

**`NSPanel` with `.nonactivatingPanel`**  
The popup becomes the key window (so SwiftUI buttons receive clicks) without ever activating the app. The previously focused app keeps its text cursor throughout — Cmd+V fires straight into it after paste.

**Session-level `CGEventTap`**  
Keyboard events are intercepted at the OS session level while the popup is visible, routing them to search and navigation without stealing focus from the source app.

**`@Observable` + `@Bindable`**  
Modern Swift observation macros throughout — no `@StateObject` or `@ObservedObject`.

**Image thumbnailing**  
Clipboard images (screenshots, browser copies, Finder files) are downscaled to ≤ 480 px PNG at capture time using `NSImage(size:flipped:drawingHandler:)`, which forces lazy clipboard images that report `size=(0,0)` to render before sampling.

</details>

---

## Contributing

Issues and pull requests are welcome.  
Please **open an issue first** before starting any large change so we can discuss the approach.

---

## License

[MIT](LICENSE) © 2025 Weiyuan Kong
