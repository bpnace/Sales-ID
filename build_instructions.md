# SalesID for macOS — full build guide, architecture, and operations

Everything in this guide is written in English. The app UI and all user facing text should be German. Follow the steps in order to ship a working local first macOS app that captures screen and audio, extracts text, enriches context with a local RAG, and renders ultra short German suggestions in a floating overlay.

---

## Contents

1. Product goals and constraints  
2. Architecture overview  
3. System requirements and tooling  
4. Repository layout  
5. Create the Xcode project  
6. Overlay UI in SwiftUI  
7. Screen capture with ScreenCaptureKit  
8. OCR with Apple Vision  
9. Audio capture for mic and system audio  
10. Realtime STT service with faster whisper  
11. Local RAG service with Chroma and sentence transformers  
12. LLM router with Ollama and optional cloud fallback  
13. App to backend IPC and message formats  
14. Prompt templates for German output  
15. Configuration and environment variables  
16. Packaging, signing, notarization, updates  
17. Performance targets and profiling  
18. GDPR and EU AI Act checklists for Germany  
19. Roadmap and milestones  
20. Troubleshooting

---

## 1. Product goals and constraints

Name: SalesID  
Purpose: invisible desktop copilot for live calls. Capture screen and audio, recognize text, add context from a local knowledge base, and show terse on screen prompts in German.

Hard constraints  
- End to end latency p95 less or equal 700 ms  
- Max 3 bullets per suggestion, each bullet less or equal 12 words  
- Local processing by default. Optional EU hosted endpoints only  
- No storage without explicit consent. Default to ephemeral buffers

---

## 2. Architecture overview

Layers  
1. Capture layer: ScreenCaptureKit for frames, AVAudioEngine for mic. Virtual device for system audio  
2. Processing layer: Vision OCR, faster whisper streaming STT  
3. Context layer: RAG over local Chroma vector store  
4. Reasoning layer: LLM router to Ollama Llama 3 for low latency. Optional GPT 4o for premium tier  
5. Presentation layer: SwiftUI transparent floating overlay with global hotkey  
6. Persistence layer: minimal SQLite or DuckDB and rolling logs with purge jobs

Data flow  
- App grabs a downscaled frame and an audio chunk  
- App runs OCR locally. Audio goes to STT service  
- App sends transcript tail plus OCR tail to LLM router with RAG hits  
- Router returns 3 German bullets. App overlays them on screen

---

## 3. System requirements and tooling

macOS 13 or newer  
Xcode 15 or newer  
Apple Silicon recommended

Install tooling
```bash
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install python@3.11 node ffmpeg sqlite chroma
brew install --cask blackhole-2ch
brew install ollama
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip wheel
pip install "faster-whisper==1.0.0" uvicorn fastapi numpy pillow sentence-transformers chromadb duckdb pydantic[dotenv] python-multipart pymupdf requests

Pull a fast local model for Ollama

ollama serve &
ollama pull llama3:8b


⸻

4. Repository layout

salesid/
├─ app/                     # macOS Swift code
│  ├─ SalesIDApp.swift
│  ├─ OverlayView.swift
│  ├─ ScreenCapture.swift
│  ├─ OCR.swift
│  ├─ AudioEngine.swift
│  ├─ IPC.swift
│  ├─ Models.swift
│  ├─ Resources/
│  │   └─ Localizable.strings (de)
│  └─ Info.plist
├─ services/
│  ├─ stt/                  # faster whisper realtime service
│  │  ├─ server.py
│  │  └─ requirements.txt
│  ├─ rag/
│  │  ├─ server.py
│  │  ├─ ingest.py
│  │  └─ data/
│  └─ llm/
│     └─ server.py
├─ scripts/
│  ├─ dev_up.sh
│  ├─ purge_data.sh
│  └─ notarize.sh
├─ .env
└─ README.md


⸻

5. Create the Xcode project
	1.	Open Xcode
	2.	File > New > Project > App
	3.	Platform macOS, Interface SwiftUI, Language Swift
	4.	Product name SalesID, Bundle Identifier com.yourdomain.salesid
	5.	Disable sandbox for Debug. Enable hardened runtime later for Release

Add capabilities later
	•	Microphone
	•	Screen Recording consent is handled by the system when you start ScreenCaptureKit

Localization
	•	Add German to the project
	•	Create Localizable.strings (German) in Resources
	•	All user visible text must live in localized strings

Resources/Localizable.strings (German)

"overlay_title" = "Live Vorschlag";
"ai_active" = "KI aktiv";

"consent_title" = "Einverständnis für Live-Mitschnitt";
"consent_body" = "Ich stimme zu, dass während dieses Gesprächs Bildschirm und Mikrofon lokal verarbeitet werden, um kurze Vorschläge zu erzeugen. Es erfolgt keine Speicherung ohne meine ausdrückliche Zustimmung.";
"consent_scope_call" = "Nur aktueller Anruf";
"consent_scope_all" = "Alle Anrufe";
"consent_accept" = "Zustimmen";
"consent_decline" = "Ablehnen";

"mic_permission_needed" = "Mikrofonzugriff benötigt. Bitte in Systemeinstellungen > Datenschutz & Sicherheit erlauben.";
"screen_permission_needed" = "Bildschirmaufnahme benötigt. Bitte in Systemeinstellungen > Datenschutz & Sicherheit erlauben und App neu starten.";

"privacy_title" = "Datenschutz";
"privacy_explain" = "Verarbeitung erfolgt lokal. Sensible Inhalte verbleiben auf diesem Gerät. In den Einstellungen können Sie Daten exportieren oder löschen.";
"export_button" = "Daten exportieren";
"delete_button" = "Daten löschen";

⸻

6. Overlay UI in SwiftUI

Create a small transparent always on top window with toggle hotkey.

SalesIDApp.swift

import SwiftUI

@main
struct SalesIDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            OverlayView()
                .frame(width: 420, height: 180)
                .background(Color.clear)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let w = NSApp.windows.first else { return }
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.ignoresMouseEvents = false
        if #available(macOS 13.0, *) {
            w.isMovableByWindowBackground = true
        }
        registerHotkey()
    }

    func registerHotkey() {
        // Simple global hotkey using event monitor. For production use HotKey library.
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.command, .option]) && event.keyCode == 49 {
                if let w = NSApp.windows.first { w.isVisible ? w.orderOut(nil) : w.makeKeyAndOrderFront(nil) }
            }
        }
    }
}

OverlayView.swift

import SwiftUI

struct OverlayView: View {
    @StateObject var ipc = IPC.shared
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(16)
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey("overlay_title")) // "Live Vorschlag"
                    .font(.headline)
                ForEach(ipc.suggestionBullets, id: \.self) { bullet in
                    HStack(spacing: 8) {
                        Circle().frame(width: 6, height: 6)
                        Text(bullet)
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .lineLimit(2)
                    }
                }
            }
            .padding(14)
        }
        .padding(8)
    }
}

VisualEffectView.swift helper

import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}


⸻

7. Screen capture with ScreenCaptureKit

ScreenCapture.swift

import Foundation
import ScreenCaptureKit
import CoreImage

final class ScreenCapture: NSObject {
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
        config.minimumFrameInterval = CMTime(value: 1, timescale: 3) // about 3 fps
        config.width = 640
        config.height = 360
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try stream?.startCapture()
    }

    func stop() {
        try? stream?.stopCapture()
        stream = nil
    }
}

extension ScreenCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen,
              let imgBuf = sampleBuffer.imageBuffer else { return }
        let ci = CIImage(cvImageBuffer: imgBuf)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        onDownscaledFrame?(cg)
    }
}

Call try await ScreenCapture.shared.start() at launch. The system will prompt the user to allow Screen Recording in Privacy settings. Give the user clear German text in the app to guide them.

⸻

8. OCR with Apple Vision

OCR.swift

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

Throttle OCR to once every 2 seconds to reduce CPU load.

⸻

9. Audio capture for mic and system audio

Mic capture with AVAudioEngine. System audio requires a virtual device such as BlackHole. In macOS Sound settings create a Multi Output device that routes to your speakers and BlackHole. Use Audio MIDI Setup to configure it.

AudioEngine.swift

import AVFoundation

final class AudioEngine {
    static let shared = AudioEngine()
    private let engine = AVAudioEngine()
    private var wsTask: URLSessionWebSocketTask?

    func startStreaming(to url: URL) throws {
        let session = URLSession(configuration: .default)
        wsTask = session.webSocketTask(with: url)
        wsTask?.resume()

        // Optional: receive loop to keep the socket alive
        receiveLoop()

        let input = engine.inputNode
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
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

For system audio capture select BlackHole as the input device in System Settings or create a separate AVAudioEngine using BlackHole as the input device UID. Mic-only capture does not interfere with meeting audio playback; it simply taps the microphone input.

⸻

10. Realtime STT service with faster-whisper (FastAPI WebSocket)

services/stt/server.py

from fastapi import FastAPI, WebSocket
from fastapi.responses import PlainTextResponse
import os
import numpy as np
from collections import deque
from faster_whisper import WhisperModel

app = FastAPI()

# Best-practice defaults for low latency on Apple Silicon
STT_MODEL = os.getenv("STT_MODEL", "small")
STT_DEVICE = os.getenv("STT_DEVICE", "cpu")  # set to 'metal' on Apple Silicon if supported
STT_COMPUTE = os.getenv("STT_COMPUTE", "default")  # try 'int8_float16' only if you know it's supported
LANG = os.getenv("STT_LANG", "de")

model = WhisperModel(STT_MODEL, device=STT_DEVICE, compute_type=STT_COMPUTE)

# Keep ~10s tail at 16kHz
SAMPLE_RATE = 16000
TAIL_SECONDS = 10
MAX_SAMPLES = SAMPLE_RATE * TAIL_SECONDS

@app.get("/health", response_class=PlainTextResponse)
def health():
    return "ok"

@app.websocket("/ws")
async def ws_recognize(ws: WebSocket):
    await ws.accept()
    buffer = deque(maxlen=MAX_SAMPLES)
    transcript_tail = ""
    try:
        while True:
            message = await ws.receive_bytes()
            # int16 PCM mono 16kHz
            audio = np.frombuffer(message, dtype=np.int16).astype(np.float32) / 32768.0
            buffer.extend(audio.tolist())

            # Transcribe only tail for speed
            tail = np.array(buffer, dtype=np.float32)
            segments, _ = model.transcribe(
                tail,
                beam_size=1,
                language=LANG,
                vad_filter=True,
                without_timestamps=True,
                temperature=0.0,
                vad_parameters=dict(min_silence_duration_ms=250),
            )
            transcript_tail = " ".join(seg.text for seg in segments)[-600:]
            await ws.send_text(transcript_tail)
    except Exception:
        await ws.close()

Run it

cd services/stt
uvicorn server:app --host 127.0.0.1 --port 8765

The app connects to ws://127.0.0.1:8765/ws and receives transcript tails.

⸻

11. Local RAG service with Chroma and sentence-transformers (persistent)

services/rag/server.py

import os
import uuid
from fastapi import FastAPI, UploadFile
from pydantic import BaseModel
from chromadb import PersistentClient
from sentence_transformers import SentenceTransformer
import fitz

app = FastAPI()

DB_PATH = os.path.expanduser(os.getenv("RAG_DB_PATH", "~/.salesid/chroma"))
EMBED_MODEL = os.getenv("RAG_EMBED_MODEL", "sentence-transformers/all-MiniLM-L6-v2")

os.makedirs(DB_PATH, exist_ok=True)
client = PersistentClient(path=DB_PATH)
collection = client.get_or_create_collection("salesid")
embedder = SentenceTransformer(EMBED_MODEL)

def pdf_to_text(path: str) -> str:
    doc = fitz.open(path)
    return "\n".join(page.get_text() for page in doc)

@app.post("/ingest")
async def ingest(file: UploadFile):
    path = f"/tmp/{uuid.uuid4()}_{file.filename}"
    with open(path, "wb") as f:
        f.write(await file.read())
    text = pdf_to_text(path) if path.lower().endswith(".pdf") else open(path, "r", encoding="utf-8").read()
    chunks = [text[i:i+1200] for i in range(0, len(text), 1100)]
    ids = [str(uuid.uuid4()) for _ in chunks]
    embs = embedder.encode(chunks, normalize_embeddings=True).tolist()
    collection.add(ids=ids, embeddings=embs, documents=chunks)
    return {"added": len(chunks)}

class Query(BaseModel):
    q: str
    k: int = 3

@app.post("/query")
def query(q: Query):
    emb = embedder.encode([q.q], normalize_embeddings=True).tolist()[0]
    res = collection.query(query_embeddings=[emb], n_results=q.k)
    docs = res["documents"][0]
    return {"hits": docs}

Run it

cd services/rag
uvicorn server:app --host 127.0.0.1 --port 8770


⸻

12. LLM router with provider selection (EU-first)

services/llm/server.py

from fastapi import FastAPI
from pydantic import BaseModel
import requests
import os

app = FastAPI()

LLM_PROVIDER = os.getenv("LLM_PROVIDER", "ollama")  # ollama | mistral | openai (EU-only: prefer mistral)

# Ollama (local, default)
OLLAMA_ENDPOINT = os.getenv("OLLAMA_ENDPOINT", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3:8b")

# Mistral (EU)
MISTRAL_API_KEY = os.getenv("MISTRAL_API_KEY")
MISTRAL_MODEL = os.getenv("MISTRAL_MODEL", "mistral-small-latest")

# OpenAI (avoid for EU-only unless via Azure EU)
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL", "https://api.openai.com")

LANG_OUTPUT = os.getenv("LANG_OUTPUT", "de")

class Payload(BaseModel):
    transcript_tail: str
    ocr_tail: str
    rag_hits: list[str]
    german: bool = True

def build_prompt(p: Payload) -> str:
    hits = "\n".join(p.rag_hits[:3])
    lang_prefix = "Antworte auf Deutsch." if LANG_OUTPUT.startswith("de") else "Antworte kurz."
    return f"""
Du bist SalesID. {lang_prefix} Ausgabe sind genau 3 Bullets, je kleiner als 12 Wörter. Keine Halbgeviertstriche oder Gedankenstriche.
Kontext:
Transcript: {p.transcript_tail}
Bildschirm: {p.ocr_tail}
Wissen: {hits}
Aufgabe: Erzeuge sofort nutzbare Sprechhilfe mit klarem nächsten Schritt.
Format:
- Bullet 1
- Bullet 2
- Bullet 3
"""

def parse_bullets(txt: str) -> list[str]:
    lines = [l.strip(" -") for l in txt.splitlines() if l.strip()]
    return [l for l in lines if len(l.split()) <= 12][:3]

@app.post("/suggest")
def suggest(p: Payload):
    prompt = build_prompt(p)
    try:
        if LLM_PROVIDER == "ollama":
            r = requests.post(
                f"{OLLAMA_ENDPOINT}/api/generate",
                json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": False},
                timeout=0.6,
            )
            txt = r.json().get("response", "")
            return {"bullets": parse_bullets(txt)}

        if LLM_PROVIDER == "mistral" and MISTRAL_API_KEY:
            r = requests.post(
                "https://api.mistral.ai/v1/chat/completions",
                headers={"Authorization": f"Bearer {MISTRAL_API_KEY}"},
                json={"model": MISTRAL_MODEL, "messages": [{"role": "user", "content": prompt}]},
                timeout=0.6,
            )
            txt = r.json()["choices"][0]["message"]["content"]
            return {"bullets": parse_bullets(txt)}

        if LLM_PROVIDER == "openai" and OPENAI_API_KEY:
            r = requests.post(
                f"{OPENAI_BASE_URL}/v1/chat/completions",
                headers={"Authorization": f"Bearer {OPENAI_API_KEY}"},
                json={"model": OPENAI_MODEL, "messages": [{"role": "user", "content": prompt}]},
                timeout=0.6,
            )
            txt = r.json()["choices"][0]["message"]["content"]
            return {"bullets": parse_bullets(txt)}

        # Default local fallback
        return {"bullets": ["Bitte Bedarf präzisieren", "Nutzen klar benennen", "Konkreten nächsten Schritt anbieten"]}
    except Exception:
        return {"bullets": ["Bitte Bedarf präzisieren", "Nutzen klar benennen", "Konkreten nächsten Schritt anbieten"]}

Run it

cd services/llm
uvicorn server:app --host 127.0.0.1 --port 8780


⸻

13. App to backend IPC and message formats

IPC.swift

import Foundation

final class IPC: ObservableObject {
    static let shared = IPC()
    @Published var suggestionBullets: [String] = []

    private var transcriptTail: String = ""
    private var ocrTail: String = ""

    func updateTranscript(_ t: String) {
        transcriptTail = String(t.suffix(600))
        requestSuggestion()
    }

    func updateOCR(_ t: String) {
        ocrTail = String(t.suffix(600))
    }

    private func requestSuggestion() {
        guard let url = URL(string: "http://127.0.0.1:8780/suggest") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = [
            "transcript_tail": transcriptTail,
            "ocr_tail": ocrTail,
            "rag_hits": queryRAG(q: transcriptTail)
        ] as [String : Any]
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
        let body = ["q": String(q.suffix(300)), "k": 3] as [String : Any]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        let sema = DispatchSemaphore(value: 0)
        var docs: [String] = []
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { sema.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hits = json["hits"] as? [String]
            else { return }
            docs = hits
        }.resume()
        _ = sema.wait(timeout: .now() + 0.25)
        return docs
    }
}

Wire it up
	•	From ScreenCapture call OCR.extractText and pass result to IPC.updateOCR
	•	AudioEngine streams mic PCM16 to ws://127.0.0.1:8765/ws and on incoming text calls IPC.updateTranscript

Note on mic-only capture
	•	Mic-only capture taps your microphone input and will not interfere with meeting audio output.

⸻

14. Prompt templates for German output

Suggestion prompt policy
	•	German output only
	•	Three bullets
	•	Each bullet max 12 words
	•	No en dashes or em dashes
	•	Always include a next step

Example template lives in services/llm/server.py as build_prompt. Keep it in one place so that changes propagate everywhere.

⸻

15. Configuration and environment variables

.env at repo root

OLLAMA_ENDPOINT=http://127.0.0.1:11434
OLLAMA_MODEL=llama3:8b
OPENAI_API_KEY=
RAG_EMBED_MODEL=sentence-transformers/all-MiniLM-L6-v2
LANG_OUTPUT=de
LLM_PROVIDER=ollama
MISTRAL_API_KEY=
MISTRAL_MODEL=mistral-small-latest
STT_MODEL=small
STT_DEVICE=metal
STT_COMPUTE=default
RAG_DB_PATH=~/.salesid/chroma
SUPABASE_URL=
SUPABASE_ANON_KEY=

App constants
	•	Backend URLs: 127.0.0.1 with fixed ports 8765, 8770, 8780
	•	Timeouts: 600 ms for LLM, 250 ms for RAG fetch
	•	OCR cadence: every 2 seconds
	•	Audio chunk: 500 ms with small overlap in STT service

⸻

16. Packaging, signing, notarization, distribution (Mac App Store)

Signing and hardened runtime
	•	In Xcode set Release to Hardened Runtime enabled
	•	Add entitlements if you use extra capabilities
	•	Set Team to your Apple Developer ID

Info.plist keys
	•	NSMicrophoneUsageDescription with a clear German reason
	•	Screen recording has no Info.plist key. The system requests user permission the first time

Notarization

xcodebuild -scheme SalesID -configuration Release -archivePath build/SalesID.xcarchive archive
xcodebuild -exportArchive -archivePath build/SalesID.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build
xcrun notarytool submit build/SalesID.app --apple-id "you@appleid.com" --team-id TEAMID --password "app-specific-password" --wait
xcrun stapler staple build/SalesID.app

Distribution
	•	Target Mac App Store (no Sparkle)
	•	Enable sandbox for Release with required entitlements (Microphone, Network)
	•	Use App Store Connect for distribution

⸻

17. Performance targets and profiling

Targets
	•	p95 latency less or equal 700 ms
	•	OCR CPU below 20 percent on M2 during capture
	•	STT backlog under 300 ms
	•	Memory under 400 MB for the app process

Profiling
	•	Instruments Time Profiler for Swift
	•	Log timestamps at capture, OCR done, STT receive, RAG done, LLM done, UI render
	•	Add a small debug HUD that shows the last latency components

Tuning
	•	Reduce OCR cadence if CPU is high
	•	Switch to smaller Ollama model if LLM latency is high
	•	Limit RAG to top 3 hits and 2 slices of 400 chars

⸻

18. GDPR and EU AI Act checklists for Germany

Consent
	•	Before any capture show a German consent dialog
	•	Store consent event with timestamp, meeting id, and scope (Supabase table); store any sensitive content locally only
	•	Stop capture if consent is withdrawn

Data minimization
	•	Only process what you need
	•	Keep raw audio buffers in memory and drop after STT
	•	Keep transcript tail only for the last 60 seconds unless the user saves notes

Local processing
	•	Default to local STT, OCR, and LLM
	•	If cloud is enabled, enforce EU region and inform the user

Transparency
	•	Overlay must show a small German label like “AI aktiv”
	•	In app settings explain what is processed and how to delete it

Rights
	•	Provide in app export and delete buttons
	•	Document a Data Processing Agreement template for commercial use

Persistence
	•	Supabase used for non-sensitive operational data (consent events, settings)
	•	Sensitive data (raw audio buffers, transcripts, OCR text, embeddings) remain on-device
	•	Provide purge job and manual purge UI

Supabase schema (SQL)

```sql
create table if not exists consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  meeting_id text not null,
  scope text not null check (scope in ('call','all')),
  accepted boolean not null,
  created_at timestamptz not null default now()
);

create table if not exists settings (
  user_id uuid primary key,
  llm_provider text not null default 'ollama',
  lang_output text not null default 'de',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

AI Act baseline
	•	Sales coaching is typically limited risk
	•	Provide a brief notice that an AI assistant is active
	•	Maintain a risk log and do a yearly review

⸻

19. Roadmap and milestones

Week 1
	•	Overlay UI, hotkey, screen capture, OCR throttle

Week 2
	•	Audio engine, STT service, transcript tail plumbing

Week 3
	•	LLM router with Ollama, suggestion loop, German prompts

Week 4
	•	RAG service, document ingest, source aware suggestions

Week 5
	•	Consent flow, privacy settings, purge and export

Week 6
	•	Packaging, signing, Sparkle updates, closed beta

⸻

20. Troubleshooting

No screen content appears
	•	Check System Settings Privacy and Security Screen Recording and allow SalesID
	•	Restart the app after toggling the permission

No audio reaches STT
	•	Ensure mic permission is granted
	•	If you also need system audio, configure BlackHole as input or a Multi Output device. Mic-only capture does not interfere with meeting audio.

High CPU from OCR
	•	Increase OCR interval to 3 or 4 seconds
	•	Limit recognition languages to de-DE only

Bullets are too long
	•	Enforce length check in the router and trim lines over 12 words

Latency over budget
	•	Switch Ollama model to a smaller one
	•	Reduce RAG hits from 3 to 2
	•	Disable language correction in Vision if needed

⸻

Quick start commands

Start services in three terminals

cd services/stt && uvicorn server:app --host 127.0.0.1 --port 8765

cd services/rag && uvicorn server:app --host 127.0.0.1 --port 8770

cd services/llm && uvicorn server:app --host 127.0.0.1 --port 8780

Run the app from Xcode
	•	Build and run SalesID in Debug
	•	Press Command plus Option plus Space to toggle the overlay
	•	Speak and watch suggestions appear in German
