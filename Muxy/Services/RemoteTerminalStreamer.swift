import Foundation
import GhosttyKit
import MuxyServer
import MuxyShared

@MainActor
final class RemoteTerminalStreamer {
    static let shared = RemoteTerminalStreamer()

    weak var server: MuxyRemoteServer?

    private var paneByToken: [Int: UUID] = [:]
    private var tokenByPane: [UUID: Int] = [:]
    private var nextToken: Int = 1

    private init() {}

    func attach(paneID: UUID, surface: ghostty_surface_t) {
        if tokenByPane[paneID] != nil { return }
        let token = nextToken
        nextToken += 1
        tokenByPane[paneID] = token
        paneByToken[token] = paneID
        RemotePaneOwnershipCache.shared.registerToken(token, paneID: paneID)
        let isOwned = PaneOwnershipStore.shared.remoteOwner(for: paneID) != nil
        RemotePaneOwnershipCache.shared.setOwned(paneID: paneID, owned: isOwned)
        ghostty_surface_set_data_callback(
            surface,
            ptyDataCallback,
            UnsafeMutableRawPointer(bitPattern: UInt(token))
        )
    }

    func detach(paneID: UUID, surface: ghostty_surface_t) {
        ghostty_surface_set_data_callback(surface, nil, nil)
        if let token = tokenByPane.removeValue(forKey: paneID) {
            paneByToken.removeValue(forKey: token)
            RemotePaneOwnershipCache.shared.unregisterToken(token)
            RemotePaneOwnershipCache.shared.removePane(paneID)
        }
    }

    func updateOwnership(paneID: UUID, hasRemoteOwner: Bool) {
        RemotePaneOwnershipCache.shared.setOwned(paneID: paneID, owned: hasRemoteOwner)
    }

    fileprivate func pane(for token: Int) -> UUID? {
        paneByToken[token]
    }

    fileprivate func forward(paneID: UUID, bytes: Data) {
        guard let clientID = PaneOwnershipStore.shared.remoteOwner(for: paneID) else { return }
        let event = MuxyEvent(
            event: .terminalOutput,
            data: .terminalOutput(TerminalOutputEventDTO(paneID: paneID, bytes: bytes))
        )
        server?.send(event, to: clientID)
    }
}

final class RemotePaneOwnershipCache: @unchecked Sendable {
    static let shared = RemotePaneOwnershipCache()

    private let lock = NSLock()
    private var ownedPanes: Set<UUID> = []
    private var tokenToPane: [Int: UUID] = [:]

    private init() {}

    func setOwned(paneID: UUID, owned: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if owned {
            ownedPanes.insert(paneID)
        } else {
            ownedPanes.remove(paneID)
        }
    }

    func registerToken(_ token: Int, paneID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        tokenToPane[token] = paneID
    }

    func unregisterToken(_ token: Int) {
        lock.lock()
        defer { lock.unlock() }
        tokenToPane.removeValue(forKey: token)
    }

    func removePane(_ paneID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        ownedPanes.remove(paneID)
        if let token = tokenToPane.first(where: { $0.value == paneID })?.key {
            tokenToPane.removeValue(forKey: token)
        }
    }

    func paneIfOwned(token: Int) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard let paneID = tokenToPane[token], ownedPanes.contains(paneID) else { return nil }
        return paneID
    }
}

private let ptyDataCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, UInt) -> Void = { userdata, ptr, len in
    guard let userdata,
          let ptr,
          len > 0
    else { return }
    let token = Int(bitPattern: userdata)
    guard let paneID = RemotePaneOwnershipCache.shared.paneIfOwned(token: token) else { return }
    let bytes = Data(bytes: ptr, count: Int(len))
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            RemoteTerminalStreamer.shared.forward(paneID: paneID, bytes: bytes)
        }
    }
}
