import Foundation
import ScreenCaptureKit
import CoreImage
import AVFoundation
import CoreMedia

final class ScreenCapture: NSObject, SCStreamDelegate {
    static let shared = ScreenCapture()

    private var stream: SCStream?
    private let ciContext = CIContext()

    var onDownscaledFrame: ((CGImage) -> Void)?

    func start() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { throw NSError(domain: "SalesID", code: 1) }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 3) // ~3 fps
        config.width = 640
        config.height = 360
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: SCStreamOutputType.screen, sampleHandlerQueue: DispatchQueue.main)
        try await stream.startCapture()
    }

    func stop() {
        guard let stream else { return }
        Task { [weak self] in
            try? await stream.stopCapture()
            self?.stream = nil
        }
    }
}

extension ScreenCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, let imgBuf = sampleBuffer.imageBuffer else { return }
        let ci = CIImage(cvImageBuffer: imgBuf)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        onDownscaledFrame?(cg)
    }
}


