import Foundation

// Comprueba el paquete 24/01 real, no solo el código fuente.
// El campo 7 de PlayInfo es music_album_art y NO debe contener progreso.
func readMusicVarint(_ bytes: [UInt8], _ offset: inout Int) -> Int? {
    var value = 0
    var shift = 0
    while offset < bytes.count && shift <= 56 {
        let byte = Int(bytes[offset])
        offset += 1
        value |= (byte & 0x7f) << shift
        if byte & 0x80 == 0 { return value }
        shift += 7
    }
    return nil
}

func musicFieldNumbers(_ payload: [UInt8]) -> [Int]? {
    var offset = 0
    var numbers: [Int] = []
    while offset < payload.count {
        guard let key = readMusicVarint(payload, &offset) else { return nil }
        numbers.append(key >> 3)
        switch key & 7 {
        case 0:
            guard readMusicVarint(payload, &offset) != nil else { return nil }
        case 2:
            guard let length = readMusicVarint(payload, &offset),
                  length >= 0, offset + length <= payload.count else { return nil }
            offset += length
        default:
            return nil
        }
    }
    return numbers
}

let musicFieldTest = WatchMusicSnapshot(
    id: "fixture", title: "Título", artist: "Artista", album: "Album",
    durationMs: 180_000, progressMs: 45_000, isPlaying: true)
let musicFrame = Array(WatchMusicProtocol.encode(musicFieldTest, code: .empty))
var topOffset = 6
guard let playInfoKey = readMusicVarint(musicFrame, &topOffset),
      playInfoKey == 10,
      let playInfoLength = readMusicVarint(musicFrame, &topOffset),
      topOffset + playInfoLength <= musicFrame.count - 2,
      let found = musicFieldNumbers(Array(musicFrame[topOffset..<(topOffset + playInfoLength)]))
else { fatalError("PlayInfo inválido") }
guard found.contains(1), found.contains(2), found.contains(3),
      !found.contains(7) else { fatalError("PlayInfo usa erróneamente campo 7 de carátula") }
print("PlayInfo 902: título/artista/álbum presentes, campo 7 reservado para album art")