import XCTest
import Foundation

final class LocalizationCatalogTests: XCTestCase {
    func testEveryUserFacingStringIsInTheCatalog() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/CaptionCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // Packages/CaptionCore
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root

        let swiftSourcesDir = repoRoot.appendingPathComponent("Apps/Spike/Sources")
        let catalogPath = swiftSourcesDir.appendingPathComponent("Localizable.xcstrings")

        // Load and parse the catalog
        let catalogData = try Data(contentsOf: catalogPath)
        guard let catalogJSON = try JSONSerialization.jsonObject(with: catalogData) as? [String: Any],
              let strings = catalogJSON["strings"] as? [String: Any] else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Localizable.xcstrings"])
        }

        // Extract catalog keys
        let catalogKeys = Set(strings.keys)

        // Find all Swift files in Sources
        let fileManager = FileManager.default
        let swiftFiles = try fileManager.contentsOfDirectory(at: swiftSourcesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        // Pattern for string literals in common call sites
        let patterns: [(regex: NSRegularExpression, context: String)] = [
            (try NSRegularExpression(pattern: "Text\\(\"([^\"]+)\"", options: []), "Text()"),
            (try NSRegularExpression(pattern: "Label\\(\"([^\"]+)\"", options: []), "Label()"),
            (try NSRegularExpression(pattern: "Button\\(\"([^\"]+)\"", options: []), "Button()"),
            (try NSRegularExpression(pattern: "\\.navigationTitle\\(\"([^\"]+)\"", options: []), "navigationTitle()"),
            (try NSRegularExpression(pattern: "\\.accessibilityLabel\\(\"([^\"]+)\"", options: []), "accessibilityLabel()"),
            (try NSRegularExpression(pattern: "\\.accessibilityValue\\(\"([^\"]+)\"", options: []), "accessibilityValue()"),
            (try NSRegularExpression(pattern: "\\.accessibilityHint\\(\"([^\"]+)\"", options: []), "accessibilityHint()"),
            (try NSRegularExpression(pattern: "Picker\\(\"([^\"]+)\"", options: []), "Picker()"),
        ]

        var missingStrings: [(file: String, pattern: String, string: String)] = []

        for swiftFile in swiftFiles {
            let content = try String(contentsOf: swiftFile, encoding: .utf8)

            for (regex, context) in patterns {
                let range = NSRange(content.startIndex..<content.endIndex, in: content)
                let matches = regex.matches(in: content, options: [], range: range)

                for match in matches {
                    if let stringRange = Range(match.range(at: 1), in: content) {
                        let extractedString = String(content[stringRange])

                        // Skip known non-user-facing patterns
                        // Skip interpolated strings (contain \( indicating Swift interpolation)
                        // Skip format strings (contain %)
                        // Skip system image names (systemName parameter)
                        // Skip symbol names (e.g., "xmark", "gearshape")
                        if extractedString.contains("\\(") { continue }
                        if extractedString.contains("%") { continue }
                        if extractedString.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }) && extractedString.lowercased() == extractedString {
                            continue
                        }

                        // Check if string is in catalog
                        if !catalogKeys.contains(extractedString) {
                            missingStrings.append((swiftFile.lastPathComponent, context, extractedString))
                        }
                    }
                }
            }
        }

        XCTAssert(missingStrings.isEmpty, "Found \(missingStrings.count) user-facing strings not in Localizable.xcstrings:\n" +
            missingStrings.map { "\($0.file) \($0.pattern): \"\($0.string)\"" }.joined(separator: "\n"))
    }
}
