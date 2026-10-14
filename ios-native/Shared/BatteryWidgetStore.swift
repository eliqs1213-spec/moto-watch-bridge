import Foundation

// Fuente única: respuesta Motorola 10/01 validada por WatchBLEManager.
// Solo se comparte un porcentaje y fecha; el widget NO consulta Bluetooth.
enum BatteryWidgetStore {
    static let groupID = "group.org.motowatchbridge.shared"
    static let widgetKind = "iWatchBattery"
    private static let valueKey = "battery.moto1001.percent"
    private static let timeKey = "battery.moto1001.timestamp"

    static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    static func save(percentage: Int, date: Date = Date()) -> Bool {
        guard (0...100).contains(percentage), isAvailable,
              let defaults = UserDefaults(suiteName: groupID) else { return false }
        defaults.set(percentage, forKey: valueKey)
        defaults.set(date.timeIntervalSince1970, forKey: timeKey)
        return true
    }

    static func load() -> (percentage: Int, date: Date)? {
        guard isAvailable, let defaults = UserDefaults(suiteName: groupID),
              let value = defaults.object(forKey: valueKey) as? Int,
              (0...100).contains(value),
              let time = defaults.object(forKey: timeKey) as? Double,
              time > 0 else { return nil }
        return (value, Date(timeIntervalSince1970: time))
    }
}
