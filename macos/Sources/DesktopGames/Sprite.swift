import AppKit
import QuartzCore

/// A Peter sprite instance, reproducing the interpreter's movement and animation rules
/// (FUN_004194d0 position setter, FUN_00419830 visibility, FUN_00419950 definition swap,
/// FUN_0041ad10 timer tick).
final class Sprite {
    private(set) var def: SpriteDef
    let layer = CALayer()

    private(set) var visible = false
    private(set) var moving = false
    private var animating = false
    private var countdown = 0
    private var stepsLeft = 0
    private var phaseValue = 0
    private var requestedPhase = -1
    private(set) var direction = 0

    private var targetX = 0.0, targetY = 0.0
    private var currentX = 0.0, currentY = 0.0
    private var stepX = 0.0, stepY = 0.0

    init(_ def: SpriteDef) {
        self.def = def
        layer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "hidden": NSNull(), "zPosition": NSNull()]
        layer.magnificationFilter = .nearest
        layer.anchorPoint = .zero
        layer.isHidden = true
    }

    // MARK: Program-facing properties

    var x: Double {
        get { currentX }
        set { setPosition(newValue, targetY) }
    }

    var y: Double {
        get { currentY }
        set { setPosition(targetX, newValue) }
    }

    var phase: Int {
        get { requestedPhase >= 0 ? requestedPhase : phaseValue }
        set { requestedPhase = newValue >= 0 && newValue < def.phases ? newValue : -1 }
    }

    func setVisible(_ v: Bool) {
        guard v != visible else { return }
        if v {
            visible = true
            startAnimating()
            return
        }
        visible = false
        animating = false
        if moving {
            currentX = targetX
            currentY = targetY
            stepsLeft = -1
            moving = false
        }
        while phaseValue >= def.restPhases { phaseValue -= def.restPhases }
    }

    func setDef(_ newDef: SpriteDef) {
        guard newDef !== def else { return }
        if visible && def.restPhases > 1 && newDef.restPhases == 1 {
            animating = false
        }
        if phaseValue < def.restPhases {
            if newDef.restPhases <= phaseValue { phaseValue = 0 }
        } else {
            phaseValue += newDef.restPhases - def.restPhases
            if newDef.phases <= phaseValue { phaseValue = newDef.restPhases }
        }
        def = newDef
        if def.phases <= phaseValue { phaseValue = 0 }
        if direction >= def.directions { direction %= def.directions }
        if visible { startAnimating() }
    }

    // MARK: Runtime

    private func pixel(_ v: Double) -> Int { Int((v * Canvas.pointsPerUnit).rounded()) }

    private func setPosition(_ nx: Double, _ ny: Double) {
        targetX = nx
        targetY = ny
        guard visible else {
            currentX = nx
            currentY = ny
            return
        }
        if pixel(nx) != pixel(currentX) || pixel(ny) != pixel(currentY) {
            animating = false
            let dx = nx - currentX, dy = ny - currentY
            let sector = 2 * Double.pi / Double(def.directions)
            var dir = Int((atan2(dy, dx) / sector).rounded())
            while dir >= def.directions { dir -= def.directions }
            while dir < 0 { dir += def.directions }
            direction = dir
            if !moving {
                moving = true
                countdown = 1
            }
            if phaseValue < def.restPhases && def.restPhases < def.phases {
                phaseValue = def.restPhases - 1
            }
            var steps = Int(((dx * dx + dy * dy).squareRoot() * def.steps).rounded())
            if steps == 0 {
                if def.steps == 0 {
                    currentX = nx
                    currentY = ny
                    stepsLeft = -1
                    moving = false
                    startAnimating()
                    return
                }
                steps = 1
            }
            stepsLeft = steps
            stepX = dx / Double(steps)
            stepY = dy / Double(steps)
            return
        }
        currentX = nx
        currentY = ny
        if moving {
            stepsLeft = -1
            moving = false
        }
        if def.restPhases == 1 { phaseValue = 0 }
        startAnimating()
    }

    private func startAnimating() {
        guard !animating, def.restPhases > 1 else { return }
        animating = true
        if countdown < 1 { countdown = def.delayTicks }
    }

    private var pendingPhaseValid: Bool { requestedPhase >= 0 && requestedPhase < def.phases }

    /// One 55 ms timer tick.
    func tick() {
        if moving {
            countdown -= 1
            guard countdown < 1 else { return }
            stepsLeft -= 1
            if stepsLeft < 0 {
                currentX = targetX
                currentY = targetY
                if pendingPhaseValid {
                    phaseValue = requestedPhase
                    requestedPhase = -1
                } else {
                    if def.restPhases <= phaseValue { phaseValue -= def.restPhases }
                    phaseValue = (phaseValue + 1) % def.restPhases
                }
                moving = false
                if def.restPhases > 1 {
                    animating = true
                    countdown = def.delayTicks
                }
            } else {
                currentX += stepX
                currentY += stepY
                countdown = def.delayTicks
                if pendingPhaseValid {
                    phaseValue = requestedPhase
                    requestedPhase = -1
                } else {
                    phaseValue += 1
                    if def.phases <= phaseValue {
                        phaseValue = def.restPhases
                        if def.phases <= phaseValue { phaseValue = 0 }
                    }
                }
            }
        } else if animating {
            countdown -= 1
            guard countdown < 1 else { return }
            if pendingPhaseValid {
                phaseValue = requestedPhase
                requestedPhase = -1
            } else {
                phaseValue = (phaseValue + 1) % def.restPhases
            }
            countdown = def.delayTicks
        }
    }

    func render() {
        if !moving && !animating && countdown < 1 && pendingPhaseValid {
            phaseValue = requestedPhase
            requestedPhase = -1
        }
        layer.isHidden = !visible
        guard visible else { return }
        let dir = min(direction, def.frames.count - 1)
        let ph = min(phaseValue, def.frames[dir].count - 1)
        layer.contents = def.frames[dir][ph]
        layer.frame = CGRect(x: pixel(currentX), y: pixel(currentY), width: def.width, height: def.height)
        layer.zPosition = CGFloat(def.level) - CGFloat(currentY) / 10_000
    }
}
