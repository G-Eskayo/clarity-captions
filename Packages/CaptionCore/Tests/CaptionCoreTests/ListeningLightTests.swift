import XCTest
@testable import CaptionCore

/// #180: the Listening light is red and follows the room in colour (owner, 2026-10-28: option C), never in size.
final class ListeningLightTests: XCTestCase {
    private let backgrounds = CaptionPreset.all.map { ($0.id, $0.background) }

    func testTheLightIsRedOnEveryLook() {
        for (id, bg) in backgrounds {
            let red = ListeningLight.color(on: bg, roomLevelDBFS: -30, reduceMotion: false)
            XCTAssertGreaterThan(red.r, red.g + 0.4, id)
            XCTAssertGreaterThan(red.r, red.b + 0.4, id)
        }
    }

    /// WCAG 1.4.11: a UI indicator needs 3:1 against what's behind it. Even a silent room must not make the light
    /// look switched off (evidence log E-entry on non-text contrast).
    func testEvenTheQuietestRoomKeepsTheLightAtThreeToOneOnEveryLook() {
        for (id, bg) in backgrounds {
            for level in [nil, -120.0, -60, -59] as [Double?] {
                let c = ListeningLight.color(on: bg, roomLevelDBFS: level, reduceMotion: false)
                XCTAssertGreaterThanOrEqual(RGBA.contrast(c, bg), 3, "\(id) at \(String(describing: level))")
            }
        }
    }

    func testALoudRoomIsBrighterThanAQuietOneOnEveryLook() {
        for (id, bg) in backgrounds {
            let quiet = ListeningLight.color(on: bg, roomLevelDBFS: -60, reduceMotion: false)
            let loud = ListeningLight.color(on: bg, roomLevelDBFS: -30, reduceMotion: false)
            XCTAssertGreaterThan(RGBA.contrast(loud, bg), RGBA.contrast(quiet, bg) + 0.8, id)
        }
    }

    func testLevelsPastTheEndsAreClampedNotExtrapolated() {
        let bg = CaptionPreset.named("paper").background
        XCTAssertEqual(ListeningLight.color(on: bg, roomLevelDBFS: 0, reduceMotion: false),
                       ListeningLight.color(on: bg, roomLevelDBFS: -30, reduceMotion: false))
        XCTAssertEqual(ListeningLight.color(on: bg, roomLevelDBFS: -200, reduceMotion: false),
                       ListeningLight.color(on: bg, roomLevelDBFS: -60, reduceMotion: false))
        XCTAssertEqual(ListeningLight.color(on: bg, roomLevelDBFS: .nan, reduceMotion: false),
                       ListeningLight.color(on: bg, roomLevelDBFS: -60, reduceMotion: false))
    }

    func testLouderNeverMakesItDimmer() {
        let bg = CaptionPreset.named("harbor").background
        var last = 0.0
        for level in stride(from: -70.0, through: -20, by: 1) {
            let c = RGBA.contrast(ListeningLight.color(on: bg, roomLevelDBFS: level, reduceMotion: false), bg)
            XCTAssertGreaterThanOrEqual(c, last - 1e-9, "at \(level)")
            last = c
        }
    }

    /// Reduce Motion keeps the red and drops the change: one steady colour whatever the room does.
    func testReduceMotionIsSteadyFullRed() {
        for (id, bg) in backgrounds {
            let quiet = ListeningLight.color(on: bg, roomLevelDBFS: -60, reduceMotion: true)
            let loud = ListeningLight.color(on: bg, roomLevelDBFS: -30, reduceMotion: true)
            XCTAssertEqual(quiet, loud, id)
            XCTAssertEqual(quiet, ListeningLight.color(on: bg, roomLevelDBFS: -30, reduceMotion: false), id)
        }
    }

    func testAPressGivesALittleAndNeverGrows() {
        XCTAssertLessThan(PressFeedback.iconScale, 1)
        XCTAssertGreaterThanOrEqual(PressFeedback.iconScale, 0.85)
        XCTAssertLessThan(PressFeedback.stopScale, 1)
        XCTAssertGreaterThanOrEqual(PressFeedback.stopScale, 0.85)
        XCTAssertLessThan(PressFeedback.iconPressedOpacity, 1)
        XCTAssertGreaterThan(PressFeedback.iconPressedOpacity, 0.3)   // dimmed, still visible under the finger
    }
}
