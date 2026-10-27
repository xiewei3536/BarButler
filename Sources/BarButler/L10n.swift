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
    static let menuArrange = Tr("Arrange Icons…", "整理圖示…", "整理图标…")

    // MARK: 設定 — 分頁與預覽
    static let tabGeneral = Tr("General", "一般", "通用")
    static let tabAdvanced = Tr("Advanced", "進階", "高级")
    static let tabAbout = Tr("About", "關於", "关于")
    static let tabLayout = Tr("Layout", "圖示配置", "图标配置")
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
    static let tipDrag = Tr("Tip: arrange icons in the Layout tab — or hold ⌘ and drag them in the menu bar; anything left of ‹ gets tucked away.",
                            "小提示：到「圖示配置」拖曳整理；也可以按住 ⌘ 直接在選單列拖曳，放在 ‹ 左邊的都會被收起。",
                            "小提示：到“图标配置”拖拽整理；也可以按住 ⌘ 直接在菜单栏拖拽，放在 ‹ 左边的都会被收起。")
    static let btnTutorial = Tr("Show Tutorial", "重看教學", "重看教程")

    // MARK: 設定 — 進階
    static let rowHotkey = Tr("Global Hotkey", "全域快捷鍵", "全局快捷键")
    static let rowHotkeySub = Tr("Toggle (or open the panel) from any app", "在任何 App 中切換（或開啟面板）", "在任何 App 中切换（或打开面板）")
    static let recordPrompt = Tr("Press shortcut… (Esc to cancel)", "請按下組合鍵…（Esc 取消）", "请按下组合键…（Esc 取消）")
    static let clickToSet = Tr("Click to Set", "點擊設定", "点击设置")
    static let rowPermission = Tr("Accessibility Permission", "輔助使用權限", "辅助功能权限")
    static let rowPermissionSub = Tr("Needed to move icons for you (Layout) and to click icons from the panel. Hiding itself needs no permission.",
                                     "「圖示配置」代你移動圖示、懸浮面板代你點擊圖示時需要；單純收合不需要任何權限。",
                                     "“图标配置”代你移动图标、悬浮面板代你点击图标时需要；单纯收起不需要任何权限。")
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
    static let floatFooter = Tr("Click to open · right-click to keep it in the menu bar · Esc to close",
                                "點擊開啟 · 右鍵可設為常駐顯示 · Esc 關閉", "点击打开 · 右键可设为常驻显示 · Esc 关闭")
    static let panelTitle = Tr("Hidden Icons", "隱藏的圖示", "隐藏的图标")
    static let panelArrange = Tr("Arrange", "整理", "整理")
    static let panelRestoreFmt = Tr("%d icons aren't where you put them", "有 %d 個圖示不在你設定的位置", "有 %d 个图标不在你设定的位置")
    static let panelRestoreBtn = Tr("Put Back", "歸位", "归位")
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

    // MARK: 圖示配置
    static let layoutTitle = Tr("Arrange Menu Bar Icons", "整理選單列圖示", "整理菜单栏图标")
    static let layoutSubtitle = Tr("Drag icons between sections, or right-click one to choose. Changes apply to the real menu bar right away.",
                                   "把圖示拖到不同區塊，或在圖示上按右鍵選擇；變更會立刻套用到真正的選單列。",
                                   "把图标拖到不同区块，或在图标上按右键选择；更改会立即应用到真正的菜单栏。")
    static let sectionShown = Tr("Always Shown", "常駐顯示", "常驻显示")
    static let sectionShownSub = Tr("Always visible, right of ‹", "永遠顯示在選單列（‹ 的右邊）", "永远显示在菜单栏（‹ 的右边）")
    static let sectionHidden = Tr("Hidden", "收合區", "收起区")
    static let sectionHiddenSub = Tr("Tucked away — shown when you click or hover ‹, and in the panel",
                                     "平時收起；點擊或懸停 ‹、或在懸浮面板裡出現", "平时收起；点击或悬停 ‹、或在悬浮面板里出现")
    static let sectionAlways = Tr("Always Hidden", "永久隱藏", "永久隐藏")
    static let sectionAlwaysSub = Tr("Rarely needed — ⌥-click ‹ (or the panel) to reach them",
                                     "幾乎用不到的；⌥ 點擊 ‹ 或在面板裡才找得到", "几乎用不到的；⌥ 点击 ‹ 或在面板里才找得到")
    static let sectionEmpty = Tr("Drop icons here", "把圖示拖到這裡", "把图标拖到这里")
    static let moveToShown = Tr("Always Show in Menu Bar", "常駐顯示在選單列", "常驻显示在菜单栏")
    static let moveToHidden = Tr("Move to Hidden", "移到收合區", "移到收起区")
    static let moveToAlways = Tr("Move to Always Hidden", "移到永久隱藏", "移到永久隐藏")
    static let movingFmt = Tr("Moving %@…", "正在移動 %@…", "正在移动 %@…")
    static let movedFmt = Tr("%@ → %@", "%@ 已移到「%@」", "%@ 已移到“%@”")
    static let moveFailed = Tr("Couldn't move %@ — the menu bar may be too full. Try again, or ⌘-drag it by hand.",
                               "無法移動 %@──選單列可能太擠了。請再試一次，或按住 ⌘ 手動拖曳。",
                               "无法移动 %@——菜单栏可能太挤了。请再试一次，或按住 ⌘ 手动拖拽。")
    static let moveGone = Tr("%@ is no longer in the menu bar", "%@ 已不在選單列上", "%@ 已不在菜单栏上")
    static let moveNeedsAX = Tr("Moving icons needs Accessibility permission", "移動圖示需要「輔助使用」權限", "移动图标需要“辅助功能”权限")
    static let moveLocked = Tr("Can't move icons while the screen is locked or a password field is active",
                               "螢幕鎖定或正在輸入密碼時無法移動圖示", "屏幕锁定或正在输入密码时无法移动图标")
    static let moveBusy = Tr("Still moving the previous icon…", "上一個圖示還在移動中…", "上一个图标还在移动中…")
    static let itemLocked = Tr("System item — macOS keeps it on the right", "系統項目──macOS 固定在最右側，無法移動", "系统项目——macOS 固定在最右侧，无法移动")
    static let layoutRefresh = Tr("Refresh", "重新整理", "刷新")
    static let layoutHideAll = Tr("Hide All", "全部收起", "全部收起")
    static let layoutHideAllHelp = Tr("Move ‹ to the right end so every icon goes into Hidden; then pick the few you want shown",
                                      "把 ‹ 移到最右端，所有圖示都進收合區；再挑幾個要常駐的拉出來",
                                      "把 ‹ 移到最右端，所有图标都进收起区；再挑几个要常驻的拉出来")
    static let layoutShowAll = Tr("Show All", "全部顯示", "全部显示")
    static let layoutShowAllHelp = Tr("Move ‹ to the left end so every icon is shown", "把 ‹ 移到最左端，所有圖示都顯示", "把 ‹ 移到最左端，所有图标都显示")
    static let layoutRealIcons = Tr("Real Menu Bar Icons", "顯示真實選單列圖示", "显示真实菜单栏图标")
    static let layoutRealIconsSub = Tr("Needs Screen Recording — only used to capture the small icon images, never your screen",
                                       "需要「螢幕錄製」權限──只用來擷取圖示外觀，不會錄你的畫面",
                                       "需要“屏幕录制”权限——只用来截取图标外观，不会录你的画面")
    static let layoutGrantScreen = Tr("Grant…", "前往授權", "前往授权")
    static let spaceFmt = Tr("Shown icons use %d of %d pt", "常駐區佔用 %d／%d pt", "常驻区占用 %d／%d pt")
    static let spaceWarn = Tr("Lots of shown icons: when an app's menus are long, macOS hides some of them — even ‹. Move a few into Hidden.",
                              "常駐圖示偏多：前景 App 的選單較長時，macOS 會把部分圖示（甚至 ‹）擠掉。建議移幾個到收合區。",
                              "常驻图标偏多：前台 App 的菜单较长时，macOS 会把部分图标（甚至 ‹）挤掉。建议移几个到收起区。")
    static let alwaysOffHint = Tr("Want a third section for icons you never use? Turn on the Always-Hidden zone.",
                                  "想再多一層放「幾乎不用」的圖示？開啟「永久隱藏區」。",
                                  "想再多一层放“几乎不用”的图标？开启“永久隐藏区”。")
    static let btnTurnOn = Tr("Turn On", "開啟", "开启")
    static let whatsNewTitle = Tr("New in 1.4 — arrange icons right here", "1.4 新功能：直接在這裡整理圖示", "1.4 新功能：直接在这里整理图标")
    static let whatsNewBody = Tr("Fixed: after sleep, 1.3 could wrongly reset your layout and stop hiding icons. It now waits for the screen to settle and never resets your arrangement. Drag icons below to set it up again.",
                                 "已修正：1.3 版在睡眠喚醒（尤其外接螢幕）後會誤把配置重設，‹ 因此失靈。現在會等螢幕穩定後才檢查，且絕不再重設你的配置。請在下方拖曳圖示重新配置。",
                                 "已修复：1.3 版在睡眠唤醒（尤其外接显示器）后会误把配置重置，‹ 因此失灵。现在会等屏幕稳定后才检查，且绝不再重置你的配置。请在下方拖拽图标重新配置。")
    static let rowRemember = Tr("Remember Layout", "記住配置、自動歸位", "记住配置、自动归位")
    static let rowRememberSub = Tr("If macOS or an app update shuffles your icons (restart, relaunch, crowded bar), BarButler moves them back",
                                   "重新開機、App 更新重開或選單列重排把圖示打亂時，BarButler 自動把它們移回你指定的區塊",
                                   "重新开机、App 更新重开或菜单栏重排把图标打乱时，BarButler 自动把它们移回你指定的区块")
    static let needAXCard = Tr("Grant Accessibility so BarButler can move icons for you", "授權「輔助使用」後，BarButler 才能代你移動圖示", "授权“辅助功能”后，BarButler 才能代你移动图标")
    static let dragHint = Tr("Drag", "拖曳", "拖拽")

    // MARK: 穩定守護與診斷
    static let rowHealth = Tr("Stability Guard", "穩定守護", "稳定守护")
    static let rowHealthSub = Tr("Checks ‹ after sleep, display changes and relaunches, and repairs gently — never resets your layout",
                                 "睡眠喚醒、換螢幕、重新啟動後自動檢查並溫和修正，絕不重設你的配置",
                                 "睡眠唤醒、换屏幕、重新启动后自动检查并温和修正，绝不重置你的配置")
    static let healthFmt = Tr("Last check %@ · %d repairs", "上次檢查 %@ · 已修正 %d 次", "上次检查 %@ · 已修正 %d 次")
    static let healthNever = Tr("not yet", "尚未", "尚未")
    static let btnCheck = Tr("Check Now", "立即檢查", "立即检查")
    static let rowDiagnose = Tr("Diagnostic Report", "診斷報告", "诊断报告")
    static let rowDiagnoseSub = Tr("Saves the menu bar layout and recent events to a text file (for troubleshooting)",
                                   "把選單列配置與近期事件存成文字檔（回報問題時附上）",
                                   "把菜单栏配置与近期事件存成文本文件（反馈问题时附上）")
    static let btnDiagnose = Tr("Create Report", "產生報告", "生成报告")
    static let toastRecovered = Tr("Fixed: ‹ was out of place — your layout is unchanged",
                                   "已自動修正 ‹ 的位置──你的配置沒有變動", "已自动修正 ‹ 的位置——你的配置没有变动")
    static let toastCrowded = Tr("The menu bar is full and macOS is hiding ‹. Use %@, or move a few icons into Hidden (Arrange Icons…).",
                                 "選單列太擠，macOS 把 ‹ 擠掉了。可用 %@ 叫出，或到「整理圖示」把幾個圖示移進收合區。",
                                 "菜单栏太挤，macOS 把 ‹ 挤掉了。可用 %@ 唤出，或到“整理图标”把几个图标移进收起区。")
    static let cmdMove = Tr("Move an icon", "移動圖示", "移动图标")
    static let cmdArrange = Tr("Arrange icons", "整理圖示", "整理图标")
    static let cmdDiagnose = Tr("Diagnostic report", "診斷報告", "诊断报告")

    // MARK: 新手教學
    static let obTitle = Tr("Welcome to BarButler", "歡迎使用選單列管家", "欢迎使用菜单栏管家")
    static let obSubtitle = Tr("Three steps to a tidy menu bar", "三個步驟，還你一條清爽選單列", "三个步骤，还你一条清爽菜单栏")
    static let obStep1T = Tr("Arrange Icons", "整理圖示", "整理图标")
    static let obStep1D = Tr("Open Arrange Icons and drag each icon into Always Shown or Hidden — BarButler moves the real icon for you. (Holding ⌘ and dragging in the menu bar works too.)",
                             "打開「整理圖示」，把每個圖示拖到「常駐顯示」或「收合區」，BarButler 會替你移動真正的圖示。（按住 ⌘ 直接在選單列拖曳也可以。）",
                             "打开“整理图标”，把每个图标拖到“常驻显示”或“收起区”，BarButler 会替你移动真正的图标。（按住 ⌘ 直接在菜单栏拖拽也可以。）")
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
