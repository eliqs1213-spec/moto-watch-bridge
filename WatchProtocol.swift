import Foundation

enum WatchCommand: String {
    case next = "SIGUIENTE"
    case previous = "ANTERIOR"
    case toggle = "PLAY / PAUSA"
    case findStart = "BUSCAR IPHONE: INICIAR"
    case findStop = "BUSCAR IPHONE: DETENER"
    case unknown = "OTRO"
}

enum MotoProtocol {
    // Tráfico real Moto Watch Fit, comparado con captura Motorola Edge.
    static let service = "FC9DF9F0-4899-11EE-BE56-0242AC120002"
    static let notifications = "FC9DF8F0-4899-11EE-BE56-0242AC120002"
    static let writes = "FC9DF8F1-4899-11EE-BE56-0242AC120002"

    static func crc16Xmodem(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    static func decode(_ data: Data) -> WatchCommand? {
        let bytes = Array(data)
        guard bytes.count >= 8, bytes[0] == 0xAA else { return nil }
        let length = Int(bytes[1]) | (Int(bytes[2]) << 8)
        guard length + 4 == bytes.count else { return nil }
        let expected = UInt16(bytes[bytes.count - 2]) | (UInt16(bytes[bytes.count - 1]) << 8)
        guard crc16Xmodem(bytes.dropLast(2)) == expected else { return nil }

        // 0x11 0x06: comandos de Buscar teléfono, identificados con dos pruebas reales.
        if bytes[4] == 0x11, bytes[5] == 0x06 {
            if bytes.count == 10 && bytes[6] == 0x08 && bytes[7] == 0x01 { return .findStart }
            if bytes.count == 8 { return .findStop }
            return .unknown
        }
        guard bytes[4] == 0x24 && bytes[5] == 0x07 else { return .unknown }
        if bytes.count == 10 && bytes[6] == 0x08 {
            if bytes[7] == 0x02 { return .next }
            if bytes[7] == 0x01 { return .previous }
        }
        if bytes.count == 8 { return .toggle }
        return .unknown
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
