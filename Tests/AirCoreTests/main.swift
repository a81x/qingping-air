import Foundation
import CoreGraphics
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
// A fresh temperature packet must not keep an old CO2 alarm alive.
samples = [.co2: Sample(value: 2000, date: now.addingTimeInterval(-121)),
           .temperature: Sample(value: 22, date: now)]
expect(DisplayPolicy.displayed(selected: .humidity, samples: samples, zones: [:], now: now) == .humidity,
       "fresh unrelated metric does not revive a stale alarm")
expect(Sample(value: 900, date: now.addingTimeInterval(-119.9)).isFresh(at: now), "freshness just before expiry")
expect(!Sample(value: 900, date: now.addingTimeInterval(-120)).isFresh(at: now), "freshness expires at boundary")
expect(DisplayPolicy.displayed(selected: .pm10, samples: [:], zones: [:], now: now) == .pm10,
       "empty readings preserve user's selected metric")
// Settings must survive encoding with non-string Dictionary keys.
let configured: [Metric: RedZone] = [.co2: RedZone(upper: 900), .temperature: RedZone(lower: 15, upper: 31)]
let restored = try JSONDecoder().decode([Metric: RedZone].self, from: JSONEncoder().encode(configured))
expect(restored == configured, "threshold persistence round trip")
expect(RedZone(lower: 20, upper: 70).contains(20), "inclusive lower boundary")
expect(!RedZone(lower: 20, upper: 70).contains(20.1), "just inside lower boundary")
// A zero-length unknown TLV cannot stall decoding; a dangling byte is invalid.
let withEmptyUnknown = Array(packet.prefix(8)) + [0xff, 0] + Array(packet.dropFirst(8))
expect(Advertisement.decode(Data(withEmptyUnknown)) == r, "skip zero-length unknown field")
expect(Advertisement.decode(Data(packet + [0x13])) == nil, "reject dangling TLV header")
let wideUnsigned = Array(packet.prefix(8)) + [0x13, 2, 0x10, 0x80]
expect(Advertisement.decode(Data(wideUnsigned))?.co2 == 32784, "CO2 decoded as unsigned")

// Regression: a status-item click must not be mistaken for an outside click.
let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
let anchor = CGRect(x: 1200, y: 876, width: 28, height: 24)
let panel = PanelBehavior.frame(anchor: anchor, visible: screen, desiredHeight: 420)
expect(screen.contains(panel), "panel fits visible screen")
expect(panel.maxY <= anchor.minY, "panel opens below status item")
expect(!PanelBehavior.shouldDismissForClick(point: CGPoint(x: 1214, y: 888), panel: panel, anchor: anchor, isPresented: true),
       "opening status click does not dismiss panel")
expect(!PanelBehavior.shouldDismissForClick(point: CGPoint(x: panel.midX, y: panel.midY), panel: panel, anchor: anchor, isPresented: true),
       "clicking panel controls keeps panel open")
expect(PanelBehavior.shouldDismissForClick(point: CGPoint(x: 20, y: 20), panel: panel, anchor: anchor, isPresented: true),
       "outside click dismisses visible panel")
expect(!PanelBehavior.shouldDismissForClick(point: CGPoint(x: 20, y: 20), panel: panel, anchor: anchor, isPresented: false),
       "outside click on hidden panel is ignored")
let leftScreen = CGRect(x: -1280, y: -200, width: 1280, height: 700)
let leftAnchor = CGRect(x: -1260, y: 501, width: 28, height: 24)
let leftPanel = PanelBehavior.frame(anchor: leftAnchor, visible: leftScreen, desiredHeight: 570)
expect(leftScreen.contains(leftPanel), "secondary display with negative origin contains panel")
expect(leftPanel.maxY <= leftAnchor.minY, "secondary-display panel below its own anchor")
let smallScreen = CGRect(x: 100, y: 100, width: 800, height: 300)
let smallPanel = PanelBehavior.frame(anchor: CGRect(x: 500, y: 401, width: 28, height: 24), visible: smallScreen, desiredHeight: 570)
expect(smallScreen.contains(smallPanel), "settings panel fits short display")

// Regression: separate sensors cannot delay one another's minute refresh.
var cadence = PublicationCadence()
expect(cadence.shouldPublish(deviceID: "first", at: now), "first sample publishes immediately")
expect(!cadence.shouldPublish(deviceID: "first", at: now.addingTimeInterval(59.9)), "no publication before minute")
expect(cadence.shouldPublish(deviceID: "second", at: now.addingTimeInterval(59.9)), "new sensor publishes immediately")
expect(cadence.shouldPublish(deviceID: "first", at: now.addingTimeInterval(60)), "new sensor does not shift first sensor cadence")
expect(!cadence.shouldPublish(deviceID: "first", at: now.addingTimeInterval(60)), "duplicate timer tick does not republish")
cadence.reset()
expect(cadence.shouldPublish(deviceID: "first", at: now.addingTimeInterval(61)), "wake reset permits immediate fresh sample")
expect(cadence.shouldPublish(deviceID: "first", at: now), "backwards clock does not freeze updates")
print("Passed \(checks) checks")
