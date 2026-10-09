import AppKit

/// Port of the Peter program "Desktop Games" (c) Miroslav Němeček, recovered from
/// stress_relief.exe. Function and variable names follow the original program's English labels;
/// see re/program.txt for the decompiled source.
@MainActor
final class DesktopGames {
    static let maxBullets = 200
    static let caption = "Desktop Games;   (c) Miroslav Nemecek, www.gemtree.com;   freeware"

    enum BulletType: Int {
        case none = 0, hit, shell, potsherd, flyingFlame, standingFlame, color, termite
    }

    private let rt: Runtime
    private let a: AssetStore

    private var introPicture: Picture
    private var toolSelectionPicture: Picture
    private var stampPrints: [Picture]

    private let selectionCursor: Sprite
    private let tool: Sprite
    private var bullets: [Sprite] = []
    private var bulletType = [BulletType](repeating: .none, count: maxBullets)
    private var speedX = [Double](repeating: 0, count: maxBullets)
    private var speedY = [Double](repeating: 0, count: maxBullets)
    private var writeIndex = 0

    private var selectedFunction = 0
    private var lastSelectedFunction = 0
    private var noInterruptOfActiveTool = true
    private var buttonState = false
    private var stereobase = 0.0

    private var desktopStorage: Picture?
    private var desktopOriginal: Picture?

    private let waitBackground: RGB
    private let waitText: RGB
    private let paintColors: [RGB]
    private let termiteColor: RGB
    private let sawColor: RGB

    init(runtime: Runtime) {
        rt = runtime
        a = runtime.assets
        introPicture = a.picture("introduction_picture")
        toolSelectionPicture = a.picture("picture_of_tool_selection")
        let assets = runtime.assets
        stampPrints = (1...10).map { assets.picture("picture_of_stamp_print_\($0)") }
        selectionCursor = rt.makeSprite(a.sprite("sprite_of_selection_cursor"))
        tool = rt.makeSprite(a.sprite("sprite_of_tool"))
        for _ in 0..<Self.maxBullets { bullets.append(rt.makeSprite(a.sprite("bullet"))) }
        waitBackground = a.iconColors[4]
        waitText = a.iconColors[5]
        paintColors = Array(a.iconColors[6...13])
        termiteColor = a.iconColors[14]
        sawColor = a.iconColors[15]
    }

    // MARK: Helpers mirroring Peter built-ins

    private func random() -> Double { Double.random(in: 0..<1) }
    private func random(_ x: Double) -> Double { x > 0 ? Double.random(in: 0..<x) : 0 }
    private func randomInt(_ n: Int) -> Int { Int(random(Double(n))) }
    private var mouseX: Double { rt.mouseX }
    private var mouseY: Double { rt.mouseY }
    private var mapWidth: Double { rt.mapWidth }
    private var mapHeight: Double { rt.mapHeight }

    private func play(_ name: String, volume: Double = 1, balance: Double = 0, loops: Int = 1, restart: Bool = true) {
        rt.audio.play(a.sound(name), volume: volume, balance: balance, loops: loops, restart: restart)
    }

    // MARK: Desktop Games (main function)

    func run() async throws {
        let language = Locale.preferredLanguages.first?.prefix(2) ?? "en"
        if !["cs", "pl", "sk"].contains(language) {
            introPicture = a.picture("introduction_picture_english")
            toolSelectionPicture = a.picture("picture_of_tool_selection_english")
            stampPrints[2] = a.picture("picture_of_stamp_print_3_english")
            stampPrints[3] = a.picture("picture_of_stamp_print_4_english")
        }

        rt.canvas.draw(introPicture, x: 0, y: 0)
        // waiting on press key or mouse
        while true {
            let left = rt.leftClick(), right = rt.rightClick()
            if left || right { break }
            if let key = rt.readKey() {
                if key == .escape { try rt.exit() }
                break
            }
            try await rt.wait()
        }

        try await initializationOfDesktopMode()
        selectedFunction = 0
        while true {
            if selectedFunction < 0 {
                try await makeSelectionOfFunction()
            }
            lastSelectedFunction = selectedFunction
            selectedFunction = -1
            buttonState = rt.leftClick()
            buttonState = rt.rightClick()
            buttonState = false
            noInterruptOfActiveTool = true
            switch lastSelectedFunction {
            case 0: try await hammerService()
            case 1: try await chainSawService()
            case 2: try await serviceOfMachineGun()
            case 3: try await serviceOfFlameThrower()
            case 4: try await serviceOfColorThrower()
            case 5: try await phaserService()
            case 6: try await serviceOfStamp()
            case 7: try await serviceOfTermite()
            case 8: try await serviceOfWashing()
            default: try rt.exit()
            }
            rt.audio.stop()
        }
    }

    private func initializationOfDesktopMode() async throws {
        // printout text "Wait..."
        rt.canvas.fill(color: waitBackground)
        drawWaitText()
        try await rt.wait(seconds: 0.2)

        // determine screen dimensions and set the window over the whole screen
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { try rt.exit() }
        let shot: CGImage?
        if rt.headless {
            shot = ScreenCapture.wallpaper(for: screen)
        } else {
            rt.window.orderOut(nil)
            try await Task.sleep(nanoseconds: 150_000_000)
            shot = await ScreenCapture.capture(screen)
        }

        let scale = screen.backingScaleFactor
        let canvas = rt.makeCanvas(width: Int(screen.frame.width * scale), height: Int(screen.frame.height * scale), scale: scale)
        if let shot {
            let target = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
            let fill = max(target.width / Double(shot.width), target.height / Double(shot.height))
            let size = CGSize(width: Double(shot.width) * fill, height: Double(shot.height) * fill)
            canvas.context.interpolationQuality = .high
            canvas.context.draw(shot, in: CGRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2,
                                                  width: size.width, height: size.height))
            canvas.context.interpolationQuality = .none
        } else {
            canvas.fill(color: RGB(r: 0, g: 96, b: 128))
        }

        let window = DesktopWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.acceptsMouseMovedEvents = true
        window.setFrame(screen.frame, display: false)
        rt.present(canvas, in: window)
        if !rt.headless {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(rt.view)
            NSApp.presentationOptions = [.hideDock, .hideMenuBar]
            NSApp.activate(ignoringOtherApps: true)
        }

        desktopStorage = canvas.snapshot()
        desktopOriginal = desktopStorage
        rt.setCursorVisible(false)
    }

    private func drawWaitText() {
        let ctx = rt.canvas.context
        let ppu = rt.canvas.pixelsPerUnit
        let font = NSFont(name: "Arial Bold", size: 3 * ppu * 0.7) ?? NSFont.boldSystemFont(ofSize: 3 * ppu * 0.7)
        let text = NSAttributedString(string: "Wait...", attributes: [.font: font, .foregroundColor: NSColor(cgColor: waitText.cgColor)!])
        let size = text.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        text.draw(at: NSPoint(x: (Double(rt.canvas.width) - size.width) / 2, y: 4 * ppu))
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Selection

    private func makeSelectionOfFunction() async throws {
        let x0 = (mapWidth - toolSelectionPicture.width) / 2
        let y0 = (mapHeight - toolSelectionPicture.height) / 2
        desktopStorage = rt.canvas.snapshot()
        rt.canvas.draw(toolSelectionPicture, x: x0, y: y0)
        buttonState = rt.leftClick()
        buttonState = rt.rightClick()
        noInterruptOfActiveTool = true
        tool.setVisible(false)
        rt.audio.stop()
        // switch off bullets (termites will not be switched off)
        for i in 0..<Self.maxBullets where bulletType[i] != .termite {
            bullets[i].setVisible(false)
        }
        rt.setCursorVisible(true)
        while noInterruptOfActiveTool {
            if rt.mouseInRegion(x: x0, y: y0 + 1, w: 12, h: 9) {
                let column = Int((mouseX - x0) / 4)
                selectionCursor.x = Double(column * 4) + x0
                let row = Int((mouseY - y0 - 1) / 3)
                selectionCursor.y = Double(row * 3) + y0 + 1
                selectionCursor.setVisible(true)
                if rt.leftClick() {
                    selectedFunction = column + (2 - row) * 3
                    break
                }
            } else {
                buttonState = rt.leftClick()
                selectionCursor.setVisible(false)
            }
            if rt.rightClick() {
                selectedFunction = lastSelectedFunction
                break
            }
            try await rt.wait()
            try serviceOfSelectionByKeyboard()
        }
        while rt.mouseLeft { try await rt.wait() }
        selectionCursor.setVisible(false)
        if let desktopStorage { rt.canvas.draw(desktopStorage, x: 0, y: 0) }
        rt.setCursorVisible(false)
    }

    private func serviceOfSelectionByKeyboard() throws {
        noInterruptOfActiveTool = false
        switch rt.readKey() {
        case .escape?: try rt.exit()
        case .tool(let n)?: selectedFunction = n
        default: noInterruptOfActiveTool = true
        }
    }

    private func calculationOfSoundStereobase() {
        stereobase = ((mouseX / mapWidth) - 0.5) * 1.4
    }

    // MARK: Bullets

    private func serviceOfBulletsFlight() {
        var thereWasFoundFire = false
        var thereWasFoundTermite = false
        for i in 0..<Self.maxBullets where bullets[i].visible {
            let bullet = bullets[i]
            switch bulletType[i] {
            case .hit:
                if bullet.phase == 0 { bullet.setVisible(false) }
            case .shell:
                bullet.x += speedX[i]
                bullet.y += speedY[i]
                speedY[i] -= 0.2
                if bullet.y < 0 { // test of shell drop
                    bullet.setVisible(false)
                    play("drop_of_shell_\(randomInt(9) + 1)", volume: 0.5, balance: ((bullet.x / mapWidth) - 0.7) * 4)
                }
            case .potsherd:
                bullet.x += speedX[i]
                bullet.y += speedY[i]
                speedY[i] -= 0.2
                if bullet.y < 0 { bullet.setVisible(false) }
            case .flyingFlame:
                if bullet.phase == 0 { // test of flame arrival
                    bullet.setDef(a.sprite("sprite_of_standing_flame"))
                    bullet.x += random(8) - 4
                    bullet.y += random(8) - 4
                    bulletType[i] = .standingFlame
                }
            case .standingFlame:
                let picture = a.picture("picture_of_flame_thrower_hit_\(randomInt(4) + 1)")
                rt.canvas.draw(picture, x: bullet.x + random() - 0.5, y: bullet.y + random() - 0.5)
                deathOfTermites(x: bullet.x - 0.75, y: bullet.y - 0.75)
                if !bullet.moving {
                    bullet.setVisible(false)
                } else {
                    thereWasFoundFire = true
                }
            case .color:
                if bullet.phase == 0 { // test of color arrival
                    play("color_thrower_drop", balance: ((bullet.x / mapWidth) - 0.5) * 4)
                    let blot = a.picture("picture_of_hit_by_color_thrower_\(randomInt(5) + 1)")
                    rt.canvas.draw(blot, x: bullet.x - 1, y: bullet.y - 1)
                    let color = paintColors[colorIndex(of: bullet.def)]
                    rt.canvas.floodFill(color: color, x: bullet.x + 1, y: bullet.y + 1)
                    deathOfTermites(x: bullet.x + 1, y: bullet.y + 1)
                    bullet.setVisible(false)
                }
            case .termite:
                thereWasFoundTermite = true
                rt.canvas.point(color: termiteColor, widthPixels: 5, x: bullet.x + 0.5, y: bullet.y + 0.5)
                if random() < 0.05 { // termite movement
                    let nx = min(max(bullet.x - 0.5 + random(), 0), mapWidth - 1)
                    let ny = min(max(bullet.y - 0.5 + random(), 0), mapHeight - 1)
                    bullet.x = nx
                    bullet.y = ny
                }
            case .none:
                break
            }
        }
        if thereWasFoundFire {
            play("fire", loops: 0, restart: false)
        } else {
            rt.audio.stop(a.sound("fire"))
        }
        if thereWasFoundTermite {
            play("termite_sound", volume: 0.2, loops: 0, restart: false)
        } else {
            rt.audio.stop(a.sound("termite_sound"))
        }
    }

    private static let colorNames = ["red", "green", "blue", "yellow", "purple", "cyan", "orange", "pink"]

    private func colorIndex(of def: SpriteDef) -> Int {
        Self.colorNames.firstIndex { def.name == "sprite_of_color_\($0)" } ?? 0
    }

    /// creation of bullet: returns the list index of the new bullet.
    @discardableResult
    private func creationOfBullet(_ type: BulletType, _ def: SpriteDef) -> Int {
        var index = writeIndex
        for _ in 0..<Self.maxBullets {
            if !bullets[index].visible { break }
            index = (index + 1) % Self.maxBullets
        }
        writeIndex = index
        bulletType[index] = type
        speedX[index] = 0
        speedY[index] = 0
        bullets[index].setVisible(false)
        bullets[index].setDef(def)
        bullets[index].phase = 1
        writeIndex = (writeIndex + 1) % Self.maxBullets
        return index
    }

    private func creationOfHit(picture: Picture, dispersion: Double, sprite: SpriteDef) {
        let i = creationOfBullet(.hit, sprite)
        let x = mouseX + random(dispersion) - dispersion / 2 - picture.width / 2
        let y = mouseY + random(dispersion) - dispersion / 2 - picture.height / 2
        bullets[i].x = x
        bullets[i].y = y
        rt.canvas.draw(picture, x: x, y: y)
        bullets[i].setVisible(true)
    }

    private func deathOfTermites(x: Double, y: Double) {
        for i in 0..<Self.maxBullets {
            let b = bullets[i]
            if b.visible && bulletType[i] == .termite && abs(x - (b.x + 0.5)) < 1.5 && abs(y - (b.y + 0.5)) < 1.5 {
                rt.canvas.draw(a.picture("dead_termite"), x: b.x, y: b.y)
                b.setVisible(false)
                play("squishy_termite", volume: 2)
            }
        }
    }

    // MARK: 0: hammer

    private func hammerService() async throws {
        tool.setVisible(true)
        while noInterruptOfActiveTool {
            if rt.rightClick() { break }
            tool.x = mouseX
            tool.y = mouseY - 4.66 // height of drop place in sprite
            calculationOfSoundStereobase()
            serviceOfBulletsFlight()
            if rt.mouseLeft { // hit
                tool.setDef(a.sprite("sprite_of_knock_hammer"))
                if !buttonState { // hit service
                    deathOfTermites(x: mouseX, y: mouseY)
                    var brightness = 0.0
                    var oy = -0.5
                    for _ in 0..<11 { // detection of color brightness in destination place
                        var ox = -0.5
                        for _ in 0..<11 {
                            brightness += colorBrightness(offsetX: ox, offsetY: oy)
                            ox += 0.1
                        }
                        oy += 0.1
                    }
                    let smash = min(7, Int(brightness / 11 / 11 * 8))
                    rt.audio.stop()
                    play("smash_\(smash + 1)", volume: 2, balance: stereobase)
                    let picture = a.picture("picture_of_hammer_hit_\(randomInt(8) + 1)")
                    rt.canvas.draw(picture, x: mouseX - picture.width / 2 - (random() - 0.5) * 0.2,
                                   y: mouseY - picture.height / 2 - (random() - 0.5) * 0.2)
                    for _ in 0..<Int(brightness / 5) { createPotsherd() }
                }
                buttonState = true
            } else {
                tool.setDef(a.sprite("sprite_of_quiet_hammer"))
                buttonState = false
            }
            try await rt.wait()
            try serviceOfSelectionByKeyboard()
        }
    }

    /// determine color brightness by offset
    private func colorBrightness(offsetX: Double, offsetY: Double) -> Double {
        let c = rt.canvas.color(x: mouseX + offsetX, y: mouseY + offsetY).peterValue
        return Double((c & 0xFF) + ((c & 0xFF00) >> 8) + ((c & 0xFF0000) >> 16)) / 256 / 3
    }

    private func createPotsherd() {
        let i = creationOfBullet(.potsherd, a.sprite("sprite_of_potsherd_\(randomInt(5) + 1)"))
        speedX[i] = random(2) - 1
        speedY[i] = random(2) - 1
        bullets[i].x = mouseX + random() - 0.5
        bullets[i].y = mouseY + random() - 0.5
        bullets[i].setVisible(true)
    }

    // MARK: 1: chain-saw

    private func chainSawService() async throws {
        var oldX = 0.0, oldY = 0.0
        tool.setDef(a.sprite("sprite_of_quiet_chain_saw"))
        tool.x = mouseX - 3
        tool.y = mouseY - 3
        tool.setVisible(true)
        while noInterruptOfActiveTool {
            if rt.rightClick() { break }
            calculationOfSoundStereobase()
            serviceOfBulletsFlight()
            if rt.mouseLeft { // sawing
                tool.setDef(a.sprite("sprite_of_sawing_chain_saw"))
                tool.x = mouseX - 3
                tool.y = mouseY - 3
                deathOfTermites(x: tool.x + 3, y: tool.y + 3)
                let newX = tool.x + 3, newY = tool.y + 3
                if !buttonState { // start sawing
                    rt.audio.stop()
                    oldX = newX
                    oldY = newY
                }
                buttonState = true
                rt.canvas.line(color: sawColor, widthPixels: 2, x1: oldX, y1: oldY, x2: newX, y2: newY)
                let distance = ((oldX - newX) * (oldX - newX) + (oldY - newY) * (oldY - newY)).squareRoot()
                for _ in 0..<Int(distance * 7) { createSplinter(x: newX, y: newY) }
                oldX = newX
                oldY = newY
                play("sawing_chain_saw", volume: 2, balance: stereobase, loops: 0, restart: false)
            } else { // transportation
                tool.setDef(a.sprite("sprite_of_quiet_chain_saw"))
                tool.x = mouseX - 3
                tool.y = mouseY - 3
                if buttonState { rt.audio.stop() } // stop sawing
                play("quiet_chain_saw", balance: stereobase, loops: 0, restart: false)
                buttonState = false
            }
            try await rt.wait()
            try serviceOfSelectionByKeyboard()
        }
    }

    private func createSplinter(x: Double, y: Double) {
        let i = creationOfBullet(.potsherd, a.sprite("sprite_of_splinter_\(randomInt(5) + 1)"))
        speedX[i] = random(2) - 1
        speedY[i] = random(2) - 1
        bullets[i].x = x + random() - 0.5
        bullets[i].y = y + random() - 0.5
        bullets[i].setVisible(true)
    }

    // MARK: 2: machine gun

    private func serviceOfMachineGun() async throws {
        tool.setVisible(true)
        while noInterruptOfActiveTool {
            if rt.rightClick() { break }
            tool.x = mouseX
            tool.y = mouseY - 6
            calculationOfSoundStereobase()
            serviceOfBulletsFlight()
            if rt.mouseLeft { // shooting
                tool.setDef(a.sprite("sprite_of_shooting_machine_gun"))
                if !buttonState { rt.audio.stop() }
                buttonState = true
                play("machine_gun", balance: stereobase, loops: 0, restart: false)
                let hit = a.picture("picture_of_hit_by_machine_gun_\(randomInt(4))")
                deathOfTermites(x: mouseX, y: mouseY)
                creationOfHit(picture: hit, dispersion: 0.5, sprite: a.sprite("sprite_of_hit_by_machine_gun"))
                createShell()
            } else {
                tool.setDef(a.sprite("sprite_of_quiet_machine_gun"))
                if buttonState {
                    rt.audio.stop()
                    play("machine_gun_reverberation")
                }
                buttonState = false
            }
            try serviceOfSelectionByKeyboard()
            try await rt.wait()
        }
    }

    private func createShell() {
        let i = creationOfBullet(.shell, a.sprite("sprite_of_shell_from_machine_gun"))
        let x = mouseX + 3 + random()
        let y = mouseY - 3 - random()
        speedX[i] = random()
        speedY[i] = random()
        bullets[i].x = x
        bullets[i].y = y
        bullets[i].setVisible(true)
    }

    // MARK: 3: flame-thrower

    private func serviceOfFlameThrower() async throws {
        tool.setDef(a.sprite("sprite_of_flame_thrower"))
        tool.setVisible(true)
        while noInterruptOfActiveTool {
            if rt.rightClick() { break }
            tool.x = mouseX
            tool.y = mouseY - 8
            calculationOfSoundStereobase()
            serviceOfBulletsFlight()
            if rt.mouseLeft { // shooting
                if !buttonState {
                    rt.audio.stop()
                    play("flame_begin", balance: stereobase)
                }
                play("flame", balance: stereobase, loops: 0, restart: false)
                buttonState = true
                createFlame()
            } else {
                if buttonState { // terminate sounds
                    play("flame", balance: stereobase, restart: false)
                    play("flame_end", balance: stereobase)
                }
                buttonState = false
            }
            try serviceOfSelectionByKeyboard()
            try await rt.wait()
        }
    }

    private func createFlame() {
        let i = creationOfBullet(.flyingFlame, a.sprite("sprite_of_flame"))
        let b = bullets[i]
        b.x = mouseX + 3 + random(0.2)
        b.y = mouseY - 3.4 - random(0.2)
        b.setVisible(true)
        b.x = b.x - 3 - random()
        b.y = b.y + 2 + random()
    }

    // MARK: 4: color-thrower

    private func serviceOfColorThrower() async throws {
        var rechargeCounter = 0
        tool.setDef(a.sprite("sprite_of_color_thrower"))
        tool.setVisible(true)
        while noInterruptOfActiveTool {
            if rt.rightClick() { break }
            tool.x = mouseX
            tool.y = mouseY - 8
            calculationOfSoundStereobase()
            serviceOfBulletsFlight()
            rechargeCounter -= 1
            if rt.mouseLeft && rechargeCounter <= 0 { // shooting
                rt.audio.stop()
                play("color_thrower_shooting", balance: stereobase)
                rechargeCounter = 9
                createColor()
            }
            try serviceOfSelectionByKeyboard()
            try await rt.wait()
        }
    }

    private func createColor() {
        let name = Self.colorNames[randomInt(8)]
        let i = creationOfBullet(.color, a.sprite("sprite_of_color_\(name)"))
        let b = bullets[i]
        b.x = mouseX + 3 + random(0.2)
        b.y = mouseY - 3.4 - random(0.2)
        b.setVisible(true)
        b.x = b.x - 4 - random()
        b.y = b.y + 2.4 + random()
    }

    // MARK: 5: phaser

    private func phaserService() async throws {
        var dischargeCounter = 0
        tool.setDef(a.sprite("sprite_of_phaser"))
        tool.setVisible(true)
        while noInterruptOfActiveTool {
            if rt.rightClick() { break }
            tool.x = mouseX - 2
            tool.y = mouseY - 8
            calculationOfSoundStereobase()
            serviceOfBulletsFlight()
            if rt.leftClick() && dischargeCounter <= 0 { // begin shoot
                dischargeCounter = 6
                rt.audio.stop()
                play("phaser", balance: stereobase)
            }
            if dischargeCounter > 0 { // service of shoot
                dischargeCounter -= 1
                tool.setDef(a.sprite("sprite_of_shooting_phaser"))
                deathOfTermites(x: mouseX, y: mouseY)
                let hit = a.picture("picture_of_phaser_hit_\(randomInt(10) + 1)")
                rt.canvas.draw(hit, x: tool.x + 0.2 - random(0.1), y: tool.y + 6 + random(0.1))
            } else {
                tool.setDef(a.sprite("sprite_of_phaser"))
            }
            try serviceOfSelectionByKeyboard()
            try await rt.wait()
        }
    }

    // MARK: 6: stamp

    private func serviceOfStamp() async throws {
        tool.setDef(a.sprite("sprite_of_stamp"))
        tool.setVisible(true)
        while noInterruptOfActiveTool {
            if rt.rightClick() { break }
            tool.x = mouseX - 1.5
            tool.y = mouseY - 1.5
            calculationOfSoundStereobase()
            serviceOfBulletsFlight()
            if rt.mouseLeft { // print of stamp
                tool.setDef(a.sprite("sprite_of_stamp_down"))
                if rt.leftClick() { // it is first print
                    rt.audio.stop()
                    play("stamp", balance: stereobase)
                    rt.canvas.draw(stampPrints[randomInt(10)], x: tool.x, y: tool.y)
                    deathOfTermites(x: mouseX, y: mouseY)
                }
            } else {
                tool.setDef(a.sprite("sprite_of_stamp"))
            }
            try serviceOfSelectionByKeyboard()
            try await rt.wait()
        }
    }

    // MARK: 7: termite

    private func serviceOfTermite() async throws {
        tool.setDef(a.sprite("sprite_of_termite_on_hand"))
        tool.setVisible(true)
        while noInterruptOfActiveTool {
            if rt.rightClick() { break }
            tool.x = mouseX - 1
            tool.y = mouseY - 1
            calculationOfSoundStereobase()
            serviceOfBulletsFlight()
            if rt.mouseLeft { // put termite down
                tool.setDef(a.sprite("sprite_of_termite_down"))
                if !buttonState { // it is first push
                    let i = creationOfBullet(.termite, a.sprite("termite"))
                    bullets[i].x = mouseX - 0.5
                    bullets[i].y = mouseY - 0.5
                    bullets[i].setVisible(true)
                }
            } else {
                tool.setDef(a.sprite("sprite_of_termite_on_hand"))
            }
            buttonState = rt.mouseLeft
            try serviceOfSelectionByKeyboard()
            try await rt.wait()
        }
    }

    // MARK: 8: washing

    private func serviceOfWashing() async throws {
        tool.setDef(a.sprite("sprite_of_washing"))
        tool.setVisible(true)
        while noInterruptOfActiveTool {
            if rt.rightClick() { break }
            tool.x = mouseX - 2
            tool.y = mouseY - 8
            calculationOfSoundStereobase()
            serviceOfBulletsFlight()
            if rt.mouseLeft { // service of washing
                tool.setDef(a.sprite("sprite_of_proceeding_washing"))
                if !buttonState { rt.audio.stop() }
                play("sound_of_washing", balance: stereobase, loops: 0, restart: false)
                restoreOnePart(width: 1, height: 2.5)
                restoreOnePart(width: 1.5, height: 2.25)
                restoreOnePart(width: 2, height: 2)
                restoreOnePart(width: 2.25, height: 1.5)
                restoreOnePart(width: 2.5, height: 1)
            } else {
                tool.setDef(a.sprite("sprite_of_washing"))
                if buttonState { rt.audio.stop() }
            }
            buttonState = rt.mouseLeft
            try serviceOfSelectionByKeyboard()
            try await rt.wait()
        }
    }

    private func restoreOnePart(width: Double, height: Double) {
        guard let desktopOriginal else { return }
        let h = height + random(0.4) - 0.2
        let w = width + random(0.4) - 0.2
        let x = max(0, mouseX - w / 2)
        let y = max(0, mouseY - h / 2)
        rt.canvas.draw(desktopOriginal, x: x, y: y, block: (x, y, w, h))
    }
}
