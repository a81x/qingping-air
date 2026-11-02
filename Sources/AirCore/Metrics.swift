import Foundation

public enum Metric: String, CaseIterable, Codable, Sendable {
    case co2, pm25, pm10, temperature, humidity
    public var label: String {
        switch self {
        case .co2: "CO₂"
        case .pm25: "PM2.5"
        case .pm10: "PM10"
        case .temperature: "Температура"
        case .humidity: "Влажность"
        }
    }
    public var shortLabel: String {
        switch self { case .temperature: "T"; case .humidity: "RH"; default: label }
    }
    public var unit: String {
        switch self { case .co2: "ppm"; case .pm25, .pm10: "мкг/м³"; case .temperature: "°C"; case .humidity: "%" }
    }
    public func format(_ value: Double) -> String {
        switch self { case .temperature, .humidity: String(format: "%.1f", value); default: String(format: "%.0f", value) }
    }
    public func value(in r: Reading) -> Double? {
        switch self {
        case .temperature: r.temperature
        case .humidity: r.humidity
        case .co2: r.co2.map(Double.init)
        case .pm25: r.pm25.map(Double.init)
        case .pm10: r.pm10.map(Double.init)
        }
    }
}

public struct RedZone: Codable, Equatable, Sendable {
    public var lower: Double?
    public var upper: Double
    public init(lower: Double? = nil, upper: Double) { self.lower = lower; self.upper = upper }
    public func contains(_ value: Double) -> Bool {
        value >= upper || lower.map { value <= $0 } == true
    }
    public static func defaultZone(for metric: Metric) -> RedZone {
        switch metric {
        case .co2: RedZone(upper: 2000)
        case .pm25: RedZone(upper: 75)
        case .pm10: RedZone(upper: 150)
        case .temperature: RedZone(lower: 16, upper: 30)
        case .humidity: RedZone(lower: 20, upper: 70)
        }
    }
}

public struct Sample: Sendable {
    public let value: Double
    public let date: Date
    public init(value: Double, date: Date) { self.value = value; self.date = date }
    public func isFresh(at now: Date) -> Bool { now.timeIntervalSince(date) < 60 }
}

public enum DisplayPolicy {
    /// Fixed priority prevents rapid switching when several metrics are red.
    public static func alerts(samples: [Metric: Sample], zones: [Metric: RedZone], now: Date) -> [Metric] {
        Metric.allCases.filter { metric in
            guard let sample = samples[metric], sample.isFresh(at: now) else { return false }
            return (zones[metric] ?? .defaultZone(for: metric)).contains(sample.value)
        }
    }
    public static func displayed(selected: Metric, samples: [Metric: Sample], zones: [Metric: RedZone], now: Date) -> Metric {
        alerts(samples: samples, zones: zones, now: now).first ?? selected
    }
}
