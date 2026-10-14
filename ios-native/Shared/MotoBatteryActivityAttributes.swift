import Foundation
import ActivityKit

// A diferencia de un widget fijo, ActivityKit recibe sus actualizaciones
// directamente desde la aplicación, sin UserDefaults compartidos ni App Groups.
struct MotoBatteryActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var percentage: Int // -1 = esperando primera lectura Motorola 10/01
        var updatedAt: Double
    }
    var watchName: String
}
