import Foundation

// Generador de prueba manual del mensaje meteorológico Motorola 23/01.
// No está validada todavía la interpretación de unidades ni los códigos de iconos.
enum WatchWeatherProtocol {
    enum EncodingError: Error { case invalidSnapshot, oversizedFrame }
    private static func vint(_ value: UInt64) -> [UInt8] {
        var n = value; var result: [UInt8] = []
        repeat {
            var x = UInt8(n & 127); n >>= 7
            if n != 0 { x |= 128 }
            result.append(x)
        } while n != 0
        return result
    }
    private static func num(_ key: Int, _ value: Int64) -> [UInt8] {
        vint(UInt64(key * 8)) + vint(UInt64(bitPattern: value))
    }
    private static func field(_ key: Int, _ value: [UInt8]) -> [UInt8] {
        vint(UInt64(key * 8 + 2)) + vint(UInt64(value.count)) + value
    }
    private static func string(_ key: Int, _ value: String) -> [UInt8] {
        field(key, Array(value.utf8))
    }
    private static func icon(_ wmo: Int) -> Int {
        switch wmo {
        case 0: return 1
        case 1, 2: return 4
        case 3: return 7
        case 45, 48: return 11
        case 51...67, 80...82: return 12
        case 71...77, 85, 86: return 22
        case 95...99: return 15
        default: return 7
        }
    }
    // El reloj informó Celsius por 23/05 y el modelo AttendCity oficial
    // contiene unitTemp (campo 9). Enviar temperaturas coherentes en °C.
    private static func temp(_ c: Double) -> Int64 { Int64(c.rounded()) }
    private static func timestamp(_ value: String, tz: TimeZone) -> Int64? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = tz
        fmt.dateFormat = value.count == 10 ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm"
        guard let date = fmt.date(from: value) else { return nil }
        return Int64(date.timeIntervalSince1970 * 1000)
    }
    static func encode(_ snapshot: WatchWeatherSnapshot) throws -> Data {
        guard snapshot.hours.count == 24, snapshot.days.count == 6,
              let tz = TimeZone(identifier: snapshot.timezone),
              abs(snapshot.fetchedAt.timeIntervalSinceNow) < 1800 else {
            throw EncodingError.invalidSnapshot
        }
        var city = string(1, "iWatch-local")
        city += string(2, snapshot.city)
        city += string(8, tz.abbreviation() ?? "GMT")
        city += num(9, 1)  // AttendCity.unitTemp: 1 = Celsius (verificado por 23/05)
        city += num(10, Int64(icon(snapshot.code)))
        city += num(11, temp(snapshot.temperatureCelsius))
        city += num(12, 1)
        city += num(22, Int64(snapshot.humidityPercent))
        city += string(23, snapshot.summary)
        city += num(40, 1)
        for day in snapshot.days {
            guard let date = timestamp(day.localDate, tz: tz) else { throw EncodingError.invalidSnapshot }
            let dayBytes = num(1, Int64(icon(day.code))) + num(2, Int64(icon(day.code)))
                + num(3, temp(day.highCelsius)) + num(4, temp(day.lowCelsius))
                + num(5, date) + string(8, OpenMeteoWeatherForecast.condition(day.code))
            city += field(20, dayBytes)
        }
        for hour in snapshot.hours {
            guard let date = timestamp(hour.localTime, tz: tz) else { throw EncodingError.invalidSnapshot }
            let hourBytes = num(1, Int64(icon(hour.code))) + num(2, temp(hour.temperatureCelsius))
                + num(3, date) + num(8, Int64(hour.rainChance))
                + string(5, OpenMeteoWeatherForecast.condition(hour.code))
            city += field(21, hourBytes)
        }
        let payload = field(2, city) + string(4, "es")
        let body: [UInt8] = [0x23, 0x01] + payload
        let n = body.count + 2
        guard n < 65536 else { throw EncodingError.oversizedFrame }
        let header: [UInt8] = [0xaa, UInt8(n & 255), UInt8(n >> 8), 0] + body
        let crc = MotoProtocol.crc16Xmodem(header[...])
        return Data(header + [UInt8(crc & 255), UInt8(crc >> 8)])
    }
    // En una prueba real CoreBluetooth informó 512 bytes, pero el reloj rechazó
    // esa escritura con "Writing is not permitted". Otros comandos de 8-20
    // bytes sí funcionaron. Limitamos SOLO el clima a 20 bytes por escritura,
    // con confirmación ATT por fragmento. No supone que el firmware rearme la trama.
    static func conservativeWriteLimit(reportedMaximum: Int) -> Int? {
        guard reportedMaximum >= 20 else { return nil }
        return min(20, reportedMaximum)
    }

    static func fragments(_ frame: Data, maximum: Int) -> [Data] {
        guard maximum >= 20 else { return [] }
        return stride(from: 0, to: frame.count, by: maximum).map {
            frame.subdata(in: $0..<min(frame.count, $0 + maximum))
        }
    }
}
