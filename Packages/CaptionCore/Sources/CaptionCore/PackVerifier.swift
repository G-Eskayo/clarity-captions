import CryptoKit
import Foundation

public enum PackVerificationProblem: Equatable, Sendable {
    case missing(String)
    case unexpected(String)
    case sizeMismatch(String)
    case checksumMismatch(String)
    case folderMissing
    case unreadable(String)
}

public enum PackVerifier {
    private static let chunkSize = 1 << 20 // 1 MB

    /// Verifies a folder against a manifest.
    /// Returns a list of problems (empty if the folder matches the manifest perfectly).
    /// Does not throw; callers can inspect the problems list for detailed state.
    public static func verify(
        _ manifest: PackManifest,
        in folderURL: URL,
        fileManager: FileManager = .default
    ) throws -> [PackVerificationProblem] {
        var problems: [PackVerificationProblem] = []

        // Check if folder exists
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDir) || !isDir.boolValue {
            return [.folderMissing]
        }

        // Build set of manifest files
        let manifestFiles = Set(manifest.files.map { $0.path })

        // Build set of actual files in folder, walking recursively
        var actualFiles = Set<String>()
        walkFolder(folderURL, fileManager: fileManager, basePath: "", into: &actualFiles)

        // Find missing files
        for path in manifestFiles.subtracting(actualFiles).sorted() {
            problems.append(.missing(path))
        }

        // Find unexpected files
        for path in actualFiles.subtracting(manifestFiles).sorted() {
            problems.append(.unexpected(path))
        }

        // Check files present in both
        for file in manifest.files.sorted(by: { $0.path < $1.path }) {
            guard actualFiles.contains(file.path) else { continue }

            let filePath = folderURL.appendingPathComponent(file.path)

            // Check size first
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try fileManager.attributesOfItem(atPath: filePath.path)
            } catch {
                problems.append(.unreadable(file.path))
                continue
            }

            guard let fileSize = attributes[.size] as? Int else {
                problems.append(.unreadable(file.path))
                continue
            }

            if fileSize != file.size {
                problems.append(.sizeMismatch(file.path))
                continue
            }

            // Size matches, check hash
            let actualHash: String
            do {
                actualHash = try hashFile(at: filePath)
            } catch {
                problems.append(.unreadable(file.path))
                continue
            }

            if actualHash != file.sha256 {
                problems.append(.checksumMismatch(file.path))
            }
        }

        return problems
    }

    private static func hashFile(at url: URL) throws -> String {
        var digest = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            digest.update(data: chunk)
        }

        let digestBytes = Data(digest.finalize())
        return digestBytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func walkFolder(
        _ folderURL: URL,
        fileManager: FileManager,
        basePath: String,
        into files: inout Set<String>
    ) {
        guard let contents = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            return
        }

        for fileURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let fileName = fileURL.lastPathComponent
            if fileName == ".DS_Store" {
                continue
            }

            let relativePath = basePath.isEmpty ? fileName : "\(basePath)/\(fileName)"

            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
                walkFolder(fileURL, fileManager: fileManager, basePath: relativePath, into: &files)
            } else {
                files.insert(relativePath)
            }
        }
    }
}
