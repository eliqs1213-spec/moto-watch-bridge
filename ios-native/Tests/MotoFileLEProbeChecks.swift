import Foundation

func checkLE(_ pass: @autoclosure () -> Bool, _ label: String) {
    if !pass() { fatalError("MotoFile LE: " + label) }
}
let request = MotoFileLEProbe.request()
let bytes = Array(request)
checkLE(bytes.prefix(11).elementsEqual([0xAA, 0x09, 0x00, 0x00, 0x20, 0x05,
                                         0x08, 0x01, 0x20, 0x80, 0x08]),
        "20/05 version=1 max=1024")
checkLE(bytes.count == 13 && MotoFileLEProbe.isFileTransmissionCandidate(request),
        "solamente 13 bytes, sin foto ni operaciones de escritura de archivos")
checkLE(MotoFileLEProbe.reply(request) == .init(protocolVersion: 1,
                                                maxDataSize: 1024,
                                                transferUnitSize: nil),
        "respuesta FileTransmission sintética")
var corrupted = bytes
corrupted[7] ^= 1
checkLE(MotoFileLEProbe.reply(Data(corrupted)) == nil, "CRC defectuoso")
checkLE(MotoFileLEProbe.reply(Data(bytes.dropLast())) == nil, "truncamiento")
var wrongCommand = bytes
wrongCommand[5] = 0x02
checkLE(!MotoFileLEProbe.isFileTransmissionCandidate(Data(wrongCommand)),
        "ignorar comandos de apertura de transferencia")
checkLE(MotoFileLEProbe.reply(Data(wrongCommand)) == nil, "ignorar otro comando")
print("MotoFt: prueba LE 20/05, CRC y guardas: OK")
