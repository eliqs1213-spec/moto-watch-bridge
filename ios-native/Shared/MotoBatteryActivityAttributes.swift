import Foundation
import ActivityKit

// A diferencia de un widget fijo, ActivityKit recibe sus actualizaciones
// directamente desde la aplicación, sin UserDefaults compartidos ni App Groups.
struct MotoBatteryActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var percentage: Int // -1 = esperando primera lectura Motorola 10/01
        var updatedAt: Double
        // Opcionales: permiten recuperar Activities creadas por versiones previas.
        // Nunca son metadatos inventados; llegan del SDK/Web API confirmado.
        var songTitle: String? = nil
        var artist: String? = nil
        var isPlaying: Bool? = nil
        var musicUpdatedAt: Double? = nil
    }
    var watchName: String
}
