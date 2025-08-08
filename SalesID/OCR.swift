import Foundation
import Vision

final class OCR {
    static let shared = OCR()

    private let request: VNRecognizeTextRequest = {
        let r = VNRecognizeTextRequest()
        r.recognitionLanguages = ["de-DE", "en-US"]
        r.usesLanguageCorrection = true
        r.minimumTextHeight = 0.02
        return r
    }()

    func extractText(from cgImage: CGImage, completion: @escaping (String) -> Void) {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([self.request])
                let texts = self.request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
                let joined = texts.joined(separator: " ")
                completion(joined)
            } catch {
                completion("")
            }
        }
    }
}


