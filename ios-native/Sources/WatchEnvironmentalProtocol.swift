import Foundation

// 23/0A y 2A/05 observados en el reloj. Sus significados exactos
// no están demostrados: no responder automáticamente ni escribir BLE.
enum WatchEnvironmentalSignal: Equatable {
    case group23Command0A
    case group2ACommand05
    var diagnostic: String {
        switch self {
        case .group23Command0A:
            return "23/0A recibido; la app Motorola lo refleja; semántica sin verificar, sin respuesta automática"
        case .group2ACommand05:
            return "2A/05 recibido; Motorola responde con estado 08 01; semántica sin verificar, sin respuesta automática"
        }
    }
}

enum WatchEnvironmentalProtocol {
    static func identify(_ packet: Data) -> WatchEnvironmentalSignal? {
        let b = Array(packet)
        guard b.count == 8, b[0] == 0xAA,
              b[1] == 0x04, b[2] == 0x00, b[3] == 0x00,
              MotoProtocol.crc16Xmodem(b.dropLast(2)) ==
                (UInt16(b[6]) | UInt16(b[7]) << 8) else { return nil }
        switch (b[4], b[5]) {
        case (0x23, 0x0A): return .group23Command0A
        case (0x2A, 0x05): return .group2ACommand05
        default: return nil
        }
    }
}
