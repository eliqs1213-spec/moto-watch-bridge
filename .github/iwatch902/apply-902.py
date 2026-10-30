#!/usr/bin/env python3
"""Aplica AccessorySetupKit permanente y arregla PlayInfo sobre el árbol build 901."""
from pathlib import Path

ROOT = Path("ios-native")

def replace_once(path, old, new):
    path = Path(path)
    data = path.read_text(encoding="utf-8")
    count = data.count(old)
    assert count == 1, f"{path}: se esperaba 1 coincidencia y hay {count}: {old[:90]!r}"
    path.write_text(data.replace(old, new), encoding="utf-8")

ble = ROOT / "Sources/WatchBLEManager.swift"
replace_once(ble,
    """        // No hace falta que la interfaz esté visible para crear el central.
        central = CBCentralManager(
            delegate: self,
            queue: DispatchQueue.main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "org.motowatchbridge.native.ble.central"]
        )
        record("SISTEMA", "Moto Watch Bridge nativo iniciado")
    }""",
    """        // AccessorySetupKit debe autorizar/migrar ANTES de crear CBCentralManager.
        record("SISTEMA", "Moto Watch Bridge iniciado; esperando autorización de accesorios")
    }

    func startCentralIfNeeded() {
        guard central == nil else { return }
        // CoreBluetooth conserva la restauración de estado y notificaciones F8F0.
        central = CBCentralManager(
            delegate: self,
            queue: DispatchQueue.main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "org.motowatchbridge.native.ble.central"]
        )
        record("BLE", "CoreBluetooth iniciado después de AccessorySetupKit")
    }""")

replace_once(ble,
    "if central.isScanning { central.stopScan() }",
    "if central != nil && central.isScanning { central.stopScan() }")

replace_once(ble,
    """    @Published private(set) var autoReconnectEnabled =
        UserDefaults.standard.object(forKey: "motowatch.ble.autoReconnect") as? Bool ?? true""",
    """    // Reconexión obligatoria y permanente. No ofrecer un toggle para apagarla.
    @Published private(set) var autoReconnectEnabled = true""")

replace_once(ble,
    """    func setAutoReconnect(_ enabled: Bool) {
        autoReconnectEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "motowatch.ble.autoReconnect")
        record("BLE", enabled ? "Reconexión automática activada" : "Reconexión automática desactivada")
        if enabled { autoConnectIfNeeded() }
    }""",
    """    func setAutoReconnect(_ enabled: Bool) {
        autoReconnectEnabled = true
        UserDefaults.standard.set(true, forKey: "motowatch.ble.autoReconnect")
        autoConnectIfNeeded()
    }""")

replace_once(ble,
    """    func autoConnectIfNeeded() {
        guard autoReconnectEnabled, !manuallyDisconnected,""",
    """    func autoConnectIfNeeded() {
        guard let central = central else { return }
        guard autoReconnectEnabled, !manuallyDisconnected,""")

replace_once(ble,
    """    func connectToWatch() {
        manuallyDisconnected = false
        UserDefaults.standard.set(false, forKey: "motowatch.ble.manualDisconnect")
        guard central.state == .poweredOn else {""",
    """    func connectToWatch() {
        manuallyDisconnected = false
        UserDefaults.standard.set(false, forKey: "motowatch.ble.manualDisconnect")
        guard let central = central else {
            if #available(iOS 18.0, *) {
                MotoAccessorySetupCoordinator.shared.requestAuthorization()
            } else {
                startCentralIfNeeded()
            }
            return
        }
        guard central.state == .poweredOn else {""")

replace_once(ble,
    """    private func connectKnownPeripheral() -> Bool {
        guard let raw = UserDefaults.standard.string(forKey: storedPeripheralKey),""",
    """    private func connectKnownPeripheral() -> Bool {
        guard let central = central else { return false }
        guard let raw = UserDefaults.standard.string(forKey: storedPeripheralKey),""")

replace_once(ble,
    """    private func scanForeground() {
        guard UIApplication.shared.applicationState != .background else {""",
    """    private func scanForeground() {
        guard let central = central else { return }
        guard UIApplication.shared.applicationState != .background else {""")

replace_once(ble,
    """            guard let self = self, self.central.isScanning else { return }
            self.central.stopScan()""",
    """            guard let self = self, let central = self.central, central.isScanning else { return }
            central.stopScan()""")

replace_once(ble,
    """        central.stopScan()
        scanTimeout?.cancel(); scanTimeout = nil
        if let p = peripheral, p.state != .disconnected {
            central.cancelPeripheralConnection(p)""",
    """        central?.stopScan()
        scanTimeout?.cancel(); scanTimeout = nil
        if let p = peripheral, p.state != .disconnected {
            central?.cancelPeripheralConnection(p)""")

replace_once(ble,
    """    private func scheduleReconnectIfNeeded() {
        guard autoReconnectEnabled, !manuallyDisconnected, !reconnectScheduled,
              central.state == .poweredOn else { return }""",
    """    private func scheduleReconnectIfNeeded() {
        guard let central = central, autoReconnectEnabled,
              !manuallyDisconnected, !reconnectScheduled,
              central.state == .poweredOn else { return }""")

replace_once(ble,
    """            self.central.cancelPeripheralConnection(peripheral)""",
    """            self.central?.cancelPeripheralConnection(peripheral)""")

app = ROOT / "Sources/MotoWatchBridgeApp.swift"
replace_once(app,
    """        // Instanciar CoreBluetooth temprano es esencial para la restauración de estado.
        _ = WatchBLEManager.shared""",
    """        // AccessorySetupKit se activa SIEMPRE desde el arranque en iOS 18+.
        // Primero registrar/migrar el dispositivo; luego crear CBCentralManager.
        _ = WatchBLEManager.shared
        if #available(iOS 18.0, *) {
            MotoAccessorySetupCoordinator.shared.start()
        } else {
            WatchBLEManager.shared.startCentralIfNeeded()
        }""")

replace_once(app,
    """    func applicationDidBecomeActive(_ application: UIApplication) {
        WatchBLEManager.shared.resumeAuxiliaryWork()""",
    """    func applicationDidBecomeActive(_ application: UIApplication) {
        if #available(iOS 18.0, *) {
            MotoAccessorySetupCoordinator.shared.becameActive()
        }
        WatchBLEManager.shared.resumeAuxiliaryWork()""")

replace_once(app,
    """            Toggle("Reconexión automática", isOn: Binding(get: { watch.autoReconnectEnabled }, set: { watch.setAutoReconnect($0) }))
                .font(.subheadline).tint(.cyan)""",
    """            Label("Reconexión automática siempre activa", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline).foregroundStyle(.secondary)
            if #available(iOS 18.0, *) {
                MotoAccessorySetupStatusView()
            }""")

project = ROOT / "project.yml"
replace_once(project,
    """        NSBluetoothAlwaysUsageDescription: 'iWatch se conecta a Moto Watch Fit para controlar Spotify, consultar batería y localizar el teléfono.'""",
    """        NSBluetoothAlwaysUsageDescription: 'iWatch se conecta a Moto Watch Fit para controlar Spotify, consultar batería y localizar el teléfono.'
        NSAccessorySetupKitSupports:
          - Bluetooth
        NSAccessorySetupBluetoothNames:
          - Moto Watch Fit
        NSAccessorySetupBluetoothServices:
          - FC9DF9F0-4899-11EE-BE56-0242AC120002
        NSAccessorySetupBluetoothCompanyIdentifiers: []""")

source = project.read_text(encoding="utf-8")
assert source.count("CFBundleShortVersionString: '0.8.4.57'") == 2, "Versión 901 inesperada"
assert source.count("CFBundleVersion: '901'") == 2, "Build 901 inesperada"
project.write_text(source.replace("CFBundleShortVersionString: '0.8.4.57'", "CFBundleShortVersionString: '0.8.4.58'").replace("CFBundleVersion: '901'", "CFBundleVersion: '902'"), encoding="utf-8")

music = ROOT / "Sources/WatchMusicProtocol.swift"
replace_once(music,
    """        if snapshot.progressMs > 0 {
            details += numberField(7, snapshot.progressMs)
        }""",
    """        // PlayInfo field #7 es music_album_art, NO el progreso temporal.
        // No enviamos datos temporales como carátula hasta implementar
        // PlayPercent con su esquema confirmado y pruebas en reloj real.""")

print("902: AccessorySetupKit permanente, migración previa a CBCentralManager, auto-reconexión fija, field 7 eliminado")
