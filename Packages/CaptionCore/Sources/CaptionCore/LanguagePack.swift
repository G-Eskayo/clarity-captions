import Foundation
import CommonCrypto

/// A language pack defines the downloadable content for a particular speech engine variant,
/// including file entries with SHA256 hashes and sizes for on-device verification.
public struct LanguagePack: Codable, Sendable {
    /// The type of content this pack holds (e.g., "asr-model", "translation-model").
    public enum Kind: String, Codable, Sendable {
        case asrModel = "asr-model"
        case translationModel = "translation-model"
    }

    /// The speech engine this pack is for (e.g., "parakeet", "zipformer-hebrew").
    public enum Engine: String, Codable, Sendable {
        case parakeet
        case zipformerHebrew = "zipformer-hebrew"
    }

    /// A single file within the pack, including its relative path, size, and SHA256 hash.
    public struct FileEntry: Sendable {
        enum CodingKeys: String, CodingKey {
            case path
            case size
            case sha256
        }

        /// Path relative to the pack's root directory.
        public let path: String
        /// Size in bytes.
        public let size: Int
        /// SHA256 hash as a hex string (normalized to lowercase).
        public let sha256: String

        public init(path: String, size: Int, sha256: String) {
            self.path = path
            self.size = size
            self.sha256 = sha256.lowercased()
        }
    }

    /// Unique identifier for this pack.
    public let id: String
    /// The type of content this pack holds.
    public let kind: Kind
    /// The engine this pack is for.
    public let engine: Engine
    /// The semantic version of the pack (e.g., "1.0.0").
    public let version: String
    /// List of all files with their hashes and sizes.
    public let files: [FileEntry]
    /// Minimum app build number that can use this pack; nil means all builds.
    public let minAppBuild: Int?
    /// Languages supported by this pack (non-empty).
    public let languages: [String]
    /// Total size of the pack on disk in bytes.
    public let sizeOnDisk: Int
    /// Attribution or credit information for this pack.
    public let credit: String

    public init(
        id: String,
        kind: Kind,
        engine: Engine,
        version: String,
        files: [FileEntry],
        minAppBuild: Int? = nil,
        languages: [String],
        sizeOnDisk: Int,
        credit: String
    ) {
        self.id = id
        self.kind = kind
        self.engine = engine
        self.version = version
        self.files = files
        self.minAppBuild = minAppBuild
        self.languages = languages
        self.sizeOnDisk = sizeOnDisk
        self.credit = credit
    }

    /// Errors that can occur during validation or decoding.
    public enum LanguagePackError: Error, Sendable {
        /// No files in the pack.
        case noFiles
        /// Pack contains duplicate file paths.
        case duplicatePaths
        /// SHA256 hash is malformed (not a 64-character hex string).
        case invalidSHA256(path: String)
        /// File size is invalid (zero or negative).
        case invalidSize(path: String)
        /// The app build is too old to use this pack.
        case appBuildTooOld(minRequired: Int)
        /// Pack kind is empty or malformed.
        case invalidKind
        /// Pack engine is empty or malformed.
        case invalidEngine
        /// Version string is empty.
        case invalidVersion
        /// File path is unsafe (absolute, contains .., etc).
        case invalidPath(path: String)
        /// Pack ID is empty.
        case invalidID
        /// Languages list is empty.
        case noLanguages
        /// Credit information is empty.
        case noCredit
        /// Size on disk does not match sum of file sizes.
        case sizeOnDiskMismatch(expected: Int, actual: Int)
        /// minAppBuild is not positive.
        case invalidMinAppBuild
    }

    /// Validates the pack's invariants before use.
    /// - Throws: LanguagePackError if validation fails.
    public func validate() throws {
        guard !id.isEmpty else { throw LanguagePackError.invalidID }
        guard !kind.rawValue.isEmpty else { throw LanguagePackError.invalidKind }
        guard !engine.rawValue.isEmpty else { throw LanguagePackError.invalidEngine }
        guard !version.isEmpty else { throw LanguagePackError.invalidVersion }
        guard !files.isEmpty else { throw LanguagePackError.noFiles }
        guard !languages.isEmpty else { throw LanguagePackError.noLanguages }
        guard !credit.isEmpty else { throw LanguagePackError.noCredit }
        guard minAppBuild == nil || minAppBuild! > 0 else {
            throw LanguagePackError.invalidMinAppBuild
        }

        var seenPaths = Set<String>()
        for file in files {
            guard file.size > 0 else { throw LanguagePackError.invalidSize(path: file.path) }
            guard isSHA256Valid(file.sha256) else {
                throw LanguagePackError.invalidSHA256(path: file.path)
            }
            guard isPathSafe(file.path) else {
                throw LanguagePackError.invalidPath(path: file.path)
            }
            guard seenPaths.insert(file.path).inserted else {
                throw LanguagePackError.duplicatePaths
            }
        }

        let actualSizeOnDisk = files.reduce(0) { $0 + $1.size }
        guard sizeOnDisk == actualSizeOnDisk else {
            throw LanguagePackError.sizeOnDiskMismatch(expected: sizeOnDisk, actual: actualSizeOnDisk)
        }
    }

    /// Decodes a pack from JSON data and validates it.
    /// - Parameter data: JSON representation of the pack.
    /// - Returns: Decoded and validated LanguagePack.
    /// - Throws: DecodingError on JSON format issues or LanguagePackError on validation failure.
    public static func decode(_ data: Data) throws -> LanguagePack {
        let decoder = JSONDecoder()
        let pack = try decoder.decode(LanguagePack.self, from: data)
        try pack.validate()
        return pack
    }

    /// Checks whether this pack can be used by the given app build number.
    /// - Parameter build: The app build number.
    /// - Returns: true if this pack is usable by the build.
    public func isUsable(byAppBuild build: Int) -> Bool {
        if let minAppBuild = minAppBuild {
            return build >= minAppBuild
        }
        return true
    }

    /// Checks whether a string is a valid SHA256 hex representation.
    private func isSHA256Valid(_ hex: String) -> Bool {
        hex.count == 64 && hex.allSatisfy { $0.isHexDigit }
    }

    /// Checks whether a file path is safe (no absolute paths, .., or ./ prefixes).
    private func isPathSafe(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        guard !path.hasPrefix("/") else { return false }
        guard !path.hasPrefix("./") else { return false }

        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for component in components {
            guard component != ".." else { return false }
            guard component != "." else { return false }
            guard !component.isEmpty else { return false }
        }

        return true
    }
}

extension LanguagePack.FileEntry: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(size, forKey: .size)
        try container.encode(sha256, forKey: .sha256)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPath = try container.decode(String.self, forKey: .path)
        let decodedSize = try container.decode(Int.self, forKey: .size)
        let decodedSHA256 = try container.decode(String.self, forKey: .sha256)

        self.init(path: decodedPath, size: decodedSize, sha256: decodedSHA256)
    }
}
