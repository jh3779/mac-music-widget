import Foundation
import CoreFoundation

enum WebMediaError: Error { case invalidMessage, unavailableContainer }

/// Only the minimal metadata needed by the widget crosses the native boundary.
struct WebMediaSnapshot: Codable, Equatable {
    static let lifetime: TimeInterval = 45
    let tabID: Int
    let videoID: String
    let title: String
    let author: String
    let isPlaying: Bool
    let documentID: String
    let canGoNext: Bool
    let canGoPrevious: Bool
    let receivedAt: Date
    var changedAt: Date

    var artworkURL: String { "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg" }
    var expiresAt: Date { receivedAt.addingTimeInterval(Self.lifetime) }

    static func validTabID(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0,
              number.doubleValue <= Double(Int32.max),
              number.doubleValue.rounded() == number.doubleValue else { return nil }
        return number.intValue
    }

    static func decode(_ message: [String: Any], now: Date = Date()) throws -> Self {
        guard validTabID(message["version"]) == 1,
              let tabID = validTabID(message["tabID"]),
              let videoID = message["videoID"] as? String,
              videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil,
              let rawTitle = message["title"] as? String, rawTitle.count <= 512,
              let author = message["author"] as? String, author.count <= 256,
              let playing = message["isPlaying"] as? NSNumber,
              CFGetTypeID(playing) == CFBooleanGetTypeID(),
              let documentID = message["documentID"] as? String, UUID(uuidString: documentID) != nil,
              let next = message["canGoNext"] as? NSNumber, CFGetTypeID(next) == CFBooleanGetTypeID(),
              let previous = message["canGoPrevious"] as? NSNumber, CFGetTypeID(previous) == CFBooleanGetTypeID() else { throw WebMediaError.invalidMessage }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw WebMediaError.invalidMessage }
        // The thumbnail URL is constructed here; web content cannot supply arbitrary fetch URLs.
        return Self(tabID: tabID, videoID: videoID, title: title, author: author,
                    isPlaying: playing.boolValue, documentID: documentID, canGoNext: next.boolValue, canGoPrevious: previous.boolValue, receivedAt: now, changedAt: now)
    }

    static func select(_ snapshots: [Self], now: Date = Date()) -> Self? {
        snapshots.filter { $0.receivedAt <= now && $0.expiresAt > now }.sorted {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
            if $0.changedAt != $1.changedAt { return $0.changedAt > $1.changedAt }
            return $0.tabID < $1.tabID
        }.first
    }
}

/// One atomic file per Safari profile/tab avoids read-modify-write races across tabs.
/// The extension is the writer; the host only reads. There is no browsing-history log.
struct WebMediaStore {
    let directory: URL

    static func configured(bundle: Bundle = .main) -> Self? {
        guard let group = bundle.object(forInfoDictionaryKey: "MediaAppGroup") as? String,
              !group.isEmpty, !group.contains("$("),
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return Self(directory: root.appendingPathComponent("SafariMedia", isDirectory: true))
    }

    private func file(tabID: Int, profile: String) throws -> URL {
        guard tabID >= 0, tabID <= Int32.max,
              profile == "default" || UUID(uuidString: profile) != nil else { throw WebMediaError.invalidMessage }
        return directory.appendingPathComponent("\(profile)-\(tabID).json")
    }

    func save(_ snapshot: WebMediaSnapshot, profile: String) throws {
        let url = try file(tabID: snapshot.tabID, profile: profile)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var next = snapshot
        if let previous = read(url), previous.expiresAt > snapshot.receivedAt,
           previous.videoID == next.videoID, previous.documentID == next.documentID, previous.isPlaying == next.isPlaying {
            next.changedAt = previous.changedAt
        }
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        // Bound retained data after a Safari crash (tab-closed events may never arrive).
        for candidate in files() where candidate != url {
            if let item = read(candidate), item.expiresAt <= snapshot.receivedAt {
                try? FileManager.default.removeItem(at: candidate)
            }
        }
    }

    func remove(tabID: Int, profile: String) throws {
        let url = try file(tabID: tabID, profile: profile)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func enqueue(_ action: SafariCommand.Action, for snapshot: WebMediaSnapshot, now: Date = Date()) throws {
        guard snapshot.expiresAt > now else { throw WebMediaError.invalidMessage }
        let folder = directory.appendingPathComponent("Commands", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let command = SafariCommand(id: UUID().uuidString, action: action, tabID: snapshot.tabID,
                                    documentID: snapshot.documentID, videoID: snapshot.videoID,
                                    expiresAt: now.addingTimeInterval(8))
        let url = try commandFile(snapshot.documentID)
        // One pending action per document: rapid clicks coalesce instead of replaying toggles later.
        try JSONEncoder().encode(command).write(to: url, options: .atomic)
    }

    func takeCommand(for snapshot: WebMediaSnapshot, now: Date = Date()) -> SafariCommand? {
        guard let url = try? commandFile(snapshot.documentID),
              let data = try? Data(contentsOf: url), data.count <= 4096,
              let command = try? JSONDecoder().decode(SafariCommand.self, from: data),
              command.tabID == snapshot.tabID, command.documentID == snapshot.documentID else { return nil }
        try? FileManager.default.removeItem(at: url)
        guard command.expiresAt > now, command.videoID == snapshot.videoID else { return nil }
        return command
    }

    private func commandFile(_ documentID: String) throws -> URL {
        guard UUID(uuidString: documentID) != nil else { throw WebMediaError.invalidMessage }
        return directory.appendingPathComponent("Commands", isDirectory: true).appendingPathComponent(documentID + ".json")
    }

    func snapshots(now: Date = Date()) -> [WebMediaSnapshot] {
        files().compactMap(read).filter { $0.receivedAt <= now && $0.expiresAt > now }
    }

    private func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
    }

    private func read(_ url: URL) -> WebMediaSnapshot? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 8192, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WebMediaSnapshot.self, from: data) else { return nil }
        return snapshot
    }
}

struct SafariCommand: Codable {
    enum Action: String, Codable { case playPause, next, previous, pause }
    let id: String
    let action: Action
    let tabID: Int
    let documentID: String
    let videoID: String
    let expiresAt: Date
}
