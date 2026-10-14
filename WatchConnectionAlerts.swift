import Foundation
import Combine
import UserNotifications

/// Notificaciones locales de conexión, independientes de WidgetKit y App Groups.
/// Nunca muestra una batería guardada de una sesión anterior: solo una respuesta
/// Motorola 10/01 válida correspondiente a la conexión actual.
final class WatchConnectionAlerts: ObservableObject {
    static let shared = WatchConnectionAlerts()
    @Published private(set) var permissionStatus = "Permiso sin comprobar"
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: "motowatch.connection.alerts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "motowatch.connection.alerts") }
    }

    private let center = UNUserNotificationCenter.current()
    private let lastAlertKey = "motowatch.connection.last.alert.time"
    private let cooldown: TimeInterval = 90

    private init() { refreshPermissionStatus() }

    func refreshPermissionStatus() {
        center.getNotificationSettings { settings in
            let label: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                label = "Avisos permitidos"
            case .denied:
                label = "Avisos desactivados en Ajustes del iPhone"
            case .notDetermined:
                label = "Pendiente: tocar Permitir avisos"
            @unknown default:
                label = "Permiso no disponible"
            }
            DispatchQueue.main.async { self.permissionStatus = label }
        }
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.permissionStatus = "Error de permisos: \(error.localizedDescription)"
                }
                self.refreshPermissionStatus()
            }
        }
    }

    /// Un aviso por conexión, evitando ráfagas tras microcortes BLE.
    func sendConnectedAlert(watchName: String, percentage: Int?) {
        guard enabled else { return }
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: lastAlertKey)
        if last > 0 && now - last < cooldown { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional ||
                  settings.authorizationStatus == .ephemeral else { return }
            let content = UNMutableNotificationContent()
            content.title = "⌚ Moto Watch Fit conectado"
            if let value = percentage, (0...100).contains(value) {
                content.body = "Conexión establecida · Batería del reloj: \(value)%"
            } else {
                content.body = "Conexión establecida · Batería todavía sin lectura"
            }
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "iwatch.connected.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            self.center.add(request) { error in
                if error == nil {
                    UserDefaults.standard.set(now, forKey: self.lastAlertKey)
                } else if let error = error {
                    DispatchQueue.main.async {
                        WatchBLEManager.shared.record("AVISO", "Aviso de conexión: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func sendTestAlert(watchName: String, percentage: Int?) {
        // Respetar permiso, pero permitir prueba explícita sin cooldown.
        guard enabled else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional ||
                  settings.authorizationStatus == .ephemeral else { return }
            let content = UNMutableNotificationContent()
            content.title = "⌚ Prueba de conexión iWatch"
            content.body = percentage.map { "\(watchName) · Batería Motorola: \($0)%" }
                ?? "\(watchName) · Consultá la batería para obtener un porcentaje"
            content.sound = .default
            self.center.add(UNNotificationRequest(
                identifier: "iwatch.connection.test.\(UUID().uuidString)",
                content: content,
                trigger: nil
            ))
        }
    }
}
