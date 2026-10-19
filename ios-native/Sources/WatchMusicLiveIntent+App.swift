import Foundation
import AppIntents

@available(iOS 17.0, *)
extension WatchMusicLiveIntent {
    func executeInHostApp() async {
        let command: WatchCommand
        switch action {
        case "previous": command = .previous
        case "next": command = .next
        case "toggle": command = .toggle
        default: return
        }

        // AudioPlaybackIntent se ejecuta en el proceso de iWatch.
        // Usar el MISMO flujo seguro que las pulsaciones BLE, con SDK prioritario
        // y Web API de respaldo; nunca duplicar NEXT/PLAY al reintentar.
        await MainActor.run {
            WatchBLEManager.shared.record("DYNAMIC-ISLAND",
                "Pulsación de control musical: \(command.rawValue)")
            SpotifyBridge.shared.receive(command)
        }
        // No terminar el intent antes que finalice el HTTP lanzado por receive.
        await SpotifyBridge.shared.waitForCurrentMusicCommand()
    }
}
