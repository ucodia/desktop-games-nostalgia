import AppKit
import QuartzCore

enum Key: Equatable {
    case escape
    case tool(Int)
    case other
}

struct ExitProgram: Error {}

/// The subset of the Peter runtime that Desktop Games relies on: a 55 ms timer tick that drives
/// sprites and resumes the program after `wait`, mouse/keyboard state and the display.
@MainActor
final class Runtime {
    static let tickInterval = 0.055

    let assets: AssetStore
    let audio = AudioMixer()
    let quantizer: PaletteQuantizer
    let view: GameView
    private(set) var canvas: Canvas
    private(set) var window: NSWindow

    private var sprites: [Sprite] = []
    private var waiters: [(ticks: Int, cont: CheckedContinuation<Void, Error>)] = []
    private var timer: Timer?
    private var exiting = false
    private var cursorHidden = false
    private var tickCount = 0

    /// Headless mode never shows windows or captures the screen (used by --selftest).
    var headless = false
    /// Called at every tick before the program resumes (used by --selftest).
    var onTick: ((Int) -> Void)?

    private(set) var mouseX = 0.0
    private(set) var mouseY = 0.0
    private(set) var mouseLeft = false
    private(set) var mouseRight = false
    private var leftClickFlag = false
    private var rightClickFlag = false
    private var keys: [Key] = []

    init(assets: AssetStore, window: NSWindow, canvas: Canvas) {
        self.assets = assets
        self.window = window
        self.canvas = canvas
        quantizer = PaletteQuantizer(palette: assets.palette)
        view = GameView(frame: window.contentLayoutRect)
        view.runtime = self
        window.contentView = view
        view.attach(canvas)

        let t = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var mapWidth: Double { canvas.widthUnits }
    var mapHeight: Double { canvas.heightUnits }

    // MARK: Display

    func makeCanvas(width: Int, height: Int, scale: Double) -> Canvas {
        Canvas(width: width, height: height, scale: scale, quantizer: quantizer)
    }

    func present(_ newCanvas: Canvas, in newWindow: NSWindow) {
        canvas = newCanvas
        if newWindow !== window {
            view.removeFromSuperview()
            view.frame = newWindow.contentLayoutRect
            newWindow.contentView = view
            window.delegate = nil
            if !headless { window.orderOut(nil) }
            window = newWindow
        }
        view.attach(newCanvas)
        render()
    }

    func makeSprite(_ def: SpriteDef) -> Sprite {
        let s = Sprite(def)
        sprites.append(s)
        view.spriteLayer.addSublayer(s.layer)
        return s
    }

    private func tick() {
        guard !exiting else { return }
        tickCount += 1
        for s in sprites { s.tick() }
        render()
        onTick?(tickCount)
        var ready: [CheckedContinuation<Void, Error>] = []
        waiters = waiters.compactMap { w in
            if w.ticks <= 1 {
                ready.append(w.cont)
                return nil
            }
            return (w.ticks - 1, w.cont)
        }
        for c in ready { c.resume() }
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.flush()
        for s in sprites { s.render() }
        CATransaction.commit()
    }

    // MARK: Program services

    /// wait: suspend the program for a number of timer ticks.
    func wait(ticks: Int = 1) async throws {
        if exiting { throw ExitProgram() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            waiters.append((max(1, ticks), c))
        }
    }

    func wait(seconds: Double) async throws {
        try await wait(ticks: Int((seconds / Self.tickInterval).rounded()))
    }

    /// exit: end the program.
    func exit(file: StaticString = #fileID, line: UInt = #line) throws -> Never {
        NSLog("exit requested at \(file):\(line)")
        throw ExitProgram()
    }

    func shutdown() {
        exiting = true
        timer?.invalidate()
        audio.stop()
        setCursorVisible(true)
        for w in waiters { w.cont.resume(throwing: ExitProgram()) }
        waiters.removeAll()
    }

    func setCursorVisible(_ visible: Bool) {
        if headless { return }
        if visible && cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        } else if !visible && !cursorHidden {
            NSCursor.hide()
            cursorHidden = true
        }
    }

    // MARK: Input

    /// mouse_l_click / mouse_r_click: true once per click, reading clears the flag.
    func leftClick() -> Bool {
        defer { leftClickFlag = false }
        return leftClickFlag
    }

    func rightClick() -> Bool {
        defer { rightClickFlag = false }
        return rightClickFlag
    }

    /// key_vkey: next key from the keyboard buffer.
    func readKey() -> Key? {
        keys.isEmpty ? nil : keys.removeFirst()
    }

    /// Composite of the sheet and sprites, as displayed.
    func snapshotDisplay() -> CGImage? {
        render()
        let scale = canvas.scale
        let size = view.bounds.size
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        view.canvasLayer.render(in: ctx)
        let sorted = (view.spriteLayer.sublayers ?? []).filter { !$0.isHidden }.sorted { $0.zPosition < $1.zPosition }
        for l in sorted {
            ctx.saveGState()
            ctx.translateBy(x: l.frame.minX, y: l.frame.minY)
            l.render(in: ctx)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    func mouseInRegion(x: Double, y: Double, w: Double, h: Double) -> Bool {
        mouseX >= x && mouseX < x + w && mouseY >= y && mouseY < y + h
    }

    func mouseMoved(to p: CGPoint) {
        mouseX = p.x / Canvas.pointsPerUnit
        mouseY = p.y / Canvas.pointsPerUnit
    }

    func mouseButton(left: Bool, down: Bool) {
        if left {
            mouseLeft = down
            if down { leftClickFlag = true }
        } else {
            mouseRight = down
            if down { rightClickFlag = true }
        }
    }

    func injectKey(_ key: Key) {
        keys.append(key)
    }

    func keyDown(_ event: NSEvent) {
        let fKeys: [UInt16: Int] = [122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9]
        if event.keyCode == 53 {
            keys.append(.escape)
        } else if let n = fKeys[event.keyCode] {
            keys.append(.tool(n - 1))
        } else if let c = event.charactersIgnoringModifiers?.first, let n = c.wholeNumberValue, (1...9).contains(n) {
            keys.append(.tool(n - 1))
        } else {
            keys.append(.other)
        }
    }
}

final class GameView: NSView {
    weak var runtime: Runtime?
    let canvasLayer = CALayer()
    let spriteLayer = CALayer()
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        for l in [canvasLayer, spriteLayer] {
            l.anchorPoint = .zero
            l.frame = bounds
            l.actions = ["bounds": NSNull(), "position": NSNull(), "sublayers": NSNull()]
            layer?.addSublayer(l)
        }
        spriteLayer.zPosition = 1
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @MainActor
    func attach(_ canvas: Canvas) {
        canvasLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        for t in canvas.tileLayers { canvasLayer.addSublayer(t) }
    }

    override func layout() {
        super.layout()
        canvasLayer.frame = bounds
        spriteLayer.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(t)
        trackingArea = t
    }

    private func track(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        MainActor.assumeIsolated { runtime?.mouseMoved(to: p) }
    }

    override func mouseMoved(with event: NSEvent) { track(event) }
    override func mouseDragged(with event: NSEvent) { track(event) }
    override func rightMouseDragged(with event: NSEvent) { track(event) }

    override func mouseDown(with event: NSEvent) {
        track(event)
        MainActor.assumeIsolated { runtime?.mouseButton(left: true, down: true) }
    }

    override func mouseUp(with event: NSEvent) {
        MainActor.assumeIsolated { runtime?.mouseButton(left: true, down: false) }
    }

    override func rightMouseDown(with event: NSEvent) {
        track(event)
        MainActor.assumeIsolated { runtime?.mouseButton(left: false, down: true) }
    }

    override func rightMouseUp(with event: NSEvent) {
        MainActor.assumeIsolated { runtime?.mouseButton(left: false, down: false) }
    }

    override func keyDown(with event: NSEvent) {
        MainActor.assumeIsolated { runtime?.keyDown(event) }
    }
}

/// Borderless window that can take keyboard focus, used for the full-screen desktop.
final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
