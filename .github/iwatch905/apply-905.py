#!/usr/bin/env python3
"""Build 905: aislar ASAccessorySession de la app sin tocar las funciones estables."""
from pathlib import Path
project = Path("ios-native/project.yml")
p = project.read_text(encoding="utf-8")
assert p.count("CFBundleVersion: '904'") == 2
assert p.count("CFBundleShortVersionString: '0.8.4.60'") == 2
p = p.replace("CFBundleVersion: '904'", "CFBundleVersion: '905'")
p = p.replace("CFBundleShortVersionString: '0.8.4.60'", "CFBundleShortVersionString: '0.8.4.61'")
project.write_text(p, encoding="utf-8")
coordinator = Path("ios-native/Sources/MotoAccessorySetupCoordinator.swift")
old = coordinator.read_text(encoding="utf-8")
assert "let accessory = ASAccessorySession()" in old
assert "func prepareManualAuthorization()" in old
coordinator.write_text("import Foundation\nimport Combine\nimport SwiftUI\n\n// 905: iOS 27.2 beta produjo SIGTRAP en ASAccessorySession.init() en 904.\n// No se crea ninguna sesion de AccessorySetupKit mientras se investiga.\n@available(iOS 18.0, *)\nfinal class MotoAccessorySetupCoordinator: ObservableObject {\n    static let shared = MotoAccessorySetupCoordinator()\n    @Published private(set) var isAuthorized = false\n    @Published private(set) var status = \"Bluetooth convencional activo · AccessorySetupKit en pausa\"\n    @Published private(set) var needsManualRestart = false\n    private var started = false\n    private init() {}\n\n    func start() {\n        guard !started else { return }\n        started = true\n        for key in [\n            \"motowatch.ask.manual-request.904\",\n            \"motowatch.ask.authorized.904\",\n            \"motowatch.ask.session.init.inflight.904\"\n        ] {\n            UserDefaults.standard.removeObject(forKey: key)\n        }\n        let ble = WatchBLEManager.shared\n        ble.startCentralIfNeeded()\n        ble.autoConnectIfNeeded()\n        ble.record(\"ACCESSORY-SETUP\", \"905: AccessorySetupKit en pausa tras SIGTRAP; CoreBluetooth activo\")\n    }\n\n    func becameActive() {}\n}\n\n@available(iOS 18.0, *)\nstruct MotoAccessorySetupStatusView: View {\n    @ObservedObject private var coordinator = MotoAccessorySetupCoordinator.shared\n    var body: some View {\n        VStack(alignment: .leading, spacing: 8) {\n            Label(coordinator.status, systemImage: \"checkmark.shield\")\n                .font(.caption)\n                .foregroundStyle(.secondary)\n            Text(\"La vinculación experimental está en pausa por un cierre confirmado. El Moto Watch Fit sigue utilizando Bluetooth convencional.\")\n                .font(.caption)\n                .foregroundStyle(.secondary)\n        }\n    }\n}\n", encoding="utf-8")
new = coordinator.read_text(encoding="utf-8")
assert "ASAccessorySession(" not in new
assert "ble.startCentralIfNeeded()" in new
assert "ble.autoConnectIfNeeded()" in new
assert "func becameActive() {}" in new
assert "Button(" not in new
assert "NSAccessorySetup" in p
ble = Path("ios-native/Sources/WatchBLEManager.swift").read_text(encoding="utf-8")
assert "MotoAccessorySetupCoordinator.shared.becameActive()" in ble
app = Path("ios-native/Sources/MotoWatchBridgeApp.swift").read_text(encoding="utf-8")
assert "BatteryLiveActivityManager.shared.start(" in app
assert "MotoAccessorySetupCoordinator.shared.start()" in app
print("905: inicio CoreBluetooth seguro; AccessorySetupKit no se instancia")
