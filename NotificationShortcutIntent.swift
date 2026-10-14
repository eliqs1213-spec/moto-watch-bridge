import AppIntents
import Foundation

// Se ejecuta cuando una automatización personal de Atajos invoca la acción.
// Atajos de iOS 27 expone un disparador «Notificación» para aplicaciones.
// Que el disparador permita leer todos los campos y ejecutar con el iPhone
// bloqueado debe verificarse en el dispositivo real.
struct SendWatchNotificationIntent: AppIntent {
    static var title: LocalizedStringResource = "Enviar notificación al Moto Watch"
    static var description = IntentDescription("Envía al Moto Watch Fit una notificación recibida por Atajos. Requiere conexión BLE activa con iWatch.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Aplicación", description: "WhatsApp, Instagram o iWatch")
    var appName: String

    @Parameter(title: "Remitente", description: "Título o nombre del contacto")
    var sender: String

    @Parameter(title: "Mensaje", description: "Texto visible de la notificación")
    var message: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = WatchBLEManager.shared.sendNotification(
            source: appName, sender: sender, message: message
        )
        if result {
            return .result(dialog: "Aviso enviado al Moto Watch")
        } else {
            return .result(dialog: "No se pudo enviar: comprobá Bluetooth, conexión o contenido")
        }
    }
}

struct IWatchNotificationShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendWatchNotificationIntent(),
            phrases: ["Enviar notificación a \(.applicationName)"],
            shortTitle: "Notificar reloj",
            systemImageName: "bell.badge"
        )
    }
}
