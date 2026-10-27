<div align="center">

# BarButler

**Give your menu bar room to breathe.**

A tiny, native menu bar manager for macOS — hide the icons you rarely use behind a single `‹` chevron.

[繁體中文](README.zh-TW.md) · [简体中文](README.zh-CN.md)

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![arch](https://img.shields.io/badge/Universal-Intel%20%7C%20Apple%20Silicon-purple)
![license](https://img.shields.io/badge/license-MIT-green)
[![release](https://img.shields.io/github/v/release/xiewei3536/BarButler)](https://github.com/xiewei3536/BarButler/releases/latest)

</div>

---

## Features

- **One-icon design** — the `‹` chevron is both the divider and the toggle. Anything to its left gets tucked away. No clutter added while removing clutter.
- **Arrange Icons (new in 1.4)** — a visual layout editor: drag icons between *Always Shown*, *Hidden* and *Always Hidden*, or right-click one. BarButler moves the real menu bar icon for you — no fiddly ⌘-dragging. Right-click an icon in the floating panel to keep it in the menu bar.
- **Remembers your layout (new in 1.4)** — if a restart, an app update or a crowded menu bar shuffles your icons, BarButler moves them back to the section you chose (it waits until you're idle and there's room).
- **Rock-solid across sleep (new in 1.4)** — a stability guard waits for displays to settle after sleep, dark wake, display changes and unlock before checking anything, and only ever repairs gently. It never resets your layout (1.3 could, after waking with an external display).
- **Floating panel mode** — hidden icons appear in a sleek panel *below* the menu bar instead. Perfect for notched MacBooks or when the menu bar is too packed to expand. Click a panel icon to trigger the real menu bar item.
- **Hover to expand** — point at `‹` and hidden icons slide out (or the panel opens); they tuck themselves back in when you leave.
- **Smart auto-collapse** — icons re-hide after 5–60 s (configurable), or the moment you click anywhere else. It never collapses while a menu is open, while you're ⌘-dragging, or while your mouse is on the menu bar.
- **Boundary while arranging** — hold ⌘ and start dragging an icon: a faint line appears left of `‹` so you can see exactly where the pocket begins.
- **Icon styles** — chevron, dots, arrows or pill for the `‹` toggle.
- **Real menu bar icons (optional)** — with Screen Recording granted, the layout editor and panel show the actual menu bar glyphs instead of app icons.
- **Global hotkey** — ⌥⌘B by default, recordable to anything you like. No Accessibility permission needed (Carbon API).
- **Always-hidden zone** — an optional second pocket for icons you almost never need; ⌥-click `‹` to peek.
- **Quick peek** — reveal everything for 5 seconds, then restore.
- **Self-healing layout** — if separators ever get dragged into an impossible order, BarButler fixes itself and tells you — without touching other apps' positions.
- **Trilingual** — English / 繁體中文 / 简体中文, switchable instantly in-app without restart.
- **Auto-updates** — built-in Sparkle updater: you'll be notified of new versions and can enable fully automatic download & install.
- **Automation** — `open barbutler://toggle` (also `show`, `hide`, `peek`, `panel`, `arrange`, `mode/float`, `mode/menubar`, `settings?tab=layout`, `diagnose`), plus `barbutler://move?item=LINE&to=shown|hidden|always` and `barbutler://click?item=Wi-Fi` — from Shortcuts, Raycast, Alfred or a terminal.
- **Helpful, not chatty** — one-time hints when you hide your first icon, a warning if macOS starts hiding `‹` because the bar is full, and a permissions panel that tells you exactly what needs what (only moving/clicking icons for you needs Accessibility; hiding itself needs nothing).
- **Native & lightweight** — pure AppKit/SwiftUI, ~3 MB, zero background daemons, universal binary.

## Install

1. Download `BarButler.dmg` from the [latest release](https://github.com/xiewei3536/BarButler/releases/latest).
2. Drag **BarButler** into **Applications**.
3. First launch (the build is not notarized by Apple):
   - macOS 13/14: **right-click the app → Open**
   - macOS 15 Sequoia: open it once, then go to **System Settings → Privacy & Security → "Open Anyway"**
   - or via terminal: `xattr -dr com.apple.quarantine /Applications/BarButler.app`

## Usage

```
[rarely used icons]  ‹  [always visible icons]  [Wi-Fi  Battery  Clock]
        ↑ hidden on collapse      ↑ the chevron — click to toggle
```

1. **Right-click `‹` → Arrange Icons…** and drag each icon into *Always Shown* or *Hidden* (or ⌘-drag icons to the **left** of `‹` yourself).
2. **Click `‹`** (or press ⌥⌘B) to hide/show them.
3. **Right-click `‹`** for the menu: floating panel, 5-second peek, arrange icons, settings.

To use the floating panel as the default: *Settings → General → Expand Style → Floating Panel*.
Clicking an icon in the panel opens that icon's real menu in one step. This uses macOS Accessibility (a one-time grant — the app is signed with a stable identity so the grant survives updates). Keyboard works too: arrows to move, Return to open, Esc to close.
If the front app's menus are so wide that the icon would not fit even when expanded, BarButler briefly becomes the front app to free the space (a Dock icon flashes for a moment), clicks the icon, then hands focus back on collapse.

## Diagnostics

*Settings → Advanced → Diagnostic Report* (or `open barbutler://diagnose`) saves the layout, permissions and recent events to `~/Library/Logs/BarButler/` — please attach it when reporting an issue. `swift scripts/inspect_menubar.swift` lists every status-bar item window with its position.

## Build from source

Requires macOS 13+ with Swift 5.9+ (Command Line Tools are enough — no Xcode needed):

```bash
git clone https://github.com/xiewei3536/BarButler.git
cd BarButler
bash build.sh   # → dist/BarButler.app + dist/BarButler.dmg (universal)
```

## How it works

Same trick as Hidden Bar / Dozer: an invisible 1-pt status item sits just left of `‹`; collapsing inflates it to 10 000 pt, pushing everything on its left out of the bar. The floating panel enumerates status item windows via `CGWindowList` (no permissions) and forwards clicks through the Accessibility API. *Arrange Icons* expands the bar, waits until the icon is really on screen, then simulates a ⌘-drag to drop the real icon left or right of `‹`.

## License

[MIT](LICENSE) © 2026 Bowei
