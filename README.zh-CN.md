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
- **悬停展开**——光标移到 `‹` 上图标自动滑出，离开后自动收回。
- **自动收起**——展开后 5–60 秒自动收回（可调）；鼠标还在菜单栏上或按着 ⌘ 整理时会贴心等待。
- **全局快捷键**——默认 ⌥⌘B，可自行录制；使用 Carbon API，无需辅助功能权限。
- **永久隐藏区**——第二层口袋收纳几乎用不到的图标；⌥ 点击 `‹` 临时查看。
- **快速一览**——显示所有图标 5 秒后自动恢复。
- **自我修复**——分隔元件被拖成不可能的顺序时会自动修正并提示，不会再“全部消失”。
- **三语界面**——简中／繁中／英文，App 内即时切换免重启。
- **自动更新**——内置 Sparkle：新版本会收到通知，可开启全自动下载安装。
- **原生轻量**——纯 AppKit/SwiftUI，约 2 MB，无后台常驻服务，Universal Binary。

## 安装

1. 到 [最新版本](https://github.com/xiewei3536/BarButler/releases/latest) 下载 `BarButler.dmg`
2. 把 **BarButler** 拖进「应用程序」
3. 首次打开请「**右键 → 打开**」（本 App 未经 Apple 公证）
   或用终端解除隔离：`xattr -dr com.apple.quarantine /Applications/BarButler.app`

## 使用方式

```
[不常用的图标]  ‹  [常用图标]  [Wi-Fi  电池  时钟]
   ↑ 收起时隐藏      ↑ 箭头——点击切换
```

1. **⌘ + 拖拽**：把图标拖到 `‹` 的**左边**，它们就会被收起
2. **点击 `‹`**（或按 ⌥⌘B）收起／展开
3. **右键点 `‹`**：悬浮面板、快速一览、教程、偏好设置

想以悬浮面板为默认：偏好设置 → 通用 → 展开方式 → 悬浮面板。
面板点击转发使用「辅助功能」权限（可选、一次性授权）；未授权时面板仍会列出隐藏图标，点击改为展开菜单栏。

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
