import XCTest
import Foundation

/// The round-2 rules (docs/design/v1-polish-spec.md "Round 2", #118), checked against the app's own source so a pop-up,
/// a sheet or a sliding screen can't come back unnoticed. The only exceptions are the ones iOS draws itself: the
/// Messages compose sheet and the share sheet for beta feedback (mock beta-feedback/05).
final class OneScreenSourceRulesTests: XCTestCase {
    private func appSources() throws -> [(name: String, text: String)] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Apps/Spike/Sources")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Code only: comments may name what used to be there.
    private func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let r = line.range(of: "//") else { return line }
                return line[..<r.lowerBound]
            }
            .joined(separator: "\n")
    }

    private func occurrences(of needle: String, in files: [(name: String, text: String)]) -> [String] {
        files.flatMap { file in
            code(file.text).components(separatedBy: "\n").enumerated()
                .filter { $0.element.contains(needle) }
                .map { "\(file.name):\($0.offset + 1): \($0.element.trimmingCharacters(in: .whitespaces))" }
        }
    }

    func testNoSystemAlertsOrConfirmationPopUps() throws {
        let files = try appSources()
        XCTAssertEqual(occurrences(of: ".alert(", in: files), [])
        XCTAssertEqual(occurrences(of: ".confirmationDialog(", in: files), [])
        XCTAssertEqual(occurrences(of: ".popover(", in: files), [])
        XCTAssertEqual(occurrences(of: ".fullScreenCover(", in: files), [])
    }

    /// #139 (owner, 2026-10-20): [ Share ] on one saved conversation opens Apple's share sheet. Nowhere else.
    func testTheOnlyShareLinkIsOnASavedConversation() throws {
        let links = occurrences(of: "ShareLink(", in: try appSources())
        XCTAssertEqual(links.count, 1, "\(links)")
        XCTAssertTrue(links.allSatisfy { $0.hasPrefix("SavedConversationsView.swift") }, "\(links)")
    }

    /// #139: conversation words are selected with our own handles and [ Copy ], live or saved, never the system's menu.
    func testConversationWordsNeverUseSystemTextSelection() throws {
        let uses = occurrences(of: ".textSelection(", in: try appSources())
        XCTAssertTrue(uses.allSatisfy { $0.hasPrefix("AboutCreditsView.swift") }, "\(uses)")
    }

    func testOnlyApplesOwnSheetsRemain() throws {
        let sheets = occurrences(of: ".sheet(", in: try appSources())
        XCTAssertEqual(sheets.count, 2, "only the Messages compose sheet and the share sheet: \(sheets)")
        XCTAssertTrue(sheets.allSatisfy { $0.hasPrefix("BetaFeedbackViews.swift") }, "\(sheets)")
    }

    func testNoSystemNavigationThatSlidesScreensIn() throws {
        let files = try appSources()
        for needle in ["NavigationStack", "NavigationLink", ".navigationTitle(", ".navigationDestination(", ".toolbar"] {
            XCTAssertEqual(occurrences(of: needle, in: files), [], needle)
        }
    }

    func testEveryTransitionIsAFade() throws {
        let transitions = occurrences(of: ".transition(", in: try appSources())
        XCTAssertFalse(transitions.isEmpty)
        let notFades = transitions.filter { $0.contains(".move(") || $0.contains(".scale") || $0.contains(".slide") || $0.contains(".push(") }
        XCTAssertEqual(notFades, [])
    }

    func testTheSealInABoxAndTheVoicesBannerAreGone() throws {
        let files = try appSources()
        XCTAssertEqual(occurrences(of: "LaunchAnimationView", in: files), [])
        XCTAssertEqual(occurrences(of: "SpeakerExplanation", in: files), [])
        XCTAssertEqual(occurrences(of: "Name this speaker", in: files), [], "naming speakers is out of v1 (#117)")
    }

    /// #150: the developer panel (mic mode, Engine picker) opens by the 1.5 s hold on the status, or, for screenshots
    /// (simctl can't hold), by `-ClarityDemoDeveloperPanel`, a DemoMode flag that is false in a shipped build.
    func testDeveloperPanelOpensByHoldOrTheDemoFlagOnly() throws {
        let files = try appSources()
        let parsed = occurrences(of: "flag(\"-ClarityDemoDeveloperPanel\")", in: files)
        XCTAssertEqual(parsed.count, 1, "\(parsed)")
        XCTAssertTrue(parsed.allSatisfy { $0.hasPrefix("DemoMode.swift") }, "\(parsed)")
        let opens = occurrences(of: "developerTools = true", in: files) + occurrences(of: "developerTools.toggle()", in: files)
        XCTAssertEqual(opens.count, 2, "\(opens)")
        XCTAssertTrue(opens.allSatisfy { $0.hasPrefix("ContentView.swift") }, "\(opens)")
        let byFlag = occurrences(of: "if DemoMode.opensDeveloperPanel { developerTools = true }", in: files)
        XCTAssertEqual(byFlag.count, 1, "\(byFlag)")
        let documented = files.first { $0.name == "DemoMode.swift" }?.text ?? ""
        XCTAssertTrue(documented.contains("///   -ClarityDemoDeveloperPanel"), "list the flag in DemoMode's header")
    }
}
