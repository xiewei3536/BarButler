<div align="center">

# BarButler 選單列管家

**讓選單列呼吸。**

輕巧原生的 macOS 選單列管理工具——把不常用的圖示收進一個 `‹` 箭頭後面。

[English](README.md) · [简体中文](README.zh-CN.md)

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![arch](https://img.shields.io/badge/通用版本-Intel%20%7C%20Apple%20Silicon-purple)
![license](https://img.shields.io/badge/授權-MIT-green)
[![release](https://img.shields.io/github/v/release/xiewei3536/BarButler)](https://github.com/xiewei3536/BarButler/releases/latest)

</div>

---

## 特色

- **單一圖示設計**──`‹` 箭頭本身就是分隔線兼開關，它左邊的圖示會被收起。整理選單列的工具，自己不該再佔兩格。
- **懸浮面板模式**──隱藏圖示改顯示在選單列「下方」的精緻面板中，點擊即可觸發原功能。瀏海機型、圖示多到展開也放不下的救星。
- **懸停展開**──游標移到 `‹` 上圖示自動滑出（或開啟面板），離開後自動收回。
- **聰明的自動收合**──展開後 5–60 秒自動收回（可調），或在你點擊其他地方的瞬間收回；有選單開著、按著 ⌘ 整理、滑鼠還在選單列上時絕不打擾。
- **整理時顯示分界線**──按住 ⌘ 開始拖曳圖示，`‹` 左側會浮現一條淡淡的線，讓你看清口袋從哪裡開始。
- **圖示樣式**──`‹` 可換成箭頭、圓點或雙向箭頭。
- **全域快捷鍵**──預設 ⌥⌘B，可自行錄製；使用 Carbon API，不需輔助使用權限。
- **永久隱藏區**──第二層口袋收納幾乎用不到的圖示；⌥ 點擊 `‹` 暫時查看。
- **快速一覽**──顯示所有圖示 5 秒後自動恢復。
- **自我修復**──分隔元件被拖成不可能的順序時會自動修正並提示，不會再「全部消失」。
- **三語介面**──繁中／簡中／英文，App 內即時切換免重啟。
- **自動更新**──內建 Sparkle：新版本會收到通知，可開啟全自動下載安裝。
- **自動化**──`open barbutler://toggle`（另有 `show`、`hide`、`peek`、`panel`、`mode/float`、`mode/menubar`、`settings`），可在捷徑、Raycast、Alfred 或終端機呼叫。
- **貼心不囉嗦**──第一次收起圖示時給一次提示、`‹` 若被擠出畫面會自我修復、權限面板明確告訴你什麼功能需要什麼（只有懸浮面板的「代點」需要輔助使用，其他一律免權限）。
- **原生輕量**──純 AppKit/SwiftUI，約 3 MB，無背景常駐服務，Universal Binary。

## 安裝

1. 到 [最新版本](https://github.com/xiewei3536/BarButler/releases/latest) 下載 `BarButler.dmg`
2. 把 **BarButler** 拖進「應用程式」
3. 首次開啟（本 App 未經 Apple 公證）：
   - macOS 13／14：**右鍵 → 打開**
   - macOS 15 Sequoia：先開啟一次，再到 **系統設定 → 隱私權與安全性 → 「仍要打開」**
   - 或用終端機解除隔離：`xattr -dr com.apple.quarantine /Applications/BarButler.app`

## 使用方式

```
[不常用的圖示]  ‹  [常用圖示]  [Wi-Fi  電池  時鐘]
   ↑ 收合時隱藏      ↑ 箭頭──點擊切換
```

1. **⌘ + 拖曳**：把圖示拖到 `‹` 的**左邊**，它們就會被收起
2. **點擊 `‹`**（或按 ⌥⌘B）收合／展開
3. **右鍵點 `‹`**：懸浮面板、快速一覽、教學、偏好設定

想以懸浮面板為預設：偏好設定 → 一般 → 展開方式 → 懸浮面板。
點擊面板中的圖示會**一步到位**開啟該圖示的真實選單。這需要「輔助使用」權限（一次性授權；App 以固定身分簽名，更新後授權不會失效）。也支援鍵盤：方向鍵移動、Return 開啟、Esc 關閉。

## 診斷

`swift scripts/inspect_menubar.swift` 會列出所有狀態列圖示視窗與位置，回報問題時很好用。

## 從原始碼建置

需 macOS 13+ 與 Swift 5.9+（Command Line Tools 即可，不需完整 Xcode）：

```bash
git clone https://github.com/xiewei3536/BarButler.git
cd BarButler
bash build.sh   # → dist/BarButler.app + dist/BarButler.dmg（通用版本）
```

## 運作原理

與 Hidden Bar / Dozer 同技巧：一個隱形的 1pt 狀態列項目貼在 `‹` 左側，收合時撐寬到 10000pt 把左邊的圖示全部擠出畫面。懸浮面板透過 `CGWindowList` 列出狀態列項目（免權限），點擊經由輔助使用 API 轉發。

## 授權

[MIT](LICENSE) © 2026 Bowei
