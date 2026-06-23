<div align="center">

<img src="docs/icon.png" width="128" height="128" alt="ClipHistory icon" />

# ClipHistory

**A lightweight, native macOS clipboard manager.**  
One hotkey. Instant popup. Text, images, and files. No subscription.

A personal fork of [**weiykong/ClipHistory**](https://github.com/weiykong/ClipHistory) with a few opinionated tweaks.

[![CI](https://github.com/jmstach/ClipHistory/actions/workflows/ci.yml/badge.svg)](https://github.com/jmstach/ClipHistory/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)](https://github.com/jmstach/ClipHistory)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![MIT License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[**Build from source**](#install) · [This fork](https://github.com/jmstach/ClipHistory) · [Original project](https://github.com/weiykong/ClipHistory)

</div>

---

## What it looks like

<div align="center">
  <img src="docs/popup.png" width="480" alt="ClipHistory popup in front of a text editor" />
</div>

---

## Why this fork?

[Weiyuan Kong](https://github.com/weiykong) built a genuinely lovely clipboard manager - fast, native, encrypted, no telemetry. All the real work is theirs, and the **[original project](https://github.com/weiykong/ClipHistory)** has the full feature list, the architecture notes, and the design rationale. Go read it there; I haven't copied it here.

However, I'm a prissy little designer, so I rearranged the furniture to suit my taste:

- **A bottom-tray mode.** A full-width tray that rises from the bottom of the screen, showing clips as large horizontal preview cards you scan with `←`/`→`. It's the default now; the classic centred popup is still a setting away.
- **Files, not just text and images.** Copy files in Finder and they land in your history — paste drops the real files back, with a thumbnail preview for images.
- **Paste keeps your formatting.** `↵` pastes with the original styling; `⇧↵` pastes as plain text. Styled clips also preview with their real bold, italics, and colour.
- **A redesigned, quieter popup.** A Liquid Glass background, no branding header or toolbar buttons — it opens straight into search, with a cleaner type scale and legible keyboard hints.
- **Open it where you want.** Bottom tray, centre, top, bottom, or at the cursor — set the popup's position in Settings.
- **Keyboard-first pin and delete.** `⌘P` pins the selected item, `⌘⌫` deletes it, without reaching for the mouse.
- **A quieter menu bar.** Hide the menu bar icon entirely and reach Settings from the gear button in the popup.
- **The shortcut recorder works.** Fixed a bug where you couldn't change the hotkey in Settings.

Everything underneath — capture, AES-256-GCM encryption, search, per-app exclusions, sensitive-data skipping — is the original's, unchanged.

---

## Install

This fork has no prebuilt release — build it from source:

```bash
git clone https://github.com/jmstach/ClipHistory.git
cd ClipHistory
bash scripts/build-dmg.sh   # → dist/ClipHistory.dmg
```

Open `dist/ClipHistory.dmg`, drag **ClipHistory.app** to `/Applications`, and grant **Accessibility** permission when the onboarding screen asks — it's needed for the hotkey and the popup's keyboard navigation.

Requires macOS 14 Sonoma or later, and Xcode Command Line Tools (`xcode-select --install`).

> **Sharing the built app with someone else?** Because it isn't notarised, macOS quarantines it when copied to another Mac. They clear it once after dragging it to `/Applications`:
> ```bash
> xattr -dr com.apple.quarantine /Applications/ClipHistory.app
> ```

---

## Usage

| Action | Shortcut |
|---|---|
| Open popup | `⌘⇧V` *(customisable in Settings)* |
| Navigate | `↑` / `↓` *(or `←` / `→` in bottom-tray mode)* |
| Paste (with formatting) | `↵` |
| Paste as plain text | `⇧↵` |
| Search | Just start typing |
| Pin / unpin item | `⌘P` *(or the pin button on the selected item)* |
| Delete item | `⌘⌫` *(or the trash button on the selected item)* |
| Close | `Esc` or click outside |
| Settings | Gear button in the popup *(or the menu bar icon, if shown)* |

---

## Credit & license

ClipHistory is the work of **[Weiyuan Kong](https://github.com/weiykong)** — this fork only changes a handful of interactions. For everything else, including how it actually works, see the [original repository](https://github.com/weiykong/ClipHistory).

[MIT](LICENSE) © 2026 Weiyuan Kong
