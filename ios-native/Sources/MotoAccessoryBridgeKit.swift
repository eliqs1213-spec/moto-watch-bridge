import Foundation

// Núcleo de adaptación de datos autorizados del iPhone para Moto Watch Fit.
// No consulta notificaciones de terceros, no accede al firmware y no escribe BLE.
// Las rutas meteorológicas y GPS solo tendrán salida al reloj después de
// verificar codificación, unidades y respuestas frente a capturas Motorola.
enum MotoAccessoryEvent: Equatable {
    case notification(AccessoryNotification)
    case weather(AccessoryWeather)
    case phoneLocation(AccessoryLocation)
}

struct AccessoryNotification: Equatable {
    let sourceApp: String
    let sender: String
    let message: String
    let receivedAt: Date
}

struct AccessoryWeather: Equatable {
    let city: String
    let temperatureCelsius: Double
    let condition: String
    let observedAt: Date
}

struct AccessoryLocation: Equatable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyMeters: Double
    let observedAt: Date
}

enum MotoAccessoryBridgeKit {
    // WhatsApp funciona actualmente por Atajos → SendWatchNotificationIntent
    // → WatchBLEManager. Este adaptador es preparatorio; no reemplaza esa ruta.
    static func notification(source: String, sender: String, message: String,
                             at date: Date = Date()) -> MotoAccessoryEvent? {
        let app = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !app.isEmpty, !text.isEmpty else { return nil }
        return .notification(AccessoryNotification(
            sourceApp: String(app.prefix(80)),
            sender: String(sender.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
            message: String(text.prefix(400)),
            receivedAt: date
        ))
    }

    // Entrada desde un futuro proveedor de clima autorizado. No hay todavía
    // un codificador 23/01 activado: el .proto confirma campos, no todos los
    // códigos de condiciones ni las unidades observadas en el firmware.
    static func weather(city: String, temperatureCelsius: Double,
                        condition: String, at date: Date = Date()) -> MotoAccessoryEvent? {
        let cityName = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cityName.isEmpty, !description.isEmpty,
              temperatureCelsius.isFinite,
              temperatureCelsius >= -100, temperatureCelsius <= 75 else {
            return nil
        }
        return .weather(AccessoryWeather(
            city: cityName,
            temperatureCelsius: temperatureCelsius,
            condition: description,
            observedAt: date
        ))
    }

    // Entrada desde Core Location, exclusivamente tras permiso del usuario.
    // No interpreta la ubicación del teléfono como una ruta GPS del reloj.
    static func phoneLocation(latitude: Double, longitude: Double,
                              accuracyMeters: Double,
                              at date: Date = Date()) -> MotoAccessoryEvent? {
        guard latitude.isFinite, longitude.isFinite, accuracyMeters.isFinite,
              latitude >= -90, latitude <= 90,
              longitude >= -180, longitude <= 180,
              accuracyMeters >= 0 else {
            return nil
        }
        return .phoneLocation(AccessoryLocation(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracyMeters: accuracyMeters,
            observedAt: date
        ))
    }
}
