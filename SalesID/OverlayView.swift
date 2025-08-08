import SwiftUI

struct OverlayView: View {
    @StateObject var ipc = IPC.shared

    var body: some View {
        ZStack {
            // Reliable frosted background
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
            // Additional vibrancy for depth
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey("overlay_title"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black)
                ForEach(ipc.suggestionBullets, id: \.self) { bullet in
                    HStack(spacing: 4) {
                        Circle().fill(Color.black).frame(width: 3, height: 3)
                        Text(bullet)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .lineLimit(2)
                            .foregroundColor(.black)
                    }
                }
                if ipc.suggestionBullets.isEmpty {
                    Text(LocalizedStringKey("ai_active"))
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .padding(6)
        }
        .padding(4)
    }
}


