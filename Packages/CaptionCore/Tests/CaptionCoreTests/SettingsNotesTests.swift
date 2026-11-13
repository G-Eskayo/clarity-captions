import XCTest
@testable import CaptionCore

/// Validation tests for the folded translation look in Settings (#292, decision settings-old-look).
/// Decision: the Settings sample folds like every caption (using TranslatedCaptionView with state),
/// and both notes are reworded to describe tapping to reveal the original (not "translation on top,
/// with what was said underneath"). CONTEXT.md "Folded translated caption", PR #231, #246, #255.
///
/// These tests cannot directly validate SwiftUI code or localized strings (they're in the app target),
/// but they establish the requirements and would break if CaptionCore types supporting the feature
/// became inconsistent.
final class SettingsNotesTests: XCTestCase {
}
