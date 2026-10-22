import Foundation
import Combine
import ActivityKit
import WidgetKit

// ActivityKit sólo confirma el registro de una actividad, NO que WidgetKit
// esté ejecutando una extensión correctamente firmada.
final class BatteryLiveActivityManager: ObservableObject {
    static let shared = BatteryLiveActivityManager()
    @Published private(set) var status = "Se activará automáticamente al conectar el reloj"

    private init() {}

    func start(percentage: Int?) {
        WidgetCenter.shared.reloadTimelines(ofKind: "iWatchDiagnosticStage7")
        Task { @MainActor in
            await self.prepareActivity(percentage: percentage, recreate: false)
        }
    }

    // Recuperación controlada de una cápsula sin contenido. Si el ejecutable
    // del widget sigue rechazado por CODESIGNING, esto NO repara la firma.
    func restart(percentage: Int?) {
        Task { @MainActor in
            await self.prepareActivity(percentage: percentage, recreate: true)
        }
    }

    @MainActor
    private func prepareActivity(percentage: Int?, recreate: Bool) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "Actividades en vivo desactivadas en los ajustes de iOS"
            return
        }
        if recreate {
            status = "Finalizando actividad anterior para nueva prueba…"
            for item in Activity<MotoBatteryActivityAttributes>.activities {
                await item.end(nil, dismissalPolicy: .immediate)
            }
        }
        let content = ActivityContent(
            state: MotoBatteryActivityAttributes.ContentState(
                percentage: percentage ?? -1,
                updatedAt: Date().timeIntervalSince1970
            ),
            staleDate: Date().addingTimeInterval(60 * 45)
        )
        if !recreate, let existing = Activity<MotoBatteryActivityAttributes>.activities.first {
            await existing.update(content)
            status = percentage.map { "Actividad en vivo activa · batería \($0)%" } ?? "Actividad en vivo activa · esperando batería"
            return
        }
        do {
            let activity = try Activity<MotoBatteryActivityAttributes>.request(
                attributes: MotoBatteryActivityAttributes(watchName: "Moto Watch Fit"),
                content: content,
                pushType: nil
            )
            status = percentage.map { "Actividad en vivo iniciada automáticamente · batería \($0)%" } ?? "Actividad en vivo iniciada automáticamente · esperando batería"
        } catch {
            status = "Error al iniciar Actividad en vivo: " + error.localizedDescription
        }
    }

    func updateBattery(_ percentage: Int) {
        // La actualización de batería también reactiva el timeline del widget
        // fijo si el usuario ya lo agregó a la pantalla de bloqueo.
        WidgetCenter.shared.reloadTimelines(ofKind: "iWatchDiagnosticStage7")
        Task { @MainActor in
            // Si todavía no existe una Actividad en vivo, crearla ahora sin
            // requerir que el usuario pulse un botón de configuración.
            await self.prepareActivity(percentage: percentage, recreate: false)
        }
    }

    func stop() {
        Task { @MainActor in
            for item in Activity<MotoBatteryActivityAttributes>.activities {
                await item.end(nil, dismissalPolicy: .immediate)
            }
            self.status = "Actividad en vivo detenida"
        }
    }
}
