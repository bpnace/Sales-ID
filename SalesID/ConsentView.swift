import SwiftUI

struct ConsentView: View {
    @ObservedObject var consent = ConsentManager.shared
    @State private var scopeAll: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringKey("consent_title")).font(.headline).foregroundColor(.black)
                Text(LocalizedStringKey("consent_body"))
                    .font(.subheadline)
                    .foregroundColor(.black)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(LocalizedStringKey("consent_scope_all"), isOn: $scopeAll)
                    .toggleStyle(.switch)
                HStack(spacing: 8) {
                    Button(LocalizedStringKey("consent_accept")) {
                        consent.accept(scopeAll: scopeAll)
                    }
                    .keyboardShortcut(.defaultAction)
                    Button(LocalizedStringKey("consent_decline")) {
                        consent.decline()
                    }
                }
            }
            .padding(16)
        }
        .frame(minWidth: 360)
        .fixedSize(horizontal: false, vertical: true)
    }
}


