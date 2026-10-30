#!/usr/bin/env python3
"""iWatch 906: prueba A/B aislada de la lista vacia de fabricantes Bluetooth y diagnostico del IPA instalado."""
from pathlib import Path

project = Path("ios-native/project.yml")
source = project.read_text(encoding="utf-8")
assert source.count("CFBundleVersion: '904'") == 2, "Se esperaba la 904"
assert source.count("CFBundleShortVersionString: '0.8.4.60'") == 2
assert source.count("NSAccessorySetupSupports:") == 1
assert source.count("NSAccessorySetupKitSupports:") == 1
assert source.count("NSAccessorySetupBluetoothCompanyIdentifiers: []") == 1
source = source.replace("CFBundleVersion: '904'", "CFBundleVersion: '906'")
source = source.replace("CFBundleShortVersionString: '0.8.4.60'", "CFBundleShortVersionString: '0.8.4.62'")
# Test de una sola variable: la lista vacia no se emplea para descubrir el reloj.
# Nombres y UUID de servicio siguen declarados como exige Apple.
source = source.replace("        NSAccessorySetupBluetoothCompanyIdentifiers: []\n", "")
assert "NSAccessorySetupBluetoothServices:" in source
assert "NSAccessorySetupBluetoothNames:" in source
project.write_text(source, encoding="utf-8")

coordinator = Path("ios-native/Sources/MotoAccessorySetupCoordinator.swift")
swift = coordinator.read_text(encoding="utf-8")
def replace_once(before: str, after: str):
    global swift
    assert swift.count(before) == 1, f"Patron inesperado: {before[:120]}"
    swift = swift.replace(before, after)

replace_once(
    '    private let knownPeripheralKey = "motowatch.last.peripheral.uuid"',
    '''    private let knownPeripheralKey = "motowatch.last.peripheral.uuid"

    // Diagnostico de la app ya instalada/firmada, NO solo del IPA original.
    var installationDiagnostics: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let supports = info["NSAccessorySetupSupports"] as? [String] ?? []
        let legacy = info["NSAccessorySetupKitSupports"] as? [String] ?? []
        let names = info["NSAccessorySetupBluetoothNames"] as? [String] ?? []
        let services = info["NSAccessorySetupBluetoothServices"] as? [String] ?? []
        let company = info["NSAccessorySetupBluetoothCompanyIdentifiers"] as? [String]
        return "Bundle: \\(Bundle.main.bundleIdentifier ?? "desconocido")" +
            " | Supports: \\(supports.joined(separator: ","))" +
            " | KitSupports: \\(legacy.joined(separator: ","))" +
            " | Names: \\(names.joined(separator: ","))" +
            " | Services: \\(services.joined(separator: ","))" +
            " | CompanyIdentifiers: \\(company.map { String($0.count) } ?? "ausente")"
    }''')

replace_once(
    '''        let defaults = UserDefaults.standard

        // La sesión de iOS puede provocar un SIGTRAP no recuperable.''',
    '''        let defaults = UserDefaults.standard
        log("906 preflight firmado: \\(installationDiagnostics)")

        // La sesión de iOS puede provocar un SIGTRAP no recuperable.''')

replace_once(
    '''    func prepareManualAuthorization() {
        guard !isAuthorized else { return }
        // No modificar la conexión actual ni abrir el selector en este proceso.''',
    '''    func prepareManualAuthorization() {
        guard !isAuthorized else { return }
        log("906 preparación solicitada: \\(installationDiagnostics)")
        guard plistConfigurationIsValid else {
            status = "La configuración firmada de AccessorySetupKit no coincide; no se intentará iniciar"
            return
        }
        // No modificar la conexión actual ni abrir el selector en este proceso.''')

replace_once(
    '''            if !coordinator.isAuthorized && !coordinator.needsManualRestart {''',
    '''            Text(coordinator.installationDiagnostics)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !coordinator.isAuthorized && !coordinator.needsManualRestart {''')

replace_once(
    '''Text("La inicialización de AccessorySetupKit falló en la 902 y 903. El próximo intento podría cerrar la app una vez; el arranque posterior recuperará Bluetooth convencional.")''',
    '''Text("Diagnóstico 906: en la build 904 AccessorySetupKit produjo SIGTRAP durante ASAccessorySession.init(). No pruebes la migración hasta revisar la configuración mostrada arriba.")''')
assert "ASAccessorySession()" in swift
assert "MotoAccessorySetupCoordinator.shared.start()" not in swift
assert "installationDiagnostics" in swift
coordinator.write_text(swift, encoding="utf-8")
print("906: se mantiene el flujo ASK manual; se elimina solo la lista vacia y se añade diagnóstico de la app firmada")
