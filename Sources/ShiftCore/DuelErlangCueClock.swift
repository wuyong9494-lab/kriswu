/// H17-inspired isolated clock fixture. This is not a D15 source table and
/// contains no original motion-to-effect values.
public struct DuelErlangCueClock: Equatable, Sendable {
    public enum Position: Equatable, Sendable {
        /// An ordinary event's source-reported Frame is already zero-based.
        case frame(Int)
        /// This named interval-start representation is one-based.
        case intervalStart(Int)
        /// Animation start, irrespective of any crop.
        case animationStart

        fileprivate var sourceSample: Int? {
            switch self {
            case .frame(let n): return n >= 0 ? n : nil
            case .intervalStart(let n): return n > 0 ? n - 1 : nil
            case .animationStart: return 0
            }
        }
    }
    public enum CropOrigin: Equatable, Sendable {
        case untrimmed
        case known(firstSourceSample: Int)
        case unknown

        fileprivate var firstSample: Int? {
            switch self {
            case .untrimmed: return 0
            case .known(let n): return n >= 0 ? n : nil
            case .unknown: return nil
            }
        }
    }

    public enum Presentation: Equatable, Sendable { case cast, sound, visualEffect }
    public struct Marker: Equatable, Sendable {
        public let id: String
        public let position: Position
        public let presentation: Presentation
        public init(id: String, at position: Position, presentation: Presentation) {
            self.id = id
            self.position = position
            self.presentation = presentation
        }
    }
    public enum Event: Equatable, Sendable {
        case presentation(id: String, channel: Presentation, sourceSample: Int)
        /// Only the authoritative collision system may record this event.
        case gameplayHit(id: String, simulationTick: Int)
    }
    public enum ConfigurationError: Error, Equatable, Sendable {
        case invalidOrigin, invalidMarkerID, duplicateMarkerID, invalidMarkerPosition
    }
    private struct Scheduled: Equatable, Sendable {
        let id: String
        let sample: Int
        let presentation: Presentation
    }

    public let origin: CropOrigin
    private let markers: [Scheduled]
    private var nextMarker = 0
    private var lastVisibleSample = -1
    private var observedHitIDs: Set<String> = []

    public init(origin: CropOrigin, markers: [Marker]) throws {
        if case .known(let n) = origin, n < 0 { throw ConfigurationError.invalidOrigin }
        var ids: Set<String> = []
        let schedule = try markers.map { marker -> Scheduled in
            guard !marker.id.isEmpty else { throw ConfigurationError.invalidMarkerID }
            guard ids.insert(marker.id).inserted else { throw ConfigurationError.duplicateMarkerID }
            guard let sample = marker.position.sourceSample else { throw ConfigurationError.invalidMarkerPosition }
            return .init(id: marker.id, sample: sample, presentation: marker.presentation)
        }
        self.origin = origin
        // Authored order is preserved for simultaneous cues.
        self.markers = schedule.enumerated().sorted {
            $0.element.sample == $1.element.sample ? $0.offset < $1.offset : $0.element.sample < $1.element.sample
        }.map(\.element)
    }

    /// Advance the active playback's visible sample. A repeat draw or a backwards
    /// presentation snap does not replay a cue. When a simulation catches up by
    /// several samples, report each crossed marker with its exact authored source
    /// sample, not the final visible sample or an adjacent approximation.
    public mutating func advance(toVisibleSample visible: Int) -> [Event] {
        guard let first = origin.firstSample, visible > lastVisibleSample, visible >= 0 else { return [] }
        let (end, overflow) = first.addingReportingOverflow(visible)
        guard !overflow else { return [] }
        lastVisibleSample = visible
        var events: [Event] = []
        while nextMarker < markers.count {
            let marker = markers[nextMarker]
            guard marker.sample <= end else { break }
            nextMarker += 1
            guard marker.sample >= first else { continue }
            events.append(.presentation(id: marker.id, channel: marker.presentation, sourceSample: marker.sample))
        }
        return events
    }

    /// Separate channel. Draw or cast markers cannot fabricate damage; an
    /// authoritative collision token is scoped to one playback instance.
    public mutating func recordGameplayHit(id: String, atSimulationTick tick: Int) -> Event? {
        guard !id.isEmpty, tick >= 0, observedHitIDs.insert(id).inserted else { return nil }
        return .gameplayHit(id: id, simulationTick: tick)
    }

    public mutating func beginNewPlayback() {
        nextMarker = 0
        lastVisibleSample = -1
        observedHitIDs.removeAll(keepingCapacity: true)
    }
}
