import CaptionCore
import SwiftUI

extension RGBA {
    var color: Color { Color(red: r, green: g, blue: b, opacity: a) }
}

extension CaptionStyle {
    /// The caption font at this look's size step. Bundled fonts (OpenDyslexic, Atkinson Hyperlegible) use a fixed size
    /// because the size already tracks Dynamic Type through `category`; scaling them again would double it.
    func font(for category: SystemTextSizeCategory, device: CaptionDeviceClass = .phone, scaled: Double = 1) -> Font {
        let points = size.pointSize(for: category, device: device) * scaled
        if let name = font.postScriptName(bold: false, italic: false) {
            return .custom(name, fixedSize: points)
        }
        let design: Font.Design = switch font {
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        case .system, .openDyslexic, .atkinsonHyperlegible: .default
        }
        return .system(size: points, weight: .regular, design: design)
    }
}

extension CaptionFont {
    /// This lettering at a fixed size, for showing each choice in its own letters (Settings).
    func sample(size: CGFloat) -> Font {
        if let name = postScriptName(bold: false, italic: false) { return .custom(name, fixedSize: size) }
        let design: Font.Design = switch self {
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        case .system, .openDyslexic, .atkinsonHyperlegible: .default
        }
        return .system(size: size, weight: .regular, design: design)
    }
}
