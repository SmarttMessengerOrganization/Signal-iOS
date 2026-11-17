import Foundation

/// The user's sent messages that the recipient's communication window is holding on the server, in
/// Signal's key-value store: collection `SmarttHeldMessages`, keyed by the message's unique ID, with
/// the time the window opens (epoch ms). The iOS counterpart of Android's `SmarttWindowHeldTable` and
/// `SmarttWindowHeldCache`. A held message shows a cloud until it's delivered.
public final class SmarttHeldMessages {
    public static let shared = SmarttHeldMessages()

    private let kvStore = KeyValueStore(collection: "SmarttHeldMessages")

    /// Entries are dropped this long after their window opened; by then the message has been delivered.
    private static let maxAgeMs: UInt64 = 7 * 24 * 60 * 60 * 1000

    private init() {}

    /// Records `message` as held when the server's answer to its send says so. As on Android, only
    /// one-to-one messages that show in the chat are recorded.
    func recordIfHeld(message: TSOutgoingMessage, thread: TSThread, response: HTTPResponse) async {
        guard thread is TSContactThread, message.shouldBeSaved else { return }
        guard
            let data = response.responseBodyData,
            let body = try? JSONDecoder().decode(SendResponse.self, from: data),
            body.communicationWindowHeld == true
        else {
            return
        }
        let now = Self.nowMs()
        let windowOpensAt = body.windowOpensAt ?? now
        let uniqueId = message.uniqueId
        await DependenciesBridge.shared.db.awaitableWrite { tx in
            self.removeOldEntries(nowMs: now, tx: tx)
            self.kvStore.setUInt64(windowOpensAt, key: uniqueId, transaction: tx)
        }
        Logger.info("Message \(message.timestamp) is held by the recipient's communication window until \(windowOpensAt)")
    }

    public func isHeld(_ message: TSOutgoingMessage, tx: DBReadTransaction) -> Bool {
        return kvStore.hasValue(message.uniqueId, transaction: tx)
    }

    private func removeOldEntries(nowMs: UInt64, tx: DBWriteTransaction) {
        let cutoff = nowMs > Self.maxAgeMs ? nowMs - Self.maxAgeMs : 0
        let oldKeys = kvStore.allKeys(transaction: tx).filter { key in
            (kvStore.getUInt64(key, transaction: tx) ?? 0) < cutoff
        }
        kvStore.removeValues(forKeys: oldKeys, transaction: tx)
    }

    private static func nowMs() -> UInt64 {
        return UInt64(Date().timeIntervalSince1970 * 1000)
    }

    /// The fields our server adds to the send response (`SmarttSendMessageResponse`).
    private struct SendResponse: Decodable {
        let communicationWindowHeld: Bool?
        let windowOpensAt: UInt64?
    }
}
