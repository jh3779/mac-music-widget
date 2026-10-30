import Foundation
import Network

/// A deliberately tiny HTTP/1.1 server bound to loopback only.
///
/// This exists because a widget extension is sandboxed: it cannot send Apple Events, so it can't
/// read YouTube Music itself. It *can* make outgoing connections, so the host publishes state
/// here and accepts commands back. Binding to 127.0.0.1 keeps it off the network entirely.
final class HTTPServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ytm.http")

    /// Returns the current state as JSON.
    var provideState: (() -> Data)?
    /// Cover art bytes for sources that hand over data instead of a URL (Apple Music).
    var provideArtwork: (() -> Data?)?
    /// Handles a command and returns once it has been dispatched.
    var handleCommand: ((WidgetCommand, String?) -> Void)?

    func start() {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: Loopback.port)!) else {
            Log.write("http: could not bind port \(Loopback.port)")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { Log.write("http: listener failed \(error)") }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHeaders(connection, accumulated: Data())
    }

    private func receiveHeaders(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self, let data, error == nil else { connection.cancel(); return }
            let bytes = accumulated + data
            guard bytes.count <= 8192 else { connection.cancel(); return }
            guard let raw = String(data: bytes, encoding: .utf8), raw.contains("\r\n\r\n") else {
                if complete { connection.cancel() }
                else { self.receiveHeaders(connection, accumulated: bytes) }
                return
            }
            let response = self.respond(to: raw)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func respond(to raw: String) -> Data {
        guard let request = LoopbackRequest(raw) else { return Self.notFound }
        if request.path == "/state" {
            return Self.ok(body: provideState?() ?? Data("{}".utf8), contentType: "application/json")
        }
        if request.path == "/artwork" {
            guard let art = provideArtwork?() else { return Self.notFound }
            return Self.ok(body: art, contentType: "image/png")
        }
        if let command = request.command {
            handleCommand?(command, request.documentID)
            return Self.ok(body: Data("{\"ok\":true}".utf8), contentType: "application/json")
        }
        return Self.notFound
    }

    private static func ok(body: Data, contentType: String) -> Data {
        var head = "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    private static var notFound: Data {
        Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }
}
