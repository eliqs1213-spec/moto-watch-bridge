import Foundation
import AppIntents

// Atajos ejecuta esta acción sólo por interacción/automatización explícita.
// No abre Spotify, no emite órdenes Play y no mantiene viva a iWatch.
// Se utiliza el modo en segundo plano que iOS autorice; puede fallar
// con el iPhone bloqueado o iWatch suspendida.
@available(iOS 16.2, *)
struct SpotifyWatchResyncIntent: AppIntent {
    static var title: LocalizedStringResource = "Resincronizar Spotify con Moto Watch"
    static var description = IntentDescription(
        "Consulta la canción actual y solicita actualizar el Moto Watch Fit si iWatch está conectada.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let status = await SpotifyBridge.shared.resyncFromShortcuts()
        return .result(value: status)
    }
}

@available(iOS 16.2, *)
struct SpotifyWatchAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SpotifyWatchResyncIntent(),
            phrases: [
                "Sincronizar Spotify con \(.applicationName)",
                "Actualizar la música en \(.applicationName)"
            ],
            shortTitle: "Sincronizar Spotify",
            systemImageName: "arrow.clockwise"
        )
    }
}
