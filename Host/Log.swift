import Foundation

/// Append-only diagnostic log at ~/Library/Logs/MacMusicWidget.log.
/// Only failures are written, so it stays small.
enum Log {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        return dir.appendingPathComponent("MacMusicWidget.log")
    }()

    private static let queue = DispatchQueue(label: "ytm.log")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static var lastMessage = ""

    /// The poll loop runs once a second, so a persistent failure would otherwise write the
    /// same entry 3,600 times an hour. Only transitions are interesting.
    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n\n"
        queue.async {
            guard message != lastMessage else { return }
            lastMessage = message
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
