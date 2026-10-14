import Foundation
import Combine
import ActivityKit

// Live Activity de batería: alternativa a App Groups en instalaciones con Sideloadly.
// Es visible en la pantalla bloqueada y en la Dynamic Island, si iOS permite
// Live Activities para iWatch y la extensión WidgetKit queda instalada.
final class BatteryLiveActivityManager: ObservableObject {
    static let shared = BatteryLiveActivityManager()
    @Published private(set) var status = "Todavía no iniciada"

    private init() {}

    func start(percentage: Int?) {
        Task { @MainActor in
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                self.status = "iOS tiene desactivadas las Actividades en vivo para esta app"
                return
            }
            let percent = percentage ?? -1
            let content = ActivityContent(
                state: MotoBatteryActivityAttributes.ContentState(
                    percentage: percent,
                    updatedAt: Date().timeIntervalSince1970
                ),
                staleDate: Date().addingTimeInterval(60 * 45)
            )
            // Evitar duplicados tras cerrar y volver a abrir iWatch.
            if let existing = Activity<MotoBatteryActivityAttributes>.activities.first {
                await existing.update(content)
                self.status = "Batería en pantalla bloqueada · actualizada"
                return
            }
            do {
                _ = try Activity<MotoBatteryActivityAttributes>.request(
                    attributes: MotoBatteryActivityAttributes(watchName: "Moto Watch Fit"),
                    content: content,
                    pushType: nil
                )
                self.status = "Actividad en vivo iniciada · bloqueá el iPhone"
            } catch {
                self.status = "No pudo iniciarse: " + error.localizedDescription
            }
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
            self.status = "Batería actualizada: \(percentage)% (Motorola 10/01)"
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
