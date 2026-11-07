#!/usr/bin/env python3
"""920: reserve Bluetooth for AccessorySetupKit picker until outcome."""
from pathlib import Path
p=Path("ios-native/project.yml")
s=p.read_text()
assert s.count("CFBundleVersion: '918'")==2
s=s.replace("CFBundleVersion: '918'","CFBundleVersion: '920'").replace("CFBundleShortVersionString: '0.8.4.73'","CFBundleShortVersionString: '0.8.4.74'")
p.write_text(s)
p=Path("ios-native/Sources/WatchBLEManager.swift")
s=p.read_text()
needle="    func startCentralIfNeeded() {\n        guard central == nil else { return }"
assert s.count(needle)==1
s=s.replace(needle,'''    func startCentralIfNeeded() {
        if UserDefaults.standard.bool(forKey: "motowatch.ask.manual-request.904") {
            record("BLE-920", "CBCentralManager pospuesto mientras AccessorySetupKit presenta selector")
            return
        }
        guard central == nil else { return }''')
p.write_text(s)
p=Path("ios-native/Sources/MotoAccessorySetupCoordinator.swift")
s=p.read_text()
needle='''        let ble = WatchBLEManager.shared
        ble.startCentralIfNeeded()
        ble.autoConnectIfNeeded()
        log("CoreBluetooth convencional activo: \\(reason)")'''
assert s.count(needle)==1
s=s.replace(needle,'''        UserDefaults.standard.set(false, forKey: manualRequestKey)
        let ble = WatchBLEManager.shared
        ble.startCentralIfNeeded()
        ble.autoConnectIfNeeded()
        log("CoreBluetooth convencional activo: \\(reason)")''')
needle='''        let ble = WatchBLEManager.shared
        ble.startCentralIfNeeded()
        ble.autoConnectIfNeeded()
        log("AccessorySetupKit autorizado; CoreBluetooth iniciado tras migración")'''
assert s.count(needle)==1
s=s.replace(needle,'''        let ble = WatchBLEManager.shared
        ble.startCentralIfNeeded()
        ble.autoConnectIfNeeded()
        log("AccessorySetupKit autorizado; CoreBluetooth iniciado tras migración")''')
# Logging via WatchBLEManager is safe: its initializer does not create a CBCentralManager.
p.write_text(s)
print("920: no conventional central before picker; release on success/failure")
