import AVFoundation
import os

/// Software mixer reproducing Peter's sound_play semantics (FUN_0042cf20):
/// one channel per sound; replaying a sound that is still playing only restarts it when
/// `restart` is set, but always updates its volume, balance and remaining loops.
final class AudioMixer {
    private struct Channel {
        let clip: SoundClip
        var position: Double = 0
        var step: Double
        var left: Float
        var right: Float
        var loops: Int
    }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    private let state = OSAllocatedUnfairLock(initialState: [Channel]())
    private var outputRate: Double = 44100
    var muted = false

    init() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        outputRate = format.sampleRate > 0 ? format.sampleRate : 44100
        let stereo = AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 2)!
        let state = self.state
        source = AVAudioSourceNode(format: stereo) { _, _, frameCount, bufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(bufferList)
            let left = abl[0].mData!.assumingMemoryBound(to: Float.self)
            let right = abl[1].mData!.assumingMemoryBound(to: Float.self)
            let n = Int(frameCount)
            for i in 0..<n {
                left[i] = 0
                right[i] = 0
            }
            state.withLock { channels in
                var k = 0
                while k < channels.count {
                    var ch = channels[k]
                    let samples = ch.clip.samples
                    let frames = ch.clip.frameCount
                    var alive = true
                    for i in 0..<n {
                        var idx = Int(ch.position)
                        if idx >= frames {
                            ch.loops -= 1
                            if ch.loops <= 0 {
                                alive = false
                                break
                            }
                            ch.position -= Double(frames)
                            idx = max(0, Int(ch.position))
                        }
                        left[i] += samples[idx * 2] * ch.left
                        right[i] += samples[idx * 2 + 1] * ch.right
                        ch.position += ch.step
                    }
                    if alive {
                        channels[k] = ch
                        k += 1
                    } else {
                        channels.remove(at: k)
                    }
                }
            }
            for i in 0..<n {
                left[i] = max(-1, min(1, left[i]))
                right[i] = max(-1, min(1, right[i]))
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: stereo)
        do {
            try engine.start()
        } catch {
            NSLog("audio engine failed to start: \(error)")
        }
    }

    /// sound_play. `loops` < 1 means endless.
    func play(_ clip: SoundClip, volume: Double = 1, balance: Double = 0, speed: Double = 1,
              loops: Int = 1, restart: Bool = true) {
        guard !muted else { return }
        let vol = Float(min(abs(volume), 1))
        let bal = max(-1, min(1, balance))
        let l = vol * Float(bal > 0 ? 1 - bal : 1)
        let r = vol * Float(bal <= 0 ? 1 + bal : 1)
        let count = loops < 1 || loops > 100_000 ? Int.max : loops
        let step = clip.sampleRate / outputRate * max(0.01, abs(speed))
        state.withLock { channels in
            if let i = channels.firstIndex(where: { $0.clip === clip }) {
                if restart { channels[i].position = 0 }
                channels[i].left = l
                channels[i].right = r
                channels[i].step = step
                channels[i].loops = count
            } else {
                channels.append(Channel(clip: clip, step: step, left: l, right: r, loops: count))
            }
        }
    }

    /// sound_stop, for one sound or all of them.
    func stop(_ clip: SoundClip? = nil) {
        state.withLock { channels in
            if let clip {
                channels.removeAll { $0.clip === clip }
            } else {
                channels.removeAll()
            }
        }
    }
}
