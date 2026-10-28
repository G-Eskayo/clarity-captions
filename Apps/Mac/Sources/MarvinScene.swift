import AppKit
import CaptionCore
import SwiftUI

/// Screenshots of the real pop-up's pages (#172 parity), through the screenshot contract: launched with
/// `-MarvinScene <scene> -MarvinScreenshot <png> -MarvinAppearance light|dark`, the app opens on that page with a demo
/// conversation, snapshots its own window and quits. Captioning never starts, the look isn't saved, and saved
/// conversations go to a throwaway folder. Scenes: veil, newquestion, settings, saved, conversation, credits.
@MainActor
enum MarvinScene {
    static var scene: String? { UserDefaults.standard.string(forKey: "MarvinScene") }
    static var isOn: Bool { scene != nil }
    static let storeDirectory: URL? = isOn
        ? FileManager.default.temporaryDirectory.appendingPathComponent("marvin-scene-\(ProcessInfo.processInfo.processIdentifier)")
        : nil

    static func run(_ model: CaptionMacModel) {
        guard let scene, let path = UserDefaults.standard.string(forKey: "MarvinScreenshot") else { return }
        let dark = UserDefaults.standard.string(forKey: "MarvinAppearance") == "dark"
        let preset = CaptionPreset.all.first { $0.id == (dark ? "harbor" : "paper") }!
        model.style.background = preset.background
        model.style.text = preset.text
        let demo: [(Int, String)] = [
            (0, "Hi! Can you read me okay on the computer?"),
            (1, "We're all here, the kids want to say hello."),
            (0, "Sunday still works for dinner."),
        ]
        for (speaker, text) in demo {
            model.stream.apply(text: text, isFinal: true, speaker: speaker, range: nil, wordEmphasis: [])
        }
        Task {
            if ["saved", "conversation"].contains(scene) {
                model.save()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            switch scene {
            case "newquestion": model.requestNew()
            case "settings": model.go { $0.openSettings() }
            case "saved": model.go { $0.openSavedFromCaptions() }
            case "conversation":
                model.go { $0.openSavedFromCaptions() }
                if let id = try? await model.store?.all().first?.id { model.go { $0.open(.savedConversation(id)) } }
            case "credits": model.go { $0.openSettings(); $0.open(.credits) }
            default: break
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if let view = NSApp.windows.first(where: { $0.title == CaptionMacApp.windowTitle })?.contentView {
                try? MarvinScreenshot.write(view, to: URL(fileURLWithPath: path))
            }
            if let dir = storeDirectory { try? FileManager.default.removeItem(at: dir) }
            exit(0)
        }
    }
}
