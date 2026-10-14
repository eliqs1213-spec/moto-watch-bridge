import Foundation

// Grupo Motorola 25/02: observado en capturas de la aplicación oficial Android.
// Campos protobuf verificados: 1=tipo, 4=1, 5=timestamp, 6=título/remitente,
// 7=contenido, 8=nombre de app, 9=paquete Android equivalente.
// No incluimos el campo opaco 10 ni información privada de capturas.
enum WatchNotificationProtocol {
    private static func varint(_ raw: UInt64) -> [UInt8] {
        var value = raw
        var output: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            output.append(byte)
        } while value != 0
        return output
    }

    private static func string(_ text: String, byteLimit: Int) -> [UInt8] {
        var result: [UInt8] = []
        for character in text {
            let part = Array(String(character).utf8)
            if result.count + part.count > byteLimit { break }
            result.append(contentsOf: part)
        }
        return result
    }

    private static func numberField(_ id: UInt64, _ n: UInt64) -> [UInt8] {
        varint(id << 3) + varint(n)
    }

    private static func textField(_ id: UInt64, _ data: [UInt8]) -> [UInt8] {
        varint((id << 3) | 2) + varint(UInt64(data.count)) + data
    }

    private static func crc(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for b in data {
            crc ^= UInt16(b) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) == 0 ? crc << 1 : (crc << 1) ^ 0x1021
            }
        }
        return crc
    }

    static func encode(source: String, sender: String, message: String, timestamp: Date = Date()) -> Data? {
        let sourceName: String
        let packageID: String
        switch source.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "whatsapp":
            sourceName = "WhatsApp"
            packageID = "com.whatsapp"
        case "instagram":
            sourceName = "Instagram"
            // Aún no hay una captura de Instagram. Este identificador es una hipótesis.
            packageID = "com.instagram.android"
        default:
            sourceName = "iWatch"
            packageID = "org.motowatchbridge.nativeprobe"
        }
        let safeSender = string(sender.trimmingCharacters(in: .whitespacesAndNewlines), byteLimit: 42)
        let safeText = string(message.trimmingCharacters(in: .whitespacesAndNewlines), byteLimit: 86)
        guard !safeText.isEmpty else { return nil }
        let time = UInt64(max(0, Int(timestamp.timeIntervalSince1970)))
        let fields = numberField(1, 1) + numberField(4, 1) + numberField(5, time)
            + textField(6, safeSender.isEmpty ? Array("Mensaje nuevo".utf8) : safeSender)
            + textField(7, safeText)
            + textField(8, Array(sourceName.utf8))
            + textField(9, Array(packageID.utf8))
        let body: [UInt8] = [0x25, 0x02] + fields
        let length = body.count + 2
        guard length < 65536 else { return nil }
        let prefix: [UInt8] = [0xAA, UInt8(length & 0xFF), UInt8((length >> 8) & 0xFF), 0x00] + body
        let check = crc(prefix)
        return Data(prefix + [UInt8(check & 0xFF), UInt8(check >> 8)])
    }
}
