import AppKit
import CaptionCore
import CoreText
import SwiftUI

/// The MARVIN Mac screenshot contract (marvin #727): launched with `-MarvinScreenshot <png>` (and optionally
/// `-MarvinAppearance light|dark`) plus a scene's own arguments, the app draws that scene off-screen, writes the PNG
/// at 2x and quits. Needs no Screen Recording permission. Scenes:
///   `-SealPopupMockup auto|switch|waiting`  the #172 pop-up mock-up (Paper when light, Harbor when dark)
enum MarvinScreenshot {
    static func runIfRequested() {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "MarvinScreenshot") else { return }
        let dark = defaults.string(forKey: "MarvinAppearance") == "dark"
        var style = CaptionStyle.standard
        let preset = CaptionPreset.all.first { $0.id == (dark ? "harbor" : "paper") }!
        style.background = preset.background
        style.text = preset.text

        let variant = CallPopupMockup.Variant(rawValue: defaults.string(forKey: "SealPopupMockup") ?? "auto") ?? .auto
        let view = CallPopupMockup(variant: variant, style: style)
            .padding(24)
            .background(Color(white: dark ? 0.16 : 0.86))   // a plain desktop behind, so the rounded corners show

        do {
            try render(view, to: URL(fileURLWithPath: path), dark: dark)
            exit(0)
        } catch {
            FileHandle.standardError.write("screenshot failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    private static func render<V: View>(_ view: V, to url: URL, dark: Bool) throws {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let scale: CGFloat = 2
        let size = host.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw CocoaError(.fileWriteUnknown)
        }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}

/// The lettering fonts the iPhone app bundles (OpenDyslexic is the default look), registered for this process.
enum BundledFonts {
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where ["otf", "ttf"].contains(url.pathExtension) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
