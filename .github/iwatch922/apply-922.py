#!/usr/bin/env python3
"""922: automatically restore a previously authorized ASK accessory at launch."""
from pathlib import Path
p=Path("ios-native/project.yml"); s=p.read_text()
assert s.count("CFBundleVersion: '920'")==2
s=s.replace("CFBundleVersion: '920'","CFBundleVersion: '922'").replace("CFBundleShortVersionString: '0.8.4.74'","CFBundleShortVersionString: '0.8.4.75'")
p.write_text(s)
p=Path("ios-native/Sources/MotoWatchBridgeApp.swift"); s=p.read_text()
old='''            if defaults.bool(forKey: "motowatch.ask.manual-request.904") {
                MotoAccessorySetupCoordinator.shared.start()
            } else {
                WatchBLEManager.shared.startCentralIfNeeded()
                WatchBLEManager.shared.record("BLE-916", "Inicio seguro 914: ASK no inicializado; CoreBluetooth directo")
            }'''
new='''            let pendingMigration = defaults.bool(forKey: "motowatch.ask.manual-request.904")
            let previouslyAuthorized = defaults.bool(forKey: "motowatch.ask.authorized.904")
            if pendingMigration || previouslyAuthorized {
                // ASK must activate before a global CBCentralManager is created.
                // No picker on automatic restore: coordinator only presents for manual request.
                MotoAccessorySetupCoordinator.shared.start()
                WatchBLEManager.shared.record("ASK-922",
                    previouslyAuthorized && !pendingMigration
                    ? "Restauración automática de accesorio previamente autorizado"
                    : "Migración manual pendiente; selector reservado")
            } else {
                WatchBLEManager.shared.startCentralIfNeeded()
                WatchBLEManager.shared.record("BLE-916", "Inicio seguro 914: ASK no inicializado; CoreBluetooth directo")
            }'''
assert s.count(old)==1
s=s.replace(old,new)
p.write_text(s)
p=Path("ios-native/Sources/MotoAccessorySetupCoordinator.swift"); s=p.read_text()
old='''        log("Sesión AccessorySetupKit creada tras solicitud manual (no al iniciar normalmente)")'''
new='''        log(requested
            ? "Sesión AccessorySetupKit creada para migración solicitada"
            : "Sesión AccessorySetupKit restaurada automáticamente por autorización previa")'''
assert s.count(old)==1
s=s.replace(old,new)
p.write_text(s)
print("922: auto-restore authorized ASK before BLE; preserve manual picker and crash fallback")
