# Changelog

## 1.5.0 — 2026-11-17

### Focused panel clicks / 單一圖示聚焦 / 单图标聚焦

- Clicking a hidden icon in the panel temporarily moves **only that icon** to the
  menu bar and opens its real menu. Neither hidden section expands, even briefly.
- Menu dismissal returns the icon to its original neighbours/section. Action-only
  icons get a short grace period; open menus and popovers are never timed out.
- Rapid requests are serialized, with the latest pending click winning. A small
  atomic return ticket enables safe recovery after app restart or interrupted sleep.
- Always-hidden icons use the same isolated path. If isolation fails, BarButler
  leaves the other icons hidden instead of falling back to expanding everything.
- The URL `barbutler://click?item=…` uses the same isolated behaviour.

### Interface / 介面 / 界面

- Refreshed layout overview and case/diacritic-insensitive, multi-term icon/app search.
- Floating panels scroll on long lists and respect the current display's height.
- Up/down arrows follow actual grid rows; Shift-Tab goes backwards. Screen-reader
  labels and reduced-motion support improve panel accessibility.
- Destructive position/layout reset now requires explicit confirmation.
- Internal drag tokens prevent external text drops from replaying a stale move.
- Layout refresh timers stop when Settings closes and resume when it reopens.
- Shortcut recording now reliably resumes the global hotkey after window closure
  or focus loss, and corrupt key-code preferences no longer risk an integer trap.

### Reliability / 穩定性 / 稳定性

- Window-addressed mouse events are verified, bounded by timeouts, and always
  release the synthetic mouse button on cancellation or failure.
- Temporary moves cannot be saved as permanent layout choices; layout editing and
  background repair are kept out of the active interaction.
- Empty automation item selectors no longer accidentally pick the first icon.
  Automation logs omit full query strings; relaunch paths use shell arguments.
- Added automated regression coverage and CI on two macOS runners. Release jobs
  run tests before signing, and signature verification failures stop packaging.
