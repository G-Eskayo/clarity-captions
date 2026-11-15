import XCTest
@testable import CaptionCore

final class SpeechLocaleReportTests: XCTestCase {
    let enUS = Locale(identifier: "en-US")
    let esES = Locale(identifier: "es-ES")
    let frFR = Locale(identifier: "fr-FR")
    let deDE = Locale(identifier: "de-DE")
    let heIL = Locale(identifier: "he-IL")
    let zhHans = Locale(identifier: "zh-Hans")

    func testBasicConstruction() {
        let report = SpeechLocaleReport(
            supportedLocales: [enUS],
            installedLocales: [enUS],
            dictionarySupported: [enUS],
            dictionaryInstalled: [enUS],
            osVersion: "iOS 18.2.1"
        )
        XCTAssertEqual(report.osVersion, "iOS 18.2.1")
        XCTAssertEqual(report.supportedLocales.count, 1)
    }

    func testDeduplication() {
        let locales = [enUS, enUS, esES, enUS, frFR]
        let report = SpeechLocaleReport(
            supportedLocales: locales,
            installedLocales: [],
            dictionarySupported: [],
            dictionaryInstalled: [],
            osVersion: "iOS 18.2.1"
        )
        XCTAssertEqual(report.supportedLocales.count, 3)
        let bcp47s = report.supportedLocales.map { CaptionLanguage.bcp47($0) }
        XCTAssertTrue(bcp47s.contains("en-US"))
        XCTAssertTrue(bcp47s.contains("es-ES"))
        XCTAssertTrue(bcp47s.contains("fr-FR"))
    }

    func testSorting() {
        let unsorted = [frFR, enUS, deDE]
        let report = SpeechLocaleReport(
            supportedLocales: unsorted,
            installedLocales: [],
            dictionarySupported: [],
            dictionaryInstalled: [],
            osVersion: "iOS 18.2.1"
        )
        let bcp47s = report.supportedLocales.map { CaptionLanguage.bcp47($0) }
        XCTAssertEqual(bcp47s, ["de-DE", "en-US", "fr-FR"])
    }

    func testJSONSchema() {
        let report = SpeechLocaleReport(
            supportedLocales: [enUS, esES],
            installedLocales: [enUS],
            dictionarySupported: [frFR],
            dictionaryInstalled: [],
            osVersion: "iOS 18.2.1"
        )
        let json = report.asJSON()
        XCTAssertEqual(json["os"] as? String, "iOS 18.2.1")
        XCTAssertNotNil(json["date"])
        XCTAssertNotNil(json["SpeechTranscriber.supportedLocales"])
        XCTAssertNotNil(json["SpeechTranscriber.installedLocales"])
        XCTAssertNotNil(json["DictationTranscriber.supportedLocales"])
        XCTAssertNotNil(json["DictationTranscriber.installedLocales"])
    }

    func testJSONLocaleArrays() {
        let report = SpeechLocaleReport(
            supportedLocales: [enUS, esES],
            installedLocales: [enUS],
            dictionarySupported: [frFR, deDE],
            dictionaryInstalled: [],
            osVersion: "iOS 18.2.1"
        )
        let json = report.asJSON()
        let supported = json["SpeechTranscriber.supportedLocales"] as? [String]
        XCTAssertEqual(supported?.sorted(), ["en-US", "es-ES"])
        let installed = json["SpeechTranscriber.installedLocales"] as? [String]
        XCTAssertEqual(installed?.sorted(), ["en-US"])
        let dictSupported = json["DictationTranscriber.supportedLocales"] as? [String]
        XCTAssertEqual(dictSupported?.sorted(), ["de-DE", "fr-FR"])
    }

    func testEmptyLists() {
        let report = SpeechLocaleReport(
            supportedLocales: [],
            installedLocales: [],
            dictionarySupported: [],
            dictionaryInstalled: [],
            osVersion: "iOS 18.2.1"
        )
        let json = report.asJSON()
        XCTAssertEqual(json["SpeechTranscriber.supportedLocales"] as? [String], [])
        XCTAssertEqual(json["SpeechTranscriber.installedLocales"] as? [String], [])
        XCTAssertEqual(json["DictationTranscriber.supportedLocales"] as? [String], [])
        XCTAssertEqual(json["DictationTranscriber.installedLocales"] as? [String], [])
    }

    func testDatedOutput() {
        let before = Date(timeIntervalSinceNow: -1)
        let report = SpeechLocaleReport(
            supportedLocales: [enUS],
            installedLocales: [],
            dictionarySupported: [],
            dictionaryInstalled: [],
            osVersion: "macOS 15.2"
        )
        let json = report.asJSON()
        let dateString = json["date"] as? String
        XCTAssertNotNil(dateString)
        let formatter = ISO8601DateFormatter()
        if let dateString = dateString, let date = formatter.date(from: dateString) {
            XCTAssertGreaterThanOrEqual(date, before)
            XCTAssertLessThanOrEqual(date, Date(timeIntervalSinceNow: 1))
        } else {
            XCTFail("Date format should be ISO8601")
        }
    }

    func testMacOSVersion() {
        let report = SpeechLocaleReport(
            supportedLocales: [heIL, zhHans],
            installedLocales: [heIL],
            dictionarySupported: [],
            dictionaryInstalled: [],
            osVersion: "macOS 15.2"
        )
        XCTAssertEqual(report.osVersion, "macOS 15.2")
        let json = report.asJSON()
        XCTAssertEqual(json["os"] as? String, "macOS 15.2")
    }
}
