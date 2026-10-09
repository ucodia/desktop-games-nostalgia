import AppKit
import UniformTypeIdentifiers

/// Headless scripted run: `DesktopGames --selftest <dir>` plays every tool with synthetic input
/// and writes composited frames to <dir>.
@MainActor
final class SelfTest {
    private let rt: Runtime
    private let out: URL
    private var events: [Int: [() -> Void]] = [:]

    init(runtime: Runtime, output: URL) {
        rt = runtime
        out = output
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        buildScript()
        rt.onTick = { [weak self] t in self?.events[t]?.forEach { $0() } }
    }

    private func at(_ tick: Int, _ action: @escaping () -> Void) {
        events[tick, default: []].append(action)
    }

    private func move(_ t: Int, _ x: Double, _ y: Double) {
        at(t) { self.rt.mouseMoved(to: CGPoint(x: x * Canvas.pointsPerUnit, y: y * Canvas.pointsPerUnit)) }
    }

    private func press(_ t: Int, left: Bool = true) { at(t) { self.rt.mouseButton(left: left, down: true) } }
    private func release(_ t: Int, left: Bool = true) { at(t) { self.rt.mouseButton(left: left, down: false) } }
    private func key(_ t: Int, _ k: Key) { at(t) { self.rt.injectKey(k) } }
    private func snap(_ t: Int, _ name: String) { at(t) { self.save(name) } }

    private func buildScript() {
        snap(3, "00_intro")
        press(5); release(6)

        // hammer
        move(20, 10, 20); press(20); release(21)
        move(22, 13, 21); press(22); release(23)
        move(24, 11, 18); press(24); release(25)
        snap(27, "01_hammer")

        // chain-saw
        key(30, .tool(1))
        move(32, 15, 10); press(32)
        for i in 0..<14 { move(33 + i, 15 + Double(i) * (i < 6 ? 3 : 0.4), 10 + Double(i % 4) * 0.3) }
        snap(46, "02_chainsaw_sawing")
        release(47)

        // machine gun
        key(50, .tool(2))
        move(52, 30, 15); press(52)
        for i in 0..<8 { move(53 + i, 30 + Double(i % 3) * 0.4, 15 + Double(i % 2) * 0.3) }
        snap(58, "03_machinegun_firing")
        release(61)
        snap(75, "04_machinegun_after")

        // flame-thrower
        key(78, .tool(3))
        move(80, 40, 20); press(80)
        snap(92, "05_flame_firing")
        release(96)
        snap(118, "06_flame_burning")

        // color-thrower
        key(132, .tool(4))
        move(134, 10, 8); press(134)
        move(143, 14, 9)
        release(150)
        snap(170, "07_color")

        // phaser
        key(172, .tool(5))
        move(174, 22, 28); press(174); release(175)
        snap(177, "08_phaser")

        // stamp
        key(182, .tool(6))
        move(184, 34, 28); press(184); release(185)
        move(186, 39, 27); press(186); release(187)
        snap(190, "09_stamp")

        // termite
        key(192, .tool(7))
        move(194, 45, 8); press(194); release(195)
        move(196, 47, 9); press(196); release(197)
        snap(260, "10_termite")

        // washing
        key(262, .tool(8))
        move(264, 10, 20); press(264)
        for i in 0..<16 { move(265 + i, 10 + Double(i) * 0.25, 20 + Double(i % 2) * 0.5) }
        release(282)
        snap(284, "11_washing")

        // menu
        press(286, left: false); release(287, left: false)
        at(290) { self.rt.mouseMoved(to: CGPoint(x: self.rt.mapWidth / 2 * Canvas.pointsPerUnit, y: self.rt.mapHeight / 2 * Canvas.pointsPerUnit)) }
        snap(293, "12_menu")
        key(296, .escape)
    }

    private func save(_ name: String) {
        guard let image = rt.snapshotDisplay(),
              let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent("\(name).png") as CFURL,
                                                         UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        print("selftest: wrote \(name).png")
    }
}
