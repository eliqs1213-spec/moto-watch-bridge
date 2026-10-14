import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
func bytes(_ text: String) -> Data {
    Data(text.split(separator: " ").map { UInt8($0, radix: 16)! })
}
let battery = WatchHealthProtocol.encode(group: 0x10, command: 0x01)
expect(battery == bytes("aa 04 00 00 10 01 7e fd"), "Existing battery command changed")
expect(WatchHealthProtocol.decode(battery)?.group == 0x10, "Short frame decode")
var damaged = battery
damaged[6] ^= 1
expect(WatchHealthProtocol.decode(damaged) == nil, "CRC corruption accepted")
expect(WatchHealthProtocol.decode(Data(battery.dropLast())) == nil, "Truncated frame accepted")
var position = 0
expect(WatchHealthProtocol.readVarint(Array(repeating: 0xff, count: 10), &position) == nil, "Varint overflow accepted")
expect(WatchHealthProtocol.fields(bytes("1a ff ff ff ff 7f")) == nil, "Invalid protobuf length accepted")
let now = Date(timeIntervalSince1970: 1800000000)
let stepPayload: [UInt8] = [0x10] + WatchHealthProtocol.varint(1064)
    + [0x30] + WatchHealthProtocol.varint(1799999900)
let stepFrame = WatchHealthProtocol.decode(WatchHealthProtocol.encode(group: 0x30, command: 0x06, payload: stepPayload))!
expect(WatchHealthProtocol.steps(stepFrame, now: now)?.count == 1064, "Step field decoding")
let missingDate = WatchHealthProtocol.decode(WatchHealthProtocol.encode(group: 0x30, command: 0x06, payload: [0x10, 0x01]))!
expect(WatchHealthProtocol.steps(missingDate, now: now) == nil, "Missing date accepted")
var pulsePayload: [UInt8] = [0x08, 0x01, 0x10] + WatchHealthProtocol.varint(1799990000)
for index in 0..<80 {
    // Synthetic samples: tests contain no bugreport or user measurements.
    let sample: [UInt8] = [0x08] + WatchHealthProtocol.varint(UInt64(index * 60)) + [0x10, 0x50]
    pulsePayload += [0x1a] + WatchHealthProtocol.varint(UInt64(sample.count)) + sample
}
let longData = WatchHealthProtocol.encode(group: 0x31, command: 0x07, payload: pulsePayload)
expect(longData[1] & 0x80 != 0, "Long fixture did not use multibyte length")
let longFrame = WatchHealthProtocol.decode(longData)!
let samples = WatchHealthProtocol.pulse(longFrame, start: now.addingTimeInterval(-20000), end: now)!
expect(samples.count == 80 && samples.last?.bpm == 80, "Long pulse series decoding")
expect(samples[1].timestamp.timeIntervalSince(samples[0].timestamp) == 60, "Sample timestamp offsets")
expect(WatchHealthProtocol.pulse(longFrame, start: now, end: now) == nil, "Out-of-window samples accepted")
print("Protocol checks passed: CRC, bounds, long frames, steps and pulse timestamps")

