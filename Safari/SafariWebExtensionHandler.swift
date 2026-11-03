import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    // File operations from native requests are serialized within this extension process.
    private static let queue = DispatchQueue(label: "safari.media.native")

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let profile = (item?.userInfo?[SFExtensionProfileKey] as? UUID)?.uuidString ?? "default"
        Self.queue.async {
            var response: [String: Any] = ["ok": true]
            do {
                guard let message,
                      JSONSerialization.isValidJSONObject(message),
                      try JSONSerialization.data(withJSONObject: message).count <= 8192,
                      WebMediaSnapshot.validTabID(message["version"]) == 1 else {
                    throw WebMediaError.invalidMessage
                }
                guard let store = WebMediaStore.configured() else {
                    throw WebMediaError.unavailableContainer
                }
                switch message["kind"] as? String {
                case "ping":
                    try store.recordPing(profile: profile)
                    response["connectionState"] = store.connectionState().rawValue
                case "clear":
                    guard let tabID = WebMediaSnapshot.validTabID(message["tabID"]) else {
                        throw WebMediaError.invalidMessage
                    }
                    if let source = message["source"], !(source is String) { throw WebMediaError.invalidMessage }
                    try store.remove(tabID: tabID, profile: profile, source: message["source"] as? String)
                case "snapshot":
                    let snapshot = try WebMediaSnapshot.decode(message)
                    try store.save(snapshot, profile: profile)
                    if let command = store.takeCommand(for: snapshot) {
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .secondsSince1970
                        response["command"] = try JSONSerialization.jsonObject(with: encoder.encode(command))
                    }
                default: throw WebMediaError.invalidMessage
                }
            } catch {
                let state: MediaConnectionState = (error as? WebMediaError) == .unavailableContainer ? .configurationRequired : .reconnectPage
                response = ["ok": false, "connectionState": state.rawValue, "error": state.message]
            }
            response["appURL"] = HostAppLink.url(.open, extensionIdentifier: Bundle.main.bundleIdentifier)?.absoluteString
            response["settingsURL"] = HostAppLink.url(.safariSettings, extensionIdentifier: Bundle.main.bundleIdentifier)?.absoluteString
            let reply = NSExtensionItem()
            reply.userInfo = [SFExtensionMessageKey: response]
            context.completeRequest(returningItems: [reply], completionHandler: nil)
        }
    }
}
