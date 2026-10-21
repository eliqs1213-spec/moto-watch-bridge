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
    @Published private(set) var weatherSyncStatus = "Clima aún no enviado al reloj"
    @Published private(set) var motorolaCharacteristicsStatus = "Todavía no se inspeccionaron las características Motorola"

    private let serviceUUID = CBUUID(string: MotoProtocol.service)
    private let notifyUUID = CBUUID(string: MotoProtocol.notifications)
    private let txUUID = CBUUID(string: MotoProtocol.writes)
    private let storedPeripheralKey = "motowatch.last.peripheral.uuid"
    private let logStorageKey = "motowatch.debug.log.v1"
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private typealias OutboundKind = WatchTrafficKind
    private struct PendingMusicWrite {
        let packet: Data
        let delayAfter: TimeInterval
        let kind: OutboundKind
        var musicStage: String? = nil
        var noticeWatchID: String? = nil
        var expiresAt: Date? = nil
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
    private var currentWriteIsNotification = false
    private var currentWriteIsWeather = false
    private var weatherTotalFragments = 0
    private var weatherConfirmedFragments = 0
    private var currentMusicStage: String? = nil
    // Coalescer sólo mientras el par ANUNCIO/ESTADO todavía está activo.
    private var latestMusicContents: String?
    private var deferredManualMusic: WatchMusicSnapshot?
    private var musicDiagnosticUntil = Date.distantPast
    private var musicDiagnosticPacketsLeft = 0
    private var writeTimeout: DispatchWorkItem?
    private var writeSequence = 0
    private var musicNotBefore = Date.distantPast
    private var queueWake: DispatchWorkItem?
    private var batteryRefresh: DispatchWorkItem?
    private var reconnectFailures = 0
    private var scanTimeout: DispatchWorkItem?
    private var logSave: DispatchWorkItem?
    @Published private(set) var notificationStatus = "Sin avisos pendientes"
    private var batteryQuerySentAt: Date? = nil
    private var lastMusicSignature: String?
    private var lastMusicSentAt = Date.distantPast
    private var manuallyDisconnected = UserDefaults.standard.bool(forKey: "motowatch.ble.manualDisconnect")
    @Published private(set) var autoReconnectEnabled =
        UserDefaults.standard.object(forKey: "motowatch.ble.autoReconnect") as? Bool ?? true
    private var readyConnectionID = 0
    private var pendingConnectionAlertID: Int? = nil
    private var reconnectScheduled = false
    // Restaurar una suscripción BLE ya conectada tras relanzamiento de iWatch
    // NO es un nuevo enlace físico; no repetir aviso de batería/conexión.
    private var restoredExistingConnection = false

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
        prunePendingNotices()
        musicQueue.removeAll { $0.kind != .notification }
        writeTimeout?.cancel(); writeTimeout = nil
        queueWake?.cancel(); queueWake = nil
        batteryRefresh?.cancel(); batteryRefresh = nil
        musicNotBefore = .distantPast
        currentWriteIsNotification = false
        currentWriteIsWeather = false
        weatherTotalFragments = 0
        weatherConfirmedFragments = 0
        currentMusicStage = nil
        weatherSyncStatus = "Envío de clima interrumpido por desconexión"
        motorolaCharacteristicsStatus = "Pendiente de descubrimiento en la nueva conexión"
        latestMusicContents = nil
        deferredManualMusic = nil
        musicDiagnosticPacketsLeft = 0
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
        guard logSave == nil else { return }
        let save = DispatchWorkItem { [weak self] in self?.flushLog() }
        logSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: save)
    }

    func flushLog() {
        logSave?.cancel(); logSave = nil
        if let data = try? JSONEncoder().encode(events) { UserDefaults.standard.set(data, forKey: logStorageKey) }
    }

    func pauseAuxiliaryWork() {
        // Se conserva el enlace, la suscripción y la cola de notificaciones.
        batteryRefresh?.cancel(); batteryRefresh = nil
        if central.isScanning { central.stopScan() }
        flushLog()
    }
    func resumeAuxiliaryWork() {
        autoConnectIfNeeded()
        if isConnected { refreshBattery(force: false); scheduleBatteryRefresh() }
    }

    func clearLog() {
        logSave?.cancel(); logSave = nil
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
        restoredExistingConnection = true
        peripheral = device
        device.delegate = self
        connectionStatus = "Enlace restaurado; redescubriendo F8F0/F8F1"
        record("BLE", "Periférico conectado sin sesión lista: redescubriendo servicios")
        device.discoverServices(nil)
    }

    func autoConnectIfNeeded() {
        guard autoReconnectEnabled, !manuallyDisconnected,
              !reconnectScheduled,
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
        scanTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, self.central.isScanning else { return }
            self.central.stopScan()
            self.connectionStatus = "Reloj no encontrado; tocá Conectar para volver a buscar"
        }
        scanTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
    }

    func disconnect() {
        manuallyDisconnected = true
        UserDefaults.standard.set(true, forKey: "motowatch.ble.manualDisconnect")
        musicQueue.removeAll { $0.kind == .notification }
        notificationStatus = "Avisos pendientes cancelados por desconexión manual"
        resetConnectionTransport()
        central.stopScan()
        scanTimeout?.cancel(); scanTimeout = nil
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
                restoredExistingConnection = true
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
        reconnectFailures = 0
        peripheral = device
        device.delegate = self
        watchName = device.name ?? "Moto Watch Fit"
        UserDefaults.standard.set(device.identifier.uuidString, forKey: storedPeripheralKey)
        resetConnectionTransport()
        restoredExistingConnection = false
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
        reconnectFailures += 1
        let delay = WatchTrafficPolicy.reconnectDelay(failures: reconnectFailures)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
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
            scheduleReconnectIfNeeded()
        }
    }

    // Una lectura de la tabla de características, sin readValue, notify adicional ni writeValue.
    func inspectMotorolaCharacteristics() {
        guard isConnected, let device = peripheral,
              let motorola = device.services?.first(where: { $0.uuid == serviceUUID }) else {
            motorolaCharacteristicsStatus = "Conectá el reloj primero"
            return
        }
        motorolaCharacteristicsStatus = "Inspeccionando características por GATT…"
        device.discoverCharacteristics(nil, for: motorola)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            record("ERROR", "Servicios: \(error.localizedDescription)")
            return
        }
        let services = peripheral.services ?? []
        // Diagnóstico pasivo de servicios BLE tras cada conexión/reconexión.
        // La ausencia de HID por GATT NO demuestra ausencia de Classic HID/AVRCP.
        record("BLE-CAPACIDADES",
               WatchBLECapabilityProbe.summarize(
                serviceUUIDs: services.map { $0.uuid.uuidString }))
        if let motorola = services.first(where: { $0.uuid == serviceUUID }) {
            // Descubrimiento pasivo: también permite detectar la F8F2 vista en el firmware.
            // No se modifica ninguna suscripción ni se escriben características desconocidas.
            peripheral.discoverCharacteristics(nil, for: motorola)
        } else {
            record("ERROR", "Servicio Motorola F9F0 no encontrado")
        }
        batteryStatus = "Batería Motorola: protocolo 10/01"
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            motorolaCharacteristicsStatus = "Error de descubrimiento: \(error.localizedDescription)"
            record("ERROR", "Características: \(error.localizedDescription)")
            return
        }
        guard service.uuid == serviceUUID else { return }
        let found = (service.characteristics ?? []).map {
            WatchBLECapabilityProbe.CharacteristicInfo(
                uuid: $0.uuid.uuidString, properties: UInt($0.properties.rawValue))
        }
        let summary = WatchBLECapabilityProbe.summarizeMotorolaCharacteristics(found)
        motorolaCharacteristicsStatus = summary
        record("BLE-CARACTERISTICAS", summary)
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
        reconnectFailures = 0
        connectionStatus = "Escuchando botones · F8F1 listo"
        record("BLE", "Sesión lista: F8F0 notificando y F8F1 escribible")
        flushMusicQueue()
        scheduleBatteryRefresh()
        let connectionID = readyConnectionID
        if restoredExistingConnection {
            pendingConnectionAlertID = nil
            record("AVISO", "Conexión restaurada; aviso de batería omitido porque no hubo un enlace físico nuevo")
        } else {
            pendingConnectionAlertID = connectionID
        }
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
        if let signal = WatchEnvironmentalProtocol.identify(data) {
            record("MOTO-ENTORNO", signal.diagnostic)
        }
        // Diagnóstico pasivo: SOLO aprovecha callbacks F8F0 reales de iOS;
        // no inventa notificaciones ni consultas periódicas al reloj.
        MusicBackgroundExperiment.shared.didReceiveRealBLEFrame(data)
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

    var healthWatchID: String? {
        peripheral?.identifier.uuidString ?? UserDefaults.standard.string(forKey: storedPeripheralKey)
    }

    @discardableResult
    func refreshHealth(includePulse: Bool = true) -> Task<Bool, Never>? {
        guard isConnected, let device = peripheral else { return nil }
        healthAssembler.reset()
        let watchID = device.identifier.uuidString
        return Task { @MainActor [weak self] in
            guard UIApplication.shared.applicationState == .active else { return false }
            guard !WatchHealthSync.shared.isRunning, !WatchStressProbe.shared.isRunning, !WatchVitalsProbe.shared.isRunning, !WatchSleepProbe.shared.isRunning else { return false }
            WatchHealthSync.shared.begin(watchID: watchID, includePulse: includePulse, clearPending: { [weak self] in
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
            return true
        }
    }

    @discardableResult
    func refreshStressProbe() -> Task<Bool, Never>? {
        guard isConnected, let device = peripheral else { return nil }
        let watchID = device.identifier.uuidString
        return Task { @MainActor [weak self] in
            guard UIApplication.shared.applicationState == .active else { return false }
            guard let self = self, !WatchHealthSync.shared.isRunning, !WatchStressProbe.shared.isRunning, !WatchVitalsProbe.shared.isRunning, !WatchSleepProbe.shared.isRunning else { return false }
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
            return true
        }
    }

    @discardableResult
    func refreshVitalsProbe(_ mode: WatchVitalsProbe.Mode, validatedOnly: Bool = false) -> Task<Bool, Never>? {
        guard isConnected, let device = peripheral else { return nil }
        let watchID = device.identifier.uuidString
        return Task { @MainActor [weak self] in
            guard UIApplication.shared.applicationState == .active else { return false }
            guard let self = self, !WatchHealthSync.shared.isRunning,
                  !WatchStressProbe.shared.isRunning, !WatchVitalsProbe.shared.isRunning, !WatchSleepProbe.shared.isRunning else { return false }
            self.vitalsAssembler.reset()
            WatchVitalsProbe.shared.begin(mode: mode, watchID: watchID, validatedOnly: validatedOnly, cleanup: { [weak self] in
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
            return true
        }
    }

    @discardableResult
    func refreshSleepProbe(day: Date) -> Task<Bool, Never>? {
        guard isConnected, let device = peripheral else { return nil }
        let watchID = device.identifier.uuidString
        return Task { @MainActor [weak self] in
            guard UIApplication.shared.applicationState == .active else { return false }
            guard let self = self, !WatchHealthSync.shared.isRunning, !WatchStressProbe.shared.isRunning,
                  !WatchVitalsProbe.shared.isRunning, !WatchSleepProbe.shared.isRunning else { return false }
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
            return true
        }
    }

    func refreshBattery(force: Bool = true) {
        guard isConnected, peripheral != nil, let tx = writeCharacteristic,
              tx.properties.contains(.write) else {
            batteryStatus = "Sin conexión o F8F1 no admite escritura"
            record("BATERIA", "No se pudo enviar consulta Motorola 10/01")
            return
        }
        guard !musicQueue.contains(where: { $0.kind == .battery }), !currentWriteIsBattery,
              Date().timeIntervalSince(batteryQuerySentAt ?? .distantPast) > (force ? 3 : 1800) else {
            batteryStatus = "Consulta Motorola 10/01 ya solicitada; esperando respuesta"
            return
        }
        batteryQuerySentAt = Date()
        // Consulta auxiliar de baja prioridad.
        let packet = Data([0xAA, 0x04, 0x00, 0x00, 0x10, 0x01, 0x7E, 0xFD])
        musicQueue.append(PendingMusicWrite(packet: packet, delayAfter: 0, kind: .battery))
        batteryStatus = "Esperando respuesta Motorola 10/01"
        record("BATERIA", "Enviando consulta Motorola 10/01: \(MotoProtocol.hex(packet))")
        flushMusicQueue()
    }

    // Prueba manual de 23/01. Sin envío automático, ni modificación de firmware.
    @discardableResult
    func sendWeatherExperimental(_ snapshot: WatchWeatherSnapshot) -> Bool {
        guard UIApplication.shared.applicationState == .active,
              isConnected, let peripheral = peripheral,
              let tx = writeCharacteristic, tx.properties.contains(.write) else {
            weatherSyncStatus = "Conectá el reloj con iWatch visible"
            return false
        }
        guard !currentWriteIsWeather, !musicQueue.contains(where: { $0.kind == .weather }) else {
            weatherSyncStatus = "Ya hay un envío del clima en curso"
            return false
        }
        do {
            let frame = try WatchWeatherProtocol.encode(snapshot)
            let reportedLimit = peripheral.maximumWriteValueLength(for: .withResponse)
            guard let size = WatchWeatherProtocol.conservativeWriteLimit(reportedMaximum: reportedLimit) else {
                weatherSyncStatus = "La conexión no permite fragmentos de 20 bytes"
                record("CLIMA-BLE", "Sin límite seguro de escritura (máximo informado \(reportedLimit))")
                return false
            }
            let parts = WatchWeatherProtocol.fragments(frame, maximum: size)
            guard !parts.isEmpty, parts.count <= 100 else {
                weatherSyncStatus = "Pronóstico demasiado grande para la prueba limitada"
                return false
            }
            weatherTotalFragments = parts.count
            weatherConfirmedFragments = 0
            for part in parts {
                musicQueue.append(PendingMusicWrite(packet: part, delayAfter: 0, kind: .weather))
            }
            weatherSyncStatus = "Enviando clima: 0/\(parts.count) fragmentos"
            record("CLIMA-BLE", "Prueba 23/01: \(frame.count) bytes, \(parts.count) fragmentos de máximo \(size) bytes (máximo iOS \(reportedLimit)); sin reintentos")
            flushMusicQueue()
            return true
        } catch {
            weatherSyncStatus = "No se pudo preparar el clima; actualizá el pronóstico"
            record("CLIMA-BLE", "Codificación rechazada: \(error)")
            return false
        }
    }

    // Envío de avisos propios o recibidos por una automatización de Atajos iOS 27.
    // No se guardan remitente ni mensaje en el log, por privacidad.
    @discardableResult
    func sendNotification(source: String, sender: String, message: String) -> Bool {
        guard !manuallyDisconnected, let target = healthWatchID,
              isConnected || autoReconnectEnabled else {
            notificationStatus = "No encolada: conectá el reloj"
            record("NOTIFICACION", notificationStatus)
            return false
        }
        let filterKey = "motowatch.notification.\(source.lowercased()).enabled"
        if let enabled = UserDefaults.standard.object(forKey: filterKey) as? Bool, !enabled {
            record("NOTIFICACION", "Origen desactivado: \(source)")
            return false
        }
        prunePendingNotices()
        guard musicQueue.filter({ $0.kind == .notification }).count < 100 else {
            notificationStatus = "Cola de avisos llena; no se aceptó el nuevo aviso"
            record("NOTIFICACION", notificationStatus); return false
        }
        guard let packet = WatchNotificationProtocol.encode(source: source, sender: sender, message: message),
              !isConnected || packet.count <= (peripheral?.maximumWriteValueLength(for: .withResponse) ?? 0) else {
            record("NOTIFICACION", "No enviada: texto vacío o trama demasiado grande para MTU")
            return false
        }
        musicQueue.append(PendingMusicWrite(packet: packet, delayAfter: 0, kind: .notification,
            noticeWatchID: target, expiresAt: Date().addingTimeInterval(120)))
        notificationStatus = isConnected ? "Aviso encolado con prioridad" : "Aviso pendiente: reconectando (máximo 2 minutos)"
        record("NOTIFICACION", "Encolada trama 25/02 para \(source), bytes=\(packet.count)")
        flushMusicQueue()
        if !isConnected { autoConnectIfNeeded() }
        return true
    }

    private func prunePendingNotices() {
        let before = musicQueue.filter { $0.kind == .notification }.count
        musicQueue.removeAll {
            $0.kind == .notification && !WatchTrafficPolicy.acceptsNotice(
                target: $0.noticeWatchID, current: healthWatchID, expiresAt: $0.expiresAt, now: Date())
        }
        if musicQueue.filter({ $0.kind == .notification }).count < before {
            notificationStatus = "Avisos pendientes vencidos o de otro reloj descartados"
            record("NOTIFICACION", notificationStatus)
        }
    }

    private func scheduleBatteryRefresh() {
        batteryRefresh?.cancel()
        let connectionID = readyConnectionID
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isConnected, self.readyConnectionID == connectionID else { return }
            if UIApplication.shared.applicationState == .active { self.refreshBattery(force: false) }
            self.scheduleBatteryRefresh()
        }
        batteryRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1800, execute: work)
    }

    // El registro hexadecimal puede revelar nombres de canciones y artistas.
    // Se activa solo por una acción explícita del usuario y por dos escrituras
    // musicales como máximo, dentro de una ventana de 20 s.
    func captureNextMusicFrames() {
        musicDiagnosticPacketsLeft = 2
        musicDiagnosticUntil = Date().addingTimeInterval(20)
        record("MUSICA-DIAG", "Captura puntual de hasta 2 paquetes 24/01 activada (20 s); contiene nombres de canciones en HEX")
    }

    // Usar la codificación probada en Windows: anuncio 08 02 de canción
    // nueva y estado estable vacío al reproducir / 08 01 al pausar.
    func sendMusic(_ snapshot: WatchMusicSnapshot, force: Bool = false,
                   reannounce: Bool = false, origin: String = "indirecto") {
        guard isConnected, writeCharacteristic != nil, peripheral != nil else {
            musicSyncStatus = "Requiere Bluetooth conectado y F8F1"
            return
        }
        let signature = "\(snapshot.id)|\(snapshot.isPlaying)"
        let contents = "\(snapshot.title)|\(snapshot.artist)|\(snapshot.album)|\(snapshot.isPlaying)"
        let pendingStages = musicQueue.filter { $0.kind == .music }
            .compactMap { $0.musicStage }
        if WatchMusicSequencePolicy.shouldCoalesce(
            requestedContent: contents, latestContent: latestMusicContents,
            inFlightStage: currentMusicStage, pendingStages: pendingStages
        ) {
            if origin == "manual" {
                deferredManualMusic = snapshot
                record("MUSICA-SEQ", "Resincronización manual diferida hasta terminar secuencia activa")
            } else {
                record("MUSICA-SEQ", "Duplicado \(origin) omitido: canción ya en secuencia BLE activa")
            }
            return
        }
        let changed = signature != lastMusicSignature
        if !force && !reannounce && !changed && Date().timeIntervalSince(lastMusicSentAt) < 25 { return }
        let trackChanged = lastMusicSignature == nil || lastMusicSignature?.components(separatedBy: "|").first != snapshot.id
        let steady = WatchMusicProtocol.encode(snapshot, code: snapshot.isPlaying ? .empty : .one)
        // Si el ANUNCIO ya salió (o está en vuelo), no descartar el ESTADO
        // que lo cierra cuando llega un evento nuevo de Spotify. Una secuencia
        // a medias puede dejar al firmware en «Poné música».
        // Si la pareja ANUNCIO+ESTADO todavía estaba toda en cola,
        // sustituirla por completo: prevalece la canción más reciente.
        let pendingMusicStages = musicQueue.filter { $0.kind == .music }
            .compactMap { $0.musicStage }
        let preserveClosingState = WatchMusicSequencePolicy.preserveClosingState(
            stages: pendingMusicStages)
        let completingOldState: PendingMusicWrite? = preserveClosingState ?
            musicQueue.first { $0.kind == .music && $0.musicStage == "ESTADO" } : nil
        let removed = musicQueue.filter { $0.kind == .music }.count
        musicQueue.removeAll { $0.kind == .music }
        if let completingOldState = completingOldState {
            musicQueue.append(completingOldState)
            record("MUSICA-SEQ", "Preservando ESTADO pendiente tras ANUNCIO previo; siguiente canción encolada detrás")
        } else if removed > 0 {
            record("MUSICA", "Secuencia musical todavía no iniciada sustituida: \(removed) paquetes")
        }
        if (trackChanged || force || reannounce) && snapshot.isPlaying {
            musicQueue.append(PendingMusicWrite(packet: WatchMusicProtocol.encode(snapshot, code: .two), delayAfter: 0.8, kind: .music, musicStage: "ANUNCIO"))
        }
        musicQueue.append(PendingMusicWrite(packet: steady, delayAfter: 0, kind: .music, musicStage: "ESTADO"))
        lastMusicSignature = signature
        latestMusicContents = contents
        lastMusicSentAt = Date()
        musicSyncStatus = "Enviando: \(snapshot.title) · \(snapshot.isPlaying ? "PLAY" : "PAUSA")"
        record("MUSICA", "Origen \(origin) · metadatos: \(snapshot.title) - \(snapshot.artist) | \(snapshot.isPlaying ? "PLAY" : "PAUSA")")
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
        latestMusicContents = nil
        deferredManualMusic = nil
        musicQueue.append(PendingMusicWrite(packet: WatchMusicProtocol.encodeNoMusic(), delayAfter: 0, kind: .music, musicStage: "SIN_MUSICA"))
        lastMusicSignature = "NO_MUSIC"
        lastMusicSentAt = Date()
        musicSyncStatus = "Sin música · señal enviada (pantalla no confirmada)"
        record("MUSICA", "Estado sin música enviado: \(reason) | paquete experimental 24/01")
        flushMusicQueue()
    }

    private func flushMusicQueue() {
        prunePendingNotices()
        guard isConnected, !musicInProgress, !musicQueue.isEmpty,
              let peripheral = peripheral, let tx = writeCharacteristic else { return }
        guard let index = WatchTrafficPolicy.nextIndex(musicQueue.map(\.kind), musicReady: Date() >= musicNotBefore) else {
            queueWake?.cancel()
            let connectionID = readyConnectionID
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.readyConnectionID == connectionID else { return }
                self.flushMusicQueue()
            }
            queueWake = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, musicNotBefore.timeIntervalSinceNow), execute: work)
            return
        }
        let next = musicQueue.remove(at: index)
        let maxLength = peripheral.maximumWriteValueLength(for: .withResponse)
        guard tx.properties.contains(.write), next.packet.count <= maxLength else {
            musicSyncStatus = "El paquete no cabe en el tamaño BLE disponible"
            record("ERROR", "Escritura F8F1 inválida: tamaño \(next.packet.count), máximo \(maxLength)")
            if next.kind == .notification { notificationStatus = "Aviso rechazado: tamaño no compatible con este enlace" }
            flushMusicQueue()
            return
        }
        musicInProgress = true
        currentWriteIsSleep = next.kind == .sleepRead
        currentWriteIsVitals = next.kind == .vitals
        currentWriteIsHealth = next.kind == .health
        currentWriteIsBattery = next.kind == .battery
        currentWriteIsNotification = next.kind == .notification
        currentWriteIsWeather = next.kind == .weather
        currentMusicStage = next.kind == .music ? next.musicStage : nil
        musicAfterDelay = next.delayAfter
        if next.kind == .music && musicDiagnosticPacketsLeft > 0 {
            if Date() <= musicDiagnosticUntil {
                musicDiagnosticPacketsLeft -= 1
                record("MUSICA-DIAG", "TX \(next.musicStage ?? "ETAPA_DESCONOCIDA") · \(next.packet.count) bytes · HEX: \(MotoProtocol.hex(next.packet))")
            } else {
                musicDiagnosticPacketsLeft = 0
                record("MUSICA-DIAG", "Captura puntual expirada antes del siguiente paquete")
            }
        }
        record("BLE-TX", "F8F1: \(next.kind == .weather ? "CLIMA" : next.kind == .battery ? "BATERIA" : next.kind == .notification ? "AVISO" : next.kind == .health ? "SALUD" : next.kind == .vitals ? "CANDIDATO" : next.kind == .sleepRead ? "SUEÑO" : "MUSICA"), bytes=\(next.packet.count)")
        writeSequence += 1
        let sequence = writeSequence
        let connectionID = readyConnectionID
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, self.musicInProgress, self.writeSequence == sequence,
                  self.readyConnectionID == connectionID else { return }
            if self.currentWriteIsNotification {
                self.notificationStatus = "Aviso con resultado incierto; no se duplica el envío"
            }
            self.record("ERROR", "Escritura sin confirmación en 8 s; recuperando enlace")
            self.resetConnectionTransport()
            self.central.cancelPeripheralConnection(peripheral)
        }
        writeTimeout?.cancel(); writeTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
        peripheral.writeValue(next.packet, for: tx, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == txUUID, musicInProgress,
              characteristic === writeCharacteristic,
              peripheral.identifier == self.peripheral?.identifier else { return }
        writeTimeout?.cancel(); writeTimeout = nil
        musicInProgress = false
        let isSleep = currentWriteIsSleep
        currentWriteIsSleep = false
        let isVitals = currentWriteIsVitals
        currentWriteIsVitals = false
        let isHealth = currentWriteIsHealth
        currentWriteIsHealth = false
        let isBattery = currentWriteIsBattery
        currentWriteIsBattery = false
        let isNotice = currentWriteIsNotification
        currentWriteIsNotification = false
        let isWeather = currentWriteIsWeather
        currentWriteIsWeather = false
        let completedMusicStage = currentMusicStage
        currentMusicStage = nil
        if let error = error {
            if isNotice {
                notificationStatus = "Falló la escritura del aviso; no se reenvía para evitar duplicados"
                record("NOTIFICACION", notificationStatus)
            }
            else if isWeather {
                weatherSyncStatus = "Clima rechazado en fragmento \(weatherConfirmedFragments + 1)/\(weatherTotalFragments); no se reintenta"
                musicQueue.removeAll { $0.kind == .weather }
                record("CLIMA-BLE", "Escritura fallida en \(weatherConfirmedFragments + 1)/\(weatherTotalFragments): \(error.localizedDescription)")
                weatherTotalFragments = 0
                weatherConfirmedFragments = 0
            }
            else if isBattery { batteryStatus = "Error de consulta Motorola" }
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
            else {
                musicSyncStatus = "Error al escribir metadatos"
                lastMusicSignature = nil
                latestMusicContents = nil
                deferredManualMusic = nil
                // No continuar el ESTADO de un ANUNCIO rechazado. Se recupera
                // cuando Spotify entregue nuevamente un estado válido.
                musicQueue.removeAll { $0.kind == .music }
            }
            if let completedMusicStage = completedMusicStage {
                record("MUSICA-DIAG", "BLE rechazó \(completedMusicStage): \(error.localizedDescription)")
            }
            record("ERROR", "Escritura F8F1: \(error.localizedDescription)")
            // Una escritura fallida no debe borrar otros avisos ya encolados.
            flushMusicQueue()
            return
        }
        let delay = musicAfterDelay
        if isNotice { notificationStatus = "Aviso escrito por Bluetooth; visualización no confirmada" }
        if isWeather {
            weatherConfirmedFragments += 1
            let completed = weatherConfirmedFragments
            let total = weatherTotalFragments
            weatherSyncStatus = "Clima BLE: \(completed)/\(total) fragmentos confirmados"
            if completed == 1 || completed % 8 == 0 || completed == total {
                record("CLIMA-BLE", "Progreso ATT: \(completed)/\(total) escrituras aceptadas por iOS")
            }
            if completed == total {
                weatherSyncStatus = "23/01 transmitido por BLE; verificá la pantalla del reloj"
                record("CLIMA-BLE", "Todos los fragmentos confirmados por iOS; pantalla NO verificada")
                weatherTotalFragments = 0
                weatherConfirmedFragments = 0
            }
        }
        if !isNotice && !isBattery && !isHealth && !isVitals && !isSleep {
            musicNotBefore = Date().addingTimeInterval(delay)
            if let completedMusicStage = completedMusicStage {
                record("MUSICA-DIAG", "BLE confirmó escritura \(completedMusicStage); firmware/pantalla NO verificados")
            }
            if completedMusicStage == "ESTADO" {
                record("MUSICA-SEQ", "Etapa ESTADO confirmada por BLE; secuencia cerrada (pantalla no verificada)")
                if let manualSnapshot = deferredManualMusic {
                    let pendingContents = "\(manualSnapshot.title)|\(manualSnapshot.artist)|\(manualSnapshot.album)|\(manualSnapshot.isPlaying)"
                    if pendingContents != latestMusicContents {
                        deferredManualMusic = nil
                        record("MUSICA-SEQ", "Resincronización manual diferida cancelada: estado musical cambiado")
                    } else if !musicQueue.contains(where: { $0.kind == .music }) {
                        deferredManualMusic = nil
                        record("MUSICA-SEQ", "Ejecutando resincronización manual tras cerrar ANUNCIO/ESTADO")
                        sendMusic(manualSnapshot, force: true, reannounce: true, origin: "manual")
                    }
                }
            }
            if musicQueue.isEmpty && completedMusicStage == "ESTADO" {
                musicSyncStatus = "Secuencia musical completa en BLE; pantalla no verificada"
            }
        }
        flushMusicQueue()
    }
}
