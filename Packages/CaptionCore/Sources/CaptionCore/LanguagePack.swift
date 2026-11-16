import CryptoKit
import Foundation

/// A model pack manifest (ADR 0029 §4.3): speech engine, diarizer, or translation models
/// distributed as asset packs on Apple platforms and Play Asset Delivery on Android.
/// Each pack carries this metadata and a set of files to be verified before first use.
public struct LanguagePack: Codable, Equatable, Sendable {
    /// Pack kind: speech transcription, speaker diarization, or translation.
    public enum Kind: String, Codable, Equatable, Sendable {
        case speech
        case diarizer
        case translation
    }

    /// Speech engine or model implementation (ADR 0025, 0029).
    public enum Engine: String, Codable, Equatable, Sendable {
        case parakeet
        case zipformer
        case apple
    }

    /// One file in the pack: a path relative to the pack's root, its size, and SHA-256 hash.
    public struct File: Codable, Equatable, Sendable {
        public let path: String
        public let size: Int64
        public let sha256: String

        public init(path: String, size: Int64, sha256: String) {
            self.path = path
            self.size = size
            self.sha256 = sha256
        }
    }

    /// Verification result: either successful or a list of problems in sorted order.
    public enum PackVerification: Equatable {
        case ok
        case failed(problems: [String])
    }

    /// Unique pack identifier (format: kind-id-version, e.g., "speech-en-parakeet-pal6-v1").
    public let id: String

    /// What this pack contains: speech engine, speaker diarizer, or translation models.
    public let kind: Kind

    /// Languages this pack supports (BCP 47 tags, e.g., ["en-US", "en-GB"]).
    public let languages: [String]

    /// Engine implementation for this pack (parakeet, zipformer, or apple).
    public let engine: Engine

    /// Minimum app build that can load this pack. Older builds ignore it.
    public let minAppBuild: Int

    /// Total size of all files on disk, in bytes.
    public let sizeOnDisk: Int64

    /// Files in the pack, with path, size, and SHA-256 hash for verification.
    public let files: [File]

    /// Attribution line for the pack (model source, license, any transformations).
    public let credit: String

    public init(id: String, kind: Kind, languages: [String], engine: Engine, minAppBuild: Int,
                sizeOnDisk: Int64, files: [File], credit: String) {
        self.id = id
        self.kind = kind
        self.languages = languages
        self.engine = engine
        self.minAppBuild = minAppBuild
        self.sizeOnDisk = sizeOnDisk
        self.files = files
        self.credit = credit
    }

    /// Verify the pack in a folder: check manifest validity, file presence, sizes, and SHA-256 hashes.
    /// Returns `.ok` if valid, or `.failed(problems:)` with a sorted list of issues found.
    /// Problems are checked in this order:
    /// 1. Invalid paths (absolute, containing "..", or outside folder)
    /// 2. Empty manifest (no files)
    /// 3. Duplicate paths in the manifest
    /// 4. Missing files on disk
    /// 5. Unexpected files in the folder (not in the manifest)
    /// 6. File size mismatches
    /// 7. SHA-256 hash mismatches
    public func verify(in folder: URL, fileManager: FileManager = .default) -> PackVerification {
        var problems: [String] = []

        // Guard: validate all paths before processing (path traversal protection)
        for file in files {
            if !isPathSafe(file.path, in: folder, fileManager: fileManager) {
                problems.append("Invalid path: rejected '\(file.path)' (path traversal detected)")
            }
        }

        if !problems.isEmpty {
            return .failed(problems: problems.sorted())
        }

        // Guard: duplicate paths
        let paths = files.map(\.path)
        let uniquePaths = Set(paths)
        if paths.count != uniquePaths.count {
            let duplicates = paths.filter { path in paths.filter { $0 == path }.count > 1 }
            for dup in Set(duplicates).sorted() {
                problems.append("Duplicate path in manifest: \(dup)")
            }
        }

        // Check: missing files
        for file in files {
            let filePath = folder.appendingPathComponent(file.path)
            if !fileManager.fileExists(atPath: filePath.path) {
                problems.append("File not found: \(file.path)")
            }
        }

        // Check: unexpected files (recursively enumerate all files in the folder)
        let expectedPaths = Set(files.map(\.path))
        let basePathNormalized = (folder.path as NSString).resolvingSymlinksInPath
        let basePathWithSlash = basePathNormalized.hasSuffix("/") ? basePathNormalized : basePathNormalized + "/"

        if let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                let filePath = (fileURL.path as NSString).resolvingSymlinksInPath
                let relativePath = filePath.hasPrefix(basePathWithSlash)
                    ? String(filePath.dropFirst(basePathWithSlash.count))
                    : filePath

                if !expectedPaths.contains(relativePath) {
                    // Only report regular files, not directories
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: filePath, isDirectory: &isDir), !isDir.boolValue {
                        problems.append("Unexpected file in pack: \(relativePath)")
                    }
                }
            }
        }

        // Guard: empty manifest (checked after unexpected files so we catch them first)
        if files.isEmpty && expectedPaths.isEmpty {
            let hasUnexpected = problems.contains { $0.contains("Unexpected") }
            if !hasUnexpected {
                problems.append("Pack manifest is empty: no files declared.")
            }
        }

        // If there are already problems, return early to avoid unnecessary hashing
        if !problems.isEmpty {
            return .failed(problems: problems.sorted())
        }

        // Check: file sizes and hashes (only if basic checks pass)
        for file in files {
            let filePath = folder.appendingPathComponent(file.path)

            // Size check first (cheaper than hashing)
            var fileSize: Int64 = 0
            do {
                let attributes = try fileManager.attributesOfItem(atPath: filePath.path)
                fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            } catch {
                problems.append("Cannot read file size for \(file.path): \(error)")
                continue
            }

            if fileSize != file.size {
                problems.append("Size mismatch for \(file.path): expected \(file.size), got \(fileSize)")
                continue
            }

            // Hash check using chunked reading to avoid loading large files entirely into memory
            do {
                let hash = try chunkedSHA256(filePath: filePath)
                if hash != file.sha256 {
                    problems.append("SHA-256 mismatch for \(file.path): expected \(file.sha256), got \(hash)")
                }
            } catch {
                problems.append("Cannot read or hash file \(file.path): \(error)")
            }
        }

        guard problems.isEmpty else {
            return .failed(problems: problems.sorted())
        }

        return .ok
    }

    /// Check if a relative path is safe (no absolute paths, no parent directory references, resolves within folder).
    private func isPathSafe(_ path: String, in folder: URL, fileManager: FileManager) -> Bool {
        // Reject absolute paths
        if path.hasPrefix("/") {
            return false
        }

        // Reject paths with parent directory references
        if path.contains("..") {
            return false
        }

        // Ensure the resolved path stays within the folder
        let filePath = folder.appendingPathComponent(path)
        let resolvedFilePath = (filePath.path as NSString).resolvingSymlinksInPath
        let resolvedFolderPath = (folder.path as NSString).resolvingSymlinksInPath

        return resolvedFilePath.hasPrefix(resolvedFolderPath + "/") || resolvedFilePath == resolvedFolderPath
    }

    /// Compute SHA-256 hash of a file using chunked reading to avoid loading the entire file into memory.
    private func chunkedSHA256(filePath: URL) throws -> String {
        let chunkSize = 1024 * 1024
        var hasher = SHA256()

        let fileHandle = try FileHandle(forReadingFrom: filePath)
        defer { try? fileHandle.close() }

        while let chunk = try fileHandle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        let digest = Data(hasher.finalize())
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
