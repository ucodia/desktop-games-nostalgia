import AppKit
import QuartzCore

/// The Peter "sheet": a bitmap the program paints on, addressed in Peter units with the origin
/// at the bottom-left (y grows upward). One unit is 32 points.
final class Canvas {
    static let pointsPerUnit: Double = 32
    static let tileSize = 256

    let width: Int
    let height: Int
    let scale: Double
    let context: CGContext
    private let pixels: UnsafeMutablePointer<UInt32>
    private let quantizer: PaletteQuantizer

    private(set) var tileLayers: [CALayer] = []
    private var tilesX = 0
    private var tilesY = 0
    private var dirtyTiles = Set<Int>()

    var pixelsPerUnit: Double { Self.pointsPerUnit * scale }
    var widthUnits: Double { Double(width) / pixelsPerUnit }
    var heightUnits: Double { Double(height) / pixelsPerUnit }

    init(width: Int, height: Int, scale: Double, quantizer: PaletteQuantizer) {
        self.width = width
        self.height = height
        self.scale = scale
        self.quantizer = quantizer
        pixels = .allocate(capacity: width * height)
        pixels.initialize(repeating: 0xFF00_0000, count: width * height)
        context = CGContext(data: pixels, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.interpolationQuality = .none
        context.setShouldAntialias(false)

        tilesX = (width + Self.tileSize - 1) / Self.tileSize
        tilesY = (height + Self.tileSize - 1) / Self.tileSize
        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                let layer = CALayer()
                let x = tx * Self.tileSize, y = ty * Self.tileSize
                let w = min(Self.tileSize, width - x), h = min(Self.tileSize, height - y)
                layer.frame = CGRect(x: Double(x) / scale, y: Double(y) / scale, width: Double(w) / scale, height: Double(h) / scale)
                layer.actions = ["contents": NSNull()]
                layer.isOpaque = true
                tileLayers.append(layer)
            }
        }
        markDirty(CGRect(x: 0, y: 0, width: width, height: height))
    }

    deinit {
        pixels.deallocate()
    }

    // MARK: Peter graphics commands

    /// background_disp: draw a picture with its lower-left corner at (x, y), optionally only a block of it.
    func draw(_ picture: Picture, x: Double, y: Double,
              block: (x: Double, y: Double, w: Double, h: Double)? = nil) {
        var image = picture.image
        var w = picture.width, h = picture.height
        if let b = block {
            let ppu = picture.pixelsPerUnit
            var src = CGRect(x: b.x * ppu, y: Double(image.height) - (b.y + b.h) * ppu, width: b.w * ppu, height: b.h * ppu)
            src = src.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard !src.isEmpty, let cropped = image.cropping(to: src) else { return }
            image = cropped
            w = src.width / ppu
            h = src.height / ppu
        }
        let rect = CGRect(x: (x * pixelsPerUnit).rounded(), y: (y * pixelsPerUnit).rounded(),
                          width: (w * pixelsPerUnit).rounded(), height: (h * pixelsPerUnit).rounded())
        context.draw(image, in: rect)
        markDirty(rect)
    }

    /// background_get: snapshot of the whole sheet.
    func snapshot() -> Picture {
        Picture(image: context.makeImage()!, pixelsPerUnit: pixelsPerUnit)
    }

    func fill(color: RGB) {
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        markDirty(CGRect(x: 0, y: 0, width: width, height: height))
    }

    func line(color: RGB, widthPixels: Double, x1: Double, y1: Double, x2: Double, y2: Double) {
        let lw = max(1, widthPixels * scale)
        context.setShouldAntialias(true)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lw)
        context.setLineCap(.round)
        let p1 = CGPoint(x: x1 * pixelsPerUnit, y: y1 * pixelsPerUnit)
        let p2 = CGPoint(x: x2 * pixelsPerUnit, y: y2 * pixelsPerUnit)
        context.move(to: p1)
        context.addLine(to: p2)
        context.strokePath()
        context.setShouldAntialias(false)
        markDirty(CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y)).insetBy(dx: -lw, dy: -lw))
    }

    func point(color: RGB, widthPixels: Double, x: Double, y: Double) {
        let d = max(1, widthPixels * scale)
        let rect = CGRect(x: x * pixelsPerUnit - d / 2, y: y * pixelsPerUnit - d / 2, width: d, height: d)
        context.setShouldAntialias(true)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: rect)
        context.setShouldAntialias(false)
        markDirty(rect.insetBy(dx: -1, dy: -1))
    }

    /// get_point: color under a unit coordinate.
    func color(x: Double, y: Double) -> RGB {
        let px = Int(x * pixelsPerUnit), py = Int(y * pixelsPerUnit)
        guard px >= 0, py >= 0, px < width, py < height else { return RGB(r: 0, g: 0, b: 0) }
        return RGB(pixel: pixels[(height - 1 - py) * width + px])
    }

    /// fill: flood fill of the area that shares the seed's color. The original runs in Peter's
    /// 224-color palette, so "same color" means "maps to the same palette entry".
    func floodFill(color: RGB, x: Double, y: Double) {
        let sx = Int(x * pixelsPerUnit), sy = height - 1 - Int(y * pixelsPerUnit)
        guard sx >= 0, sy >= 0, sx < width, sy < height else { return }
        let target = quantizer.index(of: pixels[sy * width + sx])
        let fill = color.pixel
        var visited = [Bool](repeating: false, count: width * height)
        var stack = [(sx, sy)]
        var minX = sx, maxX = sx, minY = sy, maxY = sy

        func matches(_ i: Int) -> Bool { !visited[i] && quantizer.index(of: pixels[i]) == target }

        while let (x0, y0) = stack.popLast() {
            let row = y0 * width
            guard matches(row + x0) else { continue }
            var l = x0, r = x0
            while l > 0 && matches(row + l - 1) { l -= 1 }
            while r < width - 1 && matches(row + r + 1) { r += 1 }
            for i in l...r {
                visited[row + i] = true
                pixels[row + i] = fill
            }
            minX = min(minX, l); maxX = max(maxX, r); minY = min(minY, y0); maxY = max(maxY, y0)
            for ny in [y0 - 1, y0 + 1] where ny >= 0 && ny < height {
                var i = l
                let nrow = ny * width
                while i <= r {
                    if matches(nrow + i) {
                        stack.append((i, ny))
                        while i <= r && matches(nrow + i) { i += 1 }
                    }
                    i += 1
                }
            }
        }
        markDirty(CGRect(x: minX, y: height - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    // MARK: Display

    private func markDirty(_ rect: CGRect) {
        let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !r.isNull, !r.isEmpty else { return }
        let x0 = Int(r.minX) / Self.tileSize, x1 = (Int(r.maxX) - 1) / Self.tileSize
        let y0 = Int(r.minY) / Self.tileSize, y1 = (Int(r.maxY) - 1) / Self.tileSize
        for ty in y0...y1 {
            for tx in x0...x1 { dirtyTiles.insert(ty * tilesX + tx) }
        }
    }

    /// Push dirty tiles to their layers.
    func flush() {
        guard !dirtyTiles.isEmpty else { return }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        for t in dirtyTiles {
            let tx = t % tilesX, ty = t / tilesX
            let x = tx * Self.tileSize, y = ty * Self.tileSize
            let w = min(Self.tileSize, width - x), h = min(Self.tileSize, height - y)
            var data = Data(count: w * h * 4)
            data.withUnsafeMutableBytes { raw in
                let dst = raw.bindMemory(to: UInt32.self).baseAddress!
                for row in 0..<h {
                    let srcRow = height - 1 - (y + h - 1 - row)
                    (dst + row * w).update(from: pixels + srcRow * width + x, count: w)
                }
            }
            let provider = CGDataProvider(data: data as CFData)!
            let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                space: space,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            tileLayers[t].contents = image
        }
        dirtyTiles.removeAll()
    }
}

extension RGB {
    init(pixel: UInt32) {
        r = UInt8(pixel & 0xFF)
        g = UInt8((pixel >> 8) & 0xFF)
        b = UInt8((pixel >> 16) & 0xFF)
    }

    var pixel: UInt32 { UInt32(r) | UInt32(g) << 8 | UInt32(b) << 16 | 0xFF00_0000 }

    var cgColor: CGColor {
        CGColor(srgbRed: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: 1)
    }

    /// The numeric color value Peter's get_point returns.
    var peterValue: Int { Int(r) | Int(g) << 8 | Int(b) << 16 }
}

/// Maps true colors to the nearest entry of Peter's palette (through a 15-bit lookup table).
final class PaletteQuantizer {
    private var table = [UInt8](repeating: 0, count: 32768)

    init(palette: [RGB]) {
        let entries = palette.enumerated().filter { $0.offset >= 2 }
        for key in 0..<32768 {
            let r = Int((key >> 10) & 31) << 3 | 4, g = Int((key >> 5) & 31) << 3 | 4, b = Int(key & 31) << 3 | 4
            var best = 0, bestDist = Int.max
            for (i, c) in entries {
                let dr = r - Int(c.r), dg = g - Int(c.g), db = b - Int(c.b)
                let dist = dr * dr * 3 + dg * dg * 4 + db * db * 2
                if dist < bestDist { bestDist = dist; best = i }
            }
            table[key] = UInt8(best)
        }
    }

    @inline(__always)
    func index(of pixel: UInt32) -> UInt8 {
        let r = Int(pixel & 0xFF) >> 3, g = Int((pixel >> 8) & 0xFF) >> 3, b = Int((pixel >> 16) & 0xFF) >> 3
        return table[r << 10 | g << 5 | b]
    }
}
