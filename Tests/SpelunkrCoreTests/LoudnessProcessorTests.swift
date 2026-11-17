import CEBUR128
import XCTest
@testable import SpelunkrCore

final class LoudnessProcessorTests: XCTestCase {
    private func render(amplitude: Float, channels: Int = 2, sampleRate: Int = 48000, seconds: Int = 10) throws -> (Double, Double) {
        let processor = try XCTUnwrap(LoudnessProcessor(channels: channels, sampleRate: Double(sampleRate)))
        let meter = try XCTUnwrap(ebur128_init(UInt32(channels), UInt(sampleRate), Int32(EBUR128_MODE_I.rawValue | EBUR128_MODE_TRUE_PEAK.rawValue)))
        defer { var optional: UnsafeMutablePointer<ebur128_state>? = meter; ebur128_destroy(&optional) }
        var block = [Float](repeating: 0, count: 480 * channels)
        for start in stride(from: 0, to: sampleRate * seconds, by: 480) {
            let frames = min(480, sampleRate * seconds - start)
            for frame in 0..<frames {
                let sample = amplitude * Float(sin(2 * .pi * 1000 * Double(start + frame) / Double(sampleRate)))
                for channel in 0..<channels { block[frame * channels + channel] = sample }
            }
            block.withUnsafeMutableBufferPointer { processor.process($0, frames: frames) }
            if start >= sampleRate * 5 { _ = ebur128_add_frames_float(meter, block, frames) }
        }
        var loudness = -Double.infinity, peak: Double = 0
        XCTAssertEqual(ebur128_loudness_global(meter, &loudness), Int32(EBUR128_SUCCESS.rawValue))
        for channel in 0..<channels {
            var value: Double = 0
            _ = ebur128_true_peak(meter, UInt32(channel), &value); peak = max(peak, value)
        }
        return (loudness, peak > 0 ? 20 * log10(peak) : -.infinity)
    }

    func testQuietAndLoudStereoTapesConvergeToSameLUFS() throws {
        let quiet = try render(amplitude: 0.03), loud = try render(amplitude: 0.6)
        XCTAssertEqual(quiet.0, -23, accuracy: 1)
        XCTAssertEqual(loud.0, -23, accuracy: 1)
        XCTAssertEqual(quiet.0, loud.0, accuracy: 1)
        XCTAssertLessThanOrEqual(loud.1, -1)
    }

    func testMonoAnd44100HzUseSameTarget() throws {
        XCTAssertEqual(try render(amplitude: 0.1, channels: 1, sampleRate: 44100).0, -23, accuracy: 1)
    }

    func testSilenceAndNonfiniteSamplesStaySafe() throws {
        let processor = try XCTUnwrap(LoudnessProcessor(channels: 2, sampleRate: 48000))
        var samples: [Float] = [.nan, .infinity, -.infinity, 0, 1, -1]
        samples.withUnsafeMutableBufferPointer { processor.process($0, frames: 3) }
        XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 0.892 })
        var silence = [Float](repeating: 0, count: 960)
        for _ in 0..<200 { silence.withUnsafeMutableBufferPointer { processor.process($0, frames: 480) } }
        XCTAssertTrue(silence.allSatisfy { $0 == 0 })
        XCTAssertLessThanOrEqual(processor.gainDB, 0)
    }
}
