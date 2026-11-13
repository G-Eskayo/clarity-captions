import XCTest
@testable import CaptionCore

final class SpeechLocaleReportTests: XCTestCase {
    func testJsonOutputIsValidJSON() {
        let result = SpeechLocaleReport.json(
            os: "iOS 27.0",
            date: ISO8601DateFormatter().date(from: "2026-10-30T09:10:32Z")!,
            speechTranscriberSupported: [Locale(identifier: "en-US")],
            speechTranscriberInstalled: [Locale(identifier: "en-US")],
            dictationSupported: [Locale(identifier: "en-US")],
            dictationInstalled: [Locale(identifier: "en-US")],
            sfSpeechSupported: [Locale(identifier: "en-US")]
        )

        let data = result.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(parsed)
    }

    func testJsonOutputHasAllExpectedKeysSorted() {
        let result = SpeechLocaleReport.json(
            os: "iOS 27.0",
            date: ISO8601DateFormatter().date(from: "2026-10-30T09:10:32Z")!,
            speechTranscriberSupported: [],
            speechTranscriberInstalled: [],
            dictationSupported: [],
            dictationInstalled: [],
            sfSpeechSupported: []
        )

        let data = result.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as! [String: Any]

        let expectedKeys = [
            "date",
            "DictationTranscriber.installedLocales",
            "DictationTranscriber.supportedLocales",
            "SFSpeechRecognizer.supportedLocales",
            "SpeechTranscriber.installedLocales",
            "SpeechTranscriber.supportedLocales",
            "os"
        ]

        for key in expectedKeys {
            XCTAssertNotNil(parsed[key], "Missing key: \(key)")
        }
    }

    func testJsonOutputDeduplicatesLocales() {
        let result = SpeechLocaleReport.json(
            os: "iOS 27.0",
            date: ISO8601DateFormatter().date(from: "2026-10-30T09:10:32Z")!,
            speechTranscriberSupported: [
                Locale(identifier: "en-US"),
                Locale(identifier: "en-US"),
                Locale(identifier: "fr-FR")
            ],
            speechTranscriberInstalled: [],
            dictationSupported: [],
            dictationInstalled: [],
            sfSpeechSupported: []
        )

        let data = result.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let supportedList = parsed["SpeechTranscriber.supportedLocales"] as! [String]

        XCTAssertEqual(supportedList.count, 2)
        XCTAssertEqual(Set(supportedList), ["en-US", "fr-FR"])
    }

    func testJsonOutputSortsLocalesBcp47() {
        let result = SpeechLocaleReport.json(
            os: "iOS 27.0",
            date: ISO8601DateFormatter().date(from: "2026-10-30T09:10:32Z")!,
            speechTranscriberSupported: [
                Locale(identifier: "zh-CN"),
                Locale(identifier: "en-US"),
                Locale(identifier: "fr-FR"),
                Locale(identifier: "de-DE")
            ],
            speechTranscriberInstalled: [],
            dictationSupported: [],
            dictationInstalled: [],
            sfSpeechSupported: []
        )

        let data = result.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let supportedList = parsed["SpeechTranscriber.supportedLocales"] as! [String]

        XCTAssertEqual(supportedList, ["de-DE", "en-US", "fr-FR", "zh-CN"])
    }

    func testSummaryCountsAreDeduplicated() {
        let summary = SpeechLocaleReport.summary(
            os: "iOS 27.0",
            speechTranscriberSupported: [
                Locale(identifier: "en-US"),
                Locale(identifier: "en-US"),
                Locale(identifier: "en-US")
            ],
            dictationSupported: [
                Locale(identifier: "en-US"),
                Locale(identifier: "fr-FR"),
                Locale(identifier: "fr-FR")
            ]
        )

        XCTAssertEqual(summary, "ST: 1 supported, DT: 2 supported (1 new)")
    }

    func testSummaryCountsDictationOnlyLocales() {
        let summary = SpeechLocaleReport.summary(
            os: "iOS 27.0",
            speechTranscriberSupported: [
                Locale(identifier: "en-US"),
                Locale(identifier: "fr-FR")
            ],
            dictationSupported: [
                Locale(identifier: "en-US"),
                Locale(identifier: "fr-FR"),
                Locale(identifier: "he-IL"),
                Locale(identifier: "ar-SA")
            ]
        )

        XCTAssertEqual(summary, "ST: 2 supported, DT: 4 supported (2 new)")
    }

    func testSummaryHandlesEmptyLists() {
        let summary = SpeechLocaleReport.summary(
            os: "iOS 27.0",
            speechTranscriberSupported: [],
            dictationSupported: []
        )

        XCTAssertEqual(summary, "ST: 0 supported, DT: 0 supported (0 new)")
    }

    func testSummaryWithOnlyDictationSupport() {
        let summary = SpeechLocaleReport.summary(
            os: "iOS 27.0",
            speechTranscriberSupported: [],
            dictationSupported: [
                Locale(identifier: "ar-SA"),
                Locale(identifier: "he-IL")
            ]
        )

        XCTAssertEqual(summary, "ST: 0 supported, DT: 2 supported (2 new)")
    }

    func testSummaryWithRepeatsInAllLists() {
        let en = Locale(identifier: "en-US")
        let fr = Locale(identifier: "fr-FR")
        let ar = Locale(identifier: "ar-SA")

        let summary = SpeechLocaleReport.summary(
            os: "iOS 27.0",
            speechTranscriberSupported: [en, en, en, fr, fr],
            dictationSupported: [en, en, fr, fr, ar, ar, ar]
        )

        XCTAssertEqual(summary, "ST: 2 supported, DT: 3 supported (1 new)")
    }

    func testSummaryWithHugeInputList() {
        var stList = [Locale]()
        var dtList = [Locale]()

        for i in 0..<100 {
            stList.append(Locale(identifier: "en-\(String(format: "%03d", i))"))
            stList.append(Locale(identifier: "en-\(String(format: "%03d", i))"))
        }

        for i in 100..<150 {
            dtList.append(Locale(identifier: "fr-\(String(format: "%03d", i))"))
        }

        let summary = SpeechLocaleReport.summary(
            os: "iOS 27.0",
            speechTranscriberSupported: stList,
            dictationSupported: dtList
        )

        XCTAssertEqual(summary, "ST: 100 supported, DT: 50 supported (50 new)")
    }

    func testJsonKeysPinToExpectedSchema() {
        let result = SpeechLocaleReport.json(
            os: "iOS 27.0",
            date: ISO8601DateFormatter().date(from: "2026-10-30T09:10:32Z")!,
            speechTranscriberSupported: [Locale(identifier: "en-US")],
            speechTranscriberInstalled: [Locale(identifier: "en-US")],
            dictationSupported: [Locale(identifier: "en-US")],
            dictationInstalled: [Locale(identifier: "en-US")],
            sfSpeechSupported: [Locale(identifier: "en-US")]
        )

        let data = result.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        let expectedKeys = [
            "date",
            "DictationTranscriber.installedLocales",
            "DictationTranscriber.supportedLocales",
            "SFSpeechRecognizer.supportedLocales",
            "SpeechTranscriber.installedLocales",
            "SpeechTranscriber.supportedLocales",
            "os"
        ]

        XCTAssertEqual(Set(parsed.keys), Set(expectedKeys), "JSON keys must match schema exactly")
    }

    func testJsonHandlesSpecialCharactersInOS() {
        let osString = "iOS 27.0.1 \"Special\" \\Path"
        let result = SpeechLocaleReport.json(
            os: osString,
            date: ISO8601DateFormatter().date(from: "2026-10-30T09:10:32Z")!,
            speechTranscriberSupported: [],
            speechTranscriberInstalled: [],
            dictationSupported: [],
            dictationInstalled: [],
            sfSpeechSupported: []
        )

        let data = result.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(parsed["os"] as? String, osString)
    }

    func testJsonDatesAreISO8601() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 30
        components.hour = 14
        components.minute = 30
        components.second = 45
        components.timeZone = TimeZone(secondsFromGMT: 0)

        let date = calendar.date(from: components)!

        let result = SpeechLocaleReport.json(
            os: "iOS 27.0",
            date: date,
            speechTranscriberSupported: [],
            speechTranscriberInstalled: [],
            dictationSupported: [],
            dictationInstalled: [],
            sfSpeechSupported: []
        )

        let data = result.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let dateString = parsed["date"] as! String

        XCTAssertTrue(dateString.contains("2026-10-30"), "Date should be in ISO8601 format")
        let formatter = ISO8601DateFormatter()
        XCTAssertNotNil(formatter.date(from: dateString), "Date should be parseable as ISO8601")
    }
}
