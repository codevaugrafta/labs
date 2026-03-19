import AVFoundation

/// Wraps AVAudioEngine + AVAudioPlayerNode to play streaming PCM-16 audio in real time.
///
/// Usage per utterance:
///   1. `prepareToPlay()` — set up the engine.
///   2. `scheduleBuffer(_:)` — call for each PCM chunk as it arrives.
///   3. `waitForCompletion()` — await until the last sample plays out.
///   4. `stop()` — called automatically by `prepareToPlay` on the next utterance,
///      or manually to halt mid-stream.
///
/// The class is `@MainActor` so all mutable state is accessed on one thread, and
/// the `scheduleBuffer` completion handlers hop back to the main actor explicitly.
@MainActor
class AudioStreamer {
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    private let sampleRate: Double = 16_000
    private let channels: AVAudioChannelCount = 1

    private var format: AVAudioFormat?

    private var scheduledBufferCount = 0
    private var completedBufferCount = 0
    private var streamingFinished = false
    private var completionContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Public API

    /// Tears down any prior session and creates a fresh engine ready for `scheduleBuffer` calls.
    func prepareToPlay() {
        stop()

        let newEngine = AVAudioEngine()
        let newPlayer = AVAudioPlayerNode()

        guard let newFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        ) else {
            print("AudioStreamer: Failed to create AVAudioFormat")
            return
        }

        newEngine.attach(newPlayer)
        newEngine.connect(newPlayer, to: newEngine.mainMixerNode, format: newFormat)

        do {
            try newEngine.start()
            newPlayer.play()
        } catch {
            print("AudioStreamer: Failed to start engine: \(error)")
            return
        }

        engine = newEngine
        playerNode = newPlayer
        format = newFormat

        scheduledBufferCount = 0
        completedBufferCount = 0
        streamingFinished = false
        completionContinuation = nil
    }

    /// Enqueues a chunk of raw PCM-16 LE mono 16 kHz bytes for immediate playback.
    func scheduleBuffer(_ data: Data) {
        guard let format, let player = playerNode, !data.isEmpty else { return }

        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount

        data.withUnsafeBytes { rawPtr in
            guard let src = rawPtr.baseAddress,
                  let dst = buffer.int16ChannelData?[0] else { return }
            memcpy(dst, src, data.count)
        }

        scheduledBufferCount += 1

        // The completion handler fires on an arbitrary AVAudioEngine thread.
        // Hop back to MainActor to update the isolated state safely.
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.completedBufferCount += 1
                self.checkCompletion()
            }
        }
    }

    /// Signals that no more buffers will be scheduled and suspends the caller until
    /// the engine has finished rendering the last queued sample.
    func waitForCompletion() async {
        streamingFinished = true

        if completedBufferCount >= scheduledBufferCount {
            return
        }

        await withCheckedContinuation { continuation in
            self.completionContinuation = continuation
        }
    }

    /// Immediately halts playback and tears down the audio engine.
    func stop() {
        completionContinuation?.resume()
        completionContinuation = nil

        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
        format = nil
    }

    // MARK: - Private

    private func checkCompletion() {
        guard streamingFinished,
              completedBufferCount >= scheduledBufferCount,
              let continuation = completionContinuation else {
            return
        }
        completionContinuation = nil
        continuation.resume()
    }
}
