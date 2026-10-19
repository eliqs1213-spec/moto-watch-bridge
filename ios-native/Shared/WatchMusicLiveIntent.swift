import Foundation
import AppIntents

// El botón de la Live Activity usa el proceso de iWatch, no el widget, para
// reutilizar el control Spotify existente y sus credenciales privadas.
// No se solicitan credenciales ni se ejecuta Spotify Web API en la extensión.
@available(iOS 17.0, *)
struct WatchMusicLiveIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Controlar Spotify desde iWatch"
    static var description = IntentDescription("Control musical de la Actividad en Vivo de iWatch.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Acción")
    var action: String

    init() {
        action = "toggle"
    }

    init(action: String) {
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        await executeInHostApp()
        return .result()
    }
}
