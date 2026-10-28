import CaptionCore
import SwiftUI

/// The Listening light (#180): an 8 pt red dot, brighter while people talk and softer when it's quiet, changing in
/// colour only, never in size. Reduce Motion: steady red.
public struct ListeningLightView: View {
    let background: RGBA
    let roomLevelDBFS: Double?
    let size: CGFloat
    /// DEBUG demos only: draw as if Reduce Motion were on.
    let forceReduceMotion: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(background: RGBA, roomLevelDBFS: Double?, size: CGFloat = 8, forceReduceMotion: Bool = false) {
        self.background = background
        self.roomLevelDBFS = roomLevelDBFS
        self.size = size
        self.forceReduceMotion = forceReduceMotion
    }

    public var body: some View {
        let still = reduceMotion || forceReduceMotion
        let c = ListeningLight.color(on: background, roomLevelDBFS: roomLevelDBFS, reduceMotion: still)
        Circle()
            .fill(Color(red: c.r, green: c.g, blue: c.b, opacity: c.a))
            .frame(width: size, height: size)
            // The room level arrives in steps; easing between them is what makes it breathe instead of flicker.
            .animation(still ? nil : .easeInOut(duration: 0.6), value: c)
            .accessibilityHidden(true)
    }
}
