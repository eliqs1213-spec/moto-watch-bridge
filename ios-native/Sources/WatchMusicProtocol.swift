import Foundation

// Replicación del mensaje musical 0x24/0x01 capturado del Motorola Edge.
// La pantalla del reloj no envía ACK de haber refrescado el título.
struct WatchMusicSnapshot: Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let durationMs: Int
    let progressMs: Int
    var isPlaying: Bool
}

enum WatchMusicCode {
    case empty    // Reproducción estable: valor confirmado experimentalmente en v8
    case one      // Pausado: valor confirmado experimentalmente en v8
    case two      // Anuncio transitorio de canción nueva
}

enum WatchMusicProtocol {
    private static func varint(_ raw: Int) -> [UInt8] {
        var value = UInt64(max(0, raw))
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
        return out
    }

    private static func dataField(_ number: Int, _ value: [UInt8]) -> [UInt8] {
        varint((number << 3) | 2) + varint(value.count) + value
    }

    private static func numberField(_ number: Int, _ value: Int) -> [UInt8] {
        varint(number << 3) + varint(value)
    }

    // Limitar por caracteres completos para no cortar UTF-8 entre bytes.
    private static func utf8(_ text: String, limit: Int) -> [UInt8] {
        var result: [UInt8] = []
        for character in text {
            let part = Array(String(character).utf8)
            if result.count + part.count > limit { break }
            result += part
        }
        return result
    }

    static func encode(_ snapshot: WatchMusicSnapshot, code: WatchMusicCode) -> Data {
        var details: [UInt8] = []
        // Límites conservadores: menor tamaño para el MTU negociado con iPhone.
        details += dataField(1, utf8(snapshot.title, limit: 42))
        details += dataField(2, utf8(snapshot.artist, limit: 38))
        details += dataField(3, utf8(snapshot.album, limit: 24))
        details += dataField(4, Array("com.spotify.music".utf8))
        details += dataField(5, Array("Spotify".utf8))
        if snapshot.progressMs > 0 {
            details += numberField(7, snapshot.progressMs)
        }

        let playbackFlag: [UInt8]
        switch code {
        case .empty: playbackFlag = []
        case .one: playbackFlag = numberField(1, 1)
        case .two: playbackFlag = numberField(1, 2)
        }
        let volume = numberField(1, 8) + numberField(2, 15)
        let duration = numberField(1, max(1, (snapshot.durationMs + 500) / 1000))
        let payload = dataField(1, details)
            + dataField(2, playbackFlag)
            + dataField(3, volume)
            + dataField(4, duration)

        let body: [UInt8] = [0x24, 0x01] + payload
        let frameLength = body.count + 2
        let prefix: [UInt8] = [0xAA, UInt8(frameLength & 0xFF), UInt8((frameLength >> 8) & 0xFF), 0x00] + body
        let checksum = crc16Xmodem(prefix)
        return Data(prefix + [UInt8(checksum & 0xFF), UInt8(checksum >> 8)])
    }

    // Variante EXPERIMENTAL: informa un objeto musical vacío. Aún no está
    // comprobado que el firmware Moto Watch Fit vuelva a su pantalla
    // «No se está reproduciendo música». Se registra la escritura BLE.
    static func encodeNoMusic() -> Data {
        let payload: [UInt8] = dataField(1, []) + dataField(2, [])
            + dataField(3, []) + dataField(4, [])
        let body: [UInt8] = [0x24, 0x01] + payload
        let length = body.count + 2
        let prefix: [UInt8] = [0xAA, UInt8(length & 0xFF),
                               UInt8((length >> 8) & 0xFF), 0x00] + body
        let checksum = crc16Xmodem(prefix)
        return Data(prefix + [UInt8(checksum & 0xFF), UInt8(checksum >> 8)])
    }

    private static func crc16Xmodem(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }
}
