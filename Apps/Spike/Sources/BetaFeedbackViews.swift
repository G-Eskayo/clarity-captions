import CaptionCore
import MessageUI
import SwiftUI
import UIKit

/// Colors for the beta screens (mock-ups in docs/design/mocks/beta-feedback/), derived from the chosen look so every
/// theme gets them.
private struct BetaPalette {
    let style: CaptionStyle
    var dark: Bool { style.background.isDark }
    /// The card: white on light looks; the look's background lifted a little on dark ones.
    var card: RGBA { dark ? mix(style.background, RGBA(1, 1, 1), 0.06) : RGBA(1, 1, 1) }
    /// Unselected 1–10 pills and the note box.
    var soft: RGBA { dark ? mix(style.background, RGBA(1, 1, 1), 0.12) : RGBA(hex: "#EFE8DC") }
    var muted: Color { (dark ? RGBA(hex: "#B9B3A6") : RGBA(hex: "#56625F")).color }
    var badge: Color { (dark ? RGBA(hex: "#1F6F6B") : RGBA(hex: "#4FB3A9")).color }

    private func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
        RGBA(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }
}

/// Mock-up 01/02: "How well could you follow the conversation?" One tap on a number rates and the card fades; Add a
/// note opens a box in the same card and Done saves both. Skip records a skip.
struct RatingCardView: View {
    let style: CaptionStyle
    let onRate: (Int, String?) -> Void
    let onSkip: () -> Void
    /// Debug demos only: open with a number chosen and the note box showing (mock-up 02).
    var demoSelected: Int? = nil
    var demoNote: String? = nil
    /// Debug demos only: a scripted tap on a number, through the same path a finger takes.
    var demoTap: Int? = nil

    @State private var selected: Int?
    @State private var demoPressed: Int?
    @State private var noting = false
    @State private var note = ""
    @FocusState private var noteFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: BetaPalette { BetaPalette(style: style) }

    var body: some View {
        VStack(spacing: 14) {
            Text("How well could you follow the conversation?")
                .font(.title3.weight(.heavy))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            numbers
            HStack {
                Text("Not at all")
                Spacer()
                Text("Every word")
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(palette.muted)
            .accessibilityHidden(true)
            if noting { noteBox } else { links }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .foregroundStyle(style.text.color)
        .background(palette.card.color, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(palette.dark ? 0 : 0.12), radius: 18, y: 6)
        .padding(.horizontal, 20)
        .onAppear {
            if let demoSelected { selected = demoSelected }
            if let demoNote { note = demoNote; noting = true }
        }
        .onChange(of: demoTap) { _, n in
            guard let n else { return }
            Task {
                demoPressed = n                                   // the squish a finger would make
                try? await Task.sleep(for: .milliseconds(160))
                demoPressed = nil
                tapped(n)
            }
        }
    }

    private func tapped(_ n: Int) {
        selected = n
        guard !noting else { return }
        // One tap: the pill squishes, then the card goes.
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 260))
            onRate(n, nil)
        }
    }

    private var numbers: some View {
        HStack(spacing: 4) {
            ForEach(1...10, id: \.self) { n in
                let isSelected = selected == n
                Button { tapped(n) } label: {
                    Text(verbatim: "\(n)")
                        .font(.system(size: 17, weight: .heavy))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(isSelected ? GummyButtonStyle(style: style, forcePressed: demoPressed == n)
                                        : GummyButtonStyle(fill: palette.soft, label: style.text))
                .accessibilityLabel(Text(verbatim: "\(n)"))
                .accessibilityValue(n == 1 ? Text("Not at all") : n == 10 ? Text("Every word") : Text(verbatim: ""))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var links: some View {
        HStack {
            Button("Add a note") {
                withAnimation(.easeInOut(duration: 0.2)) { noting = true }
                noteFocused = true
            }
            .foregroundStyle(style.gear.color)
            Spacer()
            Button("Skip") { onSkip() }
                .foregroundStyle(palette.muted)
        }
        .font(.body.weight(.bold))
        .buttonStyle(.plain)
    }

    private var noteBox: some View {
        VStack(alignment: .trailing, spacing: 14) {
            TextField("Add a note", text: $note, axis: .vertical)
                .lineLimit(3...5)
                .focused($noteFocused)
                .padding(14)
                .background(palette.soft.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel(Text("Your note"))
            Button { if let selected { onRate(selected, note) } } label: {
                Text("Done").font(.body.weight(.heavy)).padding(.horizontal, 26).frame(minHeight: 48)
            }
            .buttonStyle(GummyButtonStyle(style: style))
            .disabled(selected == nil)
            .accessibilityHint(selected == nil ? Text("Choose a number first") : Text(verbatim: ""))
        }
    }
}

/// Mock-up 06: shown once, after the launch animation, on the first launch of a TestFlight build.
struct BetaNoticeView: View {
    let style: CaptionStyle
    let onDismiss: () -> Void
    private var palette: BetaPalette { BetaPalette(style: style) }

    var body: some View {
        VStack(spacing: 14) {
            Text("Test version")
                .font(.footnote.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(palette.badge, in: Capsule())
            Text("Thanks for testing Seal")
                .font(.title2.weight(.heavy))
                .multilineTextAlignment(.center)
            Text("After a conversation, Seal asks how it went. It also keeps measurements like caption lag and battery.")
                .multilineTextAlignment(.center)
            Text("It never keeps what anyone said.")
                .font(.body.weight(.heavy))
                .multilineTextAlignment(.center)
            Text("You choose when to send them to Gil, from Settings.")
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
            Button(action: onDismiss) {
                Text("Got it").font(.title3.weight(.heavy)).frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(GummyButtonStyle(style: style))
            .padding(.top, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(22)
        .foregroundStyle(style.text.color)
        .background(palette.card.color, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(palette.dark ? 0 : 0.12), radius: 18, y: 6)
        .padding(.horizontal, 22)
        .accessibilityElement(children: .contain)
    }
}

/// Mock-up 04/05: exactly what will be sent, in words; then Apple's Messages, addressed to Gil, with the file
/// attached. Without Messages (or without a recipient in the build), the share sheet. Nothing leaves the phone unless
/// the tester sends it.
struct FeedbackSendView: View {
    let style: CaptionStyle
    let idleStop: IdleStopSetting
    @ObservedObject var beta: BetaFeedbackCenter
    @Environment(\.dismiss) private var dismiss
    @State private var prepared: Prepared?
    @State private var composing = false
    @State private var sharing = false
    /// Debug demos only: continue to Messages by itself, for the screen recording.
    var demoAutoContinue = false

    struct Prepared {
        let report: FeedbackReport
        let ids: Set<UUID>
        let data: Data
        let fileName: String
        let fileURL: URL
    }

    private var palette: BetaPalette { BetaPalette(style: style) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("What will be sent").font(.headline.weight(.heavy))
                HStack {
                    Button("Cancel") { dismiss() }.foregroundStyle(style.gear.color).font(.body.weight(.bold))
                    Spacer()
                }
            }
            .padding(.top, 22).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let prepared {
                        Text(String(format: String(localized: "%lld conversations since your last report. Seal never sends what anyone said, any audio, or names."), prepared.report.conversations.count))
                            .foregroundStyle(palette.muted)
                        ForEach(FeedbackPreview.cards(for: prepared.report)) { card in cardView(card) }
                        Text(verbatim: "\(prepared.report.device.model) · \(prepared.report.device.os) · Seal \(prepared.report.app.version) (\(prepared.report.app.build))")
                            .font(.footnote)
                            .foregroundStyle(palette.muted)
                    }
                }
                .padding(.bottom, 12)
            }
            Button(action: continueToMessages) {
                Text("Continue to Messages").font(.title3.weight(.heavy)).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(GummyButtonStyle(style: style))
            .disabled(prepared == nil || prepared?.report.conversations.isEmpty == true)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .foregroundStyle(style.text.color)
        .background(palette.card.color.ignoresSafeArea())
        .preferredColorScheme(style.background.isDark ? .dark : .light)
        .task {
            await beta.ensureResolved()
            prepare()
            if demoAutoContinue {
                try? await Task.sleep(for: .seconds(2.5))
                continueToMessages()
            }
        }
        .sheet(isPresented: $composing) {
            if let prepared, let to = beta.recipient {
                MessageComposeView(recipient: to, body: prepared.report.summary, data: prepared.data, fileName: prepared.fileName) { sent in
                    composing = false
                    if sent { beta.markSent(prepared.ids); dismiss() }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $sharing) {
            if let prepared {
                ShareSheet(items: [prepared.fileURL, prepared.report.summary]) { completed in
                    sharing = false
                    if completed { beta.markSent(prepared.ids); dismiss() }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func cardView(_ card: FeedbackPreviewCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title).font(.headline.weight(.heavy))
            ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label).foregroundStyle(palette.muted)
                    Spacer(minLength: 8)
                    Text(row.value).fontWeight(.bold).multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .background(palette.soft.color, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func prepare() {
        let made = beta.makeReport(style: style, idleStop: idleStop)
        guard let data = try? made.report.json() else { return }
        let name = FeedbackReport.fileName(build: made.report.app.build, date: made.report.sentAt)
        let tmp = FileManager.default.temporaryDirectory
        // Only the file being sent exists: earlier previews' copies go.
        for old in (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix("seal-feedback-") { try? FileManager.default.removeItem(at: old) }
        let url = tmp.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        prepared = Prepared(report: made.report, ids: made.ids, data: data, fileName: name, fileURL: url)
    }

    private func continueToMessages() {
        guard prepared != nil else { return }
        if MFMessageComposeViewController.canSendText(), MFMessageComposeViewController.canSendAttachments(), beta.recipient != nil {
            composing = true
        } else {
            sharing = true
        }
    }
}

/// Apple's Messages compose sheet, addressed to Gil, with the report attached. `onFinish(true)` only when Messages
/// says it was sent.
struct MessageComposeView: UIViewControllerRepresentable {
    let recipient: String
    let body: String
    let data: Data
    let fileName: String
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = context.coordinator
        vc.recipients = [recipient]
        vc.body = body
        vc.addAttachmentData(data, typeIdentifier: "public.json", filename: fileName)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish(result == .sent)
        }
    }
}

/// The share sheet, when Messages can't send (an iPad without Messages, the simulator) or no recipient was built in.
/// `onFinish(true)` when the tester completed a share.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
