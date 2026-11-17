import AVFoundation
import MediaToolbox
import SpelunkrCore

struct PlaybackAudioStatistics {
    var frames = 0
    var channels = 0
    var inputLUFS: Double = -.infinity
    var gainDB: Double = 0
}

/// One tap per player item, shared by volume leveling and optional speech transcription.
final class PlaybackAudioTap {
    @MainActor private static var installed: [ObjectIdentifier: WeakTap] = [:]
    private final class WeakTap { weak var value: PlaybackAudioTap?; init(_ value: PlaybackAudioTap) { self.value = value } }
    private let bridge: PlaybackAudioBridge
    private let mix: AVAudioMix
    private weak var item: AVPlayerItem?
    private init(bridge: PlaybackAudioBridge, mix: AVAudioMix, item: AVPlayerItem) {
        self.bridge = bridge; self.mix = mix; self.item = item
    }

    @MainActor static func shared(for item: AVPlayerItem) async throws -> PlaybackAudioTap {
        let key = ObjectIdentifier(item)
        if let existing = installed[key]?.value { return existing }
        guard let track = try await item.asset.loadTracks(withMediaType: .audio).first else { throw AudioTapError.noAudio }
        try Task.checkCancellation()
        if let existing = installed[key]?.value { return existing }
        let bridge = PlaybackAudioBridge()
        let retained = Unmanaged.passRetained(bridge)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: retained.toOpaque(),
            init: { _, info, storage in storage.pointee = info },
            finalize: { tap in Unmanaged<PlaybackAudioBridge>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
            prepare: { tap, frames, description in
                Unmanaged<PlaybackAudioBridge>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .prepare(frames: AVAudioFrameCount(frames), description: description)
            }, unprepare: nil,
            process: { tap, frames, _, buffers, outputFrames, flags in
                var range = CMTimeRange.zero
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flags, &range, outputFrames) == noErr,
                      outputFrames.pointee > 0 else { return }
                Unmanaged<PlaybackAudioBridge>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .process(buffers, frames: AVAudioFrameCount(outputFrames.pointee), time: range.start)
            })
        var tap: MTAudioProcessingTap?
        let parameters = AVMutableAudioMixInputParameters(track: track)
        let result: OSStatus
        if #available(tvOS 27.0, *) {
            let stereo = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
            result = MTAudioProcessingTapCreateWithPreferredFormat(kCFAllocatorDefault, &callbacks,
                kMTAudioProcessingTapCreationFlag_PreEffects, stereo.formatDescription, &tap)
        } else {
            result = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        }
        guard result == noErr, let tap else { retained.release(); throw AudioTapError.creation }
        try Task.checkCancellation()
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix(); mix.inputParameters = [parameters]
        item.audioMix = mix
        let value = PlaybackAudioTap(bridge: bridge, mix: mix, item: item)
        installed = installed.filter { $0.value.value != nil }
        installed[key] = WeakTap(value)
        return value
    }

    @MainActor static func attach(to item: AVPlayerItem, targetFormat: AVAudioFormat,
        receive: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void) async throws -> PlaybackAudioTap {
        let tap = try await shared(for: item)
        tap.bridge.startCaptions(format: targetFormat, receive: receive)
        return tap
    }
    @MainActor func setNormalization(_ enabled: Bool) { bridge.setNormalization(enabled) }
    @MainActor var statistics: PlaybackAudioStatistics { bridge.statistics }
    @MainActor func stopCaptions() { bridge.stopCaptions() }
    @MainActor func stop() {
        bridge.stopCaptions()
        if item?.audioMix === mix { item?.audioMix = nil }
        if let item { Self.installed[ObjectIdentifier(item)] = nil }
    }
}

private enum AudioTapError: LocalizedError {
    case noAudio, creation
    var errorDescription: String? {
        switch self {
        case .noAudio: return "This tape has no audio track to process."
        case .creation: return "Audio processing could not start for this tape."
        }
    }
}

private final class PlaybackAudioBridge: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "tv.spelunkr.caption-audio", qos: .userInitiated)
    private var sourceFormat: AVAudioFormat?
    private var pool: [AVAudioPCMBuffer] = []
    private var scratch: [Float] = []
    private var normalizer: LoudnessProcessor?
    private var normalizationEnabled = true
    private var lastNormalizationEnabled = true
    private var processedFrames = 0
    private var savedStatistics = PlaybackAudioStatistics()
    var statistics: PlaybackAudioStatistics { lock.lock(); defer { lock.unlock() }; return savedStatistics }
    private var captionsEnabled = false
    // The following conversion state belongs exclusively to queue.
    private var target: AVAudioFormat?
    private var conversionSource: AVAudioFormat?
    private var receive: (@Sendable (AVAudioPCMBuffer, CMTime) -> Void)?
    private var converter: AVAudioConverter?

    func prepare(frames: AVAudioFrameCount, description: UnsafePointer<AudioStreamBasicDescription>) {
        guard let source = AVAudioFormat(streamDescription: description) else { return }
        sourceFormat = source
        scratch = [Float](repeating: 0, count: Int(frames) * Int(source.channelCount))
        normalizer = LoudnessProcessor(channels: Int(source.channelCount), sampleRate: source.sampleRate)
        queue.sync { conversionSource = source; converter = target.flatMap { AVAudioConverter(from: source, to: $0) } }
        let buffers = (0..<8).compactMap { _ in AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames) }
        lock.lock(); pool = buffers; lock.unlock()
    }
    func setNormalization(_ enabled: Bool) { lock.lock(); normalizationEnabled = enabled; lock.unlock() }
    func startCaptions(format: AVAudioFormat, receive: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void) {
        queue.sync {
            target = format; self.receive = receive
            converter = conversionSource.flatMap { AVAudioConverter(from: $0, to: format) }
        }
        lock.lock(); captionsEnabled = true; lock.unlock()
    }
    func stopCaptions() {
        lock.lock(); captionsEnabled = false; lock.unlock()
        queue.async { [self] in receive = nil; converter = nil; target = nil }
    }

    func process(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: AVAudioFrameCount, time: CMTime) {
        // Speech sees the original source, independent of the playback gain.
        copyForCaptions(buffers, frames: frames, time: time)
        if lock.try() { lastNormalizationEnabled = normalizationEnabled; lock.unlock() }
        guard lastNormalizationEnabled, let format = sourceFormat, let normalizer else { return }
        let channels = Int(format.channelCount), count = Int(frames)
        guard count * channels <= scratch.count else { return }
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        let interleaved = list.count == 1 && Int(list[0].mNumberChannels) == channels
        guard interleaved || list.count == channels else { return }
        let common = format.commonFormat
        guard [.pcmFormatFloat32, .pcmFormatFloat64, .pcmFormatInt16, .pcmFormatInt32].contains(common) else { return }
        scratch.withUnsafeMutableBufferPointer { samples in
            for frame in 0..<count {
                for channel in 0..<channels {
                    let index = frame * channels + channel
                    guard let memory = list[interleaved ? 0 : channel].mData else { samples[index] = 0; continue }
                    let offset = interleaved ? index : frame
                    switch common {
                    case .pcmFormatFloat32: samples[index] = memory.assumingMemoryBound(to: Float.self)[offset]
                    case .pcmFormatFloat64: samples[index] = Float(memory.assumingMemoryBound(to: Double.self)[offset])
                    case .pcmFormatInt16: samples[index] = Float(memory.assumingMemoryBound(to: Int16.self)[offset]) / 32768
                    case .pcmFormatInt32: samples[index] = Float(memory.assumingMemoryBound(to: Int32.self)[offset]) / 2147483648
                    default: break
                    }
                }
            }
            normalizer.process(samples, frames: count)
            processedFrames += count
            if lock.try() {
                savedStatistics = PlaybackAudioStatistics(frames: processedFrames, channels: channels, inputLUFS: normalizer.inputLUFS, gainDB: normalizer.gainDB)
                lock.unlock()
            }
            for frame in 0..<count {
                for channel in 0..<channels {
                    let index = frame * channels + channel
                    guard let memory = list[interleaved ? 0 : channel].mData else { continue }
                    let offset = interleaved ? index : frame, value = samples[index]
                    switch common {
                    case .pcmFormatFloat32: memory.assumingMemoryBound(to: Float.self)[offset] = value
                    case .pcmFormatFloat64: memory.assumingMemoryBound(to: Double.self)[offset] = Double(value)
                    case .pcmFormatInt16: memory.assumingMemoryBound(to: Int16.self)[offset] = Int16(value * 32768)
                    case .pcmFormatInt32: memory.assumingMemoryBound(to: Int32.self)[offset] = Int32(value * 2147483648)
                    default: break
                    }
                }
            }
        }
    }

    private func copyForCaptions(_ source: UnsafeMutablePointer<AudioBufferList>, frames: AVAudioFrameCount, time: CMTime) {
        guard lock.try() else { return }
        guard captionsEnabled, let buffer = pool.popLast() else { lock.unlock(); return }
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
            guard let target, let converter, let receive else { return }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32)
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false, error: NSError?
            let result = converter.convert(to: converted, error: &error) { _, status in
                guard !supplied else { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            if result != .error, error == nil, converted.frameLength > 0 { receive(converted, time) }
        }
    }
    private func recycle(_ buffer: AVAudioPCMBuffer) { lock.lock(); pool.append(buffer); lock.unlock() }
}
