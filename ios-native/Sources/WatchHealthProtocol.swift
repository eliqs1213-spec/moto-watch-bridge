import Foundation

// Decodificación estructural comprobada con la captura. La interpretación
// de pasos/pulso continúa experimental hasta comparar con el reloj real.
enum WatchHealthProtocol {
    struct Frame { let group: UInt8; let command: UInt8; let payload: Data }
    struct Field { let number: Int; let integer: UInt64?; let data: Data? }
    struct StepCandidate { let count: Int; let timestamp: Date }
    struct PulseCandidate { let timestamp: Date; let bpm: Int }

    static func readVarint(_ bytes: [UInt8], _ position: inout Int) -> UInt64? {
        var result: UInt64 = 0
        for index in 0..<10 {
            guard position < bytes.count else { return nil }
            let byte = bytes[position]; position += 1
            if index == 9 && byte > 1 { return nil }
            result |= UInt64(byte & 0x7f) << (index * 7)
            if byte & 0x80 == 0 { return result }
        }
        return nil
    }
    static func varint(_ value: UInt64) -> [UInt8] {
        var value = value; var result: [UInt8] = []
        repeat {
            let byte = UInt8(value & 0x7f); value >>= 7
            result.append(byte | (value == 0 ? 0 : 0x80))
        } while value != 0
        return result
    }
    static func crc(_ bytes: [UInt8]) -> UInt16 {
        var value: UInt16 = 0
        for byte in bytes {
            value ^= UInt16(byte) << 8
            for _ in 0..<8 { value = value & 0x8000 != 0 ? (value << 1) ^ 0x1021 : value << 1 }
        }
        return value
    }
    static func encode(group: UInt8, command: UInt8, payload: [UInt8] = []) -> Data {
        var bytes: [UInt8] = [0xaa] + varint(UInt64(payload.count + 4)) + [0, 0, group, command] + payload
        let checksum = crc(bytes)
        bytes += [UInt8(checksum & 255), UInt8(checksum >> 8)]
        return Data(bytes)
    }
    // Solo identifica la ruta; no valida ni acepta los datos.
    static func route(_ data: Data) -> (group: UInt8, command: UInt8)? {
        let bytes = Array(data); var pos = 1
        guard bytes.first == 0xaa, let size = readVarint(bytes, &pos), size >= 4, size <= 65536,
              pos + 3 < bytes.count, bytes[pos] == 0, bytes[pos + 1] == 0 else { return nil }
        return (bytes[pos + 2], bytes[pos + 3])
    }
    static func canProbeFirstPulseBlock(_ indicator: UInt64?) -> Bool {
        // 1 en la captura Android y 2 en la prueba iPhone. No asumir que
        // todo valor positivo sea válido ni que el indicador sea un booleano.
        return indicator == 1 || indicator == 2
    }
    static func pulseRejectionReason(_ frame: Frame, start: Date, end: Date, expectedSelector: UInt64 = 1) -> String {
        guard let items = fields(frame.payload) else { return "Formato Protobuf inválido" }
        guard integer(1, in: items) == expectedSelector else { return "Tipo de serie ausente o distinto de \(expectedSelector)" }
        guard let base = integer(2, in: items), base >= 1577836800 else { return "Fecha base ausente o inválida" }
        for field in items where field.number == 3 {
            guard let data = field.data, let sample = fields(data) else { return "Muestra anidada inválida" }
            guard let bpm = integer(2, in: sample) else { return "Muestra sin valor o con campo duplicado" }
            guard bpm >= 25 && bpm <= 240 else { return "Valor fuera del rango admitido; posible marcador sin lectura" }
            let offsets = sample.filter { $0.number == 1 }
            guard offsets.count <= 1, offsets.first == nil || offsets.first?.integer != nil else { return "Desplazamiento de tiempo inválido" }
            let offset = integer(1, in: sample) ?? 0
            guard offset <= 604800, base <= UInt64.max - offset else { return "Desplazamiento de tiempo fuera de límites" }
            let date = Date(timeIntervalSince1970: Double(base + offset))
            guard date >= start, date <= end.addingTimeInterval(300) else { return "Muestra fuera de la ventana de 24 horas" }
        }
        return "Respuesta no compatible con el decoder"
    }
    static func decode(_ data: Data) -> Frame? {
        let bytes = Array(data); var pos = 1
        guard bytes.first == 0xaa, let size = readVarint(bytes, &pos), size >= 4,
              size <= 65536, bytes.count == pos + 2 + Int(size),
              bytes[pos] == 0, bytes[pos + 1] == 0 else { return nil }
        let offset = pos + 2
        guard crc(Array(bytes.dropLast(2))) == (UInt16(bytes[bytes.count - 2]) | (UInt16(bytes[bytes.count - 1]) << 8)) else { return nil }
        return Frame(group: bytes[offset], command: bytes[offset + 1],
                     payload: Data(bytes[(offset + 2)..<(bytes.count - 2)]))
    }
    static func fields(_ data: Data) -> [Field]? {
        let bytes = Array(data); var pos = 0; var result: [Field] = []
        while pos < bytes.count {
            guard result.count < 10000, let tag = readVarint(bytes, &pos),
                  tag >> 3 > 0, tag >> 3 <= 536870911 else { return nil }
            let number = Int(tag >> 3)
            switch tag & 7 {
            case 0:
                guard let value = readVarint(bytes, &pos) else { return nil }
                result.append(Field(number: number, integer: value, data: nil))
            case 2:
                guard let length = readVarint(bytes, &pos), length <= UInt64(bytes.count - pos) else { return nil }
                let end = pos + Int(length)
                result.append(Field(number: number, integer: nil, data: Data(bytes[pos..<end])))
                pos = end
            case 1, 5:
                let size = tag & 7 == 1 ? 8 : 4
                guard pos + size <= bytes.count else { return nil }
                pos += size // Campos no usados por los dos decoders de esta etapa.
            default: return nil
            }
        }
        return result
    }
    static func integer(_ number: Int, in fields: [Field]) -> UInt64? {
        let items = fields.filter { $0.number == number }
        guard items.count == 1 else { return nil }
        return items[0].integer
    }
    static func steps(_ frame: Frame, now: Date = Date()) -> StepCandidate? {
        guard frame.group == 0x30, frame.command == 0x06,
              let items = fields(frame.payload), let steps = integer(2, in: items), steps <= 200000,
              let seconds = integer(6, in: items), seconds >= 1577836800,
              Double(seconds) <= now.timeIntervalSince1970 + 300 else { return nil }
        return StepCandidate(count: Int(steps), timestamp: Date(timeIntervalSince1970: Double(seconds)))
    }
    static func pulse(_ frame: Frame, start: Date, end: Date, expectedSelector: UInt64 = 1) -> [PulseCandidate]? {
        guard frame.group == 0x31, frame.command == 0x07,
              let items = fields(frame.payload), integer(1, in: items) == expectedSelector,
              let base = integer(2, in: items), base >= 1577836800 else { return nil }
        var result: [PulseCandidate] = []
        for field in items where field.number == 3 {
            guard let data = field.data, let sample = fields(data),
                  let bpm = integer(2, in: sample), bpm >= 25, bpm <= 240 else { return nil }
            let offsetFields = sample.filter { $0.number == 1 }
            guard offsetFields.count <= 1, offsetFields.first == nil || offsetFields.first?.integer != nil else { return nil }
            let offset = integer(1, in: sample) ?? 0
            guard offset <= 604800, base <= UInt64.max - offset else { return nil }
            let timestamp = Date(timeIntervalSince1970: Double(base + offset))
            guard timestamp >= start, timestamp <= end.addingTimeInterval(300) else { return nil }
            result.append(PulseCandidate(timestamp: timestamp, bpm: Int(bpm)))
        }
        return result
    }
}



// El reloj divide mensajes Motorola grandes entre valores ATT de hasta 509
// bytes. Las continuaciones no llevan otra cabecera AA. CoreBluetooth
// reconstruye HCI/ACL, pero no esta fragmentación del protocolo del reloj.
struct WatchHealthFrameAssembler {
    enum Result {
        case unrelated
        case pending(received: Int, expected: Int)
        case complete(Data)
        case rejected(String)
    }
    private let commands: Set<UInt8>
    init(commands: Set<UInt8> = [0x07]) { self.commands = commands }
    private var buffer = Data()
    private var expected = 0
    private var began = Date.distantPast
    mutating func reset() { buffer.removeAll(); expected = 0; began = .distantPast }

    mutating func consume(_ data: Data, now: Date = Date()) -> Result {
        if !buffer.isEmpty && now.timeIntervalSince(began) > 20 { reset() }
        // Tramas completas intercaladas no son continuaciones del histórico.
        if let frame = WatchHealthProtocol.decode(data) {
            if frame.group == 0x31 && commands.contains(frame.command) {
                reset()
                return .complete(data)
            }
            return .unrelated
        }
        if let route = WatchHealthProtocol.route(data) {
            if route.group == 0x31 && commands.contains(route.command) {
                let bytes = Array(data); var position = 1
                guard let length = WatchHealthProtocol.readVarint(bytes, &position),
                      length <= 65536 else { reset(); return .rejected("Longitud anunciada fuera de límites") }
                let total = position + 2 + Int(length)
                if data.count == total {
                    reset()
                    return .complete(data) // receive comprueba CRC, incluso si es incorrecto.
                }
                guard data.count < total else { reset(); return .rejected("Trama supera la longitud anunciada") }
                buffer = data
                expected = total
                began = now
                return .pending(received: buffer.count, expected: expected)
            }
            // Otra cabecera Motorola reconocible: no mezclar batería/botones.
            return .unrelated
        }
        guard !buffer.isEmpty else { return .unrelated }
        guard !data.isEmpty, buffer.count + data.count <= expected else {
            reset()
            return .rejected("Continuación supera la longitud anunciada")
        }
        buffer.append(data)
        if buffer.count < expected { return .pending(received: buffer.count, expected: expected) }
        let message = buffer
        reset()
        return .complete(message)
    }
}

 
// El grupo es candidato a estrés; no se considera semánticamente confirmado.
// Este decoder comprueba estructura, fechas y rango, no la categoría real.
enum WatchStressProtocol {
    struct Sample: Identifiable {
        let timestamp: Date
        let value: Int
        var id: Int64 { Int64(timestamp.timeIntervalSince1970) }
    }
    static func decode(_ frame: WatchHealthProtocol.Frame, selector: UInt64,
                       start: Date, end: Date) -> [Sample]? {
        guard frame.group == 0x31, frame.command == 0x0E,
              let fields = WatchHealthProtocol.fields(frame.payload),
              WatchHealthProtocol.integer(1, in: fields) == selector,
              let base = WatchHealthProtocol.integer(2, in: fields), base >= 1577836800 else { return nil }
        var result: [Sample] = []
        for item in fields where item.number == 3 {
            guard let data = item.data, let sample = WatchHealthProtocol.fields(data),
                  let value = WatchHealthProtocol.integer(2, in: sample), value <= 100 else { return nil }
            let offsets = sample.filter { $0.number == 1 }
            guard offsets.count <= 1, offsets.first == nil || offsets.first?.integer != nil else { return nil }
            let offset = WatchHealthProtocol.integer(1, in: sample) ?? 0
            guard offset <= 604800, base <= UInt64.max - offset else { return nil }
            let timestamp = Date(timeIntervalSince1970: Double(base + offset))
            guard timestamp >= start, timestamp <= end.addingTimeInterval(300) else { return nil }
            result.append(Sample(timestamp: timestamp, value: Int(value)))
        }
        return result
    }
}


// Candidatos para comparación, sin interpretación clínica ni unidades asignadas.
enum VitalsCandidateProtocol {
    struct Reading: Identifiable {
        let channel: String
        let timestamp: Date
        let value: Int
        var id: String { "\(channel):\(Int64(timestamp.timeIntervalSince1970))" }
    }
    struct Counter: Identifiable {
        let field: Int
        let value: UInt64
        var id: Int { field }
        var label: String { field == 9 ? "Calorías activas" : "Contador B (sin identificar)" }
        var unitSuffix: String { field == 9 ? " kcal" : "" }
    }
    struct CounterResult { let timestamp: Date; let values: [Counter] }
    static func counters(_ frame: WatchHealthProtocol.Frame, now: Date) -> CounterResult? {
        guard frame.group == 0x30, frame.command == 0x06,
              let fields = WatchHealthProtocol.fields(frame.payload),
              let seconds = WatchHealthProtocol.integer(6, in: fields), seconds >= 1577836800,
              Double(seconds) <= now.timeIntervalSince1970 + 300 else { return nil }
        var values: [Counter] = []
        // Campo 9: candidato principal. Campo 3: contador alternativo, podría
        // representar distancia. No se supone que ambos sean calorías.
        for field in [9, 3] {
            let matches = fields.filter { $0.number == field }
            guard matches.count <= 1 else { return nil }
            if let value = WatchHealthProtocol.integer(field, in: fields) {
                guard value <= 10000000 else { return nil }
                values.append(Counter(field: field, value: value))
            } else if !matches.isEmpty { return nil }
        }
        guard !values.isEmpty else { return nil }
        return CounterResult(timestamp: Date(timeIntervalSince1970: Double(seconds)), values: values)
    }
    static func oxygenCursor(_ fields: [WatchHealthProtocol.Field], indexCommand: UInt8,
                             start: Date, end: Date) -> UInt64? {
        guard [0x0B, 0x11].contains(indexCommand),
              let value = WatchHealthProtocol.integer(2, in: fields) else { return nil }
        // 31/0B anuncia un cursor pequeño en iPhone; puede ser ordinal.
        // No interpretar ese cursor como fecha de la muestra.
        if indexCommand == 0x0B && value > 0 && value <= 65535 { return value }
        guard value >= 1577836800, Double(value) >= start.timeIntervalSince1970 - 1,
              Double(value) <= end.timeIntervalSince1970 else { return nil }
        return value
    }
    static func schema(_ frame: WatchHealthProtocol.Frame) -> String {
        guard let fields = WatchHealthProtocol.fields(frame.payload) else { return "Protobuf inválido" }
        return fields.prefix(14).map { field in
            "\(field.number):" + (field.integer != nil ? "varint" : "bytes")
        }.joined(separator: ",")
    }
    static func oxygenCandidates(_ frame: WatchHealthProtocol.Frame, command: UInt8, selector: UInt64,
                                 start: Date, end: Date) -> [Reading]? {
        guard [0x0C, 0x12].contains(command), frame.group == 0x31, frame.command == command,
              let fields = WatchHealthProtocol.fields(frame.payload),
              WatchHealthProtocol.integer(1, in: fields) == selector,
              let base = WatchHealthProtocol.integer(2, in: fields), base >= 1577836800 else { return nil }
        var result: [Reading] = []
        for item in fields where item.number == 3 {
            guard let data = item.data, let sample = WatchHealthProtocol.fields(data),
                  let value = WatchHealthProtocol.integer(2, in: sample), value <= 100 else { return nil }
            let offsets = sample.filter { $0.number == 1 }
            guard offsets.count <= 1, offsets.first == nil || offsets.first?.integer != nil else { return nil }
            let offset = WatchHealthProtocol.integer(1, in: sample) ?? 0
            guard offset <= 604800, base <= UInt64.max - offset else { return nil }
            let date = Date(timeIntervalSince1970: Double(base + offset))
            guard date >= start, date <= end.addingTimeInterval(300) else { return nil }
            result.append(Reading(channel: command == 0x0C ? "A" : "B", timestamp: date, value: Int(value)))
        }
        return result
    }
}
