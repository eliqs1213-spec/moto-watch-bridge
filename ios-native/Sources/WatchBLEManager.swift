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
    @Published private(set) var batteryPercentage: Int? = nil
    @Published private(set) var batteryStatus = "Sin lectura"
    @Published private(set) var musicSyncStatus = "Sin sincronizar"

    private let serviceUUID = CBUUID(string: MotoProtocol.service)
    private let notifyUUID = CBUUID(string: MotoProtocol.notifications)
    private let txUUID = CBUUID(string: MotoProtocol.writes)
    private let storedPeripheralKey = "motowatch.last.peripheral.uuid"
    private let logStorageKey = "motowatch.debug.log.v1"
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private struct PendingMusicWrite { let packet: Data; let delayAfter: TimeInterval }
    private var musicQueue: [PendingMusicWrite] = []
    private var musicInProgress = false
    private var musicAfterDelay: TimeInterval = 0
    private var currentWriteIsBattery = false
    private var batteryQuerySentAt: Date? = nil
    private var lastMusicSignature: String?
    private var lastMusicSentAt = Date.distantPast
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
        writeCharacteristic = nil
        musicQueue.removeAll()
        musicInProgress = false
        lastMusicSignature = nil
        isConnected = false
        batteryPercentage = nil
        batteryStatus = "Desconectado"
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
                p.discoverServices(nil)
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
        device.discoverServices(nil)
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
        writeCharacteristic = nil
        musicQueue.removeAll()
        musicInProgress = false
        lastMusicSignature = nil
        batteryPercentage = nil
        batteryStatus = "Desconectado"
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
        let services = peripheral.services ?? []
        if let motorola = services.first(where: { $0.uuid == serviceUUID }) {
            peripheral.discoverCharacteristics([notifyUUID, txUUID], for: motorola)
        } else {
            record("ERROR", "Servicio Motorola F9F0 no encontrado")
        }
        batteryStatus = "Batería Motorola: protocolo 10/01"
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            record("ERROR", "Características: \(error.localizedDescription)")
            return
        }
        guard service.uuid == serviceUUID else { return }
        writeCharacteristic = service.characteristics?.first(where: { $0.uuid == txUUID })
        if writeCharacteristic == nil { record("ERROR", "No se encontró F8F1 para actualizar música") }
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
        guard characteristic.uuid == notifyUUID else { return }
        if let error = error {
            record("ERROR", "Notificaciones BLE: \(error.localizedDescription)")
            isConnected = false
            connectionStatus = "Suscripción fallida"
            return
        }
        isConnected = characteristic.isNotifying
        connectionStatus = characteristic.isNotifying ? "Escuchando los botones" : "Sin notificaciones"
        record("BLE", characteristic.isNotifying ? "Notificaciones F8F0 activadas" : "Notificaciones F8F0 desactivadas")
        if characteristic.isNotifying && SpotifyBridge.shared.controlEnabled {
            Task { await SpotifyBridge.shared.refreshPlaybackInfo() }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            record("ERROR", "Lectura BLE: \(error.localizedDescription)")
            return
        }
        guard characteristic.uuid == notifyUUID, let data = characteristic.value else { return }
        // Respuesta Motorola 10/01 observada en el registro Android.
        // Protobuf: 08 <porcentaje>; el reloj mostró 59 en una captura antigua.
        let bytes = Array(data)
        if bytes.count >= 10 && bytes[4] == 0x10 && bytes[5] == 0x01 {
            let len = Int(bytes[1]) | (Int(bytes[2]) << 8)
            guard bytes[0] == 0xAA, len + 4 == bytes.count,
                  MotoProtocol.crc16Xmodem(bytes.dropLast(2)) ==
                    (UInt16(bytes[bytes.count-2]) | (UInt16(bytes[bytes.count-1]) << 8)),
                  bytes[6] == 0x08, bytes[7] <= 100 else {
                record("BATERIA", "Respuesta Motorola 10/01 inválida: \(MotoProtocol.hex(data))")
                return
            }
            let percentage = Int(bytes[7])
            batteryPercentage = percentage
            batteryStatus = "\(percentage)% (Motorola 10/01)"
            record("BATERIA", "Respuesta 10/01: \(percentage)%, trama \(MotoProtocol.hex(data))")
            if #available(iOS 16.2, *) {
                BatteryLiveActivityManager.shared.updateBattery(percentage)
            }
            return
        }
        guard let command = MotoProtocol.decode(data) else {
            record("BLE", "Paquete no reconocido / CRC incorrecto: \(MotoProtocol.hex(data))")
            return
        }
        let raw = MotoProtocol.hex(data)
        switch command {
        case .next: nextCount += 1; lastCommand = "⏭ Siguiente"
        case .previous: previousCount += 1; lastCommand = "⏮ Anterior"
        case .toggle: toggleCount += 1; lastCommand = "⏯ Play / Pausa"
        case .findStart: lastCommand = "📳 Encontrar iPhone"
        case .findStop: lastCommand = "🔕 Detener búsqueda"
        case .unknown: lastCommand = "Otro comando"
        }
        record("RELOJ", "\(command.rawValue) | \(raw)")
        switch command {
        case .findStart: PhoneFinder.shared.start()
        case .findStop: PhoneFinder.shared.stop()
        case .next, .previous, .toggle: SpotifyBridge.shared.receive(command)
        case .unknown: break
        }
    }

    func refreshBattery() {
        guard isConnected, peripheral != nil, let tx = writeCharacteristic,
              tx.properties.contains(.write) else {
            batteryStatus = "Sin conexión o F8F1 no admite escritura"
            record("BATERIA", "No se pudo enviar consulta Motorola 10/01")
            return
        }
        guard Date().timeIntervalSince(batteryQuerySentAt ?? .distantPast) > 3 else { return }
        batteryQuerySentAt = Date()
        // Consulta real capturada al conectar Moto Watch en el Motorola Edge.
        let packet = Data([0xAA, 0x04, 0x00, 0x00, 0x10, 0x01, 0x7E, 0xFD])
        musicQueue.append(PendingMusicWrite(packet: packet, delayAfter: 0))
        batteryStatus = "Esperando respuesta Motorola 10/01"
        record("BATERIA", "Enviando consulta Motorola 10/01: \(MotoProtocol.hex(packet))")
        flushMusicQueue()
    }

    // Usar la codificación probada en Windows: anuncio 08 02 de canción
    // nueva y estado estable vacío al reproducir / 08 01 al pausar.
    func sendMusic(_ snapshot: WatchMusicSnapshot, force: Bool = false) {
        guard isConnected, writeCharacteristic != nil, peripheral != nil else {
            musicSyncStatus = "Requiere Bluetooth conectado y F8F1"
            return
        }
        let signature = "\(snapshot.id)|\(snapshot.isPlaying)"
        let changed = signature != lastMusicSignature
        if !force && !changed && Date().timeIntervalSince(lastMusicSentAt) < 25 { return }
        let trackChanged = lastMusicSignature == nil || lastMusicSignature?.components(separatedBy: "|").first != snapshot.id
        let steady = WatchMusicProtocol.encode(snapshot, code: snapshot.isPlaying ? .empty : .one)
        // Reemplazar cola obsoleta si Spotify cambió de estado mientras se escribía.
        musicQueue.removeAll()
        if trackChanged && snapshot.isPlaying {
            musicQueue.append(PendingMusicWrite(packet: WatchMusicProtocol.encode(snapshot, code: .two), delayAfter: 0.8))
        }
        musicQueue.append(PendingMusicWrite(packet: steady, delayAfter: 0))
        lastMusicSignature = signature
        lastMusicSentAt = Date()
        musicSyncStatus = "Enviando: \(snapshot.title) · \(snapshot.isPlaying ? "PLAY" : "PAUSA")"
        record("MUSICA", "Metadatos: \(snapshot.title) - \(snapshot.artist) | \(snapshot.isPlaying ? "PLAY" : "PAUSA")")
        flushMusicQueue()
    }

    // Spotify no disponible o desvinculado: intentar limpiar los datos musicales
    // manteniendo la conexión BLE para batería, botones y Buscar iPhone.
    // El efecto en la pantalla depende del firmware y se valida en el reloj real.
    func sendNoMusic(reason: String, force: Bool = false) {
        guard isConnected, writeCharacteristic != nil, peripheral != nil else {
            musicSyncStatus = "Sin música (pendiente de conexión Bluetooth)"
            record("MUSICA", "No se pudo avisar estado inactivo: Bluetooth no conectado")
            return
        }
        if !force && lastMusicSignature == "NO_MUSIC" { return }
        musicQueue.removeAll()
        musicQueue.append(PendingMusicWrite(packet: WatchMusicProtocol.encodeNoMusic(), delayAfter: 0))
        lastMusicSignature = "NO_MUSIC"
        lastMusicSentAt = Date()
        musicSyncStatus = "Sin música · señal enviada (pantalla no confirmada)"
        record("MUSICA", "Estado sin música enviado: \(reason) | paquete experimental 24/01")
        flushMusicQueue()
    }

    private func flushMusicQueue() {
        guard !musicInProgress, !musicQueue.isEmpty,
              let peripheral = peripheral, let tx = writeCharacteristic else { return }
        let next = musicQueue.removeFirst()
        let maxLength = peripheral.maximumWriteValueLength(for: .withResponse)
        guard tx.properties.contains(.write), next.packet.count <= maxLength else {
            musicSyncStatus = "El paquete no cabe en el tamaño BLE disponible"
            record("ERROR", "Escritura F8F1 inválida: tamaño \(next.packet.count), máximo \(maxLength)")
            musicQueue.removeAll()
            return
        }
        musicInProgress = true
        currentWriteIsBattery = next.packet.count == 8 && next.packet[4] == 0x10 && next.packet[5] == 0x01
        musicAfterDelay = next.delayAfter
        peripheral.writeValue(next.packet, for: tx, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == txUUID else { return }
        musicInProgress = false
        let isBattery = currentWriteIsBattery
        currentWriteIsBattery = false
        if let error = error {
            if isBattery { batteryStatus = "Error de consulta Motorola" }
            else { musicSyncStatus = "Error al escribir metadatos" }
            record("ERROR", "Escritura F8F1: \(error.localizedDescription)")
            musicQueue.removeAll()
            return
        }
        let delay = musicAfterDelay
        if musicQueue.isEmpty && !isBattery { musicSyncStatus = "Datos enviados; pantalla no confirmada" }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.flushMusicQueue()
            }
        } else {
            flushMusicQueue()
        }
    }
}
