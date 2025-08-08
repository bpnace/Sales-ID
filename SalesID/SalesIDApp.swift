//
//  SalesIDApp.swift
//  SalesID
//
//  Created by Tarik Marshall on 08.08.25.
//

import SwiftUI
import AppKit
import Combine

@main
struct SalesIDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
            .background(Color.clear)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var lastOCRAt: Date = .distantPast
    private var consentCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let window = NSApp.windows.first else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        if #available(macOS 13.0, *) {
            window.isMovableByWindowBackground = true
        }
        // Set initial compact size based on consent
        setInitialWindowSize(window)
        registerHotkey()

        // Wire capture -> OCR -> IPC (starts after consent)
        ScreenCapture.shared.onDownscaledFrame = { [weak self] cg in
            guard let self else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastOCRAt) < 2.0 { return }
            self.lastOCRAt = now
            OCR.shared.extractText(from: cg) { text in
                guard !text.isEmpty else { return }
                DispatchQueue.main.async {
                    IPC.shared.updateOCR(text)
                }
            }
        }

        if ConsentManager.shared.isAccepted {
            Task { try? await ScreenCapture.shared.start() }
        }

        // Observe consent to start/stop capture and resize window
        consentCancellable = ConsentManager.shared.$isAccepted
            .receive(on: DispatchQueue.main)
            .sink { accepted in
                if let w = NSApp.windows.first { self.resizeWindow(w, accepted: accepted) }
                if accepted {
                    Task { try? await ScreenCapture.shared.start() }
                } else {
                    ScreenCapture.shared.stop()
                }
            }
    }

    private func registerHotkey() {
        // Cmd + Option + Space toggles overlay visibility
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.command, .option]) && event.keyCode == 49 { // space
                if let w = NSApp.windows.first {
                    w.isVisible ? w.orderOut(nil) : w.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
    private func setInitialWindowSize(_ window: NSWindow) {
        let accepted = ConsentManager.shared.isAccepted
        resizeWindow(window, accepted: accepted)
    }

    private func resizeWindow(_ window: NSWindow, accepted: Bool) {
        // Consent view slightly wider; overlay is compact 220x84
        let size = accepted ? NSSize(width: 220, height: 84) : NSSize(width: 360, height: 220)
        window.setContentSize(size)
        window.center()
    }
}
