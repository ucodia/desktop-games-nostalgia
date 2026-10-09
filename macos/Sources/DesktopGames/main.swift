import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var runtime: Runtime?
    private var game: DesktopGames?
    private var selfTest: SelfTest?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        guard let dir = AssetStore.locate() else {
            fail("Game assets were not found. Build the app with scripts/build-app.sh.")
            return
        }
        let assets: AssetStore
        do {
            assets = try AssetStore(directory: dir)
        } catch {
            fail("Could not load game assets: \(error)")
            return
        }

        // Peter's default window: the 15x11 unit "sheet" (480x352 points).
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 352),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = DesktopGames.caption
        window.delegate = self
        window.acceptsMouseMovedEvents = true
        window.center()

        let scale = window.backingScaleFactor
        let placeholder = Canvas(width: Int(480 * scale), height: Int(352 * scale), scale: scale,
                                 quantizer: PaletteQuantizer(palette: []))
        let rt = Runtime(assets: assets, window: window, canvas: placeholder)
        rt.present(rt.makeCanvas(width: Int(480 * scale), height: Int(352 * scale), scale: scale), in: window)
        runtime = rt
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count {
            rt.headless = true
            rt.audio.muted = true
            selfTest = SelfTest(runtime: rt, output: URL(fileURLWithPath: args[i + 1]))
        } else {
            if args.contains("--autostart") {
                rt.onTick = { t in
                    if t == 5 { rt.mouseButton(left: true, down: true) }
                    if t == 6 { rt.mouseButton(left: true, down: false) }
                }
            }
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(rt.view)
            NSApp.activate(ignoringOtherApps: true)
            if !args.contains("--autostart") {
                Task { await ScreenRecordingGate.run(on: window) }
            }
        }

        let game = DesktopGames(runtime: rt)
        self.game = game
        Task { @MainActor in
            do {
                try await game.run()
            } catch {
                NSLog("program ended: \(error)")
            }
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.shutdown()
        NSApp.presentationOptions = []
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === runtime?.window else { return }
        NSApp.terminate(nil)
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Desktop Games", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    private func fail(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        if CommandLine.arguments.contains("--selftest") { exit(1) }
        let alert = NSAlert()
        alert.messageText = "Desktop Games"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
