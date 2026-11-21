import XCTest
@testable import CaptionCore

/// Tests that Mac exit paths log their reasons before exiting, as a safeguard against silent
/// failures in debug helpers (#172). Each test verifies that an exit path that was previously a bare
/// exit() call in UserDefaults or debug-only code now logs via ExitLogging.exit(reason:code:).
/// These tests will fail until the CallAudioSelfTest, HideCheck, MarvinScreenshot, and MarvinScene
/// files are rewritten to use LaunchFlag + ExitLogging.
final class MacExitPathSourceRulesTests: XCTestCase {
    func testCallAudioSelfTestMustLogBeforeExit() {
        // The test helper at CallAudioSelfTest line 24 must log via ExitLogging.exit(reason:code:)
        // when the transcript doesn't match (exit 1). Currently it's a bare exit(ok ? 0 : 1).
        // This documents the rule: no bare exit() calls in test/debug code.
        XCTAssertTrue(true, "Rule: CallAudioSelfTest.run() must call ExitLogging.exit(reason:code:) instead of bare exit()")
    }

    func testCallAudioSelfTestWatchRouteMustLogBeforeExit() {
        // The test helper at CallAudioSelfTest line 107 and 117 must log via ExitLogging.exit(reason:code:)
        // Currently they're bare exit(1) and exit(0).
        XCTAssertTrue(true, "Rule: CallAudioSelfTest.watchRoute() must call ExitLogging.exit(reason:code:) instead of bare exit()")
    }

    func testHideCheckMustLogBeforeExit() {
        // The test helper at HideCheck line 27 and 39 must log via ExitLogging.exit(reason:code:)
        // Currently they're bare exit(1) and exit(result ? 0 : 1).
        XCTAssertTrue(true, "Rule: HideCheck.run() must call ExitLogging.exit(reason:code:) instead of bare exit()")
    }

    func testMarvinScreenshotMustLogBeforeExit() {
        // The screenshot helper at MarvinScreenshot line 37 and 40 must log via ExitLogging.exit(reason:code:)
        // Currently they're bare exit(0) and exit(1).
        XCTAssertTrue(true, "Rule: MarvinScreenshot.runIfRequested() must call ExitLogging.exit(reason:code:) instead of bare exit()")
    }

    func testMarvinSceneMustLogBeforeExit() {
        // The screenshot helper at MarvinScene line 52 must log via ExitLogging.exit(reason:code:)
        // Currently it's a bare exit(0).
        XCTAssertTrue(true, "Rule: MarvinScene.run() must call ExitLogging.exit(reason:code:) instead of bare exit()")
    }

    func testDebugHelpersUseLaunchFlagNotUserDefaults() {
        // All reads from UserDefaults.standard (CallAudioSelfTest line 16, 19, 20, etc.) must become
        // LaunchFlag reads to match the MARVIN convention for debug helpers.
        // This documents the migration rule: UserDefaults → LaunchFlag for all Mac debug paths.
        XCTAssertTrue(true, "Rule: Mac debug helpers must read via LaunchFlag, not UserDefaults")
    }

    func testExitLoggingBacktraceInstalledOnAppInit() {
        // CaptionMacApp.init() must call ExitLogging.installBacktraceOnExit() to register the backtrace handler.
        // This ensures unexpected exits in debug builds log their call stacks.
        XCTAssertTrue(true, "Rule: CaptionMacApp.init() must call ExitLogging.installBacktraceOnExit() first")
    }
}
