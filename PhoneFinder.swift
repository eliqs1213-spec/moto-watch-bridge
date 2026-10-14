import Foundation
import AVFoundation
import UserNotifications
import UIKit

/// El reloj envía 11/06 + 08 01 para iniciar; 11/06 vacío para detener.
/// Un sonido WAV local se reproduce en bucle. El usuario puede detenerlo
/// desde el reloj o desde la pantalla de la aplicación.
final class PhoneFinder: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PhoneFinder()
    @Published private(set) var status = "Listo para encontrar el iPhone"
    @Published private(set) var searching = false

    private var player: AVAudioPlayer?
    private let notificationID = "motowatch.find.phone.fallback"
    private let center = UNUserNotificationCenter.current()
    private var lastStart = Date.distantPast

    private override init() {
        super.init()
        center.delegate = self
        NotificationCenter.default.addObserver(self,
            selector: #selector(interruptionReceived(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance())
    }

    /// Opcional: permiso solo para el aviso de respaldo si iOS rechaza iniciar audio.
    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                WatchBLEManager.shared.record("BUSCAR", error?.localizedDescription ??
                    (granted ? "Avisos de respaldo permitidos" : "Avisos de respaldo no permitidos"))
            }
        }
    }

    func updateAuthorizationStatus() {
        // La alarma WAV no necesita permiso de notificaciones.
        if !searching { status = "Alarma lista (sin permiso de notificaciones)" }
    }

    func start() {
        if searching && player?.isPlaying == true { return }
        // Protección frente a repetición accidental de paquetes BLE.
        if Date().timeIntervalSince(lastStart) < 0.5 { return }
        lastStart = Date()
        searching = true
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        WatchBLEManager.shared.record("BUSCAR", "Inicio de búsqueda solicitado por reloj")
        do {
            guard let url = Bundle.main.url(forResource: "FindPhoneAlert", withExtension: "wav") else {
                throw NSError(domain: "MotoWatchBridge", code: 21,
                              userInfo: [NSLocalizedDescriptionKey: "No se incorporó FindPhoneAlert.wav al IPA"])
            }
            let audio = AVAudioSession.sharedInstance()
            // Audio audible incluso con el conmutador Silencio; reduce otras apps.
            try audio.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audio.setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = -1
            newPlayer.volume = 1.0
            newPlayer.prepareToPlay()
            guard newPlayer.play() else {
                throw NSError(domain: "MotoWatchBridge", code: 22,
                              userInfo: [NSLocalizedDescriptionKey: "iOS no permitió iniciar audio"])
            }
            player = newPlayer
            status = "🔊 Sonando hasta detener la búsqueda"
            WatchBLEManager.shared.record("BUSCAR", "Alarma continua iniciada; app en \(UIApplication.shared.applicationState == .background ? "segundo plano" : "primer plano")")
        } catch {
            searching = false
            player?.stop()
            player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            status = "No se pudo iniciar el sonido: \(error.localizedDescription)"
            WatchBLEManager.shared.record("ERROR", "Buscar iPhone: \(error.localizedDescription)")
            fallbackNotification()
        }
    }

    func stop() {
        let wasSearching = searching
        searching = false
        player?.stop()
        player = nil
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        status = "Búsqueda detenida"
        if wasSearching {
            WatchBLEManager.shared.record("BUSCAR", "Alarma detenida desde reloj o aplicación")
        }
    }

    func test() { start() }

    @objc private func interruptionReceived(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began && searching {
            status = "Audio interrumpido por iOS o una llamada"
            WatchBLEManager.shared.record("BUSCAR", "Alarma interrumpida por el sistema")
        }
        // No reactivar automáticamente una alarma interrumpida durante una llamada.
    }

    private func fallbackNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Moto Watch Fit"
        content.body = "El reloj está buscando tu iPhone. Abrí Moto Watch Bridge."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
