import Foundation

func checkLE(_ pass: @autoclosure () -> Bool, _ label: String) {
    if !pass() { fatalError("MotoFile LE: " + label) }
}
let request = MotoFileLEProbe.request()
let expected = Data([0xAA, 0x0A, 0x00, 0x00, 0x20, 0x05,
                     0x08, 0x01, 0x20, 0x80, 0x80, 0x01, 0x0F, 0x79])
checkLE(request == expected, "solicitud 20/05 verificada (version=1, max=16384)")
checkLE(request.count == 14, "solo negociación; no se envía foto")
checkLE(!MotoFileLEProbe.isFileTransmissionCandidate(request), "no tratar 20/05 como respuesta")
// Datos de protocolo, sin contenido privado: respuesta 20/85 de Motorola.
let reply = Data([0xAA, 0x0D, 0x00, 0x00, 0x20, 0x85,
                  0x08, 0x01, 0x18, 0x80, 0x28,
                  0x20, 0x80, 0x80, 0x01, 0xE5, 0x51])
checkLE(MotoFileLEProbe.isFileTransmissionCandidate(reply), "20/85 es respuesta Motorola")
checkLE(MotoFileLEProbe.reply(reply) ==
        .init(protocolVersion: 1, maxDataSize: 16384, transferUnitSize: 5120),
        "parsear campos 1/3/4, longitud y CRC de respuesta real")
var corrupted = Array(reply)
corrupted[7] ^= 1
checkLE(MotoFileLEProbe.reply(Data(corrupted)) == nil, "rechazar CRC alterado")
checkLE(MotoFileLEProbe.reply(Data(Array(reply).dropLast())) == nil, "rechazar truncamiento")
var otherCommand = Array(reply)
otherCommand[5] = 0x84
checkLE(!MotoFileLEProbe.isFileTransmissionCandidate(Data(otherCommand)),
        "ignorar 20/84 (ACK de bloque)")
checkLE(MotoFileLEProbe.reply(Data(otherCommand)) == nil, "rechazar CID no solicitado")
print("MotoFt 20/05->20/85: bytes, CRC, tamaños y rechazo de errores OK")
