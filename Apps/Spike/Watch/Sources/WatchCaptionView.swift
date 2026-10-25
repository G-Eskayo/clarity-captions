import SwiftUI

struct WatchCaptionView: View {
    @StateObject private var receiver = CaptionReceiver()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !receiver.speakerLabel.isEmpty {
                    Text(receiver.speakerLabel)
                        .font(.caption2)
                        .lineLimit(1)
                        .opacity(0.7)
                        .padding(.bottom, 4)
                }
                Text(receiver.line)
                    .font(.title3)
                    .lineLimit(10)
                    .minimumScaleFactor(0.8)
            }
            .padding()
        }
    }
}
