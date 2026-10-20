import Foundation
import Combine
import CoreLocation

@MainActor
final class WatchWeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WatchWeatherService()

    @Published private(set) var snapshot: WatchWeatherSnapshot?
    @Published private(set) var status = "Pronóstico disponible al solicitarlo"
    @Published private(set) var isLoading = false

    private let location = CLLocationManager()
    private override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // Nunca se solicita ubicación ni se inicia HTTP sin pulsar el botón.
    func requestWeather() {
        guard !isLoading else { return }
        isLoading = true
        switch location.authorizationStatus {
        case .notDetermined:
            status = "Esperando permiso de ubicación…"
            location.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestOneLocation()
        case .restricted, .denied:
            fail("Permití ubicación para iWatch desde Ajustes de iOS.")
        @unknown default:
            fail("No se pudo comprobar el permiso de ubicación.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isLoading else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestOneLocation()
        case .denied, .restricted:
            fail("No se autorizó el acceso a ubicación.")
        case .notDetermined: break
        @unknown default:
            fail("Estado de ubicación desconocido.")
        }
    }

    private func requestOneLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            fail("Activá Localización en Ajustes para consultar el clima.")
            return
        }
        status = "Obteniendo ubicación aproximada…"
        location.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLoading, let latest = locations.last else { return }
        guard latest.horizontalAccuracy >= 0 else {
            fail("No se obtuvo una ubicación válida.")
            return
        }
        status = "Consultando pronóstico por Internet…"
        let latitude = latest.coordinate.latitude
        let longitude = latest.coordinate.longitude
        Task {
            do {
                let url = try OpenMeteoWeatherForecast.requestURL(latitude: latitude, longitude: longitude)
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw OpenMeteoWeatherForecast.ForecastError.incompleteForecast
                }
                let value = try OpenMeteoWeatherForecast.decode(data, city: "Ubicación actual")
                guard MotoAccessoryBridgeKit.weather(city: value.city,
                         temperatureCelsius: value.temperatureCelsius,
                         condition: value.summary) != nil else {
                    throw OpenMeteoWeatherForecast.ForecastError.incompleteForecast
                }
                snapshot = value
                status = "Clima del iPhone actualizado; todavía no enviado al reloj"
                WatchBLEManager.shared.record("CLIMA-IOS", "Pronóstico válido: 6 días, 24 horas. Sin envío BLE.")
            } catch {
                status = "No se pudo consultar el pronóstico: \(error.localizedDescription)"
                WatchBLEManager.shared.record("CLIMA-IOS", "Consulta fallida: \(type(of: error))")
            }
            isLoading = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isLoading else { return }
        fail("No se pudo obtener la ubicación del iPhone.")
    }

    private func fail(_ message: String) {
        status = message
        isLoading = false
    }
}
