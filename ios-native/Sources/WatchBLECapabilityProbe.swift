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



    // Datos simples para poder probar el diagnóstico sin enlazar CoreBluetooth.
    struct CharacteristicInfo {
        let uuid: String
        let properties: UInt
    }

    private static func propertyLabels(_ flags: UInt) -> String {
        let available: [(UInt, String)] = [
            (0x01, "broadcast"), (0x02, "read"), (0x04, "writeWithoutResponse"),
            (0x08, "write"), (0x10, "notify"), (0x20, "indicate"),
            (0x40, "signedWrite"), (0x80, "extended"),
            (0x100, "notifyEncrypted"), (0x200, "indicateEncrypted")
        ]
        let labels = available.compactMap { (bit, label) in flags & bit != 0 ? label : nil }
        return labels.isEmpty ? "ninguna" : labels.joined(separator: "+")
    }

    static func summarizeMotorolaCharacteristics(_ characteristics: [CharacteristicInfo]) -> String {
        let entries = characteristics.map {
            (id: canonical($0.uuid), properties: propertyLabels($0.properties))
        }
        func report(_ suffix: String) -> String {
            let id = "FC9D" + suffix + "-4899-11EE-BE56-0242AC120002"
            let hits = entries.filter { $0.id == id }
            guard !hits.isEmpty else { return "\(suffix)=ausente" }
            return "\(suffix)=presente [\(hits.map(\.properties).joined(separator: ","))]"
        }
        let listed = entries.map { "\($0.id)[\($0.properties)]" }.sorted().joined(separator: ";")
        return "Características Motorola=\(entries.count); "
            + [report("F8F0"), report("F8F1"), report("F8F2")].joined(separator: "; ")
            + "; UUIDs=\(listed); lectura/escritura F8F2 NO ejecutadas; HID Classic no verificado"
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
