import SwiftUI

struct RootView: View {
    @ObservedObject var consent = ConsentManager.shared

    var body: some View {
        Group {
            if !consent.shouldShowConsent {
                OverlayView()
                    .frame(width: 220, height: 84)
            } else {
                ConsentView()
                    .frame(width: 320)
            }
        }
        .background(Color.clear)
    }
}


