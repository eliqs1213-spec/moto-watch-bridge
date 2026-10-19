import Foundation
import AppIntents

@available(iOS 17.0, *)
extension WatchMusicLiveIntent {
    func executeInHostApp() async {
        // Firma necesaria para compilar Button(intent:) en la extensión.
        // AudioPlaybackIntent se ejecuta en el proceso de la app iWatch.
        // Aquí no se accede a tokens, Bluetooth ni a Spotify.
    }
}
