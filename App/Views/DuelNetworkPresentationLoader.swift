import Foundation

/// Room-owned lifecycle seam. Synthetic test implementations never manufacture a
/// production identity; the shipping room initializer always uses prepare(bundle:).
@MainActor
protocol DuelNetworkRoomLoading: AnyObject, Sendable {
    var pendingPreparation: DuelNetworkMatchPreparation? { get }
    var isClosed: Bool { get }
    var didChange: (@MainActor () -> Void)? { get set }
    func makeCoordinator(transport: any DuelLobbyTransport) throws -> DuelNetworkCombatCoordinator
    func cancel()
}

/// Retains preflight's exact objects through committed mount and terminal close.
/// Construction does not start transport, construct a session or report GPU readiness.
@MainActor
final class DuelNetworkPresentationLoader: DuelNetworkRoomLoading {
    enum Failure: Error { case closed, alreadyUsed, configurationChanged, unverifiedMount }
    private var prepared: DuelNetworkPreparedResources?
    private var configuration: DuelNetworkStartBarrier.Configuration?
    private var token: UUID? = UUID()
    private var issuedCoordinator = false
    private var issuedResources = false
    private var issuedPresentation = false
    private(set) var pendingPreparation: DuelNetworkMatchPreparation?
    private(set) var isClosed = false
    var didChange: (@MainActor () -> Void)?

    init(prepared: DuelNetworkPreparedResources) { self.prepared = prepared }

    func makeCoordinator(transport: any DuelLobbyTransport) throws -> DuelNetworkCombatCoordinator {
        guard !isClosed, let prepared, prepared.hasExactResources else { throw Failure.closed }
        guard !issuedCoordinator else { throw Failure.alreadyUsed }
        issuedCoordinator = true
        return DuelNetworkCombatCoordinator(transport: transport, verified: prepared.identity,
            loader: { [weak self] configuration, completion in
                guard let self else { completion(.failure(Failure.closed)); return }
                self.load(configuration, completion: completion)
            }, cancelLoading: { [weak self] in self?.cancel() })
    }

    private func load(_ configuration: DuelNetworkStartBarrier.Configuration,
                      completion: @escaping DuelNetworkCombatCoordinator.Completion) {
        guard !isClosed, let prepared, prepared.hasExactResources else {
            completion(.failure(Failure.closed)); return
        }
        guard !issuedResources else { completion(.failure(Failure.alreadyUsed)); return }
        issuedResources = true; self.configuration = configuration
        // These bytes/objects were synchronously verified before transport began.
        // The core checks the full offered configuration against this exact catalog.
        let resources = DuelNetworkCombatCoordinator.Resources(verified: prepared.identity,
            makePresentation: { [weak self] barrier, callback in
                guard let self else { callback(.failure(Failure.closed)); return }
                self.mount(barrier, completion: callback)
            }, release: { [weak self] in self?.cancel() })
        completion(.success(resources))
    }

    private func mount(_ barrier: DuelNetworkStartBarrier,
                       completion: @escaping DuelNetworkCombatCoordinator.PresentationCompletion) {
        guard !isClosed, let token, let prepared, prepared.hasExactResources else {
            completion(.failure(Failure.closed)); return
        }
        guard !issuedPresentation else { completion(.failure(Failure.alreadyUsed)); return }
        guard let configuration, barrier.committedConfiguration == configuration else {
            completion(.failure(Failure.configurationChanged)); return
        }
        issuedPresentation = true
        do {
            let session = try DuelSession.networkPresentation(committed: barrier, prepared: prepared)
            let mount = try DuelNetworkMatchPreparation(session: session, prepared: prepared,
                invalidated: { [weak self] _ in self?.cancel() }) { [weak self, weak session] result in
                    guard let self, let session, !self.isClosed, self.token == token,
                          self.pendingPreparation?.session === session else { return }
                    switch result {
                    case .failure(let error): completion(.failure(error))
                    case .success(let receipt):
                        guard receipt.owner == self.pendingPreparation?.id,
                              receipt.initialScenePrepared, receipt.runtimeEffectVariantsPrepared,
                              receipt.controlsPrepared, receipt.verifiedResourceOwnershipComplete,
                              self.prepared?.hasExactResources == true, session.hasLiveVerifiedResources else {
                            completion(.failure(Failure.unverifiedMount)); self.cancel(); return
                        }
                        completion(.success(session))
                    }
                }
            guard !isClosed, self.token == token else { mount.cancel(); return }
            // Publish the committed, PAUSED session before GPU/control readiness.
            // Waiting on coordinator.presentation here would deadlock the mount.
            pendingPreparation = mount
            didChange?()
        } catch {
            completion(.failure(error))
            cancel()
        }
    }

    func cancel() {
        guard !isClosed else { return }
        isClosed = true; token = nil; configuration = nil
        let mount = pendingPreparation, resources = prepared
        pendingPreparation = nil; prepared = nil
        mount?.cancel(); resources?.release()
        didChange?()
    }
}
