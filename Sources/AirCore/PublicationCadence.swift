import Foundation

/// Each sensor has its own publication clock. Only an actual publication advances it.
public struct PublicationCadence: Sendable {
    private let interval: TimeInterval
    private var publishedAt: [String: Date] = [:]

    public init(interval: TimeInterval = 60) { self.interval = interval }

    public mutating func shouldPublish(deviceID: String, at now: Date) -> Bool {
        if let previous = publishedAt[deviceID], now.timeIntervalSince(previous) >= 0,
           now.timeIntervalSince(previous) < interval { return false }
        publishedAt[deviceID] = now
        return true
    }

    /// Resume immediately when the transport returns rather than waiting for an old interval.
    public mutating func reset() { publishedAt.removeAll() }
}
