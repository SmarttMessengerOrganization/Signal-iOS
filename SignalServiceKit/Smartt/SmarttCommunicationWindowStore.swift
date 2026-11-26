import Foundation

extension Notification.Name {
    /// Posted on the main thread after the local windows change.
    public static let smarttCommunicationWindowsDidChange = Notification.Name("SmarttCommunicationWindowsDidChange")
}

/// The windows saved on the device, in Signal's key-value store: collection
/// `SmarttCommunicationWindows`, one entry per window ID. The iOS counterpart of Android's
/// `SmarttCommunicationWindowsTable`.
public struct SmarttCommunicationWindowStore {
    private struct Record: Codable {
        var window: SmarttCommunicationWindow
        /// The window has local changes that haven't reached our server yet.
        var needsSync: Bool
        /// Keeps the windows in the order they were added.
        var createdAt: Date
    }

    private let kvStore = KeyValueStore(collection: "SmarttCommunicationWindows")

    /// IDs of windows deleted on the device whose delete the server hasn't confirmed yet: collection
    /// `SmarttPendingWindowDeletes`, one entry per window ID. Every sync retries them, and a pull
    /// doesn't bring them back.
    private let pendingDeletesStore = KeyValueStore(collection: "SmarttPendingWindowDeletes")

    public init() {}

    public func windows(tx: DBReadTransaction) -> [SmarttCommunicationWindow] {
        return loadRecords(tx: tx).map(\.window)
    }

    public func window(windowId: String, tx: DBReadTransaction) -> SmarttCommunicationWindow? {
        return loadRecord(windowId: windowId, tx: tx)?.window
    }

    public func windowsNeedingSync(tx: DBReadTransaction) -> [SmarttCommunicationWindow] {
        return loadRecords(tx: tx).filter(\.needsSync).map(\.window)
    }

    func upsert(_ window: SmarttCommunicationWindow, needsSync: Bool, tx: DBWriteTransaction) {
        let createdAt = loadRecord(windowId: window.windowId, tx: tx)?.createdAt ?? Date()
        save(Record(window: window, needsSync: needsSync, createdAt: createdAt), tx: tx)
        notifyChange(tx: tx)
    }

    /// Clears the needs-sync flag, unless the window changed again after `pushed` was sent.
    func markSynced(_ pushed: SmarttCommunicationWindow, tx: DBWriteTransaction) {
        guard var record = loadRecord(windowId: pushed.windowId, tx: tx), record.needsSync, record.window == pushed else {
            return
        }
        record.needsSync = false
        save(record, tx: tx)
    }

    /// Removes a window the user deleted and remembers the delete until the server confirms it.
    func deleteAndRememberDelete(windowId: String, tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: windowId, transaction: tx)
        pendingDeletesStore.setBool(true, key: windowId, transaction: tx)
        notifyChange(tx: tx)
    }

    /// Removes a window the server no longer has, unless it has changes not pushed yet.
    func deleteIfNotPending(windowId: String, tx: DBWriteTransaction) {
        guard let record = loadRecord(windowId: windowId, tx: tx), !record.needsSync else {
            return
        }
        kvStore.removeValue(forKey: windowId, transaction: tx)
        notifyChange(tx: tx)
    }

    /// Writes the server's copy of a window, unless it has changes not pushed yet.
    func upsertFromServerIfNotPending(_ window: SmarttCommunicationWindow, tx: DBWriteTransaction) {
        if let record = loadRecord(windowId: window.windowId, tx: tx), record.needsSync {
            return
        }
        upsert(window, needsSync: false, tx: tx)
    }

    func pendingDeletes(tx: DBReadTransaction) -> Set<String> {
        return Set(pendingDeletesStore.allKeys(transaction: tx))
    }

    func clearPendingDelete(windowId: String, tx: DBWriteTransaction) {
        pendingDeletesStore.removeValue(forKey: windowId, transaction: tx)
    }

    private func save(_ record: Record, tx: DBWriteTransaction) {
        do {
            try kvStore.setCodable(record, key: record.window.windowId, transaction: tx)
        } catch {
            owsFailDebug("Couldn't save window \(record.window.windowId): \(error)")
        }
    }

    private func loadRecord(windowId: String, tx: DBReadTransaction) -> Record? {
        do {
            return try kvStore.getCodableValue(forKey: windowId, transaction: tx)
        } catch {
            return nil
        }
    }

    private func loadRecords(tx: DBReadTransaction) -> [Record] {
        let result: [Record]
        do {
            result = try kvStore.allCodableValues(transaction: tx)
        } catch {
            owsFailDebug("Couldn't read windows: \(error)")
            return []
        }
        return result.sorted { $0.createdAt < $1.createdAt }
    }

    private func notifyChange(tx: DBWriteTransaction) {
        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .smarttCommunicationWindowsDidChange, object: nil)
        }
    }
}
