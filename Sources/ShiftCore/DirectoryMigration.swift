import Foundation

/// Move an owned directory without merging or discarding an existing directory.
/// A failed or interrupted legacy migration may leave both locations populated;
/// keep both copies until the conflict can be resolved explicitly.
public enum DirectoryMigration {
    public enum Failure: LocalizedError {
        case destinationContainsFiles

        public var errorDescription: String? {
            "另一个存储位置已有文件，已保留两边的内容，未覆盖或删除。"
        }
    }

    public static func move(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let sourceIsEmpty = try fm.contentsOfDirectory(atPath: source.path).isEmpty
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue && sourceIsEmpty {
                // A leftover empty old directory is not a second data set.
                // Keep the populated current location available on startup.
                try fm.removeItem(at: source)
                return
            }
            guard isDirectory.boolValue,
                  try fm.contentsOfDirectory(atPath: destination.path).isEmpty else {
                throw Failure.destinationContainsFiles
            }
            // Only an empty directory may be removed. Never remove the source
            // after individual move attempts: one failed move would lose data.
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: source, to: destination)
    }
}
