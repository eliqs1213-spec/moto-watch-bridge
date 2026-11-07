#!/usr/bin/env python3
"""Build 914: conventional CoreBluetooth-only startup, no ASK or state restoration."""
from pathlib import Path
p=Path("ios-native/project.yml")
s=p.read_text()
assert s.count("CFBundleVersion: '912'")==2
assert s.count("CFBundleShortVersionString: '0.8.4.68'")==2
s=s.replace("CFBundleVersion: '912'","CFBundleVersion: '914'").replace("CFBundleShortVersionString: '0.8.4.68'","CFBundleShortVersionString: '0.8.4.70'")
# Isolate AccessorySetupKit registration on the main target, preserve widget and Live Activities.
lines=s.splitlines(keepends=True)
out=[]
skip=False
for line in lines:
    if line.startswith("        NSAccessorySetupSupports:") or line.startswith("        NSAccessorySetupKitSupports:") or line.startswith("        NSAccessorySetupBluetoothNames:") or line.startswith("        NSAccessorySetupBluetoothServices:"):
        skip=True
        continue
    if skip and line.startswith("          - "):
        continue
    skip=False
    out.append(line)
s="".join(out)
assert "NSBluetoothAlwaysUsageDescription:" in s
p.write_text(s)
p=Path("ios-native/Sources/MotoWatchBridgeApp.swift")
s=p.read_text()
old='''        if #available(iOS 18.0, *) {
            MotoAccessorySetupCoordinator.shared.start()
        } else {
            WatchBLEManager.shared.startCentralIfNeeded()
        }'''
assert s.count(old)==1
s=s.replace(old,'''        // 914 A/B: do not create or activate AccessorySetupKit at launch.
        WatchBLEManager.shared.startCentralIfNeeded()''')
# Avoid the manual migration button in the isolated test.
old='''                MotoAccessorySetupStatusView()'''
assert s.count(old)==1
s=s.replace(old,'''                Text("914: AccessorySetupKit desactivado para diagnóstico BLE")
                    .font(.caption).foregroundStyle(.secondary)''')
p.write_text(s)
p=Path("ios-native/Sources/WatchBLEManager.swift")
s=p.read_text()
old='''            options: [CBCentralManagerOptionRestoreIdentifierKey: "org.motowatchbridge.native.ble.central"]'''
assert s.count(old)==1
s=s.replace(old,'''            options: [CBCentralManagerOptionShowPowerAlertKey: true]''')
s=s.replace('record("BLE", "CoreBluetooth iniciado después de AccessorySetupKit")','record("BLE-914", "CoreBluetooth convencional sin AccessorySetupKit ni restauración de estado")')
# 912 extra central is not needed; remove its invocation to keep this test one central only.
old='''        probeBluetoothAuthorizationIfNeeded()'''
assert s.count(old)==1
s=s.replace(old,'''        record("BLE-914", "Solicitud de autorización mediante central principal sin restore identifier")''')
p.write_text(s)
print("914: conventional CoreBluetooth only; ASK not started or advertised; restoration disabled")
