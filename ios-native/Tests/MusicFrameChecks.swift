import Foundation

func assertMusic(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

func hasValidMusicFraming(_ data: Data) -> Bool {
    let bytes = Array(data)
    guard bytes.count >= 8, bytes[0] == 0xAA, bytes[4] == 0x24, bytes[5] == 0x01 else { return false }
    let length = Int(bytes[1]) | (Int(bytes[2]) << 8)
    guard length + 4 == bytes.count else { return false }
    let crc = MotoProtocol.crc16Xmodem(bytes.dropLast(2))
    return UInt8(crc & 0xFF) == bytes[bytes.count - 2] &&
           UInt8(crc >> 8) == bytes[bytes.count - 1]
}

let music = WatchMusicSnapshot(
    id: "synthetic-fixture",
    title: "Canción de prueba 🎵",
    artist: "Artista de prueba",
    album: "Disco de prueba",
    durationMs: 220_000,
    progressMs: 33_000,
    isPlaying: true
)
let announcement = WatchMusicProtocol.encode(music, code: .two)
let playing = WatchMusicProtocol.encode(music, code: .empty)
let paused = WatchMusicProtocol.encode(music, code: .one)
let noMusic = WatchMusicProtocol.encodeNoMusic()

assertMusic(hasValidMusicFraming(announcement), "Anuncio 24/01 mal formado")
assertMusic(hasValidMusicFraming(playing), "Reproducción estable mal formada")
assertMusic(hasValidMusicFraming(paused), "Pausa mal formada")
assertMusic(hasValidMusicFraming(noMusic), "Paquete de reposo mal formado")
assertMusic(announcement.count == playing.count + 2, "El anuncio debe tener dos bytes adicionales de estado")
assertMusic(paused.count == playing.count + 2, "La pausa debe tener dos bytes adicionales de estado")
assertMusic(noMusic.count == 16, "El paquete experimental de reposo cambió de tamaño")
assertMusic(announcement != paused, "Anuncio y pausa no deben ser iguales")
var invalid = announcement
invalid[invalid.count - 1] ^= 0x01
assertMusic(!hasValidMusicFraming(invalid), "CRC corrupto aceptado")
print("Music frame checks passed: 24/01 length, CRC, announcement, state, pause, idle")
