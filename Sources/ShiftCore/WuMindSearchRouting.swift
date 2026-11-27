import Foundation

/// Selects the search connection independently of the selected chat model. A personal
/// search failure is never permission to send that query to a billable gateway.
public enum WuMindSearchRouting {
    public enum Route: Equatable, Sendable {
        case personal
        case gateway
        case unavailable
    }

    public enum Choice: Equatable, Sendable {
        case tryGateway
        case continueOffline
        case cancel
    }

    public struct Decision: Equatable, Sendable {
        public let shouldAsk: Bool
        public let offerGateway: Bool
    }

    public static func firstRoute(usesOwnChat: Bool, hasPersonalKey: Bool, hasGatewaySession: Bool) -> Route {
        if usesOwnChat && hasPersonalKey { return .personal }
        if hasGatewaySession { return .gateway }
        return .unavailable
    }

    public static func decision(hasSearchEvidence: Bool, route: Route, gatewayReady: Bool) -> Decision {
        .init(shouldAsk: !hasSearchEvidence, offerGateway: !hasSearchEvidence && route == .personal && gatewayReady)
    }
}
