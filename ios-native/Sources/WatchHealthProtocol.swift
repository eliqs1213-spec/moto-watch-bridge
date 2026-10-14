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
    static func pulseRejectionReason(_ frame: Frame, start: Date, end: Date) -> String {
        guard let items = fields(frame.payload) else { return "Formato Protobuf inválido" }
        guard integer(1, in: items) == 1 else { return "Tipo de serie ausente o distinto de 1" }
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
    static func pulse(_ frame: Frame, start: Date, end: Date) -> [PulseCandidate]? {
        guard frame.group == 0x31, frame.command == 0x07,
              let items = fields(frame.payload), integer(1, in: items) == 1,
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

