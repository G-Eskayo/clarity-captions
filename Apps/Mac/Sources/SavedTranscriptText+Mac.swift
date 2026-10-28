import CaptionCore
import SwiftUI

/// A saved conversation's words on the Mac (#172). Same lines and lettering as the iPhone's `SavedTranscriptText`, which
/// the shared Saved page calls; the iPhone's hold-and-drag selection is built on touch gestures, so on the Mac the
/// words use the Mac's own selection (drag, ⌘C, right-click Copy). A long click below the words brings the dim back.
struct SavedTranscriptText: View {
    let transcript: String
    let style: CaptionStyle
    var minHeight: CGFloat = 0
    var dimmed = false
    var onHoldEmptySpace: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SavedConversationExport.lines(from: transcript)) { line in
                Text(line.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5, perform: onHoldEmptySpace)
    }
}
