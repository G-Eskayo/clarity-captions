import XCTest
import AVFoundation
@testable import CaptionCore

#if os(iOS)
final class InterruptionResumeTests: XCTestCase {
    func testShouldResumeWithNilOptions() {
        let result = TranscriptionEngine.shouldResumeAfterInterruption(optionsRawValue: nil)
        XCTAssertFalse(result)
    }

    func testShouldResumeWithShouldResumeOption() {
        let options = AVAudioSession.InterruptionOptions.shouldResume
        let result = TranscriptionEngine.shouldResumeAfterInterruption(optionsRawValue: options.rawValue)
        XCTAssertTrue(result)
    }

    func testShouldResumeWithoutShouldResumeOption() {
        let options = AVAudioSession.InterruptionOptions([])
        let result = TranscriptionEngine.shouldResumeAfterInterruption(optionsRawValue: options.rawValue)
        XCTAssertFalse(result)
    }

    func testShouldResumeWithOtherOptions() {
        // Test with a raw value that doesn't correspond to shouldResume.
        let badRawValue: UInt = 999
        let result = TranscriptionEngine.shouldResumeAfterInterruption(optionsRawValue: badRawValue)
        XCTAssertFalse(result)
    }

    func testShouldResumeWithInvalidRawValue() {
        // Use a UInt value that can't be converted to InterruptionOptions.
        let invalidRawValue: UInt = UInt.max
        let result = TranscriptionEngine.shouldResumeAfterInterruption(optionsRawValue: invalidRawValue)
        XCTAssertFalse(result)
    }
}
#endif
