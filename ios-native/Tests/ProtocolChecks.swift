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

var stressPayload: [UInt8] = [0x08, 0x01, 0x10] + WatchHealthProtocol.varint(1799990000)
for index in 0..<80 {
    let sample: [UInt8] = [0x08] + WatchHealthProtocol.varint(UInt64(index * 60)) + [0x10, 0x05]
    stressPayload += [0x1a] + WatchHealthProtocol.varint(UInt64(sample.count)) + sample
}
let stressData = WatchHealthProtocol.encode(group: 0x31, command: 0x0E, payload: stressPayload)
let stressFrame = WatchHealthProtocol.decode(stressData)!
let stressRows = WatchStressProtocol.decode(stressFrame, selector: 1, start: now.addingTimeInterval(-20000), end: now)!
expect(stressRows.count == 80 && stressRows[0].value == 5, "Stress candidate uses 0...100, not pulse limits")
expect(stressRows[1].timestamp.timeIntervalSince(stressRows[0].timestamp) == 60, "Stress candidate offsets")
expect(WatchStressProtocol.decode(stressFrame, selector: 2, start: now.addingTimeInterval(-20000), end: now) == nil, "Wrong stress selector accepted")
expect(WatchStressProtocol.decode(longFrame, selector: 1, start: now.addingTimeInterval(-20000), end: now) == nil, "Pulse frame accepted as stress")
expect(WatchStressProtocol.decode(stressFrame, selector: 1, start: now, end: now) == nil, "Out-of-window stress accepted")
var invalidStressPayload: [UInt8] = [0x08, 0x01, 0x10] + WatchHealthProtocol.varint(1799990000)
invalidStressPayload += [0x1a, 0x02, 0x10, 0x65]
let invalidStress = WatchHealthProtocol.decode(WatchHealthProtocol.encode(group: 0x31, command: 0x0E, payload: invalidStressPayload))!
expect(WatchStressProtocol.decode(invalidStress, selector: 1, start: now.addingTimeInterval(-20000), end: now) == nil, "Stress value >100 accepted")
var stressAssembler = WatchHealthFrameAssembler(commands: [0x0E])
_ = stressAssembler.consume(Data(stressData.prefix(509)), now: now)
switch stressAssembler.consume(Data(stressData.dropFirst(509)), now: now) {
case .complete(let data): expect(data == stressData && WatchHealthProtocol.decode(data) != nil, "Stress fragmented CRC failed")
default: fatalError("Stress fragments not assembled")
}
var pulseOnlyAssembler = WatchHealthFrameAssembler()
switch pulseOnlyAssembler.consume(stressData, now: now) {
case .unrelated: break
default: fatalError("Stress intercepted by pulse-only assembler")
}
print("Stress candidate checks passed: bounds, selector, timestamps, frame routing and fragmentation")

let caloriePayload: [UInt8] = [0x18, 0x2a, 0x30] + WatchHealthProtocol.varint(1799999900) + [0x48, 0x64]
let calorieFrame = WatchHealthProtocol.decode(WatchHealthProtocol.encode(group: 0x30, command: 0x06, payload: caloriePayload))!
let calorieRows = VitalsCandidateProtocol.counters(calorieFrame, now: now)!
expect(calorieRows.values.count == 2 && calorieRows.values[0].field == 9 && calorieRows.values[0].value == 100, "Raw counters changed units or fields")
expect(VitalsCandidateProtocol.counters(longFrame, now: now) == nil, "Pulse accepted as calories")
let futureCalorie = WatchHealthProtocol.Frame(group: 0x30, command: 0x06, payload: Data([0x30] + WatchHealthProtocol.varint(1800001000) + [0x48, 0x01]))
expect(VitalsCandidateProtocol.counters(futureCalorie, now: now) == nil, "Future counters accepted")
let oxygenFrameA = WatchHealthProtocol.Frame(group: 0x31, command: 0x0C, payload: Data(stressPayload))
let oxygenFrameB = WatchHealthProtocol.Frame(group: 0x31, command: 0x12, payload: Data(stressPayload))
expect(VitalsCandidateProtocol.oxygenCandidates(oxygenFrameA, command: 0x0C, selector: 1, start: now.addingTimeInterval(-20000), end: now)?.first?.channel == "A", "Candidate A label failed")
expect(VitalsCandidateProtocol.oxygenCandidates(oxygenFrameB, command: 0x12, selector: 1, start: now.addingTimeInterval(-20000), end: now)?.first?.channel == "B", "Candidate B label failed")
expect(VitalsCandidateProtocol.oxygenCandidates(oxygenFrameA, command: 0x12, selector: 1, start: now.addingTimeInterval(-20000), end: now) == nil, "Cross-channel oxygen accepted")
expect(VitalsCandidateProtocol.oxygenCandidates(stressFrame, command: 0x0E, selector: 1, start: now.addingTimeInterval(-20000), end: now) == nil, "Confirmed stress command reused as oxygen")
let oxygenData = WatchHealthProtocol.encode(group: 0x31, command: 0x0C, payload: stressPayload)
var oxygenAssembler = WatchHealthFrameAssembler(commands: [0x0C, 0x12])
_ = oxygenAssembler.consume(Data(oxygenData.prefix(509)), now: now)
switch oxygenAssembler.consume(Data(oxygenData.dropFirst(509)), now: now) {
case .complete(let data): expect(WatchHealthProtocol.decode(data)?.command == 0x0C, "Oxygen CRC or fragment routing failed")
default: fatalError("Oxygen fragment reconstruction failed")
}
print("Vitals candidate checks passed: raw counters, dates, candidate isolation and fragmented replies")

let ordinalIndexFields = WatchHealthProtocol.fields(Data([0x08, 0x01, 0x10, 0x01, 0x18, 0x07]))!
expect(VitalsCandidateProtocol.oxygenCursor(ordinalIndexFields, indexCommand: 0x0B, start: now.addingTimeInterval(-86400), end: now) == 1, "Small oxygen cursor rejected")
expect(VitalsCandidateProtocol.oxygenCursor(ordinalIndexFields, indexCommand: 0x11, start: now.addingTimeInterval(-86400), end: now) == nil, "Temporal index accepted ordinal cursor")
let zeroCursor = WatchHealthProtocol.fields(Data([0x10, 0x00]))!
expect(VitalsCandidateProtocol.oxygenCursor(zeroCursor, indexCommand: 0x0B, start: now.addingTimeInterval(-86400), end: now) == nil, "Zero ordinal accepted")
let duplicateCursor = WatchHealthProtocol.fields(Data([0x10, 0x01, 0x10, 0x02]))!
expect(VitalsCandidateProtocol.oxygenCursor(duplicateCursor, indexCommand: 0x0B, start: now.addingTimeInterval(-86400), end: now) == nil, "Duplicate cursor accepted")
expect(calorieRows.values[0].label == "Calorías activas" && calorieRows.values[0].unitSuffix == " kcal", "Validated active calorie label")
print("Oxygen cursor checks passed: small cursor, temporal separation, zero and duplicate rejection")
