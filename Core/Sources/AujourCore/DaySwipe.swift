import Foundation

public struct DaySwipe: Equatable, Sendable {
    public enum Axis: Hashable, Sendable {
        case sideways
        case upAndDown
    }

    public enum Landing: Hashable, Sendable {
        case theDayBefore
        case theDayAfter
        case whereItStarted

        public var days: Int {
            switch self {
            case .theDayBefore: -1
            case .theDayAfter: 1
            case .whereItStarted: 0
            }
        }
    }

    public static let declaresItself: Double = 10

    public static let follows: Double = 0.4

    public static let asFarAs: Double = 44

    public static let turnsTheDay: Double = 72

    public private(set) var axis: Axis?

    private var acrossTheFinger: Double = 0

    public init() {}

    public var isBeingDragged: Bool { axis != nil }

    public var carried: Double {
        min(max(acrossTheFinger * Self.follows, -Self.asFarAs), Self.asFarAs)
    }

    public mutating func dragged(across: Double, down: Double) {
        if axis == nil {
            guard max(abs(across), abs(down)) >= Self.declaresItself else { return }
            axis = abs(across) > abs(down) ? .sideways : .upAndDown
        }
        guard axis == .sideways else { return }
        acrossTheFinger = across
    }

    @discardableResult
    public mutating func letGo(heading: Double) -> Landing {
        let wentSideways = axis == .sideways
        let across = acrossTheFinger
        calledOff()

        guard wentSideways else { return .whereItStarted }
        let going = abs(heading) > abs(across) ? heading : across
        guard abs(going) > Self.turnsTheDay else { return .whereItStarted }
        return going < 0 ? .theDayAfter : .theDayBefore
    }

    public mutating func calledOff() {
        axis = nil
        acrossTheFinger = 0
    }
}
