import AppKit
import ScreenCaptureKit

/// Replaces Peter's "transparent window + background_get" trick: grab what is on screen.
enum ScreenCapture {
    @MainActor
    static func capture(_ screen: NSScreen) async -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else {
            NSLog("screen recording permission not granted, using the wallpaper")
            return wallpaper(for: screen)
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                return wallpaper(for: screen)
            }
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            NSLog("screen capture failed: \(error)")
            return wallpaper(for: screen)
        }
    }

    @MainActor
    static func wallpaper(for screen: NSScreen) -> CGImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}

/// Settles Screen Recording access on the intro window, before the game covers the screen.
/// macOS shows its own permission popup only the first time an app identity asks, so later
/// launches without access offer a sheet instead. A new grant applies after "Quit & Reopen".
@MainActor
enum ScreenRecordingGate {
    private static let requestedKey = "screenCaptureRequestedForBuild"

    static func run(on window: NSWindow) async {
        guard !CGPreflightScreenCaptureAccess() else { return }

        let build = codeIdentity()
        if build == nil || UserDefaults.standard.string(forKey: requestedKey) != build {
            UserDefaults.standard.set(build, forKey: requestedKey)
            await requestAccess()
            return
        }

        let ask = NSAlert()
        ask.messageText = "Smash your real screen?"
        ask.informativeText = "Desktop Games needs Screen Recording access to take a picture of your screen to play on. Without it, you play on your wallpaper."
        ask.addButton(withTitle: "Open System Settings")
        ask.addButton(withTitle: "Play on Wallpaper")
        guard await ask.beginSheetModal(for: window) == .alertFirstButtonReturn else { return }

        await requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Both calls register the app in the Screen Recording list; the ScreenCaptureKit query is
    /// what reliably adds it on recent macOS versions.
    private static func requestAccess() async {
        _ = CGRequestScreenCaptureAccess()
        _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// The identity macOS ties the permission to: the team of a Developer ID build, or the code
    /// hash of an ad-hoc build (which changes with every build).
    private static func codeIdentity() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        if let team = dict[kSecCodeInfoTeamIdentifier as String] as? String { return team }
        guard let unique = dict[kSecCodeInfoUnique as String] as? Data else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }
}
