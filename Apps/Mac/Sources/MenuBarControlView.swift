import SwiftUI
import CaptionCore

struct MenuBarControlView: View {
    @ObservedObject var model: CaptionMacModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(StatusWords.headline(for: model.state))
                .font(.headline)

            if let detail = StatusWords.detail(for: model.state) {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button(action: toggleCaptions) {
                Label(PrimaryControl.for(model.state).title, systemImage: MenuBarPresentation.symbolName(for: model.state))
            }
            .disabled(!PrimaryControl.for(model.state).isEnabled)

            Divider()

            Button("Settings") {
                if let window = NSApplication.shared.windows.first(where: { $0.title == "Captions" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(minWidth: 200)
    }

    private func toggleCaptions() {
        switch model.state {
        case .idle, .failed:
            model.start()
        case .listening:
            model.stop()
        case .preparing:
            break
        }
    }
}
