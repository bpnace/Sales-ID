import Foundation

final class IPC: ObservableObject {
    static let shared = IPC()

    @Published var suggestionBullets: [String] = []

    private var transcriptTail: String = ""
    private var ocrTail: String = ""

    func updateTranscript(_ text: String) {
        transcriptTail = String(text.suffix(600))
        requestSuggestion()
    }

    func updateOCR(_ text: String) {
        ocrTail = String(text.suffix(600))
    }

    private func requestSuggestion() {
        guard let url = URL(string: "http://127.0.0.1:8780/suggest") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "transcript_tail": transcriptTail,
            "ocr_tail": ocrTail,
            "rag_hits": queryRAG(q: transcriptTail)
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let bullets = json["bullets"] as? [String]
            else { return }
            DispatchQueue.main.async { self.suggestionBullets = bullets }
        }.resume()
    }

    private func queryRAG(q: String) -> [String] {
        guard let url = URL(string: "http://127.0.0.1:8770/query") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["q": String(q.suffix(300)), "k": 3]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        let semaphore = DispatchSemaphore(value: 0)
        var docs: [String] = []
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hits = json["hits"] as? [String]
            else { return }
            docs = hits
        }.resume()
        _ = semaphore.wait(timeout: .now() + 0.25)
        return docs
    }
}


