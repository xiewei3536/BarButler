import Foundation

/// 三語字串（en / 繁中 / 簡中），支援 App 內即時切換
struct Tr {
    let en: String, hant: String, hans: String
    init(_ en: String, _ hant: String, _ hans: String) {
        self.en = en; self.hant = hant; self.hans = hans
    }
    var s: String {
        switch L.resolved {
        case .en: return en
        case .hant: return hant
        case .hans: return hans
        }
    }
    func f(_ args: CVarArg...) -> String { String(format: s, arguments: args) }
}

enum ResolvedLang { case en, hant, hans }

enum L {
    static var resolved: ResolvedLang {
        switch Prefs.shared.language {
        case "en": return .en
        case "zh-Hant": return .hant
        case "zh-Hans": return .hans
        default:
            for id in Locale.preferredLanguages {
                let l = id.lowercased()
                if l.hasPrefix("zh") {
                    if l.contains("hant") || l.contains("-tw") || l.contains("-hk") || l.contains("-mo") { return .hant }
                    return .hans
                }
                if l.hasPrefix("en") { return .en }
            }
            return .en
        }
    }

    // MARK: 選單列
    static let appName = Tr("BarButler", "選單列管家", "菜单栏管家")
    static let tooltipMenubar = Tr("Click or hover: show hidden icons · ⌥ click: always-hidden zone · right-click: menu",
                                   "點擊或懸停：展開隱藏圖示｜⌥ 點擊：永久隱藏區｜右鍵：選單",
                                   "点击或悬停：展开隐藏图标｜⌥ 点击：永久隐藏区｜右键：菜单")
    static let tooltipFloat = Tr("Click: hidden icons panel · ⌥ click: always-hidden zone · right-click: menu",
                                 "點擊：隱藏圖示面板｜⌥ 點擊：永久隱藏區｜右鍵：選單",
                                 "点击：隐藏图标面板｜⌥ 点击：永久隐藏区｜右键：菜单")
    static let menuHide = Tr("Hide Icons", "收合圖示", "收起图标")
    static let menuShow = Tr("Show Hidden Icons", "顯示隱藏的圖示", "显示隐藏的图标")
    static let menuPeek = Tr("Peek for 5 Seconds", "快速一覽 5 秒", "快速一览 5 秒")
    static let menuRevealAlways = Tr("Show Always-Hidden Zone", "顯示「永久隱藏」區", "显示“永久隐藏”区")
    static let menuHideAlways = Tr("Hide Always-Hidden Zone", "隱藏「永久隱藏」區", "隐藏“永久隐藏”区")
    static let menuHowTo = Tr("How to Arrange Icons…", "如何整理圖示…", "如何整理图标…")
    static let menuFloatPanel = Tr("Hidden Icons Panel", "隱藏圖示面板", "隐藏图标面板")
    static let menuFloatMode = Tr("Floating Panel Mode", "懸浮面板模式", "悬浮面板模式")
    static let menuLoginItem = Tr("Launch at Login", "登入時啟動", "登录时启动")
    static let menuSettings = Tr("Settings…", "偏好設定…", "偏好设置…")
    static let menuQuit = Tr("Quit BarButler", "結束 BarButler", "退出 BarButler")
    static let menuCheckUpdates = Tr("Check for Updates…", "檢查更新…", "检查更新…")

    // MARK: 設定 — 分頁與預覽
    static let tabGeneral = Tr("General", "一般", "通用")
    static let tabAdvanced = Tr("Advanced", "進階", "高级")
    static let tabAbout = Tr("About", "關於", "关于")
    static let previewTitle = Tr("Live Preview", "即時預覽", "实时预览")
    static let previewMenubar = Tr("Click or hover ‹ — hidden icons slide out in the menu bar",
                                   "點擊或懸停 ‹ ── 隱藏的圖示在選單列中滑出",
                                   "点击或悬停 ‹ —— 隐藏的图标在菜单栏中滑出")
    static let previewFloat = Tr("Click ‹ — hidden icons appear in a panel below; click one to open its menu",
                                 "點擊 ‹ ── 隱藏的圖示顯示在下方面板；點一下就開啟它的選單",
                                 "点击 ‹ —— 隐藏的图标显示在下方面板；点一下就打开它的菜单")

    // MARK: 設定 — 一般
    static let rowLanguage = Tr("Language", "語言", "语言")
    static let langAuto = Tr("Follow System", "跟隨系統", "跟随系统")
    static let rowLaunch = Tr("Launch at Login", "登入時啟動", "登录时启动")
    static let rowLaunchSub = Tr("Start automatically after login", "開機登入後自動啟動", "开机登录后自动启动")
    static let rowExpandStyle = Tr("Expand Style", "展開方式", "展开方式")
    static let rowExpandStyleSub = Tr("Floating panel suits notched Macs or a packed menu bar",
                                      "懸浮面板適合瀏海機型，或圖示多到展開也放不下的情況",
                                      "悬浮面板适合刘海机型，或图标多到展开也放不下的情况")
    static let modeMenubar = Tr("In Menu Bar", "選單列展開", "菜单栏展开")
    static let modeFloat = Tr("Floating Panel", "懸浮面板", "悬浮面板")
    static let rowIconStyle = Tr("Icon Style", "‹ 圖示樣式", "‹ 图标样式")
    static let styleChevron = Tr("Chevron", "箭頭", "箭头")
    static let styleDots = Tr("Dots", "圓點", "圆点")
    static let styleArrows = Tr("Arrows", "雙向箭頭", "双向箭头")
    static let rowAutoCollapse = Tr("Auto-Collapse", "自動收合", "自动收起")
    static let rowAutoCollapseSub = Tr("Re-hide after expanding. Waits while a menu is open or you're ⌘-dragging",
                                       "展開一段時間後自動收合；有選單開著或按住 ⌘ 整理時會等你",
                                       "展开一段时间后自动收起；有菜单开着或按住 ⌘ 整理时会等你")
    static let never = Tr("Never", "永不", "从不")
    static let secondsFmt = Tr("%d sec", "%d 秒", "%d 秒")
    static let rowHover = Tr("Expand on Hover", "滑鼠懸停展開", "鼠标悬停展开")
    static let rowHoverSub = Tr("Point at ‹ to expand (or open the panel) — no click needed",
                                "游標移到 ‹ 上即自動展開（或開啟面板），免點擊",
                                "光标移到 ‹ 上即自动展开（或打开面板），免点击")
    static let rowClickAway = Tr("Collapse on Click Elsewhere", "點擊他處即收合", "点击他处即收起")
    static let rowClickAwaySub = Tr("Click anywhere outside the menu bar to collapse right away",
                                    "在選單列以外任意處點一下，立即收合",
                                    "在菜单栏以外任意处点一下，立即收起")
    static let tipDrag = Tr("Tip: hold ⌘ and drag menu bar icons — anything left of ‹ gets tucked away.",
                            "小提示：按住 ⌘ 拖曳選單列圖示；放在 ‹ 左邊的都會被收起。",
                            "小提示：按住 ⌘ 拖拽菜单栏图标；放在 ‹ 左边的都会被收起。")
    static let btnTutorial = Tr("Show Tutorial", "重看教學", "重看教程")

    // MARK: 設定 — 進階
    static let rowHotkey = Tr("Global Hotkey", "全域快捷鍵", "全局快捷键")
    static let rowHotkeySub = Tr("Toggle (or open the panel) from any app", "在任何 App 中切換（或開啟面板）", "在任何 App 中切换（或打开面板）")
    static let recordPrompt = Tr("Press shortcut… (Esc to cancel)", "請按下組合鍵…（Esc 取消）", "请按下组合键…（Esc 取消）")
    static let clickToSet = Tr("Click to Set", "點擊設定", "点击设置")
    static let rowPermission = Tr("Accessibility Permission", "輔助使用權限", "辅助功能权限")
    static let rowPermissionSub = Tr("Only needed for the panel to click icons for you. Nothing else needs permissions.",
                                     "只有懸浮面板「代你點擊圖示」需要；其他功能一律不需任何權限。",
                                     "只有悬浮面板“代你点击图标”需要；其他功能一律不需任何权限。")
    static let permGranted = Tr("Granted", "已授權", "已授权")
    static let permMissing = Tr("Not granted", "未授權", "未授权")
    static let btnOpenPrivacy = Tr("Open System Settings", "打開系統設定", "打开系统设置")
    static let rowBoundary = Tr("Show Boundary While Arranging", "整理時顯示分界線", "整理时显示分界线")
    static let rowBoundarySub = Tr("While ⌘-dragging icons, a faint line appears left of ‹ so you can see where the pocket starts",
                                   "按住 ⌘ 拖曳圖示時，‹ 左側浮現一條淡淡的線，讓你看清口袋從哪裡開始",
                                   "按住 ⌘ 拖拽图标时，‹ 左侧浮现一条淡淡的线，让你看清口袋从哪里开始")
    static let rowPanelLabels = Tr("App Names in Panel", "面板顯示 App 名稱", "面板显示 App 名称")
    static let rowPanelLabelsSub = Tr("Show a name under each icon in the floating panel",
                                      "在懸浮面板每個圖示下方顯示名稱", "在悬浮面板每个图标下方显示名称")
    static let rowAlways = Tr("Always-Hidden Zone", "永久隱藏區", "永久隐藏区")
    static let rowAlwaysSub = Tr("A second pocket further left for icons you almost never need. ⌥ click ‹ to peek.",
                                 "更左邊的第二層口袋，收納幾乎用不到的圖示；⌥ 點擊 ‹ 可暫時查看。",
                                 "更左边的第二层口袋，收纳几乎用不到的图标；⌥ 点击 ‹ 可临时查看。")
    static let rowBorrow = Tr("Make Room When the Bar Is Full", "空間不足時暫借選單列", "空间不足时暂借菜单栏")
    static let rowBorrowSub = Tr("When icons won't fit, BarButler briefly becomes the front app (a Dock icon appears for a moment) to free the left side, then switches back on collapse. The panel always does this automatically when needed.",
                                 "預測到圖示放不下時，讓 BarButler 短暫成為前景 App（Dock 會暫時出現圖示）以騰出左側空間，收合時自動切回原 App。懸浮面板代點時一律自動處理。",
                                 "预测到图标放不下时，让 BarButler 短暂成为前台 App（Dock 会暂时出现图标）以腾出左侧空间，收起时自动切回原 App。悬浮面板代点时一律自动处理。")
    static let borrowMenuTitle = Tr("Making room in the menu bar…", "正在騰出選單列空間…", "正在腾出菜单栏空间…")
    static let toastOverflow = Tr("The menu bar is full — %d icons don't fit. The floating panel can open them directly.",
                                  "選單列空間不足，有 %d 個圖示放不下──用懸浮面板點它們最快",
                                  "菜单栏空间不足，有 %d 个图标放不下——用悬浮面板点它们最快")
    static let rowPeek = Tr("Quick Peek", "快速一覽", "快速一览")
    static let rowPeekSub = Tr("Reveal everything for 5 seconds, then restore",
                               "顯示所有圖示 5 秒後自動恢復原狀", "显示所有图标 5 秒后自动恢复原状")
    static let btnPeekNow = Tr("Peek Now", "立即一覽", "立即一览")
    static let rowAutomation = Tr("Automation", "自動化", "自动化")
    static let rowAutomationSub = Tr("Call from Shortcuts, Raycast, Alfred or Terminal — e.g. open barbutler://toggle",
                                     "可在捷徑、Raycast、Alfred 或終端機呼叫，例如 open barbutler://toggle",
                                     "可在快捷指令、Raycast、Alfred 或终端调用，例如 open barbutler://toggle")
    static let cmdToggle = Tr("Toggle", "切換收合", "切换收起")
    static let cmdShow = Tr("Expand", "展開", "展开")
    static let cmdHide = Tr("Collapse", "收合", "收起")
    static let cmdPeek = Tr("Peek 5 s", "快速一覽", "快速一览")
    static let cmdPanel = Tr("Toggle panel", "開關面板", "开关面板")
    static let cmdSettings = Tr("Settings", "偏好設定", "偏好设置")
    static let copied = Tr("Copied", "已複製", "已复制")
    static let rowReset = Tr("Reset Positions", "重設位置", "重置位置")
    static let rowResetSub = Tr("Move ‹ back to the right end and relaunch",
                                "讓 ‹ 回到最右側並重新啟動 App", "让 ‹ 回到最右侧并重新启动 App")
    static let btnReset = Tr("Reset & Relaunch", "重設並重啟", "重置并重启")

    // MARK: 設定 — 關於
    static let aboutTagline = Tr("Give your menu bar room to breathe.", "讓選單列呼吸。", "让菜单栏呼吸。")
    static let aboutUniversal = Tr("Universal — Intel & Apple Silicon", "通用版本 ─ Intel 與 Apple Silicon", "通用版本 — Intel 与 Apple Silicon")
    static let versionFmt = Tr("Version %@", "版本 %@", "版本 %@")
    static let aboutGitHub = Tr("GitHub", "GitHub 專案頁", "GitHub 项目页")
    static let aboutIssue = Tr("Report an Issue", "回報問題", "反馈问题")
    static let rowUpdates = Tr("Software Updates", "軟體更新", "软件更新")
    static let rowAutoCheck = Tr("Check automatically", "自動檢查更新", "自动检查更新")
    static let rowAutoDownload = Tr("Download & install automatically", "自動下載並安裝", "自动下载并安装")
    static let btnCheckNow = Tr("Check Now", "立即檢查", "立即检查")
    static let alertLoginFail = Tr("Could not change login item", "無法變更登入項目", "无法更改登录项")
    static let ok = Tr("OK", "好", "好")

    // MARK: 懸浮面板
    static let floatEmpty = Tr("No hidden icons yet — hold ⌘ and drag icons to the left of ‹",
                               "還沒有隱藏的圖示──按住 ⌘ 把圖示拖到 ‹ 左邊",
                               "还没有隐藏的图标——按住 ⌘ 把图标拖到 ‹ 左边")
    static let floatFooter = Tr("Click an icon to open its menu · Esc to close",
                                "點擊圖示開啟它的選單 · Esc 關閉", "点击图标打开它的菜单 · Esc 关闭")
    static let floatAXHint = Tr("Grant Accessibility so clicks open the icon's menu directly",
                                "授權「輔助使用」後，點擊就會直接開啟該圖示的選單",
                                "授权“辅助功能”后，点击就会直接打开该图标的菜单")
    static let floatGrant = Tr("Grant…", "前往授權", "前往授权")
    static let floatNeedAX = Tr("Accessibility permission is needed to click icons for you",
                                "需要「輔助使用」權限才能代你點擊圖示",
                                "需要“辅助功能”权限才能代你点击图标")

    // MARK: 提示
    static let toastFixed = Tr("Auto-fixed: the always-hidden divider was moved back left of ‹",
                               "已自動修正：永久隱藏區分隔線已移回 ‹ 左側",
                               "已自动修正：永久隐藏区分隔线已移回 ‹ 左侧")
    static let toastHealed = Tr("‹ was pushed off-screen — moved it back to the right end",
                                "‹ 被擠出畫面了──已移回最右側", "‹ 被挤出画面了——已移回最右侧")
    static let toastHiddenCount = Tr("%d icons tucked away — click ‹ anytime to show them",
                                     "已收起 %d 個圖示──點 ‹ 隨時展開", "已收起 %d 个图标——点 ‹ 随时展开")
    static let toastNothingHidden = Tr("Nothing hidden yet — hold ⌘ and drag an icon to the left of ‹",
                                       "還沒有隱藏任何圖示──按住 ⌘ 把圖示拖到 ‹ 左邊試試",
                                       "还没有隐藏任何图标——按住 ⌘ 把图标拖到 ‹ 左边试试")
    static let toastLoginOn = Tr("BarButler will launch at login", "已設定登入時啟動", "已设置登录时启动")
    static let toastLoginOff = Tr("Launch at login turned off", "已取消登入時啟動", "已取消登录时启动")
    static let toastModeFloat = Tr("Floating panel mode on", "已切換為懸浮面板模式", "已切换为悬浮面板模式")
    static let toastModeMenubar = Tr("Menu bar expand mode on", "已切換為選單列展開模式", "已切换为菜单栏展开模式")
    static let toastUpdateAvailable = Tr("BarButler %@ is available — see the update window",
                                         "BarButler %@ 已推出──請看更新視窗", "BarButler %@ 已推出——请看更新窗口")

    // MARK: 新手教學
    static let obTitle = Tr("Welcome to BarButler", "歡迎使用選單列管家", "欢迎使用菜单栏管家")
    static let obSubtitle = Tr("Three steps to a tidy menu bar", "三個步驟，還你一條清爽選單列", "三个步骤，还你一条清爽菜单栏")
    static let obStep1T = Tr("⌘ + Drag", "⌘ + 拖曳", "⌘ + 拖拽")
    static let obStep1D = Tr("Hold ⌘ and drag icons to the LEFT of ‹ — they'll be tucked away. A faint line shows you the boundary while you drag.",
                             "按住 ⌘ 把圖示拖到 ‹ 的「左邊」，它們就會被收進口袋；拖曳時會浮現一條分界線幫你對位。",
                             "按住 ⌘ 把图标拖到 ‹ 的“左边”，它们就会被收进口袋；拖拽时会浮现一条分界线帮你对位。")
    static let obStep2T = Tr("Click or Hover ‹", "點擊或懸停 ‹", "点击或悬停 ‹")
    static let obStep2D = Tr("Hidden icons slide out; they tuck back in after a moment or when you click elsewhere.",
                             "隱藏的圖示會滑出來；稍後或點擊其他地方時自動收回。",
                             "隐藏的图标会滑出来；稍后或点击其他地方时自动收回。")
    static let obStep3T = Tr("Floating Panel & Hotkey", "懸浮面板與快捷鍵", "悬浮面板与快捷键")
    static let obStep3D = Tr("Prefer a panel below the menu bar? Switch in Settings. ⌥⌘B works from anywhere.",
                             "想改成在選單列下方彈出面板？到偏好設定切換。⌥⌘B 在任何地方都能用。",
                             "想改成在菜单栏下方弹出面板？到偏好设置切换。⌥⌘B 在任何地方都能用。")
    static let obLaunch = Tr("Launch at login", "登入時自動啟動", "登录时自动启动")
    static let obStart = Tr("Get Started", "開始使用", "开始使用")
    static let obSettings = Tr("Open Settings", "打開偏好設定", "打开偏好设置")
}
