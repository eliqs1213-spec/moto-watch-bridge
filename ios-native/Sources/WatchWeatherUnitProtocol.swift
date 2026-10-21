import Foundation

// Protocolo de unidad meteorológica derivado de la APK oficial Moto Watch.
// WEATHER=0x23, SET_WEATHER_UNIT=0x04, GET_WEATHER_UNIT=0x05.
// WeatherUnitInfo usa el campo protobuf #1 (varint). El valor 1 (Celsius)
// se infiere de la selección predeterminada por país; requiere validación en Fit.
enum WatchTemperatureUnit: UInt8 {
    case fahrenheit = 0
    case celsius = 1

    var label: String {
        switch self {
        case .fahrenheit: return "Fahrenheit (°F)"
        case .celsius: return "Celsius (°C)"
        }
    }
}

enum WatchWeatherUnitProtocol {
    private static func frame(command: UInt8, payload: [UInt8]) -> Data {
        let length = 4 + payload.count
        let header: [UInt8] = [0xAA, UInt8(length), 0x00, 0x00, 0x23, command] + payload
        let crc = MotoProtocol.crc16Xmodem(header[...])
        return Data(header + [UInt8(crc & 0xFF), UInt8(crc >> 8)])
    }

    static func set(_ unit: WatchTemperatureUnit) -> Data {
        frame(command: 0x04, payload: [0x08, unit.rawValue])
    }

    static func get() -> Data {
        frame(command: 0x05, payload: [])
    }

    static func unitFromGetResponse(_ data: Data) -> WatchTemperatureUnit? {
        let b = Array(data)
        guard b.count == 10, b[0] == 0xAA, b[1] == 0x06, b[2] == 0,
              b[3] == 0, b[4] == 0x23, b[5] == 0x05, b[6] == 0x08,
              MotoProtocol.crc16Xmodem(b.dropLast(2)) ==
                (UInt16(b[8]) | UInt16(b[9]) << 8) else { return nil }
        return WatchTemperatureUnit(rawValue: b[7])
    }
}
