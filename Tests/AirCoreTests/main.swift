import Foundation
import AirCore

var checks = 0
@MainActor func expect(_ condition: Bool, _ message: String) {
    guard condition else { print("FAIL: \(message)"); exit(1) }
    checks += 1
}
let packet: [UInt8] = [0x0a, 0x24, 6, 5, 4, 3, 2, 1,
    1, 4, 0xea, 0, 0xf4, 1, 0x12, 4, 12, 0, 18, 0, 0x13, 2, 0x20, 3]
let r = Advertisement.decode(Data(packet))!
expect(r.deviceID == "01:02:03:04:05:06", "address byte order")
expect(r.temperature == 23.4 && r.humidity == 50, "temperature and humidity scaling")
expect(r.pm25 == 12 && r.pm10 == 18 && r.co2 == 800, "particulate and CO2 decoding")
var negative = packet; negative[1] = 0x0e; negative[10] = 0xce; negative[11] = 0xff
expect(Advertisement.decode(Data(negative))?.temperature == -5, "signed temperature and model 0e")
for count in [0, 1, 7, 9, 11, 13, 15, 17, 19, 21, 23] {
    expect(Advertisement.decode(Data(packet.prefix(count))) == nil, "reject truncated length \(count)")
}
let partial = Array(packet.prefix(8)) + [0xff, 1, 42, 0x13, 2, 0x20, 3]
expect(Advertisement.decode(Data(partial))?.co2 == 800, "skip unknown TLV")
expect(Advertisement.decode(Data(partial))?.temperature == nil, "partial update is not zero")
var unknown = packet; unknown[1] = 0xff
expect(Advertisement.decode(Data(unknown)) == nil, "reject unsupported model")
expect(Advertisement.decode(Data(Array(packet.prefix(8)) + [0xff, 0])) == nil, "reject empty reading")
let now = Date(timeIntervalSince1970: 1000)
var samples: [Metric: Sample] = [.co2: Sample(value: 2100, date: now), .humidity: Sample(value: 45, date: now)]
expect(DisplayPolicy.displayed(selected: .humidity, samples: samples, zones: [:], now: now) == .co2, "red overrides selection")
samples[.co2] = Sample(value: 700, date: now)
expect(DisplayPolicy.displayed(selected: .humidity, samples: samples, zones: [:], now: now) == .humidity, "recovery restores selection")
samples[.co2] = Sample(value: 3000, date: now.addingTimeInterval(-120))
expect(DisplayPolicy.alerts(samples: samples, zones: [:], now: now).isEmpty, "stale values cannot trigger alerts")
samples = [.co2: Sample(value: 900, date: now), .pm25: Sample(value: 100, date: now)]
expect(DisplayPolicy.alerts(samples: samples, zones: [:], now: now) == [.co2, .pm25], "stable multiple-alert priority and inclusive boundary")
samples = [.temperature: Sample(value: 15, date: now), .co2: Sample(value: 1000, date: now)]
expect(DisplayPolicy.alerts(samples: samples, zones: [.co2: RedZone(upper: 1000)], now: now) == [.co2, .temperature], "custom and lower thresholds")
expect(!RedZone(lower: 20, upper: 70).contains(45), "in-range value")
expect(!RedZone.defaultZone(for: .co2).contains(899), "CO2 below 900 is normal")
expect(RedZone.defaultZone(for: .co2).contains(900), "CO2 red starts at 900")
print("Passed \(checks) checks")
