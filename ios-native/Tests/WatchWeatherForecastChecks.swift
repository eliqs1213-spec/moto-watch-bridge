import Foundation

func checkWeather(_ yes: @autoclosure () -> Bool, _ label: String) {
    if !yes() { fatalError("Clima Open-Meteo: " + label) }
}
let url = try OpenMeteoWeatherForecast.requestURL(latitude: -31.416, longitude: -64.188)
let params = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
checkWeather(params.first(where: {$0.name == "latitude"})?.value == "-31.42", "ubicación aproximada")
checkWeather(params.first(where: {$0.name == "forecast_days"})?.value == "6", "seis días")
do {
    _ = try OpenMeteoWeatherForecast.requestURL(latitude: 100, longitude: 0)
    fatalError("Latitud inválida aceptada")
} catch OpenMeteoWeatherForecast.ForecastError.invalidCoordinate {}
let hours = (0..<6).flatMap { day in
    (0..<24).map { String(format: "2026-10-%02dT%02d:00", day+20, $0) }
}
let fixture: [String:Any] = [
    "timezone":"America/Argentina/Cordoba",
    "current":["time":"2026-10-20T12:00","temperature_2m":24.1,"relative_humidity_2m":47,"weather_code":2,"wind_speed_10m":10.3],
    "hourly":["time":hours,"temperature_2m":Array(repeating:20.0,count:144),"weather_code":Array(repeating:2,count:144),"precipitation_probability":Array(repeating:12,count:144)],
    "daily":["time":(20..<26).map{String(format:"2026-10-%02d",$0)},"temperature_2m_min":Array(repeating:14.0,count:6),"temperature_2m_max":Array(repeating:26.0,count:6),"weather_code":Array(repeating:2,count:6)]
]
let snapshot = try OpenMeteoWeatherForecast.decode(JSONSerialization.data(withJSONObject:fixture),city:"Córdoba")
checkWeather(snapshot.days.count == 6, "días")
checkWeather(snapshot.hours.count == 24, "24 horas")
checkWeather(snapshot.hours.first?.localTime == "2026-10-20T12:00", "hora actual")
checkWeather(snapshot.summary == "Parcialmente nublado", "código meteorológico")
print("WeatherForecast: 6 días / 24 horas y URL aproximada: OK")
