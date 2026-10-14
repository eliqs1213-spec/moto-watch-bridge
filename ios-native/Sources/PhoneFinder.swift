import Foundation
import UserNotifications
import UIKit

// Aviso local del iPhone al recibir los paquetes 0x11/0x06 del reloj.
// iOS puede silenciar estos avisos por modo silencio o concentración.
final class PhoneFinder: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PhoneFinder()
    @Published private(set) var status = "Avisos sin configurar"
    @Published private(set) var searching = false
    private let notificationID = "motowatch.find.phone"
    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
        updateAuthorizationStatus()
    }

    func updateAuthorizationStatus() {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional: self.status = "Avisos permitidos"
                case .denied: self.status = "Permiso denegado: activar en Ajustes"
                default: self.status = "Activar avisos para recibir sonido"
                }
            }
        }
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.status = granted ? "Avisos permitidos" : "Avisos no permitidos"
                WatchBLEManager.shared.record("BUSCAR", error?.localizedDescription ?? self.status)
            }
        }
    }

    func start() {
        searching = true
        WatchBLEManager.shared.record("BUSCAR", "Reloj solicitó localizar iPhone")
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        let content = UNMutableNotificationContent()
        content.title = "Moto Watch Fit"
        content.body = "¡Estoy acá! Tu reloj está buscando este iPhone."
        content.sound = .default
        // No crear una notificación recurrente: una sola alerta para evitar spam.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)) { error in
            if let error = error {
                DispatchQueue.main.async {
                    WatchBLEManager.shared.record("ERROR", "Aviso Buscar teléfono: \(error.localizedDescription)")
                }
            }
        }
    }

    func stop() {
        searching = false
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        WatchBLEManager.shared.record("BUSCAR", "Reloj detuvo la búsqueda (no puede cortar el sonido ya emitido)")
    }

    // Permite comprobar el sonido sin pulsar el reloj.
    func test() { start() }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
