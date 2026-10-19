import Foundation
import Combine
import ActivityKit

// ActivityKit sólo confirma el registro de una actividad, NO que WidgetKit
// esté ejecutando una extensión correctamente firmada.
final class BatteryLiveActivityManager: ObservableObject {
    static let shared = BatteryLiveActivityManager()
    @Published private(set) var status = "Todavía no iniciada"

    private init() {}

    func start(percentage: Int?) {
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
            status = "Actividad registrada (\(String(existing.id.prefix(8)))) · revisá si muestra contenido"
            return
        }
        do {
            let activity = try Activity<MotoBatteryActivityAttributes>.request(
                attributes: MotoBatteryActivityAttributes(watchName: "Moto Watch Fit"),
                content: content,
                pushType: nil
            )
            status = "ActivityKit: \(String(describing: activity.activityState)) · ID \(String(activity.id.prefix(8))) · render sin verificar"
        } catch {
            status = "Error al iniciar Actividad en vivo: " + error.localizedDescription
        }
    }

    func updateBattery(_ percentage: Int) {
        Task { @MainActor in
            let current = Activity<MotoBatteryActivityAttributes>.activities
            guard !current.isEmpty else { return }
            let content = ActivityContent(
                state: MotoBatteryActivityAttributes.ContentState(
                    percentage: percentage,
                    updatedAt: Date().timeIntervalSince1970
                ),
                staleDate: Date().addingTimeInterval(60 * 45)
            )
            for item in current { await item.update(content) }
            self.status = "ActivityKit recibió batería \(percentage)% · WidgetKit no verificado"
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
