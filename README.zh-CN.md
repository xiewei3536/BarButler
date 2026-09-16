<div align="center">

# BarButler 菜单栏管家

**让菜单栏呼吸。**

轻巧原生的 macOS 菜单栏管理工具——把不常用的图标收进一个 `‹` 箭头后面。

[English](README.md) · [繁體中文](README.zh-TW.md)

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![arch](https://img.shields.io/badge/通用版本-Intel%20%7C%20Apple%20Silicon-purple)
![license](https://img.shields.io/badge/许可-MIT-green)
[![release](https://img.shields.io/github/v/release/xiewei3536/BarButler)](https://github.com/xiewei3536/BarButler/releases/latest)

</div>

---

## 特色

- **单图标设计**——`‹` 箭头本身就是分隔线兼开关，它左边的图标会被收起。整理菜单栏的工具，自己不该再占两格。
- **悬浮面板模式**——隐藏图标改显示在菜单栏“下方”的精致面板中，点击即可触发原功能。刘海机型、图标多到展开也放不下的救星。
- **悬停展开**——光标移到 `‹` 上图标自动滑出（或打开面板），离开后自动收回。
- **聪明的自动收起**——展开后 5–60 秒自动收回（可调），或在你点击其他地方的瞬间收回；有菜单开着、按着 ⌘ 整理、鼠标还在菜单栏上时绝不打扰。
- **整理时显示分界线**——按住 ⌘ 开始拖拽图标，`‹` 左侧会浮现一条淡淡的线，让你看清口袋从哪里开始。
- **图标样式**——`‹` 可换成箭头、圆点或双向箭头。
- **全局快捷键**——默认 ⌥⌘B，可自行录制；使用 Carbon API，无需辅助功能权限。
- **永久隐藏区**——第二层口袋收纳几乎用不到的图标；⌥ 点击 `‹` 临时查看。
- **快速一览**——显示所有图标 5 秒后自动恢复。
- **自我修复**——分隔元件被拖成不可能的顺序时会自动修正并提示，不会再“全部消失”。
- **三语界面**——简中／繁中／英文，App 内即时切换免重启。
- **自动更新**——内置 Sparkle：新版本会收到通知，可开启全自动下载安装。
- **自动化**——`open barbutler://toggle`（另有 `show`、`hide`、`peek`、`panel`、`mode/float`、`mode/menubar`、`settings`），可在快捷指令、Raycast、Alfred 或终端调用。
- **贴心不啰嗦**——第一次收起图标时给一次提示、`‹` 若被挤出画面会自我修复、权限面板明确告诉你什么功能需要什么（只有悬浮面板的“代点”需要辅助功能，其他一律免权限）。
- **原生轻量**——纯 AppKit/SwiftUI，约 3 MB，无后台常驻服务，Universal Binary。

## 安装

1. 到 [最新版本](https://github.com/xiewei3536/BarButler/releases/latest) 下载 `BarButler.dmg`
2. 把 **BarButler** 拖进「应用程序」
3. 首次打开（本 App 未经 Apple 公证）：
   - macOS 13／14：**右键 → 打开**
   - macOS 15 Sequoia：先打开一次，再到 **系统设置 → 隐私与安全性 → “仍要打开”**
   - 或用终端解除隔离：`xattr -dr com.apple.quarantine /Applications/BarButler.app`

## 使用方式

```
[不常用的图标]  ‹  [常用图标]  [Wi-Fi  电池  时钟]
   ↑ 收起时隐藏      ↑ 箭头——点击切换
```

1. **⌘ + 拖拽**：把图标拖到 `‹` 的**左边**，它们就会被收起
2. **点击 `‹`**（或按 ⌥⌘B）收起／展开
3. **右键点 `‹`**：悬浮面板、快速一览、教程、偏好设置

想以悬浮面板为默认：偏好设置 → 通用 → 展开方式 → 悬浮面板。
点击面板中的图标会**一步到位**打开该图标的真实菜单。这需要“辅助功能”权限（一次性授权；App 以固定身份签名，更新后授权不会失效）。也支持键盘：方向键移动、Return 打开、Esc 关闭。
若前台 App 的菜单太长、图标展开后仍放不下，BarButler 会短暂成为前台 App 腾出空间（Dock 会闪现图标一下）、点开该图标的菜单，收起时自动把前台交还原本的 App。

## 诊断

`swift scripts/inspect_menubar.swift` 会列出所有状态栏图标窗口与位置，反馈问题时很好用。

## 从源码构建

需 macOS 13+ 与 Swift 5.9+（Command Line Tools 即可，无需完整 Xcode）：

```bash
git clone https://github.com/xiewei3536/BarButler.git
cd BarButler
bash build.sh   # → dist/BarButler.app + dist/BarButler.dmg（通用版本）
```

## 工作原理

与 Hidden Bar / Dozer 同技巧：一个隐形的 1pt 状态栏项目贴在 `‹` 左侧，收起时撑宽到 10000pt 把左边的图标全部挤出画面。悬浮面板通过 `CGWindowList` 列出状态栏项目（免权限），点击经由辅助功能 API 转发。

## 许可

[MIT](LICENSE) © 2026 Bowei
