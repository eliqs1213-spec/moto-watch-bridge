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
    private enum OutboundKind { case music, battery, notification, health, vitals, sleepRead }
    private struct PendingMusicWrite {
        let packet: Data
        let delayAfter: TimeInterval
        let kind: OutboundKind
    }
    private var sleepAssembler = WatchHealthFrameAssembler(commands: [0x09])
    private var vitalsAssembler = WatchHealthFrameAssembler(commands: [0x0C, 0x12])
    private var stressAssembler = WatchHealthFrameAssembler(commands: [0x0E])
    private var healthAssembler = WatchHealthFrameAssembler()
    private var musicQueue: [PendingMusicWrite] = []
    private var musicInProgress = false
    private var musicAfterDelay: TimeInterval = 0
    private var currentWriteIsSleep = false
    private var currentWriteIsVitals = false
    private var currentWriteIsHealth = false
    private var currentWriteIsBattery = false
    private var batteryQuerySentAt: Date? = nil
    private var lastMusicSignature: String?
    private var lastMusicSentAt = Date.distantPast
    private var manuallyDisconnected = UserDefaults.standard.bool(forKey: "motowatch.ble.manualDisconnect")
    @Published private(set) var autoReconnectEnabled =
        UserDefaults.standard.object(forKey: "motowatch.ble.autoReconnect") as? Bool ?? true
    private var readyConnectionID = 0
    private var pendingConnectionAlertID: Int? = nil
    private var reconnectScheduled = false

    // Una sesión nueva no puede heredar características, cola ni un writeWithResponse
    // que pertenecían a la conexión anterior. Un callback antiguo tampoco debe
    // reanudar una cola obsoleta tras una restauración de iOS.
    private func resetConnectionTransport() {
        Task { @MainActor in WatchHealthSync.shared.cancel(); WatchStressProbe.shared.cancel(); WatchVitalsProbe.shared.cancel(); WatchSleepProbe.shared.cancel() }
        sleepAssembler.reset()
        currentWriteIsSleep = false
        vitalsAssembler.reset()
        currentWriteIsVitals = false
        stressAssembler.reset()
        currentWriteIsHealth = false
        healthAssembler.reset()
        readyConnectionID += 1
        isConnected = false
        notifyCharacteristic = nil
        writeCharacteristic = nil
        musicQueue.removeAll()
        musicInProgress = false
        currentWriteIsBattery = false
        musicAfterDelay = 0
        pendingConnectionAlertID = nil
        batteryQuerySentAt = nil
        batteryPercentage = nil
        lastMusicSignature = nil
        lastMusicSentAt = .distantPast
    }

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

    func setAutoReconnect(_ enabled: Bool) {
        autoReconnectEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "motowatch.ble.autoReconnect")
        record("BLE", enabled ? "Reconexión automática activada" : "Reconexión automática desactivada")
        if enabled { autoConnectIfNeeded() }
    }

    private func rediscoverIfAlreadyConnected(_ device: CBPeripheral) {
        // CoreBluetooth puede restaurar el enlace físico sin reconstruir las
        // características para esta instancia de la app. Reconectar no alcanza.
        guard !isConnected else { return }
        resetConnectionTransport()
        peripheral = device
        device.delegate = self
        connectionStatus = "Enlace restaurado; redescubriendo F8F0/F8F1"
        record("BLE", "Periférico conectado sin sesión lista: redescubriendo servicios")
        device.discoverServices(nil)
    }

    func autoConnectIfNeeded() {
        guard autoReconnectEnabled, !manuallyDisconnected,
              central.state == .poweredOn,
              !isConnected, !central.isScanning else { return }
        if let p = peripheral, p.state == .connected {
            rediscoverIfAlreadyConnected(p)
            return
        }
        if let p = peripheral, p.state == .connecting { return }
        if let p = peripheral, p.state == .disconnected {
            connectionStatus = "Reconectando reloj conocido"
            central.connect(p, options: nil)
        } else if !connectKnownPeripheral() {
            scanForeground()
        }
    }

    func connectToWatch() {
        manuallyDisconnected = false
        UserDefaults.standard.set(false, forKey: "motowatch.ble.manualDisconnect")
        guard central.state == .poweredOn else {
            record("BLE", "Bluetooth no disponible: \(bluetoothStatus)")
            return
        }
        if let p = peripheral, p.state == .connected {
            rediscoverIfAlreadyConnected(p)
            return
        }
        if let p = peripheral, p.state == .connecting {
            record("BLE", "El reloj se está conectando")
            return
        }
        if let p = peripheral, p.state == .disconnected {
            central.connect(p, options: nil)
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
        if known.state == .connected {
            rediscoverIfAlreadyConnected(known)
        } else {
            connectionStatus = "Reconectando"
            record("BLE", "Intentando reconectar dispositivo conocido")
            central.connect(known, options: nil)
        }
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
        UserDefaults.standard.set(true, forKey: "motowatch.ble.manualDisconnect")
        resetConnectionTransport()
        central.stopScan()
        if let p = peripheral, p.state != .disconnected {
            central.cancelPeripheralConnection(p)
        }
        batteryStatus = "Desconectado"
        connectionStatus = "Desconectado manualmente"
        record("BLE", "Desconexión solicitada por el usuario")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothStatus = "Bluetooth encendido"
            record("BLE", "Bluetooth encendido")
            autoConnectIfNeeded()
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
                resetConnectionTransport()
                connectionStatus = "Restaurado; descubriendo servicios"
                p.discoverServices(nil)
            } else if autoReconnectEnabled && !manuallyDisconnected {
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
        resetConnectionTransport()
        connectionStatus = "Conectado; descubriendo características F8F0/F8F1"
        // La primera respuesta 10/01 de esta conexión será la del aviso.
        record("BLE", "Conexión BLE establecida: \(watchName)")
        device.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect device: CBPeripheral,
                        error: Error?) {
        connectionStatus = "No se pudo conectar"
        isConnected = false
        record("ERROR", "Falló conexión: \(error?.localizedDescription ?? "desconocido")")
        scheduleReconnectIfNeeded()
    }

    private func scheduleReconnectIfNeeded() {
        guard autoReconnectEnabled, !manuallyDisconnected, !reconnectScheduled,
              central.state == .poweredOn else { return }
        reconnectScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self = self else { return }
            self.reconnectScheduled = false
            self.autoConnectIfNeeded()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral device: CBPeripheral,
                        error: Error?) {
        resetConnectionTransport()
        batteryStatus = "Desconectado"
        connectionStatus = "Desconectado"
        record("BLE", "Reloj desconectado\(error.map { ": " + $0.localizedDescription } ?? "")")
        if !manuallyDisconnected && autoReconnectEnabled && central.state == .poweredOn {
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
        guard let tx = writeCharacteristic, tx.properties.contains(.write) else {
            isConnected = false
            connectionStatus = "F8F1 no disponible para escritura"
            record("ERROR", "F8F1 ausente o sin permiso de escritura tras la reconexión")
            return
        }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == notifyUUID }) else {
            record("ERROR", "No se encontró característica de notificaciones F8F0")
            return
        }
        notifyCharacteristic = characteristic
        if characteristic.isNotifying {
            // CoreBluetooth puede restaurar una suscripción ya activa sin volver
            // a llamar didUpdateNotificationStateFor.
            finishBluetoothSetupIfReady()
        } else {
            peripheral.setNotifyValue(true, for: characteristic)
            record("BLE", "Suscribiendo característica F8F0")
        }
    }

    private func finishBluetoothSetupIfReady() {
        guard let rx = notifyCharacteristic, rx.isNotifying,
              let tx = writeCharacteristic, tx.properties.contains(.write),
              peripheral?.state == .connected else { return }
        // Se ejecuta una única vez por sesión BLE, aunque iOS repita callbacks.
        guard !isConnected else { return }
        isConnected = true
        connectionStatus = "Escuchando botones · F8F1 listo"
        record("BLE", "Sesión lista: F8F0 notificando y F8F1 escribible")
        let connectionID = readyConnectionID
        pendingConnectionAlertID = connectionID
        refreshBattery()
        // Si la lectura no llega, intentar UNA consulta adicional. Sin timers
        // de vigilancia permanentes: iOS puede suspenderlos en segundo plano.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self = self, self.isConnected,
                  self.readyConnectionID == connectionID,
                  self.pendingConnectionAlertID == connectionID,
                  self.batteryPercentage == nil else { return }
            self.record("BATERIA", "Sin respuesta 10/01 a los 6 s; reintentando una vez")
            self.refreshBattery()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 14) { [weak self] in
            guard let self = self, self.isConnected,
                  self.readyConnectionID == connectionID,
                  self.pendingConnectionAlertID == connectionID else { return }
            self.pendingConnectionAlertID = nil
            self.batteryStatus = "Sin respuesta de batería en esta conexión"
            WatchConnectionAlerts.shared.sendConnectedAlert(
                watchName: self.watchName, percentage: nil)
        }
        Task { await SpotifyBridge.shared.recoverAfterWatchReady() }
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
        record("BLE", characteristic.isNotifying ? "Notificaciones F8F0 activadas" : "Notificaciones F8F0 desactivadas")
        if characteristic.isNotifying {
            finishBluetoothSetupIfReady()
        } else {
            isConnected = false
            connectionStatus = "Sin notificaciones F8F0"
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            record("ERROR", "Lectura BLE: \(error.localizedDescription)")
            return
        }
        guard characteristic.uuid == notifyUUID, let data = characteristic.value else { return }
        switch sleepAssembler.consume(data) {
        case .pending(let received, let expected):
            Task { @MainActor in WatchSleepProbe.shared.progress(received: received, expected: expected) }
            return
        case .complete(let message):
            let watchID = peripheral.identifier.uuidString
            Task { @MainActor in WatchSleepProbe.shared.receive(message, watchID: watchID) }
            return
        case .rejected(let reason):
            Task { @MainActor in WatchSleepProbe.shared.rejected(reason) }
            return
        case .unrelated: break
        }
        if let route = WatchHealthProtocol.route(data), route.group == 0x31, [0x08, 0x09].contains(route.command) {
            let watchID = peripheral.identifier.uuidString
            Task { @MainActor in WatchSleepProbe.shared.receive(data, watchID: watchID) }
            return
        }
        switch vitalsAssembler.consume(data) {
        case .pending(let received, let expected):
            Task { @MainActor in WatchVitalsProbe.shared.progress(received: received, expected: expected) }
            return
        case .complete(let message):
            let watchID = peripheral.identifier.uuidString
            Task { @MainActor in WatchVitalsProbe.shared.receive(message, watchID: watchID) }
            return
        case .rejected(let reason):
            Task { @MainActor in WatchVitalsProbe.shared.rejected(reason) }
            return
        case .unrelated: break
        }
        // Solo responde el propietario de la consulta; no mezclar con pasos.
        if let route = WatchHealthProtocol.route(data),
           (route.group == 0x30 && route.command == 0x06)
            || (route.group == 0x31 && [0x0B, 0x0C, 0x11, 0x12].contains(route.command)) {
            let watchID = peripheral.identifier.uuidString
            Task { @MainActor in WatchVitalsProbe.shared.receive(data, watchID: watchID) }
            if route.group == 0x31 { return }
        }
        switch stressAssembler.consume(data) {
        case .pending(let received, let expected):
            Task { @MainActor in WatchStressProbe.shared.progress(received: received, expected: expected) }
            return
        case .complete(let message):
            let watchID = peripheral.identifier.uuidString
            Task { @MainActor in WatchStressProbe.shared.receive(message, watchID: watchID) }
            return
        case .rejected(let reason):
            Task { @MainActor in WatchStressProbe.shared.rejected(reason) }
            return
        case .unrelated: break
        }
        switch healthAssembler.consume(data) {
        case .pending(let received, let expected):
            Task { @MainActor in
                WatchHealthSync.shared.transferProgress(received: received, expected: expected)
            }
            return
        case .complete(let message):
            let watchID = peripheral.identifier.uuidString
            Task { @MainActor in
                _ = WatchHealthSync.shared.receive(message, watchID: watchID)
            }
            return
        case .rejected(let reason):
            Task { @MainActor in WatchHealthSync.shared.transferRejected(reason) }
            return
        case .unrelated: break
        }
        if let frame = WatchHealthProtocol.route(data),
           (frame.group == 0x30 && frame.command == 0x06)
            || (frame.group == 0x31 && [0x06, 0x07, 0x0D, 0x0E].contains(frame.command)) {
            let watchID = peripheral.identifier.uuidString
            Task { @MainActor in
                if frame.group == 0x31 && [0x0D, 0x0E].contains(frame.command) {
                    WatchStressProbe.shared.receive(data, watchID: watchID)
                } else {
                    _ = WatchHealthSync.shared.receive(data, watchID: watchID)
                }
            }
            return
        }
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
            if pendingConnectionAlertID == readyConnectionID {
                pendingConnectionAlertID = nil
                WatchConnectionAlerts.shared.sendConnectedAlert(
                    watchName: watchName, percentage: percentage)
            }
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

    func refreshHealth() {
        guard isConnected, let device = peripheral else { return }
        healthAssembler.reset()
        let watchID = device.identifier.uuidString
        Task { @MainActor [weak self] in
            guard !WatchStressProbe.shared.isRunning, !WatchVitalsProbe.shared.isRunning, !WatchSleepProbe.shared.isRunning else { return }
            WatchHealthSync.shared.begin(watchID: watchID, clearPending: { [weak self] in
                self?.musicQueue.removeAll { $0.kind == .health }
                self?.healthAssembler.reset()
            }) { [weak self] data in
                guard let self = self, self.isConnected,
                      self.peripheral?.identifier.uuidString == watchID,
                      let tx = self.writeCharacteristic, tx.properties.contains(.write) else { return false }
                self.musicQueue.append(PendingMusicWrite(packet: data, delayAfter: 0, kind: .health))
                self.flushMusicQueue()
                return true
            }
        }
    }

    func refreshStressProbe() {
        guard isConnected, let device = peripheral else { return }
        let watchID = device.identifier.uuidString
        Task { @MainActor [weak self] in
            guard let self = self, !WatchHealthSync.shared.isRunning, !WatchStressProbe.shared.isRunning, !WatchVitalsProbe.shared.isRunning, !WatchSleepProbe.shared.isRunning else { return }
            self.stressAssembler.reset()
            WatchStressProbe.shared.begin(watchID: watchID, cleanup: { [weak self] in
                self?.musicQueue.removeAll { $0.kind == .health }
                self?.stressAssembler.reset()
            }) { [weak self] data in
                guard let self = self, self.isConnected,
                      self.peripheral?.identifier.uuidString == watchID,
                      let tx = self.writeCharacteristic, tx.properties.contains(.write) else { return false }
                self.musicQueue.append(PendingMusicWrite(packet: data, delayAfter: 0, kind: .health))
                self.flushMusicQueue()
                return true
            }
        }
    }

    func refreshVitalsProbe(_ mode: WatchVitalsProbe.Mode) {
        guard isConnected, let device = peripheral else { return }
        let watchID = device.identifier.uuidString
        Task { @MainActor [weak self] in
            guard let self = self, !WatchHealthSync.shared.isRunning,
                  !WatchStressProbe.shared.isRunning, !WatchVitalsProbe.shared.isRunning, !WatchSleepProbe.shared.isRunning else { return }
            self.vitalsAssembler.reset()
            WatchVitalsProbe.shared.begin(mode: mode, watchID: watchID, cleanup: { [weak self] in
                self?.musicQueue.removeAll { $0.kind == .vitals }
                self?.vitalsAssembler.reset()
            }) { [weak self] data in
                guard let self = self, self.isConnected,
                      self.peripheral?.identifier.uuidString == watchID,
                      let tx = self.writeCharacteristic, tx.properties.contains(.write) else { return false }
                self.musicQueue.append(PendingMusicWrite(packet: data, delayAfter: 0, kind: .vitals))
                self.flushMusicQueue()
                return true
            }
        }
    }

    func refreshSleepProbe(day: Date) {
        guard isConnected, let device = peripheral else { return }
        let watchID = device.identifier.uuidString
        Task { @MainActor [weak self] in
            guard let self = self, !WatchHealthSync.shared.isRunning, !WatchStressProbe.shared.isRunning,
                  !WatchVitalsProbe.shared.isRunning, !WatchSleepProbe.shared.isRunning else { return }
            self.sleepAssembler.reset()
            WatchSleepProbe.shared.begin(day: day, watchID: watchID, cleanup: { [weak self] in
                self?.musicQueue.removeAll { $0.kind == .sleepRead }
                self?.sleepAssembler.reset()
            }) { [weak self] data in
                guard let self = self, self.isConnected,
                      self.peripheral?.identifier.uuidString == watchID,
                      let tx = self.writeCharacteristic, tx.properties.contains(.write) else { return false }
                self.musicQueue.append(PendingMusicWrite(packet: data, delayAfter: 0, kind: .sleepRead))
                self.flushMusicQueue()
                return true
            }
        }
    }

    func refreshBattery() {
        guard isConnected, peripheral != nil, let tx = writeCharacteristic,
              tx.properties.contains(.write) else {
            batteryStatus = "Sin conexión o F8F1 no admite escritura"
            record("BATERIA", "No se pudo enviar consulta Motorola 10/01")
            return
        }
        guard Date().timeIntervalSince(batteryQuerySentAt ?? .distantPast) > 3 else {
            batteryStatus = "Consulta Motorola 10/01 ya solicitada; esperando respuesta"
            return
        }
        batteryQuerySentAt = Date()
        // La batería tiene prioridad sobre metadatos musicales pendientes.
        let packet = Data([0xAA, 0x04, 0x00, 0x00, 0x10, 0x01, 0x7E, 0xFD])
        musicQueue.insert(PendingMusicWrite(packet: packet, delayAfter: 0, kind: .battery), at: 0)
        batteryStatus = "Esperando respuesta Motorola 10/01"
        record("BATERIA", "Enviando consulta Motorola 10/01: \(MotoProtocol.hex(packet))")
        flushMusicQueue()
    }

    // Envío de avisos propios o recibidos por una automatización de Atajos iOS 27.
    // No se guardan remitente ni mensaje en el log, por privacidad.
    @discardableResult
    func sendNotification(source: String, sender: String, message: String) -> Bool {
        guard isConnected, let peripheral = peripheral, let tx = writeCharacteristic,
              tx.properties.contains(.write) else {
            record("NOTIFICACION", "No enviada: reloj BLE sin conexión de escritura")
            return false
        }
        let filterKey = "motowatch.notification.\(source.lowercased()).enabled"
        if let enabled = UserDefaults.standard.object(forKey: filterKey) as? Bool, !enabled {
            record("NOTIFICACION", "Origen desactivado: \(source)")
            return false
        }
        guard let packet = WatchNotificationProtocol.encode(source: source, sender: sender, message: message),
              packet.count <= peripheral.maximumWriteValueLength(for: .withResponse) else {
            record("NOTIFICACION", "No enviada: texto vacío o trama demasiado grande para MTU")
            return false
        }
        musicQueue.append(PendingMusicWrite(packet: packet, delayAfter: 0, kind: .notification))
        record("NOTIFICACION", "Encolada trama 25/02 para \(source), bytes=\(packet.count)")
        flushMusicQueue()
        return true
    }

    // Usar la codificación probada en Windows: anuncio 08 02 de canción
    // nueva y estado estable vacío al reproducir / 08 01 al pausar.
    func sendMusic(_ snapshot: WatchMusicSnapshot, force: Bool = false,
                   reannounce: Bool = false) {
        guard isConnected, writeCharacteristic != nil, peripheral != nil else {
            musicSyncStatus = "Requiere Bluetooth conectado y F8F1"
            return
        }
        let signature = "\(snapshot.id)|\(snapshot.isPlaying)"
        let changed = signature != lastMusicSignature
        if !force && !reannounce && !changed && Date().timeIntervalSince(lastMusicSentAt) < 25 { return }
        let trackChanged = lastMusicSignature == nil || lastMusicSignature?.components(separatedBy: "|").first != snapshot.id
        let steady = WatchMusicProtocol.encode(snapshot, code: snapshot.isPlaying ? .empty : .one)
        // Reemplazar SOLO metadatos antiguos; no descartar WhatsApp ni batería.
        musicQueue.removeAll { $0.kind == .music }
        if (trackChanged || force || reannounce) && snapshot.isPlaying {
            musicQueue.append(PendingMusicWrite(packet: WatchMusicProtocol.encode(snapshot, code: .two), delayAfter: 0.8, kind: .music))
        }
        musicQueue.append(PendingMusicWrite(packet: steady, delayAfter: 0, kind: .music))
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
        musicQueue.removeAll { $0.kind == .music }
        musicQueue.append(PendingMusicWrite(packet: WatchMusicProtocol.encodeNoMusic(), delayAfter: 0, kind: .music))
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
            flushMusicQueue()
            return
        }
        musicInProgress = true
        currentWriteIsSleep = next.kind == .sleepRead
        currentWriteIsVitals = next.kind == .vitals
        currentWriteIsHealth = next.kind == .health
        currentWriteIsBattery = next.kind == .battery
        musicAfterDelay = next.delayAfter
        record("BLE-TX", "F8F1: \(next.kind == .battery ? "BATERIA" : next.kind == .notification ? "AVISO" : next.kind == .health ? "SALUD" : next.kind == .vitals ? "CANDIDATO" : next.kind == .sleepRead ? "SUEÑO" : "MUSICA"), bytes=\(next.packet.count)")
        peripheral.writeValue(next.packet, for: tx, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == txUUID, musicInProgress,
              peripheral.identifier == self.peripheral?.identifier else { return }
        musicInProgress = false
        let isSleep = currentWriteIsSleep
        currentWriteIsSleep = false
        let isVitals = currentWriteIsVitals
        currentWriteIsVitals = false
        let isHealth = currentWriteIsHealth
        currentWriteIsHealth = false
        let isBattery = currentWriteIsBattery
        currentWriteIsBattery = false
        if let error = error {
            if isBattery { batteryStatus = "Error de consulta Motorola" }
            else if isSleep {
                Task { @MainActor in WatchSleepProbe.shared.cancel() }
                musicQueue.removeAll { $0.kind == .sleepRead }
            }
            else if isVitals {
                Task { @MainActor in WatchVitalsProbe.shared.cancel() }
                musicQueue.removeAll { $0.kind == .vitals }
            }
            else if isHealth {
                Task { @MainActor in
                    if WatchStressProbe.shared.isRunning {
                        WatchStressProbe.shared.cancel()
                    } else {
                        WatchHealthSync.shared.cancel(message: "Falló la consulta Bluetooth de salud")
                    }
                }
                musicQueue.removeAll { $0.kind == .health }
            }
            else { musicSyncStatus = "Error al escribir metadatos" }
            record("ERROR", "Escritura F8F1: \(error.localizedDescription)")
            // Una escritura fallida no debe borrar otros avisos ya encolados.
            flushMusicQueue()
            return
        }
        let delay = musicAfterDelay
        let connectionID = readyConnectionID
        if musicQueue.isEmpty && !isBattery && !isHealth && !isVitals && !isSleep { musicSyncStatus = "Datos enviados; pantalla no confirmada" }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.readyConnectionID == connectionID else { return }
                self.flushMusicQueue()
            }
        } else {
            flushMusicQueue()
        }
    }
}

