# Changelog

## Unreleased — recovery hardening / 修復流程強化

- Serialize divider repairs and verify their geometry before reporting success.
  If both pusher-only attempts are ignored, rebuild only BarButler's own toggle
  and pusher, preserving the saved toggle position and all remembered icon sections.
- Cancel stale repair stages across display/system sleep, lock, session changes,
  and display configuration transitions. Delayed checks from an older transition
  cannot mutate a later recovery.
- Bound failed repairs to two attempts per settled session, rather than retrying
  the same failure indefinitely every ten minutes. Manual checks explicitly retry.
- Prevent icon moves and layout recording from racing with anchor replacement.
- Deterministically retain the oldest live instance on overlapping launches and
  ask that instance to show Settings instead of silently ignoring another launch.
- Added deterministic recovery/launch regression tests. **Not released:** real
  sleep/wake, display-change and extended runtime validation remain release gates.

## 2026-11-18 — 1.5.0 distribution paused / 暫停推送 1.5.0

- Paused automatic distribution of 1.5.0 after a report of an unavailable menu-bar
  interface. Investigation found a live process and repeated divider re-anchoring
  failures that persisted through sleep/wake; the initiating trigger is unconfirmed.
  No process crash report was found in the captured incident.
- The stable update feed points back to 1.4.1 while the recovery path is verified.
  Existing 1.5.0 installations are not silently downgraded. Preferences and saved
  icon layouts must be retained during manual recovery.

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
  or focus loss. Corrupt key-code preferences no longer risk an integer trap,
  and the letter F is no longer mistaken for an unmodified function-key shortcut.

### Reliability / 穩定性 / 稳定性

- Window-addressed mouse events are verified, bounded by timeouts, and always
  release the synthetic mouse button on cancellation or failure.
- Temporary moves cannot be saved as permanent layout choices; layout editing and
  background repair are kept out of the active interaction.
- Empty automation item selectors no longer accidentally pick the first icon.
  Automation logs omit full query strings; relaunch paths use shell arguments.
- Updated Sparkle to 2.10.1 and moved release builds off the retired runner.
- Added automated regression coverage and CI on Intel and Apple Silicon runners. Release jobs
  run tests before signing, signing keys are passed through stdin instead of a
  plaintext temporary file, and signature verification failures stop packaging.
