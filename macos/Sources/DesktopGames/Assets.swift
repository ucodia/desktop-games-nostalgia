import AppKit
import ImageIO

/// A Peter "background" picture. Coordinates are expressed in Peter units (1 unit = 32 px at 1x).
struct Picture {
    let image: CGImage
    let pixelsPerUnit: Double

    var width: Double { Double(image.width) / pixelsPerUnit }
    var height: Double { Double(image.height) / pixelsPerUnit }
}

final class SpriteDef {
    let name: String
    /// frames[direction][phase]
    let frames: [[CGImage]]
    let width: Int
    let height: Int
    let phases: Int
    let directions: Int
    let restPhases: Int
    let delayMs: Int
    let level: Int
    let steps: Double

    init(name: String, frames: [[CGImage]], width: Int, height: Int, phases: Int, directions: Int,
         restPhases: Int, delayMs: Int, level: Int, steps: Double) {
        self.name = name
        self.frames = frames
        self.width = width
        self.height = height
        self.phases = phases
        self.directions = directions
        self.restPhases = max(1, restPhases)
        self.delayMs = delayMs
        self.level = level
        self.steps = steps
    }

    /// Number of 55 ms ticks between animation steps, as computed by the Peter runtime.
    var delayTicks: Int { (delayMs + 22) / 55 }
}

final class SoundClip {
    let name: String
    /// Interleaved stereo samples.
    let samples: [Float]
    let sampleRate: Double

    var frameCount: Int { samples.count / 2 }

    init(name: String, samples: [Float], sampleRate: Double) {
        self.name = name
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

struct RGB: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
}

enum AssetError: Error {
    case missing(String)
    case badWave(String)
}

/// Assets extracted from the original program by tools/extract.py.
final class AssetStore {
    private(set) var pictures: [String: Picture] = [:]
    private(set) var sprites: [String: SpriteDef] = [:]
    private(set) var sounds: [String: SoundClip] = [:]
    private(set) var iconColors: [RGB] = []
    private(set) var palette: [RGB] = []

    init(directory: URL) throws {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        palette = manifest.palette.map { RGB(r: UInt8($0[0]), g: UInt8($0[1]), b: UInt8($0[2])) }
        iconColors = manifest.icons.map { RGB(r: UInt8($0.center_color[0]), g: UInt8($0.center_color[1]), b: UInt8($0.center_color[2])) }

        for p in manifest.pictures {
            pictures[p.name] = Picture(image: try Self.loadImage(directory.appendingPathComponent(p.file)), pixelsPerUnit: 32)
        }

        for s in manifest.sprites {
            let sheet = try Self.loadImage(directory.appendingPathComponent(s.file))
            var frames: [[CGImage]] = []
            for d in 0..<s.directions {
                var row: [CGImage] = []
                for ph in 0..<s.phases {
                    let rect = CGRect(x: ph * s.width, y: d * s.height, width: s.width, height: s.height)
                    guard let frame = sheet.cropping(to: rect) else { throw AssetError.missing(s.file) }
                    row.append(frame)
                }
                frames.append(row)
            }
            sprites[s.name] = SpriteDef(name: s.name, frames: frames, width: s.width, height: s.height,
                                        phases: s.phases, directions: s.directions, restPhases: s.rest_phases,
                                        delayMs: s.delay_ms, level: s.level, steps: s.steps)
        }

        for s in manifest.sounds {
            sounds[s.name] = try Self.loadWave(directory.appendingPathComponent(s.file), name: s.name)
        }
    }

    func picture(_ name: String) -> Picture {
        guard let p = pictures[name] else { fatalError("missing picture \(name)") }
        return p
    }

    func sprite(_ name: String) -> SpriteDef {
        guard let s = sprites[name] else { fatalError("missing sprite \(name)") }
        return s
    }

    func sound(_ name: String) -> SoundClip {
        guard let s = sounds[name] else { fatalError("missing sound \(name)") }
        return s
    }

    private static func loadImage(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw AssetError.missing(url.lastPathComponent)
        }
        return img
    }

    /// Minimal reader for the canonical PCM16 WAV files written by extract.py.
    private static func loadWave(_ url: URL, name: String) throws -> SoundClip {
        let d = try Data(contentsOf: url)
        func u32(_ o: Int) -> UInt32 { d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) } }
        func u16(_ o: Int) -> UInt16 { d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) } }
        guard d.count >= 44, d.prefix(4) == Data("RIFF".utf8) else { throw AssetError.badWave(name) }

        var pos = 12
        var channels = 1, rate = 22050, bits = 16
        var pcm = Data()
        while pos + 8 <= d.count {
            let id = String(decoding: d[pos..<pos + 4], as: UTF8.self)
            let size = Int(u32(pos + 4))
            if id == "fmt " {
                channels = Int(u16(pos + 10))
                rate = Int(u32(pos + 12))
                bits = Int(u16(pos + 22))
            } else if id == "data" {
                pcm = d[(pos + 8)..<min(d.count, pos + 8 + size)]
            }
            pos += 8 + size + (size & 1)
        }
        guard bits == 16 else { throw AssetError.badWave(name) }

        let count = pcm.count / 2
        var out = [Float](repeating: 0, count: (count / channels) * 2)
        pcm.withUnsafeBytes { raw in
            let s = raw.bindMemory(to: Int16.self)
            let frames = count / channels
            for f in 0..<frames {
                let l = Float(Int16(littleEndian: s[f * channels])) / 32768
                let r = channels > 1 ? Float(Int16(littleEndian: s[f * channels + 1])) / 32768 : l
                out[f * 2] = l
                out[f * 2 + 1] = r
            }
        }
        return SoundClip(name: name, samples: out, sampleRate: Double(rate))
    }

    static func locate() -> URL? {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL?.appendingPathComponent("Assets"),
           fm.fileExists(atPath: res.appendingPathComponent("manifest.json").path) {
            return res
        }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("re/assets")
            if fm.fileExists(atPath: candidate.appendingPathComponent("manifest.json").path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}

private struct Manifest: Decodable {
    struct Icon: Decodable { let index: Int; let center_color: [Int] }
    struct Pic: Decodable { let name: String; let file: String }
    struct Spr: Decodable {
        let name: String; let file: String; let width: Int; let height: Int
        let phases: Int; let directions: Int; let rest_phases: Int
        let delay_ms: Int; let level: Int; let steps: Double
    }
    struct Snd: Decodable { let name: String; let file: String }

    let icons: [Icon]
    let pictures: [Pic]
    let sprites: [Spr]
    let sounds: [Snd]
    let palette: [[Int]]
}
