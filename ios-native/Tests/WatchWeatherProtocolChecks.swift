import Foundation

func expectWeatherBLE(_ yes: @autoclosure () -> Bool, _ what: String) {
    if !yes() { fatalError("Weather BLE: " + what) }
}
let base = Date()
let formatter = DateFormatter()
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.timeZone = TimeZone(identifier: "America/Argentina/Cordoba")
formatter.dateFormat = "yyyy-MM-dd"
let days = (0..<6).map { i -> WatchWeatherDay in
    let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: i, to: base)!
    return WatchWeatherDay(localDate: formatter.string(from: d), lowCelsius: 12, highCelsius: 25, code: 2)
}
formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
let hours = (0..<24).map { i -> WatchWeatherHour in
    let d = Calendar(identifier: .gregorian).date(byAdding: .hour, value: i, to: base)!
    return WatchWeatherHour(localTime: formatter.string(from: d), temperatureCelsius: 23,
                            code: 2, rainChance: 15)
}
let s = WatchWeatherSnapshot(city: "Prueba", temperatureCelsius: 23, humidityPercent: 45,
    windKmh: 12, code: 2, timezone: "America/Argentina/Cordoba",
    hours: hours, days: days, fetchedAt: base)
let frame = try WatchWeatherProtocol.encode(s)
let b = Array(frame)
// Capturas originales de Motorola: AA + longitud varint + 00 00 + 23 01.
// No confundir con LE16 de los comandos cortos.
func parseMotoWeatherHeader(_ bytes: [UInt8]) -> (length: Int, commandOffset: Int)? {
    guard bytes.first == 0xAA else { return nil }
    var length = 0
    var shift = 0
    var index = 1
    while index < bytes.count && shift <= 21 {
        let byte = Int(bytes[index])
        length |= (byte & 0x7F) << shift
        index += 1
        if (byte & 0x80) == 0 {
            guard index + 2 < bytes.count,
                  bytes[index] == 0, bytes[index + 1] == 0 else { return nil }
            return (length, index + 2)
        }
        shift += 7
    }
    return nil
}
guard let header = parseMotoWeatherHeader(b) else {
    fatalError("Weather BLE: encabezado varint inválido")
}
expectWeatherBLE(b[header.commandOffset] == 0x23 && b[header.commandOffset + 1] == 0x01,
    "cabecera 23/01 después del prefijo variable")
expectWeatherBLE(header.length + header.commandOffset == b.count, "longitud varint exacta")
expectWeatherBLE(b[1] & 0x80 != 0 && b[2] & 0x80 == 0,
    "paquetes meteorológicos de prueba >127 usan varint de dos bytes")
expectWeatherBLE(MotoProtocol.crc16Xmodem(b.dropLast(2)) ==
    UInt16(b[b.count-2]) | (UInt16(b[b.count-1]) << 8), "CRC")
// Contrastado con Motorola MotoWeather.AttendCity: #9 unitTemp, #11 temp.
func hasBytes(_ sequence: [UInt8], within bytes: [UInt8]) -> Bool {
    guard !sequence.isEmpty, bytes.count >= sequence.count else { return false }
    return (0...(bytes.count - sequence.count)).contains { start in
        Array(bytes[start..<(start + sequence.count)]) == sequence
    }
}
expectWeatherBLE(hasBytes([0x48, 0x01, 0x50], within: b),
    "AttendCity marca Celsius antes de weatherId")
expectWeatherBLE(hasBytes([0x58, 0x17], within: b),
    "temperatura 23°C en protobuf; no Fahrenheit 73°F")
expectWeatherBLE(hasBytes([0x18, 0x19, 0x20, 0x0C], within: b),
    "máxima 25°C y mínima 12°C del pronóstico diario")
let chunks = WatchWeatherProtocol.fragments(frame, maximum: 120)
expectWeatherBLE(chunks.count > 1, "fragmentación")
expectWeatherBLE(chunks.allSatisfy { $0.count <= 120 }, "MTU máximo")
expectWeatherBLE(Data(chunks.flatMap { $0 }) == frame, "reensamblado sin pérdidas")
// Caso real de la 885: MTU informado=512, primera escritura de 512 rechazada.
// Nueva prueba: segmentos ATT conservadores, sin cambiar ni perder bytes.
expectWeatherBLE(WatchWeatherProtocol.conservativeWriteLimit(reportedMaximum: 512) == 20,
                 "un máximo de 512 no obliga al reloj a aceptar 512")
expectWeatherBLE(WatchWeatherProtocol.conservativeWriteLimit(reportedMaximum: 20) == 20,
                 "enlace con longitud ATT de 20")
expectWeatherBLE(WatchWeatherProtocol.conservativeWriteLimit(reportedMaximum: 19) == nil,
                 "no iniciar si iOS no admite 20 bytes")
let safe = WatchWeatherProtocol.fragments(frame, maximum:
    WatchWeatherProtocol.conservativeWriteLimit(reportedMaximum: 512)!)
expectWeatherBLE(safe.count > 2 && safe.allSatisfy { (1...20).contains($0.count) },
                 "ninguna escritura de clima excede 20 bytes")
expectWeatherBLE(Data(safe.flatMap { $0 }) == frame,
                 "trama 23/01, CRC y orden conservados")
let reproduced = Data(repeating: 0x42, count: 945)
let candidate = WatchWeatherProtocol.fragments(reproduced, maximum: 20)
expectWeatherBLE(candidate.count == 48, "945 bytes se transmiten en 48 fragmentos")
expectWeatherBLE(Data(candidate.flatMap { $0 }) == reproduced,
                 "reensamblado 945 bytes exacto")

var expired = s
// Struct con propiedades let: crear otro snapshot vencido
let old = WatchWeatherSnapshot(city:s.city,temperatureCelsius:s.temperatureCelsius,
 humidityPercent:s.humidityPercent,windKmh:s.windKmh,code:s.code,timezone:s.timezone,
 hours:s.hours,days:s.days,fetchedAt:Date().addingTimeInterval(-3600))
do { _ = try WatchWeatherProtocol.encode(old); fatalError("Pronóstico viejo aceptado") }
catch WatchWeatherProtocol.EncodingError.invalidSnapshot {}
print("WatchWeatherProtocol: protobuf 23/01, CRC, longitud, MTU y vencimiento OK")
