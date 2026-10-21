import Foundation

struct WatchWeatherHour: Equatable {
    let localTime: String
    let temperatureCelsius: Double
    let code: Int
    let rainChance: Int
}
struct WatchWeatherDay: Equatable {
    let localDate: String
    let sunriseLocalTime: String
    let sunsetLocalTime: String
    let lowCelsius: Double
    let highCelsius: Double
    let code: Int
}
struct WatchWeatherSnapshot: Equatable {
    let city: String
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double
    let humidityPercent: Int
    let windKmh: Double
    let code: Int
    let timezone: String
    let hours: [WatchWeatherHour]
    let days: [WatchWeatherDay]
    let fetchedAt: Date
    var summary: String { OpenMeteoWeatherForecast.condition(code) }
}

enum WatchWeatherAutoPolicy {
    static let forecastInterval: TimeInterval = 3600
    static let transportFreshness: TimeInterval = 1800
    static let failureRetry: TimeInterval = 600

    static func shouldFetch(fetchedAt: Date, deliveredInConnection: Bool, now: Date) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        return age >= (deliveredInConnection ? forecastInterval : transportFreshness)
    }
    static func canRetry(lastAttempt: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastAttempt) >= failureRetry
    }
}

enum OpenMeteoWeatherForecast {
    struct Response: Decodable {
        let timezone: String
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }
    struct Current: Decodable {
        let time: String
        let temperature_2m: Double
        let apparent_temperature: Double
        let relative_humidity_2m: Int
        let wind_speed_10m: Double
        let weather_code: Int
    }
    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let weather_code: [Int]
        let precipitation_probability: [Int]
    }
    struct Daily: Decodable {
        let time: [String]
        let temperature_2m_min: [Double]
        let temperature_2m_max: [Double]
        let weather_code: [Int]
        let sunrise: [String]
        let sunset: [String]
    }
    enum ForecastError: LocalizedError {
        case invalidCoordinate, incompleteForecast
        var errorDescription: String? {
            switch self {
            case .invalidCoordinate: return "Ubicación inválida."
            case .incompleteForecast: return "El proveedor devolvió un pronóstico incompleto."
            }
        }
    }

    // Ubicación aproximada (~1 km) enviada solo por una acción explícita.
    static func requestURL(latitude: Double, longitude: Double) throws -> URL {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw ForecastError.invalidCoordinate
        }
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "6"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh")
        ]
        return url.url!
    }

    static func decode(_ data: Data, city: String, at date: Date = Date()) throws -> WatchWeatherSnapshot {
        let source = try JSONDecoder().decode(Response.self, from: data)
        let daily = source.daily
        let hourly = source.hourly
        guard !source.timezone.isEmpty,
              daily.time.count >= 6,
              daily.temperature_2m_min.count >= 6, daily.temperature_2m_max.count >= 6,
              daily.weather_code.count >= 6,
              daily.sunrise.count >= 6, daily.sunset.count >= 6,
              hourly.time.count == hourly.temperature_2m.count,
              hourly.time.count == hourly.weather_code.count,
              hourly.time.count == hourly.precipitation_probability.count,
              source.current.temperature_2m.isFinite,
              source.current.apparent_temperature.isFinite,
              source.current.wind_speed_10m.isFinite, source.current.wind_speed_10m >= 0,
              (0...100).contains(source.current.relative_humidity_2m) else {
            throw ForecastError.incompleteForecast
        }
        // Open-Meteo retorna horas locales. Comenzamos desde la hora actual.
        let currentHour = String(source.current.time.prefix(13))
        guard let first = hourly.time.firstIndex(where: { $0 >= currentHour }),
              hourly.time.count - first >= 24 else {
            throw ForecastError.incompleteForecast
        }
        let hours = (first..<(first + 24)).map {
            WatchWeatherHour(localTime: hourly.time[$0],
                             temperatureCelsius: hourly.temperature_2m[$0],
                             code: hourly.weather_code[$0],
                             rainChance: hourly.precipitation_probability[$0])
        }
        let days = (0..<6).map {
            WatchWeatherDay(localDate: daily.time[$0],
                            sunriseLocalTime: daily.sunrise[$0],
                            sunsetLocalTime: daily.sunset[$0],
                            lowCelsius: daily.temperature_2m_min[$0],
                            highCelsius: daily.temperature_2m_max[$0],
                            code: daily.weather_code[$0])
        }
        guard hours.allSatisfy({ $0.temperatureCelsius.isFinite && (0...100).contains($0.rainChance) }),
              days.allSatisfy({ $0.lowCelsius.isFinite && $0.highCelsius.isFinite }) else {
            throw ForecastError.incompleteForecast
        }
        return WatchWeatherSnapshot(city: city, temperatureCelsius: source.current.temperature_2m,
            apparentTemperatureCelsius: source.current.apparent_temperature,
            humidityPercent: source.current.relative_humidity_2m,
            windKmh: source.current.wind_speed_10m, code: source.current.weather_code,
            timezone: source.timezone, hours: hours, days: days, fetchedAt: date)
    }

    static func cityLabel(locality: String?, province: String?) -> String {
        let city = locality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let area = province?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !city.isEmpty && !area.isEmpty && city.localizedCaseInsensitiveCompare(area) != .orderedSame {
            return "\(city) - \(area)"
        }
        if !city.isEmpty { return city }
        if !area.isEmpty { return area }
        return "Ubicación sin identificar"
    }

    static func condition(_ code: Int) -> String {
        switch code {
        case 0: return "Despejado"
        case 1, 2: return "Parcialmente nublado"
        case 3: return "Nublado"
        case 45, 48: return "Niebla"
        case 51...57: return "Llovizna"
        case 61...67, 80...82: return "Lluvia"
        case 71...77, 85, 86: return "Nieve"
        case 95...99: return "Tormenta"
        default: return "Condición \(code)"
        }
    }
}
