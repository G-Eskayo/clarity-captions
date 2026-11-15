import Foundation

public struct PackManifest: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case speech
        case diarizer
        case translation
    }

    public struct File: Codable, Equatable, Sendable {
        public let path: String
        public let size: Int
        public let sha256: String

        public init(path: String, size: Int, sha256: String) {
            self.path = path
            self.size = size
            self.sha256 = sha256
        }
    }

    public let id: String
    public let kind: Kind
    public let languages: [String]
    public let engine: String
    public let minAppBuild: Int
    public let sizeOnDisk: Int
    public let files: [File]
    public let credit: String

    public init(
        id: String,
        kind: Kind,
        languages: [String],
        engine: String,
        minAppBuild: Int,
        sizeOnDisk: Int,
        files: [File],
        credit: String
    ) {
        self.id = id
        self.kind = kind
        self.languages = languages
        self.engine = engine
        self.minAppBuild = minAppBuild
        self.sizeOnDisk = sizeOnDisk
        self.files = files
        self.credit = credit
    }

    /// Validates the manifest against schema constraints.
    /// - Throws: `PackManifestError` if validation fails
    public func validate() throws {
        if files.isEmpty {
            throw PackManifestError.emptyFiles
        }

        if languages.isEmpty {
            throw PackManifestError.emptyLanguages
        }

        if minAppBuild < 1 {
            throw PackManifestError.invalidMinAppBuild
        }

        if credit.isEmpty {
            throw PackManifestError.emptyCredit
        }

        var seenPaths = Set<String>()
        for file in files {
            if file.size < 0 {
                throw PackManifestError.invalidFileSize(file.path)
            }

            if !isValidSha256(file.sha256) {
                throw PackManifestError.invalidSha256(file.path)
            }

            if seenPaths.contains(file.path) {
                throw PackManifestError.duplicatePath(file.path)
            }
            seenPaths.insert(file.path)
        }
    }

    private func isValidSha256(_ hex: String) -> Bool {
        guard hex.count == 64 else { return false }
        return hex.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

public enum PackManifestError: LocalizedError, Equatable {
    case emptyFiles
    case emptyLanguages
    case invalidMinAppBuild
    case emptyCredit
    case invalidFileSize(String)
    case invalidSha256(String)
    case duplicatePath(String)

    public var errorDescription: String? {
        switch self {
        case .emptyFiles:
            "Pack manifest must contain at least one file"
        case .emptyLanguages:
            "Pack manifest must specify at least one language"
        case .invalidMinAppBuild:
            "minAppBuild must be at least 1"
        case .emptyCredit:
            "Pack manifest must include a credit line"
        case .invalidFileSize(let path):
            "File size must be non-negative: \(path)"
        case .invalidSha256(let path):
            "sha256 must be exactly 64 lowercase hex characters: \(path)"
        case .duplicatePath(let path):
            "Duplicate file path in manifest: \(path)"
        }
    }
}
