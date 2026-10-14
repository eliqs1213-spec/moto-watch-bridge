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


expect(WatchHealthProtocol.route(damaged)?.group == 0x10, "Damaged frame should retain routing only")
expect(WatchHealthProtocol.decode(damaged) == nil, "Routing must not bypass CRC")
let wrongType = WatchHealthProtocol.Frame(group: 0x31, command: 0x07, payload: bytes("08 02"))
expect(WatchHealthProtocol.pulseRejectionReason(wrongType, start: now, end: now) == "Tipo de serie ausente o distinto de 1", "Missing series diagnostic")
expect(WatchHealthProtocol.pulseRejectionReason(longFrame, start: now, end: now) == "Muestra fuera de la ventana de 24 horas", "Time-window diagnostic")
print("Diagnostic checks passed: routing preserves CRC rejection and reports type/time failures")

expect(WatchHealthProtocol.canProbeFirstPulseBlock(1), "Captured index indicator 1 rejected")
expect(WatchHealthProtocol.canProbeFirstPulseBlock(2), "Observed iPhone index indicator 2 rejected")
expect(!WatchHealthProtocol.canProbeFirstPulseBlock(nil), "Missing index accepted")
expect(!WatchHealthProtocol.canProbeFirstPulseBlock(0), "Empty index accepted")
expect(!WatchHealthProtocol.canProbeFirstPulseBlock(255), "Unknown index accepted")
print("Index checks passed: indicators 1/2 accepted; missing, zero and unknown rejected")

var assembler = WatchHealthFrameAssembler()
let firstPart = Data(longData.prefix(509))
let secondPart = Data(longData.dropFirst(509))
switch assembler.consume(firstPart, now: now) {
case .pending(let received, let expected): expect(received == 509 && expected == longData.count, "Fragment length accounting")
default: fatalError("First 509-byte fragment was not buffered")
}
switch assembler.consume(battery, now: now) {
case .unrelated: break
default: fatalError("Interleaved battery consumed health buffer")
}
switch assembler.consume(secondPart, now: now) {
case .complete(let data): expect(data == longData && WatchHealthProtocol.decode(data) != nil, "Fragmented message CRC")
default: fatalError("Continuation did not complete health message")
}
_ = assembler.consume(firstPart, now: now)
assembler.reset()
switch assembler.consume(secondPart, now: now) {
case .unrelated: break
default: fatalError("Continuation leaked across connections")
}
_ = assembler.consume(firstPart, now: now)
switch assembler.consume(secondPart, now: now.addingTimeInterval(21)) {
case .unrelated: break
default: fatalError("Expired fragment was reused")
}
_ = assembler.consume(firstPart, now: now)
var badTail = secondPart
badTail[badTail.count - 1] ^= 1
switch assembler.consume(badTail, now: now) {
case .complete(let data): expect(WatchHealthProtocol.decode(data) == nil, "Assembler bypassed CRC")
default: fatalError("Corruption test did not assemble")
}
print("Assembly checks passed: 509-byte split, interleaving, reset, expiry and CRC rejection")

var selectorTwoPayload = pulsePayload
selectorTwoPayload[1] = 2
let selectorTwoFrame = WatchHealthProtocol.Frame(group: 0x31, command: 0x07, payload: Data(selectorTwoPayload))
expect(WatchHealthProtocol.pulse(selectorTwoFrame, start: now.addingTimeInterval(-20000), end: now) == nil, "Selector 2 accepted as selector 1")
expect(WatchHealthProtocol.pulse(selectorTwoFrame, start: now.addingTimeInterval(-20000), end: now, expectedSelector: 2)?.count == 80, "Selector 2 decoder failed")
expect(WatchHealthProtocol.pulse(longFrame, start: now.addingTimeInterval(-20000), end: now, expectedSelector: 2) == nil, "Late selector 1 accepted as selector 2")
print("Selector checks passed: expected series is enforced for selectors 1 and 2")
