import AppKit

enum SSTLLog {
    private static let lock = NSLock()
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Screenshots Timelapse.log")

    static func revealInFinder() {
        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logURL])
        } else {
            NSWorkspace.shared.open(logURL.deletingLastPathComponent())
        }
    }

    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Past 1 MB the log becomes "….old.log", replacing the previous one, so it never grows without bound.
            let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
            if size > 1_000_000 {
                let old = logURL.deletingPathExtension().appendingPathExtension("old.log")
                try? FileManager.default.removeItem(at: old)
                try FileManager.default.moveItem(at: logURL, to: old)
            }
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: logURL, options: .atomic)
            }
        } catch {
            NSLog("SSTL log write failed: %@", error.localizedDescription)
        }
    }
}
