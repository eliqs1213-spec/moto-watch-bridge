import Foundation

func checkWeather(_ yes: @autoclosure () -> Bool, _ label: String) {
    if !yes() { fatalError("Clima Open-Meteo: " + label) }
}
let url = try OpenMeteoWeatherForecast.requestURL(latitude: -31.416, longitude: -64.188)
let params = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
checkWeather(params.first(where: {$0.name == "latitude"})?.value == "-31.42", "ubicación aproximada")
checkWeather(params.first(where: {$0.name == "forecast_days"})?.value == "6", "seis días")
checkWeather(params.first(where: {$0.name == "daily"})?.value?.contains("sunrise,sunset") == true,
             "solicitud de amanecer/atardecer")
checkWeather(params.first(where: {$0.name == "current"})?.value?.contains("apparent_temperature") == true,
             "solicitud de temperatura aparente")
do {
    _ = try OpenMeteoWeatherForecast.requestURL(latitude: 100, longitude: 0)
    fatalError("Latitud inválida aceptada")
} catch OpenMeteoWeatherForecast.ForecastError.invalidCoordinate {}
let hours = (0..<6).flatMap { day in
    (0..<24).map { String(format: "2026-10-%02dT%02d:00", day+20, $0) }
}
let fixture: [String:Any] = [
    "timezone":"America/Argentina/Cordoba",
    "current":["time":"2026-10-20T12:00","temperature_2m":24.1,"apparent_temperature":22.0,"relative_humidity_2m":47,"weather_code":2,"wind_speed_10m":10.3],
    "hourly":["time":hours,"temperature_2m":Array(repeating:20.0,count:144),"weather_code":Array(repeating:2,count:144),"precipitation_probability":Array(repeating:12,count:144)],
    "daily":["time":(20..<26).map{String(format:"2026-10-%02d",$0)},"temperature_2m_min":Array(repeating:14.0,count:6),"temperature_2m_max":Array(repeating:26.0,count:6),"weather_code":Array(repeating:2,count:6),
             "sunrise":(20..<26).map{String(format:"2026-10-%02dT06:30",$0)},
             "sunset":(20..<26).map{String(format:"2026-10-%02dT19:15",$0)}]
]
let snapshot = try OpenMeteoWeatherForecast.decode(JSONSerialization.data(withJSONObject:fixture),city:"Córdoba")
checkWeather(snapshot.days.count == 6, "días")
checkWeather(snapshot.days[0].sunriseLocalTime == "2026-10-20T06:30", "amanecer local")
checkWeather(snapshot.days[0].sunsetLocalTime == "2026-10-20T19:15", "atardecer local")
checkWeather(snapshot.apparentTemperatureCelsius == 22, "sensación térmica")
checkWeather(OpenMeteoWeatherForecast.cityLabel(locality:"Villa Allende", province:"Córdoba") == "Villa Allende - Córdoba", "localidad")
checkWeather(snapshot.hours.count == 24, "24 horas")
checkWeather(snapshot.hours.first?.localTime == "2026-10-20T12:00", "hora actual")
checkWeather(snapshot.summary == "Parcialmente nublado", "código meteorológico")
let tick = Date()
checkWeather(!WatchWeatherAutoPolicy.shouldFetch(
    fetchedAt: tick.addingTimeInterval(-3500), deliveredInConnection: true, now: tick),
    "sin repetir la descarga en una hora activa")
checkWeather(WatchWeatherAutoPolicy.shouldFetch(
    fetchedAt: tick.addingTimeInterval(-3601), deliveredInConnection: true, now: tick),
    "consulta tras cumplir 60 min")
checkWeather(WatchWeatherAutoPolicy.shouldFetch(
    fetchedAt: tick.addingTimeInterval(-1801), deliveredInConnection: false, now: tick),
    "reconexión exige pronóstico transmitible menor a 30 min")
checkWeather(!WatchWeatherAutoPolicy.canRetry(lastAttempt: tick.addingTimeInterval(-599), now: tick),
    "se limita reintento de error a 10 min")
print("WeatherForecast: 6 días / 24 horas, actualización automática, localidad y URL aproximada: OK")
