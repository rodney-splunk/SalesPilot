import Foundation

enum CallPresentation: Equatable {
    case ready, starting, live, finishing
    init(listening: Bool, starting: Bool, finishing: Bool) {
        if finishing { self = .finishing }
        else if starting { self = .starting }
        else if listening { self = .live }
        else { self = .ready }
    }
    var label: String {
        switch self {
        case .ready: return "Ready"
        case .starting: return "Starting"
        case .live: return "Live"
        case .finishing: return "Finishing"
        }
    }
    var actionTitle: String {
        switch self {
        case .ready: return "Start live call"
        case .live: return "End live call"
        case .starting: return "Starting call…"
        case .finishing: return "Finishing call…"
        }
    }
    var canToggle: Bool { self == .ready || self == .live }
}
