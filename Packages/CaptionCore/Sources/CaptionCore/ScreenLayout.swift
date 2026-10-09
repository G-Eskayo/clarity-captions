import Foundation

public enum WidthClass: Sendable { case compact, regular }
public enum HeightClass: Sendable { case compact, regular }

/// Which of the two existing main-screen layouts to use. Phone landscape is detected by height
/// (reliable across Plus/Max, where width stays compact); iPad full width is detected by width,
/// since iPad height never goes compact outside genuinely narrow multitasking.
public enum ScreenLayout: Equatable, Sendable {
    case stacked   // portrait layout: vertically stacked UI
    case wide      // landscape layout: thin top bar + corner control

    /// Select layout based on size classes. Wide layout is used when either height is compact
    /// (phone landscape) OR width is regular (iPad at any orientation).
    public static func `for`(width: WidthClass, height: HeightClass) -> ScreenLayout {
        (height == .compact || width == .regular) ? .wide : .stacked
    }
}
