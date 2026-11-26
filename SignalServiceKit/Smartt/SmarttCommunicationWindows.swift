import Foundation
public import LibSignalClient

/// The user's communication windows, local-first like Signal's notification profiles: changes are
/// saved on the device at once and pushed to our server in the background, so the screens never
/// wait for the network. The iOS counterpart of Android's `CommunicationWindowsRepository`.
public final class SmarttCommunicationWindows {
    public static let shared = SmarttCommunicationWindows()

    public let store = SmarttCommunicationWindowStore()
    private let api = SmarttCommunicationWindowAPI()

    private init() {}

    private var db: any DB { DependenciesBridge.shared.db }

    public func windows() -> [SmarttCommunicationWindow] {
        return db.read { tx in store.windows(tx: tx) }
    }

    public func window(windowId: String) -> SmarttCommunicationWindow? {
        return db.read { tx in store.window(windowId: windowId, tx: tx) }
    }

    /// Creates or updates a window. It's saved on the device right away and pushed in the
    /// background; a failed push is retried by the next sync.
    public func save(_ window: SmarttCommunicationWindow) async {
        await db.awaitableWrite { tx in store.upsert(window, needsSync: true, tx: tx) }
        Task { await self.push(window) }
    }

    /// Deletes a window on the device, remembers the delete, and deletes it on the server in the
    /// background. If the server delete fails, every later sync retries it until the server
    /// confirms it, so the server stops holding messages for the window.
    public func delete(windowId: String) async {
        await db.awaitableWrite { tx in store.deleteAndRememberDelete(windowId: windowId, tx: tx) }
        Task { await self.pushDelete(windowId: windowId) }
    }

    /// Pushes pending deletes, then local changes, then pulls the server's windows; in that order,
    /// so a pull can't overwrite an edit still waiting to be pushed. On a fresh install there is
    /// nothing to push, so this is what brings the windows back. Does nothing until the account is
    /// registered.
    public func syncAll() {
        guard isRegistered() else { return }
        Task {
            await self.pushPending()
            do {
                try await self.pull()
            } catch {
                Logger.warn("Couldn't pull windows; the local ones may be stale: \(error)")
            }
        }
    }

    /// Pushes pending deletes, then the windows whose changes haven't reached the server yet.
    public func syncPending() {
        guard isRegistered() else { return }
        Task { await self.pushPending() }
    }

    /// The window `recipient` has active for the local user, as the server reports it.
    public func windowMetadata(for recipient: ServiceId) async throws -> SmarttWindowMetadata {
        return try await api.windowMetadata(for: recipient)
    }

    private func isRegistered() -> Bool {
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            Logger.info("Not registered yet; skipping window sync")
            return false
        }
        return true
    }

    private func push(_ window: SmarttCommunicationWindow) async {
        do {
            try await api.putWindow(window)
            await db.awaitableWrite { tx in store.markSynced(window, tx: tx) }
        } catch {
            Logger.warn("Couldn't push window \(window.windowId); the next sync retries: \(error)")
        }
    }

    /// Clears the pending delete once the server has deleted the window, or answered that it had
    /// none (`deleteWindow` treats the server's 404 as done). Otherwise the next sync retries it.
    private func pushDelete(windowId: String) async {
        do {
            try await api.deleteWindow(windowId: windowId)
            await db.awaitableWrite { tx in store.clearPendingDelete(windowId: windowId, tx: tx) }
        } catch {
            Logger.warn("Couldn't delete window \(windowId) on the server; the next sync retries: \(error)")
        }
    }

    private func pushPending() async {
        let pendingDeletes = db.read { tx in store.pendingDeletes(tx: tx) }
        for windowId in pendingDeletes.sorted() {
            await pushDelete(windowId: windowId)
        }
        let pending = db.read { tx in store.windowsNeedingSync(tx: tx) }
        for window in pending {
            await push(window)
        }
    }

    /// Makes the device mirror the server: windows deleted on another device, or on the server, are
    /// removed here too. Two exceptions: windows with changes not pushed yet are left alone (a new
    /// window must survive a pull that runs before its first push), and a window whose delete is
    /// still pending isn't brought back. Throws, changing nothing, when the server can't be reached.
    private func pull() async throws {
        let remoteWindows = try await api.listWindows()
        let remoteIds = Set(remoteWindows.map(\.windowId))
        await db.awaitableWrite { tx in
            let pendingDeletes = store.pendingDeletes(tx: tx)
            for window in remoteWindows where !pendingDeletes.contains(window.windowId) {
                store.upsertFromServerIfNotPending(window, tx: tx)
            }
            for window in store.windows(tx: tx) where !remoteIds.contains(window.windowId) {
                store.deleteIfNotPending(windowId: window.windowId, tx: tx)
            }
        }
    }
}
