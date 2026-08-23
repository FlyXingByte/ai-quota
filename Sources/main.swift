import AppKit
import Combine
import ServiceManagement
import SwiftUI

// MARK: - Headless modes (used for verification and troubleshooting)

let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    print("""
    \(AppInfo.name) \(AppInfo.version)

      --probe            读取全部配额并打印为文本，然后退出
      --dump <来源>      抓取原始响应（opencode | billing | codex | claude）
      --snapshot         把面板离屏渲染成 ~/Desktop/ai-quota-preview.png
      --snapshot-setup   把无凭据的首次设置界面渲染到 /private/tmp
      --config           打印配置文件路径和当前内容
      --identity         打印 App 身份、图标和登录项状态
      --self-test        运行离线发布自检
    不带参数时以菜单栏 App 运行。
    """)
    exit(0)
}

if args.contains("--snapshot-setup") {
    let out = URL(fileURLWithPath: "/private/tmp/ai-quota-setup-preview.png")
    _ = NSApplication.shared
    final class SetupRenderFlag: @unchecked Sendable { var done = false }
    let flag = SetupRenderFlag()
    Task { @MainActor in
        let store = QuotaStore(config: Config())
        let view = SetupView(store: store)
            .frame(width: 372)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: out)
                print("已渲染首次设置界面 -> \(out.path)")
            }
        }
        window.orderOut(nil)
        flag.done = true
    }
    while !flag.done {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    exit(0)
}

if args.contains("--self-test") {
    var failures: [String] = []
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures.append(message) }
    }

    let sampleWorkspace = "wrk" + "_example"
    expect(SetupView.workspaceID(from: sampleWorkspace) == sampleWorkspace,
           "workspace ID passthrough")
    expect(SetupView.workspaceID(
        from: "https://opencode.ai/workspace/\(sampleWorkspace)/go") == sampleWorkspace,
        "workspace URL extraction")

    let legacyObject: [String: Any] = [
        "opencodeWorkspaceID": sampleWorkspace,
        "deepseekKeychainService": "DeepSeek API Key",
        "deepseekKeychainAccount": "codex",
        "showCodex": true,
        "showClaude": true,
        "showOpenCode": true,
        "showDeepSeek": true,
        "refreshMinutes": 10,
        "menuBarSource": "codex-weekly",
    ]
    if let data = try? JSONSerialization.data(withJSONObject: legacyObject),
       let migrated = try? JSONDecoder().decode(Config.self, from: data) {
        expect(migrated.opencodeWorkspaceID == sampleWorkspace, "legacy workspace migration")
        expect(migrated.deepseekKeychainAccount == "codex", "legacy keychain migration")
        expect(!migrated.setupCompleted, "legacy config enters onboarding")
    } else {
        failures.append("legacy config decoding")
    }

    let fresh = Config()
    expect(!fresh.showOpenCode && !fresh.showDeepSeek, "optional sources disabled by default")
    expect(fresh.deepseekKeychainAccount == "default", "generic DeepSeek account")
    expect(AppInfo.version == "1.3.0", "version")

    if failures.isEmpty {
        print("Self-test passed.")
        exit(0)
    }
    print("Self-test failed: " + failures.joined(separator: ", "))
    exit(1)
}

if args.contains("--identity") {
    let bundle = Bundle.main
    let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "(missing)"
    let identifier = bundle.bundleIdentifier ?? "(missing)"
    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "(missing)"
    let iconName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String ?? "(missing)"
    let iconURL = bundle.resourceURL?.appendingPathComponent(iconName)
    let loginStatus: String
    switch SMAppService.mainApp.status {
    case .notRegistered: loginStatus = "notRegistered"
    case .enabled: loginStatus = "enabled"
    case .requiresApproval: loginStatus = "requiresApproval"
    case .notFound: loginStatus = "notFound"
    @unknown default: loginStatus = "unknown"
    }
    print("name=\(name)")
    print("bundle_id=\(identifier)")
    print("version=\(version)")
    print("bundle_path=\(bundle.bundlePath)")
    print("executable=\(bundle.executablePath ?? "(missing)")")
    print("icon=\(iconURL?.path ?? "(missing)")")
    print("icon_exists=\(iconURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)")
    print("login_item=\(loginStatus)")
    exit(0)
}

if args.contains("--config") {
    let cfg = Config.load()
    print("配置文件: \(Config.fileURL.path)")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(data: (try? encoder.encode(cfg)) ?? Data(), encoding: .utf8) ?? "")
    exit(0)
}

if args.contains("--probe") {
    let semaphore = DispatchSemaphore(value: 0)
    let config = Config.load()
    Task {
        let cards = await withTaskGroup(of: (Int, ProviderCard).self) { group -> [ProviderCard] in
            for (i, p) in config.providers.enumerated() {
                group.addTask { (i, await p.fetch()) }
            }
            var out: [(Int, ProviderCard)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        for card in cards {
            print("\n═══ \(card.name)\(card.subtitle.map { "  [\($0)]" } ?? "") ═══")
            if let error = card.error { print("  ✗ \(error)") }
            for w in card.windows {
                var line = "  • \(w.label): "
                if let remaining = w.remainingPercent {
                    let filled = Int((remaining / 100 * 20).rounded())
                    line += String(repeating: "█", count: filled)
                        + String(repeating: "░", count: 20 - filled)
                        + String(format: " 剩余 %3d%%", Int(remaining))
                } else if let value = w.value {
                    line += value
                }
                if let reset = Fmt.relative(w.resetsAt) { line += "  (\(reset))" }
                print(line)
            }
            for note in card.notes { print("    – \(note)") }
        }

        print("\n═══ 菜单栏 ═══")
        var snapshot = Snapshot()
        snapshot.cards = cards
        if config.menuBar == .all {
            print("  来源: all（每个源并排显示）")
        } else if let headline = snapshot.headline(for: config.menuBar) {
            print("  来源: \(config.menuBar.title) [\(config.menuBarSource)] → \(headline.label)")
            print("  显示: \(headline.tag) \(headline.text)"
                  + (headline.isStandIn
                     ? "   ⚠︎ \(config.menuBar.title)不可用，这是临时代替" : ""))
        } else {
            print("  来源: \(config.menuBarSource) → 暂无可显示的额度")
        }
        print("")
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
}

if let dumpIndex = args.firstIndex(of: "--dump") {
    let which = dumpIndex + 1 < args.count ? args[dumpIndex + 1] : "opencode"
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        switch which {
        case "opencode", "billing":
            let cfg = Config.load()
            do {
                let cookie = try ChromeCookies.header(matching: "%opencode.ai")
                print("cookie 条数: \(cookie.split(separator: ";").count)")
                let page = which == "billing" ? "billing" : "go"
                let url = URL(string: "https://opencode.ai/workspace/\(cfg.opencodeWorkspaceID)/\(page)")!
                var req = URLRequest(url: url)
                req.setValue(cookie, forHTTPHeaderField: "Cookie")
                req.setValue("Mozilla/5.0 (Macintosh) Chrome/140.0.0.0", forHTTPHeaderField: "User-Agent")
                let (data, resp) = try await URLSession.shared.data(for: req)
                let http = resp as? HTTPURLResponse
                print("HTTP \(http?.statusCode ?? -1), \(data.count) bytes")
                let path = FileManager.default.temporaryDirectory
                    .appendingPathComponent("aiquota-opencode-\(page).html")
                try data.write(to: path)
                print("已写入 \(path.path)")
            } catch {
                print("✗ \(error.localizedDescription)")
            }
        case "codex":
            let card = await CodexProvider().fetch()
            print(card.error ?? "ok: \(card.windows.count) 个窗口, notes=\(card.notes)")
        case "claude":
            do {
                let json = try await ClaudeProvider().rawUsage()
                let pretty = try JSONSerialization.data(withJSONObject: json,
                                                        options: [.prettyPrinted, .sortedKeys])
                print(String(data: pretty, encoding: .utf8) ?? "")
            } catch {
                print("✗ \(error.localizedDescription)")
            }
        default:
            print("未知来源: \(which)")
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
}

if args.contains("--snapshot") {
    // Renders the popover offscreen so the UI can be checked without a screen
    // recording permission.
    let out = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/ai-quota-preview.png")
    _ = NSApplication.shared  // AppKit drawing needs an initialized app
    final class Flag: @unchecked Sendable { var done = false }
    let flag = Flag()
    Task { @MainActor in
        let store = QuotaStore()
        await store.refresh()
        // NSHostingView inside a real (offscreen) window draws the actual AppKit
        // controls. SwiftUI's ImageRenderer cannot: it skips ScrollView contents
        // and paints Buttons as placeholders.
        let view = PopoverView(store: store, onQuit: {})
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))  // offscreen, still rendered
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        // Yield so the outer run-loop pump can flush a display cycle before capture.
        try? await Task.sleep(nanoseconds: 400_000_000)

        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: out)
                print("已渲染 \(Int(hosting.bounds.width))x\(Int(hosting.bounds.height)) -> \(out.path)")
            } else {
                print("✗ PNG 编码失败")
            }
        } else {
            print("✗ 渲染失败")
        }
        window.orderOut(nil)
        flag.done = true
    }
    // Pump the main run loop so the @MainActor task above can actually run —
    // blocking on a semaphore here would deadlock it.
    while !flag.done {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    exit(0)
}

// MARK: - Menu bar app

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var panelWindow: NSWindow?
    private let store = QuotaStore()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: store, onQuit: { NSApp.terminate(nil) })
        )

        // Redraw the menu bar whenever the snapshot changes — no polling timer.
        // Redraw on new data *and* on a settings change — picking a different
        // menu bar source has to take effect without waiting for a refresh.
        cancellable = Publishers.Merge(store.$snapshot.map { _ in () },
                                       store.$config.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateStatusTitle() }
            }

        if store.config.setupCompleted {
            store.start()
        } else {
            // Show onboarding before any provider can trigger a keychain prompt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                MainActor.assumeIsolated { self?.showPanel() }
            }
        }
        updateStatusTitle()
        logStatusItemPlacement()
    }

    /// macOS silently drops menu bar items that do not fit — common on notched
    /// displays with a crowded bar. Record where the button actually landed so
    /// "I can't see the icon" can be diagnosed without a screenshot.
    private func logStatusItemPlacement() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                var lines = ["[\(Date())] 启动"]
                lines.append("statusItem.isVisible = \(self.statusItem.isVisible)")
                if let window = self.statusItem.button?.window {
                    lines.append("按钮窗口 frame = \(NSStringFromRect(window.frame))")
                    if let screen = window.screen {
                        lines.append("所在屏幕 = \(NSStringFromRect(screen.frame))")
                        lines.append("刘海左侧可用区 = \(screen.auxiliaryTopLeftArea.map(NSStringFromRect) ?? "无刘海")")
                        lines.append("刘海右侧可用区 = \(screen.auxiliaryTopRightArea.map(NSStringFromRect) ?? "无刘海")")
                        lines.append("能否点到 = \(AppDelegate.isReachable(window))")
                    } else {
                        lines.append("⚠︎ 按钮窗口没有关联屏幕 — 图标很可能被挤掉了")
                    }
                } else {
                    lines.append("⚠︎ 按钮没有窗口 — 状态项没有真正显示")
                }
                let path = Config.directory.appendingPathComponent("last-launch.log")
                try? FileManager.default.createDirectory(at: Config.directory,
                                                         withIntermediateDirectories: true)
                try? lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Re-launching the app (double-clicking it in Finder) has no visible effect
    /// for a menu bar app — macOS just activates the existing instance. Treat it
    /// as "show me the panel" instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showPanel()
        return true
    }

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        button.image = gaugeImage()
        button.imagePosition = .imageLeading
        button.attributedTitle = readout()
        var tooltip: [String] = []
        if !store.config.setupCompleted {
            button.toolTip = "AI Quota：需要完成首次设置"
            return
        }
        if store.config.menuBar != .all, let headline = store.headline {
            var heading = "菜单栏显示：\(headline.label)"
            if headline.isStandIn {
                heading += "（\(store.config.menuBar.title)暂不可用，临时代替）"
            }
            if let reset = Fmt.relative(headline.resetsAt) { heading += " · \(reset)" }
            tooltip.append(heading)
            tooltip.append("")
        }
        tooltip += store.snapshot.cards.map { card -> String in
            if let error = card.error { return "\(card.name): \(error)" }
            let parts = card.windows.map { w -> String in
                if let remaining = w.remainingPercent {
                    return "\(w.label) 剩余 \(Int(remaining))%"
                }
                return "\(w.label) \(w.value ?? "")"
            }
            return "\(card.name): " + parts.joined(separator: ", ")
        }
        button.toolTip = tooltip.joined(separator: "\n")
    }

    /// One figure per source, tagged, so the bar answers the question without
    /// anything being opened. Deliberately not minimal: a status item is laid
    /// out right-to-left from whatever sits beside it, so a longer readout
    /// reaches further left — out from under the notch on a crowded bar.
    private func readout() -> NSAttributedString {
        if !store.config.setupCompleted {
            return NSAttributedString(string: " 设置", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }
        return store.config.menuBar == .all ? everySourceReadout() : singleSourceReadout()
    }

    /// One number, pinned by config — Codex's weekly quota unless changed. Also
    /// keeps the status item narrow, which matters on a crowded menu bar.
    private func singleSourceReadout() -> NSAttributedString {
        let tagFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        guard let headline = store.headline else {
            let placeholder = store.hasError ? " !" : " …"
            return NSAttributedString(string: placeholder, attributes: [
                .font: valueFont,
                .foregroundColor: store.hasError ? NSColor.systemOrange : .secondaryLabelColor,
            ])
        }
        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: " ", attributes: [.font: valueFont]))
        line.append(NSAttributedString(string: headline.tag + " ", attributes: [
            .font: tagFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .baselineOffset: 0.5,
        ]))
        line.append(NSAttributedString(string: headline.text, attributes: [
            .font: valueFont,
            .foregroundColor: headline.remaining.map(AppDelegate.tint) ?? .labelColor,
        ]))
        return line
    }

    private func everySourceReadout() -> NSAttributedString {
        let tagFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let line = NSMutableAttributedString()

        for card in store.snapshot.cards {
            guard let segment = AppDelegate.segment(for: card) else { continue }
            line.append(NSAttributedString(string: line.length == 0 ? " " : "  ",
                                           attributes: [.font: valueFont]))
            line.append(NSAttributedString(string: card.tag + " ", attributes: [
                .font: tagFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .baselineOffset: 0.5,
            ]))
            line.append(NSAttributedString(string: segment.text, attributes: [
                .font: valueFont,
                .foregroundColor: segment.color,
            ]))
        }

        if line.length == 0 {
            return NSAttributedString(string: " …", attributes: [
                .font: valueFont, .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }
        return line
    }

    /// What to show for one source: the tightest window as a percentage, a bare
    /// balance for the sources that report one instead, or a marker on failure.
    private static func segment(for card: ProviderCard) -> (text: String, color: NSColor)? {
        if card.error != nil { return ("!", .systemOrange) }
        if let remaining = card.headlineWindow?.remainingPercent {
            return ("\(Int(remaining))%", tint(for: remaining))
        }
        if var value = card.windows.compactMap(\.value).first {
            // Cents never matter at a glance and cost four points of bar width.
            if value.hasSuffix(".00") { value.removeLast(3) }
            return (value, .labelColor)
        }
        return nil
    }

    private static func tint(for remaining: Double) -> NSColor {
        QuotaTheme.menuBarColor(for: remaining)
    }

    /// The needle tracks what is left, so a full gauge means plenty of quota.
    private func gaugeImage() -> NSImage? {
        let name: String
        var tint = NSColor.labelColor
        if !store.config.setupCompleted {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                .applying(.init(paletteColors: [NSColor.systemBlue]))
            return NSImage(systemSymbolName: "slider.horizontal.3",
                           accessibilityDescription: "AI Quota 设置")?
                .withSymbolConfiguration(config)
        }
        // A balance has no ceiling, so there is no needle position to imply —
        // show a neutral full gauge rather than a made-up level.
        if let headline = store.headline, let remaining = headline.remaining {
            if remaining <= 10 {
                name = "gauge.with.dots.needle.33percent"
                tint = .systemRed
            } else if remaining <= 25 {
                name = "gauge.with.dots.needle.33percent"
                tint = .systemOrange
            } else if remaining < 60 {
                name = "gauge.with.dots.needle.67percent"
            } else {
                name = "gauge.with.dots.needle.100percent"
            }
        } else if store.hasError {
            name = "exclamationmark.triangle"
            tint = .systemOrange
        } else {
            name = "gauge.with.dots.needle.33percent"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(paletteColors: [tint]))
        return NSImage(systemSymbolName: name, accessibilityDescription: "AI 配额")?
            .withSymbolConfiguration(config)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }

    /// Anchors the popover to the menu bar icon when that icon is actually on
    /// screen, and otherwise opens the same view as a free-standing window —
    /// so a crowded or notched menu bar never leaves the app unreachable.
    private func showPanel() {
        Task { await store.refresh() }

        if let button = statusItem.button, statusItem.isVisible,
           let window = button.window, AppDelegate.isReachable(window) {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            return
        }
        showFallbackWindow()
    }

    /// True when the menu bar button is somewhere the user can actually click.
    ///
    /// On notched displays the usable menu bar is split into two auxiliary areas
    /// either side of the camera housing. A crowded bar can push a status item
    /// into the gap between them, where it stays "visible" to AppKit but is
    /// hidden behind the notch.
    static func isReachable(_ window: NSWindow) -> Bool {
        guard let screen = window.screen else { return false }
        guard screen.frame.contains(window.frame.origin) else { return false }

        let areas = [screen.auxiliaryTopLeftArea, screen.auxiliaryTopRightArea].compactMap { $0 }
        guard !areas.isEmpty else { return true }  // no notch on this display

        // A multi-source readout is wide enough to straddle the notch. What
        // matters is not the fraction in the clear but whether there is enough
        // of it to aim at — one menu bar item's worth, ~24pt.
        let needed = min(window.frame.width, 24)
        return areas.contains { $0.intersection(window.frame).width >= needed }
    }

    private func showFallbackWindow() {
        if let panelWindow {
            panelWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // A ScrollView has no intrinsic height, so in a window it collapses to
        // nothing — the popover gets its height from the anchor instead. Give the
        // windowed variant an explicit size and let the user resize from there.
        let hosting = NSHostingController(
            rootView: PopoverView(store: store, onQuit: { NSApp.terminate(nil) })
                .frame(width: 340, height: 520)
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.title = AppInfo.name
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        panelWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
// Top-level code already runs on the main thread; this just tells the compiler.
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
