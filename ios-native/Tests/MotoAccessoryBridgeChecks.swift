import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError("MotoAccessoryBridgeKit: " + message) }
}

let when = Date(timeIntervalSince1970: 1_700_000_000)

guard case .notification(let notice)? =
    MotoAccessoryBridgeKit.notification(source: " WhatsApp ", sender: " Ana ",
                                       message: " Hola ", at: when) else {
    fatalError("Falta normalización de Atajos")
}
require(notice.sourceApp == "WhatsApp", "nombre de aplicación")
require(notice.sender == "Ana", "remitente")
require(notice.message == "Hola", "mensaje")
require(notice.receivedAt == when, "fecha original")
require(MotoAccessoryBridgeKit.notification(source: "iWatch", sender: "",
                                            message: "  ") == nil,
        "rechazar contenido vacío")

guard case .weather(let weather)? =
    MotoAccessoryBridgeKit.weather(city: " Córdoba ", temperatureCelsius: 22.5,
                                  condition: "Despejado", at: when) else {
    fatalError("Falta modelo de clima")
}
require(weather.city == "Córdoba", "localidad normalizada")
require(weather.temperatureCelsius == 22.5, "temperatura")
require(MotoAccessoryBridgeKit.weather(city: "", temperatureCelsius: 20,
                                       condition: "Sol") == nil,
        "rechazar localidad ausente")
require(MotoAccessoryBridgeKit.weather(city: "Córdoba",
                                       temperatureCelsius: .infinity,
                                       condition: "Sol") == nil,
        "rechazar temperatura no finita")

guard case .phoneLocation(let location)? =
    MotoAccessoryBridgeKit.phoneLocation(latitude: -31.4, longitude: -64.2,
                                        accuracyMeters: 12.0, at: when) else {
    fatalError("Falta modelo de ubicación")
}
require(location.latitude == -31.4, "latitud válida")
require(location.observedAt == when, "timestamp original")
require(MotoAccessoryBridgeKit.phoneLocation(latitude: 100,
                                             longitude: 0, accuracyMeters: 10) == nil,
        "rechazar latitud fuera de rango")
require(MotoAccessoryBridgeKit.phoneLocation(latitude: 0,
                                             longitude: 0, accuracyMeters: -1) == nil,
        "rechazar precisión negativa")
print("MotoAccessoryBridgeKit: entradas verificadas, sin escritura BLE")
