#!/usr/bin/env python3
"""908: latencia de Spotify y sincronización de metadatos, sin cambiar BLE/ASK."""
from pathlib import Path
p=Path("ios-native/Sources/SpotifyBridge.swift")
s=p.read_text()
old='''        if requestBusy {
            lastAction = "Spotify ocupado · pulsación descartada (sin cola)"
            record("[SPOTIFY] Orden anterior en curso: pulsación descartada, NO encolada")
            return
        }'''
new='''        if requestBusy {
            // Conservar una sola pulsación de salto reciente. Nunca duplicar
            // Play/Pausa, que es una orden no idempotente.
            if command == .next || command == .previous {
                pendingWatchCommands.removeAll()
                enqueuePendingWatchCommand(command, receivedAt: now)
            } else {
                record("[SPOTIFY] Play/Pausa ocupado: no duplicar alternancia")
            }
            return
        }'''
assert s.count(old)==1
s=s.replace(old,new)
old='''                if self.requestBusy {
                    self.record("[SPOTIFY] Recuperación Connect ocupada: descartado sin cola")
                } else {'''
new='''                if self.requestBusy {
                    if command == .next || command == .previous {
                        self.pendingWatchCommands.removeAll()
                        self.enqueuePendingWatchCommand(command, receivedAt: receivedAt)
                    }
                } else {'''
assert s.count(old)==1
s=s.replace(old,new)
# Un comando HTTP que excede el presupuesto de la ejecución BLE no debe
# bloquear otros botones durante los 12+ segundos observados.
needle='''        request.httpMethod = method'''
assert s.count(needle)==1
s=s.replace(needle,'''        request.timeoutInterval = (method == "POST" || method == "PUT") ? 5 : 7
'''+needle)
# Reducir latencia de la primera lectura de metadatos tras NEXT/ANTERIOR.
needle='''try? await Task.sleep(nanoseconds: 850_000_000)'''
assert s.count(needle)==1
s=s.replace(needle,'''try? await Task.sleep(nanoseconds: 350_000_000)''')
# Menos bloqueo antirrebote, manteniendo protección de dobles toques.
needle='''let limit = command == .toggle ? 1.5 : 0.65'''
assert s.count(needle)==1
s=s.replace(needle,'''let limit = command == .toggle ? 0.8 : 0.35''')
p.write_text(s)
v=Path("ios-native/project.yml")
t=v.read_text()
assert t.count("CFBundleVersion: '907'")==2
assert t.count("CFBundleShortVersionString: '0.8.4.63'")==2
v.write_text(t.replace("CFBundleVersion: '907'","CFBundleVersion: '908'").replace("CFBundleShortVersionString: '0.8.4.63'","CFBundleShortVersionString: '0.8.4.64'"))
print("908: cola acotada a un salto reciente, timeout HTTP y lectura de metadatos acelerada")
