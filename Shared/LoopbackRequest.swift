import Foundation

/// A local client protocol, not an HTTP endpoint intended for websites.
struct LoopbackRequest {
    let path: String
    let command: WidgetCommand?
    let documentID: String?
    let videoID: String?

    init?(_ raw: String) {
        guard raw.utf8.count <= 8192, raw.contains("\r\n\r\n") else { return nil }
        let lines = raw.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count == 3, parts[2] == "HTTP/1.1", parts[1].hasPrefix("/"),
              let components = URLComponents(string: String(parts[1])), components.host == nil else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon].lowercased()
            guard headers[name] == nil else { return nil }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["host"] == "127.0.0.1:\(Loopback.port)",
              headers["origin"] == nil, headers["referer"] == nil,
              headers["sec-fetch-site"] == nil else { return nil }
        path = components.path
        let ids = (components.queryItems ?? []).filter { $0.name == "document" }
        guard ids.count <= 1 else { return nil }
        documentID = ids.first?.value
        let videos = (components.queryItems ?? []).filter { $0.name == "video" }
        guard videos.count <= 1 else { return nil }
        videoID = videos.first?.value
        if let videoID, UUID(uuidString: videoID) == nil, videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) == nil { return nil }
        if let documentID, UUID(uuidString: documentID) == nil { return nil }
        if path.hasPrefix("/cmd/") {
            guard parts[0] == "POST", let parsed = WidgetCommand(rawValue: String(path.dropFirst(5))) else { return nil }
            command = parsed
        } else {
            guard parts[0] == "GET", path == "/state" || path == "/artwork" else { return nil }
            command = nil
        }
    }
}
