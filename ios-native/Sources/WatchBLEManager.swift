import Foundation
import CoreBluetooth
import Combine
import UIKit

struct WatchLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: String
    let message: String
}

final class WatchBLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = WatchBLEManager()

    @Published private(set) var bluetoothStatus = "Inicializando Bluetooth"
    @Published private(set) var connectionStatus = "Desconectado"
    @Published private(set) var watchName = "Sin reloj seleccionado"
    @Published private(set) var lastCommand = "Esperando botones"
    @Published private(set) var nextCount = 0
    @Published private(set) var previousCount = 0
    @Published private(set) var toggleCount = 0
    @Published private(set) var events: [WatchLogEntry] = []
    @Published private(set) var isConnected = false

    private let serviceUUID = CBUUID(string: MotoProtocol.service)
    private let notifyUUID = CBUUID(string: MotoProtocol.notifications)
    private let txUUID = CBUUID(string: MotoProtocol.writes)
    private let storedPeripheralKey = "motowatch.last.peripheral.uuid"
    private let logStorageKey = "motowatch.debug.log.v1"
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?
    private var manuallyDisconnected = false

    private override init() {
        super.init()
        if let saved = UserDefaults.standard.data(forKey: logStorageKey),
           let history = try? JSONDecoder().decode([WatchLogEntry].self, from: saved) {
            events = history
        }
        // No hace falta que la interfaz esté visible para crear el central.
        central = CBCentralManager(
            delegate: self,
            queue: DispatchQueue.main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "org.motowatchbridge.native.ble.central"]
        )
        record("SISTEMA", "Moto Watch Bridge nativo iniciado")
    }

    func record(_ kind: String, _ message: String) {
        let item = WatchLogEntry(id: UUID(), timestamp: Date(), kind: kind, message: message)
        events.append(item)
        if events.count > 200 { events.removeFirst(events.count - 200) }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: logStorageKey)
        }
    }

    func clearLog() {
        events.removeAll()
        UserDefaults.standard.removeObject(forKey: logStorageKey)
        record("SISTEMA", "Registro limpiado")
    }

    var report: String {
        let dateFormatter = ISO8601DateFormatter()
        return (["Moto Watch Bridge — registro de diagnóstico", "Estado: \(connectionStatus)", ""]
                + events.map { "\(dateFormatter.string(from: $0.timestamp)) [\($0.kind)] \($0.message)" })
            .joined(separator: "\n")
    }

    func connectToWatch() {
        manuallyDisconnected = false
        guard central.state == .poweredOn else {
            record("BLE", "Bluetooth no disponible: \(bluetoothStatus)")
            return
        }
        if let p = peripheral, p.state == .connected {
            record("BLE", "El reloj ya está conectado")
            return
        }
        if connectKnownPeripheral() { return }
        scanForeground()
    }

    private func connectKnownPeripheral() -> Bool {
        guard let raw = UserDefaults.standard.string(forKey: storedPeripheralKey),
              let uuid = UUID(uuidString: raw) else { return false }
        guard let known = central.retrievePeripherals(withIdentifiers: [uuid]).first else {
            return false
        }
        peripheral = known
        known.delegate = self
        connectionStatus = "Reconectando"
        record("BLE", "Intentando reconectar dispositivo conocido")
        central.connect(known, options: nil)
        return true
    }

    private func scanForeground() {
        guard UIApplication.shared.applicationState != .background else {
            record("BLE", "Primer emparejamiento: abrí la app en pantalla para buscar el reloj")
            return
        }
        connectionStatus = "Buscando Moto Watch Fit"
        record("BLE", "Escaneo BLE: buscando Moto Watch Fit")
        // En nuestras pruebas el reloj anuncia su nombre, no necesariamente el UUID de servicio.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func disconnect() {
        manuallyDisconnected = true
        central.stopScan()
        if let p = peripheral, p.state != .disconnected {
            central.cancelPeripheralConnection(p)
        }
        notifyCharacteristic = nil
        isConnected = false
        connectionStatus = "Desconectado manualmente"
        record("BLE", "Desconexión solicitada por el usuario")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothStatus = "Bluetooth encendido"
            record("BLE", "Bluetooth encendido")
            if !manuallyDisconnected && peripheral == nil {
                _ = connectKnownPeripheral()
            }
        case .poweredOff:
            bluetoothStatus = "Bluetooth apagado"
            isConnected = false
            connectionStatus = "Esperando Bluetooth"
            record("BLE", "Bluetooth apagado")
        case .unauthorized:
            bluetoothStatus = "Permiso Bluetooth denegado"
            record("BLE", "Autorización denegada en Ajustes > Privacidad > Bluetooth")
        case .unsupported:
            bluetoothStatus = "Bluetooth LE no compatible"
        case .resetting:
            bluetoothStatus = "Reiniciando Bluetooth"
        case .unknown:
            bluetoothStatus = "Estado Bluetooth desconocido"
        @unknown default:
            bluetoothStatus = "Otro estado Bluetooth"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        willRestoreState dict: [String: Any]) {
        record("BLE", "iOS restauró el estado de CoreBluetooth")
        if let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let p = restored.first {
            peripheral = p
            p.delegate = self
            watchName = p.name ?? "Moto Watch Fit"
            if p.state == .connected {
                connectionStatus = "Restaurado; descubriendo servicios"
                p.discoverServices([serviceUUID])
            } else {
                central.connect(p, options: nil)
            }
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover device: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = device.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        guard name.localizedCaseInsensitiveContains("Moto Watch Fit") else { return }
        central.stopScan()
        peripheral = device
        device.delegate = self
        watchName = name
        connectionStatus = "Conectando"
        record("BLE", "Reloj encontrado: \(name)")
        central.connect(device, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect device: CBPeripheral) {
        peripheral = device
        device.delegate = self
        watchName = device.name ?? "Moto Watch Fit"
        UserDefaults.standard.set(device.identifier.uuidString, forKey: storedPeripheralKey)
        connectionStatus = "Conectado; preparando notificaciones"
        record("BLE", "Conexión BLE establecida: \(watchName)")
        device.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect device: CBPeripheral,
                        error: Error?) {
        connectionStatus = "No se pudo conectar"
        isConnected = false
        record("ERROR", "Falló conexión: \(error?.localizedDescription ?? "desconocido")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral device: CBPeripheral,
                        error: Error?) {
        isConnected = false
        notifyCharacteristic = nil
        connectionStatus = "Desconectado"
        record("BLE", "Reloj desconectado\(error.map { ": " + $0.localizedDescription } ?? "")")
        if !manuallyDisconnected && central.state == .poweredOn {
            connectionStatus = "Esperando reconexión"
            central.connect(device, options: nil)
            record("BLE", "Reconexión automática solicitada")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            record("ERROR", "Servicios: \(error.localizedDescription)")
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            record("ERROR", "Servicio Motorola F9F0 no encontrado")
            return
        }
        peripheral.discoverCharacteristics([notifyUUID, txUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            record("ERROR", "Características: \(error.localizedDescription)")
            return
        }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == notifyUUID }) else {
            record("ERROR", "No se encontró característica de notificaciones F8F0")
            return
        }
        notifyCharacteristic = characteristic
        peripheral.setNotifyValue(true, for: characteristic)
        record("BLE", "Suscribiendo característica F8F0")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            record("ERROR", "Notificaciones BLE: \(error.localizedDescription)")
            isConnected = false
            connectionStatus = "Suscripción fallida"
            return
        }
        guard characteristic.uuid == notifyUUID else { return }
        isConnected = characteristic.isNotifying
        connectionStatus = characteristic.isNotifying ? "Escuchando los botones" : "Sin notificaciones"
        record("BLE", characteristic.isNotifying ? "Notificaciones F8F0 activadas" : "Notificaciones F8F0 desactivadas")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            record("ERROR", "Lectura BLE: \(error.localizedDescription)")
            return
        }
        guard characteristic.uuid == notifyUUID, let data = characteristic.value else { return }
        guard let command = MotoProtocol.decode(data) else {
            record("BLE", "Paquete no reconocido / CRC incorrecto: \(MotoProtocol.hex(data))")
            return
        }
        let raw = MotoProtocol.hex(data)
        switch command {
        case .next: nextCount += 1; lastCommand = "⏭ Siguiente"
        case .previous: previousCount += 1; lastCommand = "⏮ Anterior"
        case .toggle: toggleCount += 1; lastCommand = "⏯ Play / Pausa"
        case .unknown: lastCommand = "Otro comando"
        }
        record("RELOJ", "\(command.rawValue) | \(raw)")
        // Etapa 2: si Spotify está habilitado, procesamos el evento incluso en segundo plano.
        SpotifyBridge.shared.receive(command)
    }
}
