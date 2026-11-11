/// Connection-scoped identity pinning for the opt-in trusted direct channel.
/// Once a peer changes its claimed identity, quarantine it until disconnect.
/// Existing games' legacy identity handling is deliberately unaffected.
struct GameRoomDirectIdentity<Peer: Hashable> {
    private var identities: [Peer: String] = [:]
    private var rejected = Set<Peer>()

    mutating func bind(_ peer: Peer, to identity: String, localID: String) {
        guard !rejected.contains(peer) else { return }
        guard !identity.isEmpty, identity != localID,
              !identities.contains(where: { $0.key != peer && $0.value == identity }),
              identities[peer] == nil || identities[peer] == identity else {
            // Reserve any original identity until this connection ends.
            rejected.insert(peer)
            return
        }
        identities[peer] = identity
    }

    func identity(for peer: Peer) -> String? { rejected.contains(peer) ? nil : identities[peer] }
    mutating func remove(_ peer: Peer) {
        identities.removeValue(forKey: peer)
        rejected.remove(peer)
    }
    mutating func removeAll() { identities.removeAll(); rejected.removeAll() }
}
