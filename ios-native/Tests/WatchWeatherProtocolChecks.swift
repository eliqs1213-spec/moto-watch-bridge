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
expectWeatherBLE(b[0] == 0xAA && b[4] == 0x23 && b[5] == 0x01, "cabecera 23/01")
expectWeatherBLE(Int(b[1]) + (Int(b[2]) << 8) + 4 == b.count, "longitud")
expectWeatherBLE(MotoProtocol.crc16Xmodem(b.dropLast(2)) ==
    UInt16(b[b.count-2]) | (UInt16(b[b.count-1]) << 8), "CRC")
let chunks = WatchWeatherProtocol.fragments(frame, maximum: 120)
expectWeatherBLE(chunks.count > 1, "fragmentación")
expectWeatherBLE(chunks.allSatisfy { $0.count <= 120 }, "MTU máximo")
expectWeatherBLE(Data(chunks.flatMap { $0 }) == frame, "reensamblado sin pérdidas")
var expired = s
// Struct con propiedades let: crear otro snapshot vencido
let old = WatchWeatherSnapshot(city:s.city,temperatureCelsius:s.temperatureCelsius,
 humidityPercent:s.humidityPercent,windKmh:s.windKmh,code:s.code,timezone:s.timezone,
 hours:s.hours,days:s.days,fetchedAt:Date().addingTimeInterval(-3600))
do { _ = try WatchWeatherProtocol.encode(old); fatalError("Pronóstico viejo aceptado") }
catch WatchWeatherProtocol.EncodingError.invalidSnapshot {}
print("WatchWeatherProtocol: protobuf 23/01, CRC, longitud, MTU y vencimiento OK")
