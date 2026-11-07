#!/usr/bin/env python3
"""916: opt-in ASK migration; preserve 914 CoreBluetooth default."""
from pathlib import Path
p=Path("ios-native/project.yml"); s=p.read_text()
assert s.count("CFBundleVersion: '914'")==2
s=s.replace("CFBundleVersion: '914'","CFBundleVersion: '916'").replace("CFBundleShortVersionString: '0.8.4.70'","CFBundleShortVersionString: '0.8.4.72'")
# Restore the descriptor metadata without enabling ASAccessorySession on normal launch.
needle="        NSBluetoothAlwaysUsageDescription:"
assert needle in s
anchor="        NSBluetoothAlwaysUsageDescription: 'iWatch se conecta a Moto Watch Fit para controlar Spotify, consultar batería y localizar el teléfono.'"
assert s.count(anchor)==1
s=s.replace(anchor,anchor+'''
        NSAccessorySetupSupports:
          - Bluetooth
        NSAccessorySetupKitSupports:
          - Bluetooth
        NSAccessorySetupBluetoothNames:
          - Moto Watch Fit
        NSAccessorySetupBluetoothServices:
          - FC9DF9F0-4899-11EE-BE56-0242AC120002''')
p.write_text(s)
p=Path("ios-native/Sources/MotoWatchBridgeApp.swift");s=p.read_text()
needle='''        _ = SpotifyBridge.shared'''
assert s.count(needle)==1
s=s.replace(needle,'''        if #available(iOS 18.0, *) {
            // A clean install of 916 ignores stale migration flags from earlier builds.
            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: "motowatch.ask.916.initialized") {
                defaults.set(true, forKey: "motowatch.ask.916.initialized")
                defaults.set(false, forKey: "motowatch.ask.manual-request.904")
                defaults.set(false, forKey: "motowatch.ask.authorized.904")
                defaults.set(false, forKey: "motowatch.ask.session.init.inflight.904")
            }
            if defaults.bool(forKey: "motowatch.ask.manual-request.904") {
                MotoAccessorySetupCoordinator.shared.start()
            } else {
                WatchBLEManager.shared.startCentralIfNeeded()
                WatchBLEManager.shared.record("BLE-916", "Inicio seguro 914: ASK no inicializado; CoreBluetooth directo")
            }
        } else {
            WatchBLEManager.shared.startCentralIfNeeded()
        }
        _ = SpotifyBridge.shared''')
needle='''    func applicationDidBecomeActive(_ application: UIApplication) {
        WatchBLEManager.shared.resumeAuxiliaryWork()'''
assert s.count(needle)==1
s=s.replace(needle,'''    func applicationDidBecomeActive(_ application: UIApplication) {
        if #available(iOS 18.0, *) {
            MotoAccessorySetupCoordinator.shared.becameActive()
        }
        WatchBLEManager.shared.resumeAuxiliaryWork()''')
needle='''                Text("914: AccessorySetupKit desactivado para diagnóstico BLE")
                    .font(.caption).foregroundStyle(.secondary)'''
assert s.count(needle)==1
s=s.replace(needle,'''                MotoAccessorySetupStatusView()''')
p.write_text(s)
# 914 central stays without restoration identifier.
p=Path("ios-native/Sources/WatchBLEManager.swift");s=p.read_text()
assert "CBCentralManagerOptionRestoreIdentifierKey" not in s
s=s.replace('record("BLE-914", "CoreBluetooth convencional sin AccessorySetupKit ni restauración de estado")','record("BLE-916", "CoreBluetooth convencional 914 conservado; sin restauración de estado")')
p.write_text(s)
print("916: safe CoreBluetooth 914 default; ASK available only after manual opt-in/relaunch")
