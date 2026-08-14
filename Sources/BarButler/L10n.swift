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

    // 選單列
    static let appName = Tr("BarButler", "選單列管家", "菜单栏管家")
    static let tooltip = Tr("BarButler — click: toggle · ⌥ click: always-hidden · right-click: menu",
                            "BarButler ─ 點擊：收合／展開｜⌥ 點擊：永久隱藏區｜右鍵：選單",
                            "BarButler — 点击：收起／展开｜⌥ 点击：永久隐藏区｜右键：菜单")
    static let menuHide = Tr("Hide Icons", "收合圖示", "收起图标")
    static let menuShow = Tr("Show Hidden Icons", "顯示隱藏的圖示", "显示隐藏的图标")
    static let menuPeek = Tr("Peek for 5 Seconds", "快速一覽 5 秒", "快速一览 5 秒")
    static let menuRevealAlways = Tr("Show Always-Hidden Zone", "顯示「永久隱藏」區", "显示“永久隐藏”区")
    static let menuHideAlways = Tr("Hide Always-Hidden Zone", "隱藏「永久隱藏」區", "隐藏“永久隐藏”区")
    static let menuHowTo = Tr("How to Arrange Icons…", "如何整理圖示…", "如何整理图标…")
    static let menuFloatPanel = Tr("Show Hidden Icons Panel", "顯示隱藏圖示面板", "显示隐藏图标面板")
    static let menuSettings = Tr("Settings…", "偏好設定…", "偏好设置…")
    static let menuQuit = Tr("Quit BarButler", "結束 BarButler", "退出 BarButler")
    static let menuCheckUpdates = Tr("Check for Updates…", "檢查更新…", "检查更新…")
    static let rowUpdates = Tr("Software Updates", "軟體更新", "软件更新")
    static let rowAutoCheck = Tr("Check automatically", "自動檢查更新", "自动检查更新")
    static let rowAutoDownload = Tr("Download & install automatically", "自動下載並安裝", "自动下载并安装")
    static let btnCheckNow = Tr("Check Now", "立即檢查", "立即检查")

    // 設定視窗
    static let tabGeneral = Tr("General", "一般", "通用")
    static let tabAdvanced = Tr("Advanced", "進階", "高级")
    static let tabAbout = Tr("About", "關於", "关于")
    static let rowLanguage = Tr("Language", "語言", "语言")
    static let langAuto = Tr("Follow System", "跟隨系統", "跟随系统")
    static let rowLaunch = Tr("Launch at Login", "登入時啟動", "登录时启动")
    static let rowLaunchSub = Tr("Start automatically after login", "開機登入後自動啟動", "开机登录后自动启动")
    static let rowAutoCollapse = Tr("Auto-Collapse", "自動收合", "自动收起")
    static let rowAutoCollapseSub = Tr("Re-hide icons after expanding", "展開一段時間後自動收合", "展开一段时间后自动收起")
    static let never = Tr("Never", "永不", "从不")
    static let secondsFmt = Tr("%d sec", "%d 秒", "%d 秒")
    static let rowHover = Tr("Expand on Hover", "滑鼠懸停展開", "鼠标悬停展开")
    static let rowHoverSub = Tr("Point at ‹ to expand — no click needed (menu bar mode only)",
                                "游標移到 ‹ 上即自動展開，免點擊（僅選單列模式）",
                                "光标移到 ‹ 上即自动展开，免点击（仅菜单栏模式）")
    static let rowExpandStyle = Tr("Expand Style", "展開方式", "展开方式")
    static let rowExpandStyleSub = Tr("Floating panel suits notched Macs or a packed menu bar — hidden icons appear below instead",
                                      "懸浮面板適合瀏海機型或圖示爆滿的情況──隱藏圖示改顯示在選單列下方，不佔選單列空間",
                                      "悬浮面板适合刘海机型或图标爆满的情况——隐藏图标改显示在菜单栏下方，不占菜单栏空间")
    static let modeMenubar = Tr("In the Menu Bar", "在選單列展開", "在菜单栏展开")
    static let modeFloat = Tr("Floating Panel", "懸浮面板", "悬浮面板")
    static let floatEmpty = Tr("No hidden icons — ⌘ drag icons to the left of ‹",
                               "沒有隱藏的圖示──按住 ⌘ 把圖示拖到 ‹ 左邊",
                               "没有隐藏的图标——按住 ⌘ 把图标拖到 ‹ 左边")
    static let floatAXHint = Tr("Grant Accessibility to click icons directly",
                                "授權「輔助使用」後可直接點擊圖示",
                                "授权“辅助功能”后可直接点击图标")
    static let floatGrant = Tr("Grant…", "前往授權", "前往授权")
    static let floatNeedAX = Tr("Accessibility permission is needed to click icons for you — grant it, then try again",
                                "需要「輔助使用」權限才能代你點擊圖示──授權後再試一次",
                                "需要“辅助功能”权限才能代你点击图标——授权后再试一次")
    static let rowHotkey = Tr("Global Hotkey", "全域快捷鍵", "全局快捷键")
    static let rowHotkeySub = Tr("Toggle from any app", "在任何 App 中快速切換", "在任何 App 中快速切换")
    static let recordPrompt = Tr("Press shortcut… (Esc to cancel)", "請按下組合鍵…（Esc 取消）", "请按下组合键…（Esc 取消）")
    static let clickToSet = Tr("Click to Set", "點擊設定", "点击设置")
    static let rowAlways = Tr("Always-Hidden Zone", "永久隱藏區", "永久隐藏区")
    static let rowAlwaysSub = Tr("A hidden second pocket for icons you almost never need. ⌥ click ‹ to peek at them.",
                                 "第二層隱形口袋，收納幾乎用不到的圖示；⌥ 點擊 ‹ 可暫時查看。",
                                 "第二层隐形口袋，收纳几乎用不到的图标；⌥ 点击 ‹ 可临时查看。")
    static let rowPeek = Tr("Quick Peek", "快速一覽", "快速一览")
    static let rowPeekSub = Tr("Reveal everything for 5 seconds, then restore",
                               "顯示所有圖示 5 秒後自動恢復原狀", "显示所有图标 5 秒后自动恢复原状")
    static let btnPeekNow = Tr("Peek Now", "立即一覽", "立即一览")
    static let rowReset = Tr("Reset Positions", "重設位置", "重置位置")
    static let rowResetSub = Tr("Move ‹ back to the right end and relaunch",
                                "讓 ‹ 回到最右側並重新啟動 App", "让 ‹ 回到最右侧并重新启动 App")
    static let btnReset = Tr("Reset & Relaunch", "重設並重啟", "重置并重启")
    static let tipDrag = Tr("Tip: hold ⌘ and drag menu bar icons — anything left of ‹ gets tucked away.",
                            "小提示：按住 ⌘ 拖曳選單列圖示；放在 ‹ 左邊的都會被收起。",
                            "小提示：按住 ⌘ 拖拽菜单栏图标；放在 ‹ 左边的都会被收起。")
    static let btnTutorial = Tr("Show Tutorial Again", "重看新手教學", "重看新手教程")
    static let aboutTagline = Tr("Give your menu bar room to breathe.", "讓選單列呼吸。", "让菜单栏呼吸。")
    static let aboutUniversal = Tr("Universal — Intel & Apple Silicon", "通用版本 ─ Intel 與 Apple Silicon", "通用版本 — Intel 与 Apple Silicon")
    static let versionFmt = Tr("Version %@", "版本 %@", "版本 %@")
    static let alertLoginFail = Tr("Could not change login item", "無法變更登入項目", "无法更改登录项")
    static let ok = Tr("OK", "好", "好")

    // 提示
    static let toastFixed = Tr("Auto-fixed: the always-hidden divider must stay left of ‹",
                               "已自動修正：永久隱藏區分隔線需在 ‹ 左側",
                               "已自动修正：永久隐藏区分隔线需在 ‹ 左侧")

    // 新手教學
    static let obTitle = Tr("Welcome to BarButler", "歡迎使用選單列管家", "欢迎使用菜单栏管家")
    static let obSubtitle = Tr("Three steps to a tidy menu bar", "三個步驟，還你一條清爽選單列", "三个步骤，还你一条清爽菜单栏")
    static let obStep1T = Tr("⌘ + Drag", "⌘ + 拖曳", "⌘ + 拖拽")
    static let obStep1D = Tr("Hold ⌘ and drag icons to the LEFT of ‹ — they'll be tucked away.",
                             "按住 ⌘ 把圖示拖到 ‹ 的「左邊」，它們就會被收進口袋。",
                             "按住 ⌘ 把图标拖到 ‹ 的“左边”，它们就会被收进口袋。")
    static let obStep2T = Tr("Click ‹ to Toggle", "點擊 ‹ 切換", "点击 ‹ 切换")
    static let obStep2D = Tr("One click hides or shows them. Hovering over ‹ expands automatically, too.",
                             "點一下即可收合／展開；滑鼠懸停在 ‹ 上也會自動展開。",
                             "点一下即可收起／展开；鼠标悬停在 ‹ 上也会自动展开。")
    static let obStep3T = Tr("Power Features", "進階玩法", "进阶玩法")
    static let obStep3D = Tr("Global hotkey ⌥⌘B, floating panel mode, 5-second peek — all in Settings.",
                             "全域快捷鍵 ⌥⌘B、懸浮面板模式、快速一覽 5 秒──都在偏好設定裡。",
                             "全局快捷键 ⌥⌘B、悬浮面板模式、快速一览 5 秒——都在偏好设置里。")
    static let obStart = Tr("Get Started", "開始使用", "开始使用")
    static let obSettings = Tr("Open Settings", "打開偏好設定", "打开偏好设置")
}
