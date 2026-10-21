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

    // Frecuencia objetivo: 1 hora mientras iWatch esté activa y conectada.
    // Si iOS suspende la app, no se promete ejecución puntual en segundo plano.
    private var lastAutomaticAttemptAt = Date.distantPast

    func automaticRefreshIfNeeded(reason: String) {
        guard UIApplication.shared.applicationState == .active,
              WatchBLEManager.shared.isConnected, !isLoading,
              location.authorizationStatus == .authorizedAlways ||
                location.authorizationStatus == .authorizedWhenInUse else { return }

        WatchBLEManager.shared.probeWeatherUnitAutomaticallyIfNeeded()
        let now = Date()
        if let value = snapshot {
            _ = WatchBLEManager.shared.synchronizeWeatherAutomatically(value)
            if !WatchWeatherAutoPolicy.shouldFetch(
                fetchedAt: value.fetchedAt, deliveredInConnection:
                    WatchBLEManager.shared.weatherDeliveredThisConnection, now: now) { return }
        }
        guard WatchWeatherAutoPolicy.canRetry(lastAttempt: lastAutomaticAttemptAt, now: now) else { return }
        lastAutomaticAttemptAt = now
        WatchBLEManager.shared.record("CLIMA-AUTO", "Actualización solicitada: \(reason)")
        beginWeatherRequest(automatic: true)
    }

    func synchronizeAvailableForecast() {
        guard UIApplication.shared.applicationState == .active else { return }
        if let value = snapshot {
            _ = WatchBLEManager.shared.synchronizeWeatherAutomatically(value)
        }
        automaticRefreshIfNeeded(reason: "unidad °C verificada")
    }

    // Botón para conceder el permiso inicial o actualizar inmediatamente.
    func requestWeather() {
        beginWeatherRequest(automatic: false)
    }

    private func beginWeatherRequest(automatic: Bool) {
        guard !isLoading else { return }
        guard !automatic || UIApplication.shared.applicationState == .active else { return }
        if automatic && location.authorizationStatus == .notDetermined { return }
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
                // Apple resuelve la localidad real; no se usa un nombre fijo.
                let places = try? await CLGeocoder().reverseGeocodeLocation(latest,
                    preferredLocale: Locale(identifier: "es_AR"))
                let place = places?.first
                let label = OpenMeteoWeatherForecast.cityLabel(
                    locality: place?.locality ?? place?.subAdministrativeArea,
                    province: place?.administrativeArea)
                let value = try OpenMeteoWeatherForecast.decode(data, city: label)
                guard MotoAccessoryBridgeKit.weather(city: value.city,
                         temperatureCelsius: value.temperatureCelsius,
                         condition: value.summary) != nil else {
                    throw OpenMeteoWeatherForecast.ForecastError.incompleteForecast
                }
                snapshot = value
                status = "Pronóstico actualizado para \(value.city) · sincronización automática"
                WatchBLEManager.shared.record("CLIMA-IOS", "Pronóstico válido: 6 días, 24 horas. Sincronización automática habilitada.")
                _ = WatchBLEManager.shared.synchronizeWeatherAutomatically(value)
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
