import CEBUR128
import Foundation

/// Streaming EBU R128 / BS.1770 metering with bounded, smoothed playback gain.
/// One instance belongs to one audio render stream and is only used on that render thread.
public final class LoudnessProcessor {
    public let targetLUFS: Double
    public private(set) var inputLUFS: Double = -.infinity
    public private(set) var gainDB: Double = -12
    public private(set) var inputTruePeakDB: Double = -.infinity
    private var state: UnsafeMutablePointer<ebur128_state>?
    private let channels: Int
    private let sampleRate: Double
    private var framesSeen = 0
    private var framesSinceAnalysis = 0
    private var desiredDB: Double = -12

    public init?(channels: Int, sampleRate: Double, targetLUFS: Double = -23) {
        guard (1...8).contains(channels), sampleRate.isFinite, (8000...192000).contains(sampleRate) else { return nil }
        self.channels = channels; self.sampleRate = sampleRate; self.targetLUFS = targetLUFS
        let mode = EBUR128_MODE_I.rawValue | EBUR128_MODE_TRUE_PEAK.rawValue | EBUR128_MODE_HISTOGRAM.rawValue
        state = ebur128_init(UInt32(channels), UInt(sampleRate), Int32(mode))
        guard state != nil else { return nil }
    }
    deinit { ebur128_destroy(&state) }

    public func process(_ samples: UnsafeMutableBufferPointer<Float>, frames: Int) {
        guard let state, let base = samples.baseAddress, frames > 0, samples.count >= frames * channels else { return }
        for index in 0..<(frames * channels) where !base[index].isFinite { base[index] = 0 }
        guard ebur128_add_frames_float(state, base, frames) == EBUR128_SUCCESS.rawValue else { return }
        framesSeen += frames; framesSinceAnalysis += frames
        if framesSeen >= Int(sampleRate * 0.4), framesSinceAnalysis >= Int(sampleRate * 0.1) {
            framesSinceAnalysis = 0
            var integrated = -Double.infinity, momentary = -Double.infinity
            if ebur128_loudness_global(state, &integrated) == EBUR128_SUCCESS.rawValue, integrated.isFinite {
                inputLUFS = integrated
                if integrated > -50 {
                    desiredDB = min(12, max(-24, targetLUFS - integrated))
                    if ebur128_loudness_momentary(state, &momentary) == EBUR128_SUCCESS.rawValue, momentary.isFinite, momentary > -50 {
                        desiredDB = min(desiredDB, targetLUFS + 3 - momentary)
                    } else { desiredDB = min(0, desiredDB); gainDB = min(0, gainDB) }
                } else { desiredDB = min(0, desiredDB) }
            }
        }
        var truePeak: Double = 0
        for channel in 0..<channels {
            var peak: Double = 0
            if ebur128_prev_true_peak(state, UInt32(channel), &peak) == EBUR128_SUCCESS.rawValue { truePeak = max(truePeak, peak) }
        }
        inputTruePeakDB = truePeak > 0 ? 20 * log10(truePeak) : -.infinity
        // A conservative true-peak ceiling leaves margin for gain ramps at block boundaries.
        let peakCeilingDB = truePeak > 0 ? -1.5 - inputTruePeakDB : 12
        gainDB = min(gainDB, peakCeilingDB)
        let target = min(desiredDB, peakCeilingDB)
        let timeConstant = target < gainDB ? 0.12 : 2.0
        let coefficient = 1 - exp(-1 / (sampleRate * timeConstant))
        let sampleCeiling: Float = 0.89125094 // -1 dBFS failsafe in addition to true-peak-based gain.
        for frame in 0..<frames {
            gainDB += (target - gainDB) * coefficient
            let gain = Float(pow(10, gainDB / 20))
            for channel in 0..<channels {
                let index = frame * channels + channel
                base[index] = max(-sampleCeiling, min(sampleCeiling, base[index] * gain))
            }
        }
    }
}
