#!/usr/bin/env python3
"""iWatch 903: resolver bloqueo ASAccessorySession.init en iOS 27.2 beta."""
from pathlib import Path

path = Path("ios-native/project.yml")
text = path.read_text(encoding="utf-8")
before = "        NSAccessorySetupKitSupports:\n          - Bluetooth"
after = ("        NSAccessorySetupSupports:\n          - Bluetooth\n"
         "        NSAccessorySetupKitSupports:\n          - Bluetooth")
assert text.count(before) == 1, "Falta la clave de AccessorySetupKit"
text = text.replace(before, after)
assert text.count("CFBundleVersion: '902'") == 2
assert text.count("CFBundleShortVersionString: '0.8.4.58'") == 2
text = text.replace("CFBundleVersion: '902'", "CFBundleVersion: '903'")
text = text.replace("CFBundleShortVersionString: '0.8.4.58'", "CFBundleShortVersionString: '0.8.4.59'")
path.write_text(text, encoding="utf-8")

bridge = Path("ios-native/Sources/MotoAccessorySetupCoordinator.swift").read_text(encoding="utf-8")
assert 'info["NSAccessorySetupSupports"]' in bridge
assert 'info["NSAccessorySetupKitSupports"]' in bridge
assert "let accessory = ASAccessorySession()" in bridge
assert "private var session: ASAccessorySession?" in bridge
print("903: dos nombres de clave ASK, comprobación previa y corrección musical conservada")