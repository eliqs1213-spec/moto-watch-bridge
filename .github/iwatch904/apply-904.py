#!/usr/bin/env python3
"""Build 904: botón de migración manual sin intentar ASAccessorySession al abrir."""
from pathlib import Path
project = Path("ios-native/project.yml")
text = project.read_text(encoding="utf-8")
assert text.count("CFBundleVersion: '903'") == 2
assert text.count("CFBundleShortVersionString: '0.8.4.59'") == 2
assert text.count("NSAccessorySetupSupports:") == 1
assert text.count("NSAccessorySetupKitSupports:") == 1
text = text.replace("CFBundleVersion: '903'", "CFBundleVersion: '904'")
text = text.replace("CFBundleShortVersionString: '0.8.4.59'", "CFBundleShortVersionString: '0.8.4.60'")
project.write_text(text, encoding="utf-8")

src = Path("ios-native/Sources/MotoAccessorySetupCoordinator.swift").read_text(encoding="utf-8")
assert 'func prepareManualAuthorization()' in src
assert 'func cancelPreparedAuthorization()' in src
assert 'let accessory = ASAccessorySession()' in src
assert 'guard requested || previouslyAuthorized else {' in src
assert 'restoreConventionalBluetooth(reason: "Bluetooth convencional activo' in src
assert "motowatch.ask.session.init.inflight.904" in src
assert "MotoAccessorySetupStatusView" in src
assert "Preparar vinculación con AccessorySetupKit" in src
assert "Cerrá iWatch desde el selector de apps" in src
assert 'info["NSAccessorySetupSupports"]' in src
# La 902 intentaba abrir el selector incluso al pulsar Conectar. En la 904
# la autorización solo puede continuar si el usuario preparó la migración,
# se reinició la app y la sesión ya está activada.
ble = Path("ios-native/Sources/WatchBLEManager.swift")
ble_text = ble.read_text(encoding="utf-8")
old_call = "MotoAccessorySetupCoordinator.shared.requestAuthorization()"
assert ble_text.count(old_call) == 1, "Falta la llamada heredada de 902"
ble_text = ble_text.replace(old_call, "MotoAccessorySetupCoordinator.shared.becameActive()")
assert old_call not in ble_text, "Persistió llamada privada desde BLE"
ble.write_text(ble_text, encoding="utf-8")

assert "session.activate(on: DispatchQueue.main)" not in src
assert "accessory.activate(on: DispatchQueue.main)" in src
assert "startCentralIfNeeded()" in src
print("904 validado: CoreBluetooth normal por defecto; AccessorySetupKit solo tras solicitud manual; Live Activity intacta.")
