import AVFoundation

final class AudioEngine {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private var wsTask: URLSessionWebSocketTask?

    func startStreaming(to url: URL) throws {
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()
        wsTask = task
        receiveLoop()

        let input = engine.inputNode
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        let converter = AVAudioConverter(from: input.outputFormat(forBus: 0), to: targetFormat)!
        let bufferSize: AVAudioFrameCount = 1024

        input.installTap(onBus: 0, bufferSize: bufferSize, format: input.outputFormat(forBus: 0)) { buf, _ in
            guard let wsTask = self.wsTask else { return }
            let pcm = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(targetFormat.sampleRate))!
            var error: NSError?
            converter.convert(to: pcm, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buf
            }
            if let data = pcm.int16Data() {
                wsTask.send(.data(data)) { _ in }
            }
        }

        engine.prepare()
        try engine.start()
    }

    private func receiveLoop() {
        wsTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case let .string(text) = message {
                    DispatchQueue.main.async {
                        IPC.shared.updateTranscript(text)
                    }
                }
            case .failure:
                break
            }
            self.receiveLoop()
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        wsTask?.cancel(with: .goingAway, reason: nil)
    }
}

private extension AVAudioPCMBuffer {
    func int16Data() -> Data? {
        guard let channel = int16ChannelData else { return nil }
        let frames = Int(frameLength)
        return Data(bytes: channel[0], count: frames * 2)
    }
}


