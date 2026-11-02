import Foundation

public struct Reading: Equatable, Sendable {
    public let deviceID: String
    public let temperature: Double?
    public let humidity: Double?
    public let pm25: Int?
    public let pm10: Int?
    public let co2: Int?
}

/// Qingping FDCD service data: flags, model, six address bytes, then TLV fields.
public enum Advertisement {
    public static func decode(_ data: Data) -> Reading? {
        let bytes = Array(data)
        guard bytes.count >= 10, [0x0e, 0x24].contains(bytes[1]) else { return nil }
        let deviceID = bytes[2..<8].reversed().map { String(format: "%02X", $0) }.joined(separator: ":")
        var temperature: Double?, humidity: Double?
        var pm25: Int?, pm10: Int?, co2: Int?
        var index = 8
        while index < bytes.count {
            guard index + 2 <= bytes.count else { return nil }
            let type = bytes[index], length = Int(bytes[index + 1])
            index += 2
            guard index + length <= bytes.count else { return nil }
            func uint16(_ offset: Int) -> Int {
                Int(bytes[index + offset]) | Int(bytes[index + offset + 1]) << 8
            }
            switch (type, length) {
            case (0x01, 4):
                temperature = Double(Int16(bitPattern: UInt16(uint16(0)))) / 10
                humidity = Double(uint16(2)) / 10
            case (0x12, 4): pm25 = uint16(0); pm10 = uint16(2)
            case (0x13, 2): co2 = uint16(0)
            default: break
            }
            index += length
        }
        guard temperature != nil || pm25 != nil || co2 != nil else { return nil }
        return Reading(deviceID: deviceID, temperature: temperature, humidity: humidity,
                       pm25: pm25, pm10: pm10, co2: co2)
    }
}
