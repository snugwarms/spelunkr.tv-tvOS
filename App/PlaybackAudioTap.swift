import AVFoundation
import MediaToolbox

/// Copies decoded playback audio into a bounded pool; conversion never runs on the audio thread.
final class PlaybackAudioTap {
    private let bridge: CaptionAudioBridge
    private let mix: AVAudioMix
    private weak var item: AVPlayerItem?
    private init(bridge: CaptionAudioBridge, mix: AVAudioMix, item: AVPlayerItem) {
        self.bridge = bridge; self.mix = mix; self.item = item
    }

    @MainActor static func attach(to item: AVPlayerItem, targetFormat: AVAudioFormat,
        receive: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void) async throws -> PlaybackAudioTap {
        let bridge = CaptionAudioBridge(target: targetFormat, receive: receive)
        let track: AVAssetTrack?
        if #available(tvOS 27.0, *) { track = nil }
        else {
            guard let audio = try await item.asset.loadTracks(withMediaType: .audio).first else { throw AudioTapError.noAudio }
            track = audio
        }
        try Task.checkCancellation()
        let retained = Unmanaged.passRetained(bridge)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: retained.toOpaque(),
            init: { _, info, storage in storage.pointee = info },
            finalize: { tap in Unmanaged<CaptionAudioBridge>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
            prepare: { tap, frames, description in
                Unmanaged<CaptionAudioBridge>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .prepare(frames: AVAudioFrameCount(frames), description: description)
            }, unprepare: nil,
            process: { tap, frames, _, buffers, outputFrames, flags in
                var range = CMTimeRange.zero
                let result = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flags, &range, outputFrames)
                guard result == noErr, outputFrames.pointee > 0 else { return }
                Unmanaged<CaptionAudioBridge>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .copy(buffers, frames: AVAudioFrameCount(outputFrames.pointee), time: range.start)
            })
        var tap: MTAudioProcessingTap?
        let result: OSStatus
        let parameters: AVMutableAudioMixInputParameters
        if #available(tvOS 27.0, *) {
            parameters = AVMutableAudioMixInputParameters()
            parameters.trackID = 0
            result = MTAudioProcessingTapCreateWithPreferredFormat(kCFAllocatorDefault, &callbacks,
                kMTAudioProcessingTapCreationFlag_PreEffects, targetFormat.formatDescription, &tap)
        } else {
            parameters = AVMutableAudioMixInputParameters(track: track)
            result = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        }
        guard result == noErr, let tap else { retained.release(); throw AudioTapError.creation(result) }
        try Task.checkCancellation()
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix(); mix.inputParameters = [parameters]
        item.audioMix = mix
        return PlaybackAudioTap(bridge: bridge, mix: mix, item: item)
    }

    @MainActor func stop() {
        bridge.stop()
        if item?.audioMix === mix { item?.audioMix = nil }
    }
}

private enum AudioTapError: LocalizedError {
    case noAudio, creation(OSStatus)
    var errorDescription: String? {
        switch self {
        case .noAudio: return "This tape has no audio track to caption."
        case .creation: return "The audio caption processor could not start."
        }
    }
}

private final class CaptionAudioBridge: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "tv.spelunkr.caption-audio", qos: .userInitiated)
    private let target: AVAudioFormat
    private let receive: @Sendable (AVAudioPCMBuffer, CMTime) -> Void
    private var pool: [AVAudioPCMBuffer] = []
    private var active = true
    private var converter: AVAudioConverter?
    init(target: AVAudioFormat, receive: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void) {
        self.target = target; self.receive = receive
    }
    func prepare(frames: AVAudioFrameCount, description: UnsafePointer<AudioStreamBasicDescription>) {
        guard let source = AVAudioFormat(streamDescription: description) else { return }
        queue.sync { converter = AVAudioConverter(from: source, to: target) }
        let buffers = (0..<8).compactMap { _ in AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames) }
        lock.lock(); pool = buffers; lock.unlock()
    }
    func stop() { lock.lock(); active = false; lock.unlock() }
    func copy(_ source: UnsafeMutablePointer<AudioBufferList>, frames: AVAudioFrameCount, time: CMTime) {
        guard lock.try() else { return }
        guard active, let buffer = pool.popLast() else { lock.unlock(); return }
        lock.unlock()
        guard frames <= buffer.frameCapacity else { recycle(buffer); return }
        buffer.frameLength = frames
        let input = UnsafeMutableAudioBufferListPointer(source)
        let output = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard input.count == output.count else { recycle(buffer); return }
        for index in input.indices {
            guard let src = input[index].mData, let dst = output[index].mData else { continue }
            memcpy(dst, src, min(Int(input[index].mDataByteSize), Int(output[index].mDataByteSize)))
        }
        queue.async { [self] in
            defer { recycle(buffer) }
            guard isActive, let converter else { return }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32)
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            let result = converter.convert(to: converted, error: &error) { _, status in
                guard !supplied else { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            if result != .error, error == nil, converted.frameLength > 0 { receive(converted, time) }
        }
    }
    private var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    private func recycle(_ buffer: AVAudioPCMBuffer) { lock.lock(); pool.append(buffer); lock.unlock() }
}
