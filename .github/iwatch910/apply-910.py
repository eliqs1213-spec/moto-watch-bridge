#!/usr/bin/env python3
"""Build 910: diagnostic only, no Spotify/widget/ASK behavior changes."""
from pathlib import Path
p=Path("ios-native/project.yml")
s=p.read_text()
assert s.count("CFBundleVersion: '906'")==2
assert s.count("CFBundleShortVersionString: '0.8.4.62'")==2
s=s.replace("CFBundleVersion: '906'","CFBundleVersion: '910'").replace("CFBundleShortVersionString: '0.8.4.62'","CFBundleShortVersionString: '0.8.4.66'")
assert "NSBluetoothAlwaysUsageDescription:" in s
assert "          - bluetooth-central" in s
p.write_text(s)
p=Path("ios-native/Sources/WatchBLEManager.swift")
s=p.read_text()
needle="    func centralManagerDidUpdateState(_ central: CBCentralManager) {"
assert s.count(needle)==1
s=s.replace(needle,needle+'''
        let authorization: String
        switch CBCentralManager.authorization {
        case .allowedAlways: authorization = "allowedAlways"
        case .denied: authorization = "denied"
        case .restricted: authorization = "restricted"
        case .notDetermined: authorization = "notDetermined"
        @unknown default: authorization = "unknown"
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let usage = info["NSBluetoothAlwaysUsageDescription"] as? String
        let modes = info["UIBackgroundModes"] as? [String] ?? []
        record("BLE-910", "CoreBluetooth state=\\(central.state.rawValue) authorization=\\(authorization) usageDescription=\\(usage == nil ? "MISSING" : "present") backgroundBluetooth=\\(modes.contains("bluetooth-central")) bundle=\\(Bundle.main.bundleIdentifier ?? "unknown")")
''')
p.write_text(s)
print("910 diagnostics: authorization and signed Info.plist checks enabled")
