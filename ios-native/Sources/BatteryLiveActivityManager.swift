import Foundation
import Combine
import ActivityKit

// ActivityKit sólo confirma el registro de una actividad, NO que WidgetKit
// esté ejecutando una extensión correctamente firmada.
final class BatteryLiveActivityManager: ObservableObject {
    static let shared = BatteryLiveActivityManager()
    @Published private(set) var status = "Todavía no iniciada"
    private var latestMusic: WatchMusicSnapshot?

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
        let previous = Activity<MotoBatteryActivityAttributes>.activities.first?.content.state
        let currentSong = latestMusic
        let content = ActivityContent(
            state: MotoBatteryActivityAttributes.ContentState(
                percentage: percentage ?? previous?.percentage ?? -1,
                updatedAt: Date().timeIntervalSince1970,
                songTitle: currentSong.map { String($0.title.prefix(80)) } ?? previous?.songTitle,
                artist: currentSong.map { String($0.artist.prefix(70)) } ?? previous?.artist,
                isPlaying: currentSong?.isPlaying ?? previous?.isPlaying,
                musicUpdatedAt: currentSong != nil ? Date().timeIntervalSince1970 : previous?.musicUpdatedAt
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
            for item in current {
                // No borrar la canción al recibir una nueva lectura Motorola.
                let previous = item.content.state
                let content = ActivityContent(
                    state: MotoBatteryActivityAttributes.ContentState(
                        percentage: percentage,
                        updatedAt: Date().timeIntervalSince1970,
                        songTitle: previous.songTitle,
                        artist: previous.artist,
                        isPlaying: previous.isPlaying,
                        musicUpdatedAt: previous.musicUpdatedAt
                    ),
                    staleDate: Date().addingTimeInterval(60 * 45)
                )
                await item.update(content)
            }
            self.status = "ActivityKit recibió batería \(percentage)% · WidgetKit no verificado"
        }
    }

    // Se alimenta ÚNICAMENTE con snapshots que SpotifyBridge/MusicSyncEngine
    // ya aceptaron. Cuando iOS suspende iWatch no se finge cambio natural.
    func updateMusic(_ snapshot: WatchMusicSnapshot?) {
        Task { @MainActor in
            self.latestMusic = snapshot
            for item in Activity<MotoBatteryActivityAttributes>.activities {
                let previous = item.content.state
                let content = ActivityContent(
                    state: MotoBatteryActivityAttributes.ContentState(
                        percentage: previous.percentage,
                        updatedAt: previous.updatedAt,
                        songTitle: snapshot.map { String($0.title.prefix(80)) },
                        artist: snapshot.map { String($0.artist.prefix(70)) },
                        isPlaying: snapshot?.isPlaying,
                        musicUpdatedAt: snapshot.map { _ in Date().timeIntervalSince1970 }
                    ),
                    staleDate: Date().addingTimeInterval(60 * 45)
                )
                await item.update(content)
            }
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
