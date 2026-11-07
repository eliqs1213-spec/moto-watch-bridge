#!/usr/bin/env python3
"""Build 912: isolated foreground CoreBluetooth authorization probe."""
from pathlib import Path
p=Path("ios-native/project.yml")
s=p.read_text()
assert s.count("CFBundleVersion: '910'")==2
assert s.count("CFBundleShortVersionString: '0.8.4.66'")==2
s=s.replace("CFBundleVersion: '910'","CFBundleVersion: '912'").replace("CFBundleShortVersionString: '0.8.4.66'","CFBundleShortVersionString: '0.8.4.68'")
p.write_text(s)
p=Path("ios-native/Sources/WatchBLEManager.swift")
s=p.read_text()
needle="    private var peripheral: CBPeripheral?"
assert s.count(needle)==1
s=s.replace(needle,'''    // Independiente del central restaurable: prueba si iOS solicita autorización
    // para un CBCentralManager convencional sin restore identifier.
    private var permissionProbe: CBCentralManager?
    private var permissionProbeAttempted = false
'''+needle)
needle='    func centralManagerDidUpdateState(_ central: CBCentralManager) {'
assert s.count(needle)==1
s=s.replace(needle,'''    func probeBluetoothAuthorizationIfNeeded() {
        guard !permissionProbeAttempted else { return }
        guard CBCentralManager.authorization == .notDetermined else {
            record("BLE-912", "Sin prueba adicional: autorización ya determinada")
            return
        }
        permissionProbeAttempted = true
        record("BLE-912", "Creando CBCentralManager de prueba sin restauración para solicitar permiso; estado previo=notDetermined")
        permissionProbe = CBCentralManager(
            delegate: self,
            queue: DispatchQueue.main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

'''+needle)
needle='        let authorization: String'
assert s.count(needle)==1
s=s.replace(needle,'''        if let probe = permissionProbe, central === probe {
            record("BLE-912", "Callback del central de prueba: state=\\(central.state.rawValue), authorization=\\(CBCentralManager.authorization.rawValue)")
            return
        }
'''+needle)
# Called after the primary central has been started by AccessorySetupKit coordinator.
needle='        record("BLE", "CoreBluetooth iniciado después de AccessorySetupKit")'
assert s.count(needle)==1
s=s.replace(needle,needle+'''
        // Solo en el caso sin decisión de permisos; no modifica el central principal.
        probeBluetoothAuthorizationIfNeeded()''')
p.write_text(s)
print("912: isolated CoreBluetooth permission probe added; Spotify, widget, ASK untouched")
