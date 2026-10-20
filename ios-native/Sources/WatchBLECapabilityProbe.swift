import Foundation

// Diagnóstico PASIVO de los servicios que CoreBluetooth realmente descubre.
// HID por BLE (0x1812) NO equivale a HID Bluetooth Classic, AVRCP ni permiso
// para controlar audio global en iOS. Nunca intenta escribir a esos servicios.
enum WatchBLECapabilityProbe {
    private static func canonical(_ uuid: String) -> String {
        let value = uuid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Bluetooth SIG Base UUID: 0000xxxx-0000-1000-8000-00805F9B34FB
        if value.count == 36, value.hasPrefix("0000"),
           value.hasSuffix("-0000-1000-8000-00805F9B34FB") {
            return String(value.dropFirst(4).prefix(4))
        }
        return value
    }

    static func summarize(serviceUUIDs: [String]) -> String {
        let uuids = Set(serviceUUIDs.map(canonical).filter { !$0.isEmpty })
        let hasHID = uuids.contains("1812")
        let hasMCS = uuids.contains("1848")
        let hasGMCS = uuids.contains("1849")
        let motorola = uuids.contains("FC9DF9F0-4899-11EE-BE56-0242AC120002")
        let listed = uuids.sorted().prefix(24).joined(separator: ",")
        return "GATT services=\(uuids.count); Motorola=\(motorola); BLE-HID 1812=\(hasHID); "
            + "MCS 1848=\(hasMCS); GMCS 1849=\(hasGMCS); "
            + "UUIDs=\(listed); Bluetooth Classic/HID/AVRCP no verificados"
    }
}
