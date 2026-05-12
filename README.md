# SalesID for macOS

[![CI](https://github.com/bpnace/Sales-ID/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/bpnace/Sales-ID/actions/workflows/ci.yml)
![Version](https://img.shields.io/badge/version-case_study-2563EB?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple&logoColor=white)
![Xcode](https://img.shields.io/badge/Xcode-16-147EFB?style=flat-square&logo=xcode&logoColor=white)
![Status](https://img.shields.io/badge/status-AI_sales_copilot_case-1F2937?style=flat-square)
![Privacy](https://img.shields.io/badge/privacy-consent_first-2ea043?style=flat-square)
![Local Services](https://img.shields.io/badge/local_services-STT_RAG_LLM-0ea5e9?style=flat-square)

SalesID is an AI sales copilot case for macOS. It explores how a consent-first
desktop overlay can assist live calls by combining screen context, OCR, speech
transcription, local retrieval, and short German response suggestions.

## What this shows

- Native macOS overlay UX for real-time sales assistance
- Consent-gated capture flow before screen or microphone access starts
- ScreenCaptureKit plus Vision OCR for contextual screen understanding
- Local service boundaries for STT, RAG, and LLM routing
- Compact German suggestion UI designed for live-call pressure

## Status
- Overlay UI implemented with frosted background, compact default size (220x84), and German localization
- Consent dialog shown on first launch; capture starts only after acceptance
- Screen capture (ScreenCaptureKit) wired to OCR (Vision) with throttling
- IPC to local services: RAG and LLM router (HTTP); STT pipeline scaffolded (WebSocket)
- Configured entitlements and microphone usage description
- Debug build is green in Xcode 16 on macOS 15

## Quick start
1) Start local services (in separate terminals):
```bash
cd services/stt && uvicorn server:app --host 127.0.0.1 --port 8765
cd services/rag && uvicorn server:app --host 127.0.0.1 --port 8770
cd services/llm && uvicorn server:app --host 127.0.0.1 --port 8780
```
2) Build and run the macOS app (Debug):
```bash
xcodebuild -scheme SalesID -configuration Debug build
```

Toggle overlay visibility with Cmd+Option+Space.

## Project structure
- `SalesID/` macOS app
  - `SalesIDApp.swift`, `RootView.swift`, `OverlayView.swift` (UI)
  - `ScreenCapture.swift` (ScreenCaptureKit)
  - `OCR.swift` (Vision)
  - `AudioEngine.swift` (mic capture, WebSocket streaming scaffold)
  - `IPC.swift` (HTTP calls to RAG and LLM)
  - `ConsentManager.swift`, `ConsentView.swift` (consent gating)
  - `Resources/de.lproj/Localizable.strings` (German localization)
  - `SalesID.entitlements`, `Info.plist`
- `services/` (see build_instructions.md for reference services; not yet committed here)

## Configuration
Create `.env` at repo root for service settings (see `build_instructions.md` for suggested values). Fixed localhost ports:
- STT: 8765 (WebSocket ws://127.0.0.1:8765/ws)
- RAG: 8770 (HTTP)
- LLM: 8780 (HTTP)

## Roadmap
- Implement consent event persistence in Supabase (non-sensitive ops data)
- Finish STT service integration and switch to `metal` device when available
- RAG ingest UI and export/delete operations
- Performance profiling to p95 ≤ 700 ms end-to-end

## License
Proprietary. All rights reserved.
