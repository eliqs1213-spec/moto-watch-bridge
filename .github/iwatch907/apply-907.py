#!/usr/bin/env python3
"""iWatch 907: corrección de ActivityAuthorizationError.visibility sin afectar AccessorySetupKit."""
from pathlib import Path
project = Path("ios-native/project.yml")
p = project.read_text(encoding="utf-8")
assert p.count("CFBundleVersion: '906'") == 2
assert p.count("CFBundleShortVersionString: '0.8.4.62'") == 2
p = p.replace("CFBundleVersion: '906'", "CFBundleVersion: '907'")
p = p.replace("CFBundleShortVersionString: '0.8.4.62'", "CFBundleShortVersionString: '0.8.4.63'")
project.write_text(p, encoding="utf-8")
manager = Path("ios-native/Sources/BatteryLiveActivityManager.swift")
old = manager.read_text(encoding="utf-8")
assert "Activity<MotoBatteryActivityAttributes>.request(" in old
assert 'status = "Error al iniciar Actividad en vivo: " + error.localizedDescription' in old
manager.write_text("import Foundation\nimport Combine\nimport ActivityKit\nimport WidgetKit\nimport UIKit\n\n// Activity.request exige que iWatch este en primer plano. Las lecturas BLE\n// tambien llegan con el iPhone bloqueado: en ese caso actualizar una\n// actividad existente, nunca intentar crear una nueva.\nfinal class BatteryLiveActivityManager: ObservableObject {\n    static let shared = BatteryLiveActivityManager()\n    @Published private(set) var status = \"Se activará automáticamente al conectar el reloj\"\n\n    private init() {}\n\n    func start(percentage: Int?) {\n        WidgetCenter.shared.reloadTimelines(ofKind: \"iWatchDiagnosticStage7\")\n        Task { @MainActor in\n            await self.prepareActivity(percentage: percentage, recreate: false)\n        }\n    }\n\n    func restart(percentage: Int?) {\n        Task { @MainActor in\n            await self.prepareActivity(percentage: percentage, recreate: true)\n        }\n    }\n\n    @MainActor\n    private func prepareActivity(percentage: Int?, recreate: Bool) async {\n        guard ActivityAuthorizationInfo().areActivitiesEnabled else {\n            status = \"Actividades en vivo desactivadas en los ajustes de iOS\"\n            return\n        }\n\n        let content = ActivityContent(\n            state: MotoBatteryActivityAttributes.ContentState(\n                percentage: percentage ?? -1,\n                updatedAt: Date().timeIntervalSince1970\n            ),\n            staleDate: Date().addingTimeInterval(60 * 45)\n        )\n\n        // ActivityKit permite actualizar mientras iWatch esta en segundo plano.\n        if !recreate, let existing = Activity<MotoBatteryActivityAttributes>.activities.first {\n            await existing.update(content)\n            status = percentage.map { \"Actividad en vivo activa · batería \\($0)%\" }\n                ?? \"Actividad en vivo activa · esperando batería\"\n            return\n        }\n\n        // La conexion BLE suele producirse cuando iOS esta en background.\n        // Se difiere el inicio; didBecomeActive vuelve a llamar a start().\n        guard UIApplication.shared.applicationState == .active else {\n            status = \"Pendiente: abrí iWatch para iniciar la Actividad en vivo\"\n            return\n        }\n\n        if recreate {\n            status = \"Finalizando actividad anterior para nueva prueba…\"\n            for item in Activity<MotoBatteryActivityAttributes>.activities {\n                await item.end(nil, dismissalPolicy: .immediate)\n            }\n        }\n\n        // Revalidar despues de cualquier await: la app pudo pasar a background.\n        guard UIApplication.shared.applicationState == .active else {\n            status = \"Pendiente: abrí iWatch para iniciar la Actividad en vivo\"\n            return\n        }\n        do {\n            _ = try Activity<MotoBatteryActivityAttributes>.request(\n                attributes: MotoBatteryActivityAttributes(watchName: \"Moto Watch Fit\"),\n                content: content,\n                pushType: nil\n            )\n            status = percentage.map {\n                \"Actividad en vivo iniciada automáticamente · batería \\($0)%\"\n            } ?? \"Actividad en vivo iniciada automáticamente · esperando batería\"\n        } catch let error as ActivityAuthorizationError {\n            switch error {\n            case .visibility:\n                status = \"Pendiente: iOS requiere iWatch en primer plano\"\n            default:\n                status = \"Error de autorización de Actividad en vivo: \\(error.localizedDescription)\"\n            }\n        } catch {\n            status = \"Error al iniciar Actividad en vivo: \" + error.localizedDescription\n        }\n    }\n\n    func updateBattery(_ percentage: Int) {\n        WidgetCenter.shared.reloadTimelines(ofKind: \"iWatchDiagnosticStage7\")\n        Task { @MainActor in\n            await self.prepareActivity(percentage: percentage, recreate: false)\n        }\n    }\n\n    func stop() {\n        Task { @MainActor in\n            for item in Activity<MotoBatteryActivityAttributes>.activities {\n                await item.end(nil, dismissalPolicy: .immediate)\n            }\n            self.status = \"Actividad en vivo detenida\"\n        }\n    }\n}\n", encoding="utf-8")
new = manager.read_text(encoding="utf-8")
assert new.count("UIApplication.shared.applicationState == .active") == 2
assert new.index("guard UIApplication.shared.applicationState == .active") < new.index("Activity<MotoBatteryActivityAttributes>.request(")
assert "if !recreate, let existing" in new and "await existing.update(content)" in new
assert "case .visibility:" in new
assert "Pendiente: abrí iWatch para iniciar" in new
assert "WidgetCenter.shared.reloadTimelines" in new
app = Path("ios-native/Sources/MotoWatchBridgeApp.swift").read_text(encoding="utf-8")
assert 'func applicationDidBecomeActive(_ application: UIApplication)' in app
assert 'BatteryLiveActivityManager.shared.start(' in app
coordinator = Path("ios-native/Sources/MotoAccessorySetupCoordinator.swift").read_text(encoding="utf-8")
assert "installationDiagnostics" in coordinator
assert "ASAccessorySession()" in coordinator
print("907: ActivityKit no inicia desde background; se actualiza lo existente y se reintenta cuando iWatch está activa.")


# Diagnostico Spotify: acotar el problema al token, transporte HTTP o tiempo iOS.
# La 906 recibe BLE aun bloqueado, pero /me/player/next acaba en timeout.
spotify = Path("ios-native/Sources/SpotifyBridge.swift")
s = spotify.read_text(encoding="utf-8")
old_token = "        let token = try await validAccessToken()\n        guard let url = URL(string: \"https://api.spotify.com/v1\\(path)\") else { throw SpotifyBridgeError.badURL }"
# Este reemplazo usa cadenas Swift literalmente, sin interpolarlas en Python.
old_token = '''        let token = try await validAccessToken()
        guard let url = URL(string: "https://api.spotify.com/v1\(path)") else { throw SpotifyBridgeError.badURL }'''
assert s.count(old_token) == 1, "SpotifyBridge.api() cambió inesperadamente"
new_token = '''        let diagnosticsStarted = Date()
        let isPlaybackCommand = method == "POST" || method == "PUT"
        if isPlaybackCommand {
            let appState = UIApplication.shared.applicationState.rawValue
            let remaining = UIApplication.shared.applicationState == .background
                ? Int(UIApplication.shared.backgroundTimeRemaining) : -1
            record("SPOTIFY-WEB-DIAG: inicio \(method) \(path), app=\(appState), iOS restante=\(remaining)s")
        }
        let token: String
        do {
            token = try await validAccessToken()
        } catch {
            if isPlaybackCommand {
                record("SPOTIFY-WEB-DIAG: token falló tras \(Int(Date().timeIntervalSince(diagnosticsStarted) * 1000))ms: \(error.localizedDescription)")
            }
            throw error
        }
        guard let url = URL(string: "https://api.spotify.com/v1\(path)") else { throw SpotifyBridgeError.badURL }'''
s = s.replace(old_token, new_token)
old_request = '''        var (data, response) = try await URLSession.shared.data(for: request)
        var statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0'''
assert s.count(old_request) == 1, "SpotifyBridge.api() transporte no esperado"
new_request = '''        var data: Data
        var response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if isPlaybackCommand {
                let duration = Int(Date().timeIntervalSince(diagnosticsStarted) * 1000)
                record("SPOTIFY-WEB-DIAG: HTTP sin respuesta \(method) \(path) tras \(duration)ms, app=\(UIApplication.shared.applicationState.rawValue), error=\(error.localizedDescription)")
            }
            throw error
        }
        var statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if isPlaybackCommand {
            record("SPOTIFY-WEB-DIAG: HTTP \(statusCode) \(method) \(path) en \(Int(Date().timeIntervalSince(diagnosticsStarted) * 1000))ms")
        }'''
s = s.replace(old_request, new_request)
assert 'SPOTIFY-WEB-DIAG: HTTP sin respuesta' in s
assert 'func receive(_ command: WatchCommand)' in s
spotify.write_text(s, encoding="utf-8")

# Permite probar la Web API DELANTE del usuario, aun si Spotify SDK funciona;
# distingue una falla de red/API de un límite de ejecución en segundo plano.
appFile = Path("ios-native/Sources/MotoWatchBridgeApp.swift")
a = appFile.read_text(encoding="utf-8")
old_button = '''                            Button("Consultar Spotify (diagnóstico)") {
                                Task { await spotify.refreshPlaybackInfo() }
                            }.buttonStyle(.bordered)'''
new_button = '''                            Button("Probar Spotify Web API (sin SDK)") {
                                Task { await spotify.refreshPlaybackInfo(force: true) }
                            }.buttonStyle(.bordered)
                            Text("GET real con iWatch en primer plano, aunque el SDK esté conectado. Revisá Reproductor y el registro para contrastar con los timeouts de pantalla bloqueada.")
                                .font(.caption).foregroundStyle(.secondary)'''
assert a.count(old_button) == 1, "No se encontró botón de diagnóstico Web"
appFile.write_text(a.replace(old_button,new_button),encoding="utf-8")
print("907: Spotify instrumentado sin reenviar comandos ni mantener procesos artificialmente en segundo plano")
