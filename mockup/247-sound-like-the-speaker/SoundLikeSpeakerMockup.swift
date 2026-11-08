import SwiftUI
import CaptionCore

/// Debug scene: inert "Sound like the speaker" toggle under "Speak it in my ear",
/// reusing EarSettingsRows' pill pattern, for pipeline screenshot of #247 (#254).
/// Not wired live yet; setting is persisted but not applied by EarCenter until a mock-up
/// is approved by Gil.
@available(iOS 18, *)
struct SoundLikeSpeakerMockup: View {
    @State private var soundsLikeSpeaker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Speak it in my ear")
                .font(.headline)

            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "speaker.wave.2")
                        .foregroundColor(.accentColor)
                    Text("Speaker on")
                    Spacer()
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                HStack {
                    Image(systemName: "headphones")
                        .foregroundColor(.accentColor)
                    Text("Headphones connected")
                    Spacer()
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                Divider()
                    .padding(.vertical, 4)

                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound like the speaker")
                            .font(.body)
                        Text("Match pitch and pace to each person")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $soundsLikeSpeaker)
                        .labelsHidden()
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            Text("Spanish only at launch; more languages coming soon.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)

            Spacer()
        }
        .padding()
        .navigationTitle("Live Translation Settings")
    }
}

#Preview {
    NavigationStack {
        SoundLikeSpeakerMockup()
    }
}
