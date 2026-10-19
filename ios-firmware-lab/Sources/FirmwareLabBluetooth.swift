import Foundation
import Combine
import CoreBluetooth

// Aplicación de diagnóstico estrictamente observacional.
// No contiene llamadas a writeValue, setNotifyValue, OTA ni comandos propietarios.
// Lee identificadores públicos Device Information / Battery y Model ID Fast Pair.
struct ObservedPeripheral: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int?
    var advertisedServices: [String]
}

struct ObservedCharacteristic: Identifiable {
    var id: String { uuid }
    let uuid: String
    let properties: String
    var standardValue: String?
}

struct ObservedService: Identifiable {
    var id: String { uuid }
    let uuid: String
    let primary: Bool
    var characteristics: [ObservedCharacteristic] = []
}

final class FirmwareLabBluetooth: NSObject, ObservableObject {
    @Published private(set) var bluetoothStatus = "Iniciando Bluetooth…"
    @Published private(set) var connectionStatus = "Sin conexión"
    @Published private(set) var isScanning = false
    @Published private(set) var devices: [ObservedPeripheral] = []
    @Published private(set) var services: [ObservedService] = []
    @Published private(set) var selectedDeviceName: String?
    @Published private(set) var logLines: [String] = []

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var active: CBPeripheral?
    private var scanStarted: Date?

    // Device Information Service 0x180A: campos estándar no sensibles.
    // Se excluye el número de serie (0x2A25) por privacidad.
    private let knownInfoUUIDs: Set<String> = [
        "2A24", // Model Number
        "2A26", // Firmware Revision
        "2A27", // Hardware Revision
        "2A28", // Software Revision
        "2A29", // Manufacturer Name
        "2A50"  // PnP ID: proveedor y producto (no es número de serie)
    ]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        note("Laboratorio iniciado. No hay rutinas de escritura Bluetooth.")
    }

    var canScan: Bool { central?.state == .poweredOn }

    func beginScan() {
        guard canScan else {
            note("Escaneo no disponible: Bluetooth no está encendido o autorizado.")
            return
        }
        stopScan()
        devices = []
        peripherals = [:]
        // No se intenta conectar automáticamente ni se escribe al dispositivo.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanStarted = Date()
        isScanning = true
        note("Escaneo BLE iniciado; seleccioná el reloj manualmente.")
        lookForAlreadyConnectedMotoWatch()
    }

    func stopScan() {
        if central?.isScanning == true {
            central.stopScan()
        }
        isScanning = false
        scanStarted = nil
    }

    // CoreBluetooth sólo puede recuperar conectados si conocemos un UUID de servicio.
    // Es un intento de descubrimiento, nunca una conexión automática.
    func lookForAlreadyConnectedMotoWatch() {
        guard canScan else { return }
        let motorolaService = CBUUID(string: "FC9DF9F0-4899-11EE-BE56-0242AC120002")
        let connected = central.retrieveConnectedPeripherals(withServices: [motorolaService])
        for peripheral in connected {
            peripherals[peripheral.identifier] = peripheral
            upsertDevice(id: peripheral.identifier,
                         name: peripheral.name ?? "BLE sin nombre",
                         rssi: nil, advertisedServices: [motorolaService.uuidString])
        }
        if !connected.isEmpty {
            note("Dispositivos previamente conectados recuperados: \(connected.count)")
        }
    }

    func connect(to id: UUID) {
        guard canScan, let peripheral = peripherals[id] else {
            note("No se pudo seleccionar el dispositivo.")
            return
        }
        stopScan()
        if let old = active, old.identifier != id {
            central.cancelPeripheralConnection(old)
        }
        active = peripheral
        selectedDeviceName = devices.first(where: { $0.id == id })?.name ?? peripheral.name
        services = []
        connectionStatus = "Conectando…"
        note("Conexión solicitada con \(selectedDeviceName ?? "dispositivo"). No se envían comandos.")
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        stopScan()
        if let active {
            central.cancelPeripheralConnection(active)
        }
        active = nil
        connectionStatus = "Sin conexión"
        note("Desconexión solicitada desde el laboratorio.")
    }

    // Exportación de texto: se hace en el teléfono, no en el firmware.
    var exportedReport: String {
        let header = [
            "Moto Firmware Lab 0.1.1",
            "Creado: \(ISO8601DateFormatter().string(from: Date()))",
            "Modo: lectura GATT estándar y enumeración de servicios",
            "Bluetooth: \(bluetoothStatus)",
            "Conexión: \(connectionStatus)",
            "Dispositivo: \(selectedDeviceName ?? "No seleccionado")",
            "AVISO: los identificadores de periférico son UUID locales de CoreBluetooth, no direcciones MAC.",
            "",
            "=== Servicios GATT ==="
        ]
        var sections = header
        for service in services {
            sections.append("Servicio \(service.uuid) | primario=\(service.primary)")
            for characteristic in service.characteristics {
                let value = characteristic.standardValue.map { " | valor=\($0)" } ?? ""
                sections.append("  Característica \(characteristic.uuid) | \(characteristic.properties)\(value)")
            }
        }
        sections.append("")
        sections.append("=== Registro ===")
        sections.append(contentsOf: logLines)
        return sections.joined(separator: "\n")
    }

    private func note(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logLines.append("[\(formatter.string(from: Date()))] \(message)")
        if logLines.count > 500 {
            logLines.removeFirst(logLines.count - 500)
        }
    }

    private func upsertDevice(id: UUID, name: String, rssi: Int?, advertisedServices: [String]) {
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].name = name
            if let rssi { devices[index].rssi = rssi }
            if !advertisedServices.isEmpty {
                devices[index].advertisedServices = advertisedServices
            }
        } else if devices.count < 100 {
            devices.append(ObservedPeripheral(id: id, name: name,
                                              rssi: rssi, advertisedServices: advertisedServices))
        }
        devices.sort {
            let a = $0.name.localizedCaseInsensitiveContains("moto") ||
                    $0.name.localizedCaseInsensitiveContains("watch")
            let b = $1.name.localizedCaseInsensitiveContains("moto") ||
                    $1.name.localizedCaseInsensitiveContains("watch")
            if a != b { return a && !b }
            return ($0.rssi ?? -120) > ($1.rssi ?? -120)
        }
    }

    private func propertiesLabel(_ properties: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if properties.contains(.read) { parts.append("READ") }
        if properties.contains(.write) { parts.append("WRITE") }
        if properties.contains(.writeWithoutResponse) { parts.append("WRITE_NO_RESPONSE") }
        if properties.contains(.notify) { parts.append("NOTIFY") }
        if properties.contains(.indicate) { parts.append("INDICATE") }
        if properties.contains(.broadcast) { parts.append("BROADCAST") }
        if properties.contains(.authenticatedSignedWrites) { parts.append("SIGNED_WRITE") }
        if properties.contains(.extendedProperties) { parts.append("EXTENDED") }
        return parts.isEmpty ? "Sin propiedades comunes" : parts.joined(separator: ", ")
    }

    private func updateService(_ service: CBService) {
        let id = service.uuid.uuidString.uppercased()
        var observed = ObservedService(uuid: id, primary: service.isPrimary)
        for characteristic in service.characteristics ?? [] {
            let key = characteristic.uuid.uuidString.uppercased()
            let oldValue = services.first(where: { $0.uuid == id })?
                .characteristics.first(where: { $0.uuid == key })?.standardValue
            observed.characteristics.append(
                ObservedCharacteristic(uuid: key,
                                       properties: propertiesLabel(characteristic.properties),
                                       standardValue: oldValue))
        }
        if let index = services.firstIndex(where: { $0.uuid == id }) {
            services[index] = observed
        } else {
            services.append(observed)
        }
        services.sort { $0.uuid < $1.uuid }
    }

    private func readOnlyKnownStandardCharacteristic(_ characteristic: CBCharacteristic,
                                                     peripheral: CBPeripheral) {
        guard characteristic.properties.contains(.read),
              let service = characteristic.service else { return }
        let serviceUUID = service.uuid.uuidString.uppercased()
        let characteristicUUID = characteristic.uuid.uuidString.uppercased()
        let info = serviceUUID == "180A" && knownInfoUUIDs.contains(characteristicUUID)
        let battery = serviceUUID == "180F" && characteristicUUID == "2A19"
        // Fast Pair Model ID es público y de sólo lectura según Google.
        // Nunca se toca 1234-1237: incluyen mecanismos de emparejamiento.
        let fastPairModel = serviceUUID == "FE2C" &&
            characteristicUUID == "FE2C1233-8366-4814-8EB0-01DE32100BEA"
        guard info || battery || fastPairModel else { return }
        peripheral.readValue(for: characteristic)
        note("READ estándar solicitada: \(serviceUUID)/\(characteristicUUID)")
    }
}

extension FirmwareLabBluetooth: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: bluetoothStatus = "Bluetooth activado"
        case .poweredOff: bluetoothStatus = "Bluetooth desactivado"
        case .unauthorized: bluetoothStatus = "Bluetooth no autorizado"
        case .unsupported: bluetoothStatus = "BLE no soportado"
        case .resetting: bluetoothStatus = "Bluetooth reiniciándose"
        case .unknown: bluetoothStatus = "Estado Bluetooth desconocido"
        @unknown default: bluetoothStatus = "Estado no reconocido"
        }
        note(bluetoothStatus)
        if central.state != .poweredOn { stopScan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? "BLE sin nombre"
        let listed = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        peripherals[peripheral.identifier] = peripheral
        upsertDevice(id: peripheral.identifier, name: name,
                     rssi: RSSI.intValue, advertisedServices: listed)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard active?.identifier == peripheral.identifier else { return }
        connectionStatus = "Conectado · descubriendo servicios"
        note("Conectado. Iniciando descubrimiento GATT de solo lectura.")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        guard active?.identifier == peripheral.identifier else { return }
        connectionStatus = "No se pudo conectar"
        note("Error de conexión: \(error?.localizedDescription ?? "sin detalle")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        guard active?.identifier == peripheral.identifier else { return }
        connectionStatus = "Desconectado"
        active = nil
        note("Conexión terminada: \(error?.localizedDescription ?? "sin error")")
    }
}

extension FirmwareLabBluetooth: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard active?.identifier == peripheral.identifier else { return }
        if let error {
            connectionStatus = "Error de descubrimiento"
            note("Error al enumerar servicios: \(error.localizedDescription)")
            return
        }
        let discovered = peripheral.services ?? []
        services = discovered.map {
            ObservedService(uuid: $0.uuid.uuidString.uppercased(), primary: $0.isPrimary)
        }.sorted { $0.uuid < $1.uuid }
        connectionStatus = "Conectado · \(discovered.count) servicios"
        note("Servicios descubiertos: \(discovered.count)")
        for service in discovered {
            note("SERVICE \(service.uuid.uuidString) | primary=\(service.isPrimary)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard active?.identifier == peripheral.identifier else { return }
        if let error {
            note("Error de características en \(service.uuid): \(error.localizedDescription)")
            return
        }
        updateService(service)
        let count = service.characteristics?.count ?? 0
        note("CHARACTERISTICS \(service.uuid.uuidString): \(count)")
        for characteristic in service.characteristics ?? [] {
            note("  \(characteristic.uuid.uuidString): \(propertiesLabel(characteristic.properties))")
            // Ningún servicio propietario se lee; se muestran sus propiedades.
            readOnlyKnownStandardCharacteristic(characteristic, peripheral: peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard active?.identifier == peripheral.identifier,
              let service = characteristic.service else { return }
        let s = service.uuid.uuidString.uppercased()
        let c = characteristic.uuid.uuidString.uppercased()
        if let error {
            note("Error de lectura \(s)/\(c): \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        let formatted: String
        if s == "180F" && c == "2A19", let level = data.first {
            formatted = "\(Int(level))%"
        } else if s == "180A" && c == "2A50" && data.count == 7 {
            let bytes = Array(data)
            let vendorSource = bytes[0]
            let vendor = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            let product = UInt16(bytes[3]) | (UInt16(bytes[4]) << 8)
            let version = UInt16(bytes[5]) | (UInt16(bytes[6]) << 8)
            formatted = String(format: "PnP: fuente=%u, vendor=0x%04X, producto=0x%04X, versión=0x%04X",
                               Int(vendorSource), Int(vendor), Int(product), Int(version))
        } else if s == "FE2C" && c == "FE2C1233-8366-4814-8EB0-01DE32100BEA" {
            formatted = "Fast Pair Model ID: 0x" + data.map {
                String(format: "%02X", $0)
            }.joined()
        } else {
            let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            formatted = (value?.isEmpty == false ? value! : data.map {
                String(format: "%02X", $0)
            }.joined(separator: " "))
        }
        if let serviceIndex = services.firstIndex(where: { $0.uuid == s }),
           let charIndex = services[serviceIndex].characteristics.firstIndex(where: { $0.uuid == c }) {
            services[serviceIndex].characteristics[charIndex].standardValue = formatted
        }
        note("READ \(s)/\(c) => \(formatted.prefix(100))")
    }
}
