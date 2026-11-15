import Foundation
import CommonCrypto

/// A single problem detected during pack verification.
public struct PackVerificationProblem: Sendable {
    public enum Kind: Sendable {
        case missingFile(path: String)
        case unexpectedFile(path: String)
        case sizeMismatch(path: String, expected: Int, actual: Int)
        case checksumMismatch(path: String, expected: String, actual: String)
        case unreadableFile(path: String, reason: String)
        case symlinkRejected(path: String)
    }

    public let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var description: String {
        switch kind {
        case .missingFile(let path):
            return "missing \(path)"
        case .unexpectedFile(let path):
            return "unexpected \(path)"
        case .sizeMismatch(let path, let expected, let actual):
            return "size mismatch \(path) (expected \(expected), got \(actual))"
        case .checksumMismatch(let path, let expected, let actual):
            return "checksum mismatch \(path) (expected \(expected), got \(actual))"
        case .unreadableFile(let path, let reason):
            return "unreadable \(path) (\(reason))"
        case .symlinkRejected(let path):
            return "symlink rejected \(path)"
        }
    }
}

/// The result of verifying a pack on disk.
public struct PackVerificationResult: Sendable {
    /// true if the pack matches the manifest exactly.
    public let isValid: Bool
    /// Problems found, if any.
    public let problems: [PackVerificationProblem]
    /// Number of files verified successfully (excluding .DS_Store).
    public let filesVerified: Int

    public init(isValid: Bool, problems: [PackVerificationProblem], filesVerified: Int) {
        self.isValid = isValid
        self.problems = problems
        self.filesVerified = filesVerified
    }
}

/// Verifies that a directory on disk matches the pack's manifest.
public enum LanguagePackVerifier {
    public enum VerificationError: Error {
        case invalidDirectory(URL)
    }

    /// Verifies a pack directory against a manifest.
    /// - Parameters:
    ///   - pack: The LanguagePack defining the expected content.
    ///   - path: File system path to the directory to verify.
    ///   - fileManager: FileManager to use for I/O.
    /// - Returns: Verification result.
    /// - Throws: VerificationError if the directory can't be read.
    public static func verify(
        _ pack: LanguagePack,
        at path: URL,
        fileManager: FileManager = .default
    ) throws -> PackVerificationResult {
        guard let enumerator = fileManager.enumerator(
            at: path,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ) else {
            throw VerificationError.invalidDirectory(path)
        }

        var problems: [PackVerificationProblem] = []

        var want = [String: (sha256: String, size: Int)]()
        for file in pack.files {
            want[file.path] = (file.sha256, file.size)
        }

        var have = Set<String>()
        var symlinks = Set<String>()
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if name == ".DS_Store" { continue }

            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])

            if resourceValues.isDirectory ?? false { continue }

            do {
                let rel = try fileURL.relativePath(from: path)
                if resourceValues.isSymbolicLink ?? false {
                    symlinks.insert(rel)
                } else {
                    have.insert(rel)
                }
            } catch {
                continue
            }
        }

        for rel in Set(want.keys).intersection(symlinks) {
            problems.append(PackVerificationProblem(.symlinkRejected(path: rel)))
        }

        for rel in symlinks.subtracting(Set(want.keys)) {
            problems.append(PackVerificationProblem(.unexpectedFile(path: rel)))
        }

        for rel in Set(want.keys).subtracting(have).subtracting(symlinks) {
            problems.append(PackVerificationProblem(.missingFile(path: rel)))
        }

        for rel in have.subtracting(Set(want.keys)) {
            problems.append(PackVerificationProblem(.unexpectedFile(path: rel)))
        }

        var filesVerified = 0
        for rel in Set(want.keys).intersection(have).sorted() {
            let filePath = path.appendingPathComponent(rel)
            let (expectedSHA256, expectedSize) = want[rel]!

            guard fileManager.fileExists(atPath: filePath.path) else {
                problems.append(PackVerificationProblem(.missingFile(path: rel)))
                continue
            }

            do {

                let attributes = try fileManager.attributesOfItem(atPath: filePath.path)
                let actualSize = attributes[.size] as? Int ?? 0

                if actualSize != expectedSize {
                    problems.append(PackVerificationProblem(
                        .sizeMismatch(path: rel, expected: expectedSize, actual: actualSize)
                    ))
                    continue
                }

                let actualSHA256 = try computeSHA256(at: filePath)
                if actualSHA256 != expectedSHA256 {
                    problems.append(PackVerificationProblem(
                        .checksumMismatch(path: rel, expected: expectedSHA256, actual: actualSHA256)
                    ))
                    continue
                }

                filesVerified += 1
            } catch {
                problems.append(PackVerificationProblem(.unreadableFile(path: rel, reason: error.localizedDescription)))
            }
        }

        return PackVerificationResult(
            isValid: problems.isEmpty,
            problems: problems,
            filesVerified: filesVerified
        )
    }

    /// Computes the SHA256 hash of a file using chunked reading (1 MB chunks).
    private static func computeSHA256(at url: URL) throws -> String {
        let chunkSize = 1024 * 1024
        let hasher = SHA256Hasher()

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        while true {
            let data = try fileHandle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        let finalized = hasher.finalize()
        return finalized.map { String(format: "%02x", $0) }.joined()
    }

}

// MARK: - URL Extensions

private extension URL {
    func relativePath(from base: URL) throws -> String {
        let basePath = base.resolvingSymlinksInPath().path
        let filePath = self.resolvingSymlinksInPath().path

        guard filePath.hasPrefix(basePath) else {
            throw URLError(.badURL)
        }

        var result = String(filePath.dropFirst(basePath.count))
        if result.hasPrefix("/") {
            result = String(result.dropFirst())
        }
        return result
    }
}

// MARK: - SHA256 Wrapper

private class SHA256Hasher {
    private var context = CC_SHA256_CTX()

    init() {
        CC_SHA256_Init(&context)
    }

    func update(data: Data) {
        _ = data.withUnsafeBytes { buffer in
            CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(data.count))
        }
    }

    func finalize() -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return Data(digest)
    }
}
