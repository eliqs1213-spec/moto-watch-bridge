import Foundation

// Etapa 1 (NO transferencia): comprobar por GATT si el firmware responde al
// handshake FILE/TRANSMISSION 20/05 que Motorola usa para archivos.
// La APK Android requiere SPP antes del envío. No asumir que GATT funciona.
enum MotoFileLEProbe {
    struct Reply: Equatable {
        let protocolVersion: Int
        let maxDataSize: Int
        let transferUnitSize: Int?
    }
    private static func vint(_ input: Int) -> [UInt8] {
        var n = input; var result: [UInt8] = []
        repeat {
            var b = UInt8(n & 127); n >>= 7
            if n > 0 { b |= 0x80 }
            result.append(b)
        } while n > 0
        return result
    }

    static func request() -> Data {
        // Captura Motorola sobre RFCOMM: 20/05 version=1, max_data_size=16384.
        // Prueba GATT independiente: la negociación sobre LE no está confirmada.
        let body: [UInt8] = [0x20, 0x05, 0x08, 0x01, 0x20, 0x80, 0x80, 0x01]
        let length = body.count + 2 // group+CID+payload+CRC16
        let message: [UInt8] = [0xAA, UInt8(length), 0x00, 0x00] + body
        let crc = MotoProtocol.crc16Xmodem(message[...])
        return Data(message + [UInt8(crc & 0xFF), UInt8(crc >> 8)])
    }

    private static func readVarint(_ bytes: [UInt8], offset: inout Int) -> Int? {
        var value = 0
        var shift = 0
        while offset < bytes.count && shift <= 28 {
            let byte = Int(bytes[offset]); offset += 1
            value |= (byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }

    // El reloj responde con comando 20/85, no con el 20/05 de solicitud.
    static func isFileTransmissionCandidate(_ data: Data) -> Bool {
        let bytes = Array(data)
        return bytes.count >= 8 && bytes[0] == 0xAA &&
               bytes[4] == 0x20 && bytes[5] == 0x85
    }

    static func reply(_ data: Data) -> Reply? {
        let b = Array(data)
        guard isFileTransmissionCandidate(data), b.count <= 256,
              Int(b[1]) + (Int(b[2]) << 8) + 4 == b.count,
              MotoProtocol.crc16Xmodem(b.dropLast(2)) ==
                (UInt16(b[b.count - 2]) | UInt16(b[b.count - 1]) << 8)
        else { return nil }

        var at = 6
        let end = b.count - 2
        var fields: [Int: Int] = [:]
        while at < end {
            guard let key = readVarint(b, offset: &at), key > 0,
                  key & 7 == 0, // campos FileTransmission varint únicamente
                  let value = readVarint(b, offset: &at), at <= end else { return nil }
            let field = key >> 3
            guard (1...5).contains(field), fields[field] == nil else { return nil }
            fields[field] = value
        }
        guard at == end, let version = fields[1], let maximum = fields[4],
              (1...2).contains(version), (20...16384).contains(maximum) else { return nil }
        return Reply(protocolVersion: version, maxDataSize: maximum,
                     transferUnitSize: fields[3])
    }
}
