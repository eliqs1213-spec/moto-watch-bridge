import SwiftUI
import UIKit

final class MotoAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Instanciar CoreBluetooth temprano es esencial para la restauración de estado.
        _ = WatchBLEManager.shared
        _ = SpotifyBridge.shared
        _ = SpotifyAppRemoteBridge.shared
        _ = PhoneFinder.shared
        _ = WatchConnectionAlerts.shared
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        WatchBLEManager.shared.record("SISTEMA", "iPhone: aplicación en segundo plano")
        SpotifyAppRemoteBridge.shared.applicationDidEnterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        WatchBLEManager.shared.record("SISTEMA", "iPhone: aplicación vuelve al primer plano")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        SpotifyAppRemoteBridge.shared.applicationDidBecomeActive()
    }
}

@main
struct MotoWatchBridgeApp: App {
    @UIApplicationDelegateAdaptor(MotoAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("iWatch", systemImage: "watch.analog") }
                NotificationsView()
                    .tabItem { Label("Notificaciones", systemImage: "bell.badge") }
            }
                .onOpenURL { url in
                    SpotifyAppRemoteBridge.shared.handleOpenURL(url)
                }
                .environmentObject(WatchBLEManager.shared)
                .environmentObject(SpotifyBridge.shared)
                .environmentObject(PhoneFinder.shared)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var watch: WatchBLEManager
    @EnvironmentObject private var spotify: SpotifyBridge
    @StateObject private var spotifyRemote = SpotifyAppRemoteBridge.shared
    @EnvironmentObject private var finder: PhoneFinder
    @StateObject private var batteryLive = BatteryLiveActivityManager.shared
    @StateObject private var connectionAlerts = WatchConnectionAlerts.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("IWATCH · ETAPA 8.2")
                            .font(.caption.bold()).foregroundStyle(.cyan)
                        Text("Moto Watch Bridge")
                            .font(.largeTitle.bold())
                        Text("Spotify, batería y Encuentra mi teléfono. Los títulos y el estado se envían al reloj; su pantalla puede tardar en refrescarse.")
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Conexión") {
                        VStack(alignment: .leading, spacing: 10) {
                            statusRow("Bluetooth", watch.bluetoothStatus)
                            statusRow("Reloj", watch.watchName)
                            statusRow("Estado", watch.connectionStatus)
                            HStack {
                                Button("Conectar reloj") { watch.connectToWatch() }
                                    .buttonStyle(.borderedProminent)
                                Button("Desconectar") { watch.disconnect() }
                                    .buttonStyle(.bordered)
                            }
                            Toggle("Reconectar reloj automáticamente", isOn: Binding(
                                get: { watch.autoReconnectEnabled },
                                set: { watch.setAutoReconnect($0) }
                            ))
                            .tint(.green)
                            Toggle("Avisar conexión y batería", isOn: $connectionAlerts.enabled)
                                .tint(.green)
                            Text(connectionAlerts.permissionStatus)
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Permitir avisos") { connectionAlerts.requestPermission() }
                                    .buttonStyle(.bordered)
                                Button("Probar aviso") {
                                    connectionAlerts.sendTestAlert(
                                        watchName: watch.watchName,
                                        percentage: watch.isConnected ? watch.batteryPercentage : nil)
                                }
                                .buttonStyle(.bordered)
                            }
                            Text("Al conectar, iWatch consulta automáticamente la batería Motorola 10/01 y manda un solo aviso con porcentaje. Si la lectura falla, avisa sin inventar el valor; evita repeticiones durante 90 s. «Desconectar» detiene la reconexión hasta pulsar «Conectar reloj».")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Antes de conectar, cerrá el puente de Windows y desconectá Bluefy y el Motorola Edge.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Batería del reloj") {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(watch.batteryPercentage.map { "\($0)%" } ?? "—")
                                .font(.largeTitle.bold()).monospacedDigit()
                            Text(watch.batteryStatus).foregroundStyle(.secondary)
                            Button("Consultar batería") { watch.refreshBattery() }
                                .buttonStyle(.bordered)
                            Text("Etapa 7: batería Motorola 10/01 sin App Groups. Probá la actividad en vivo de abajo.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Batería: exclusivamente protocolo Motorola 10/01. Solo se muestran respuestas con trama y checksum válidos.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Pantalla de bloqueo · Widget experimental") {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Batería real por Actividad en vivo (ActivityKit), sin App Groups.")
                                .font(.subheadline)
                            HStack {
                                Button("Mostrar batería en bloqueo") {
                                    batteryLive.start(percentage: watch.batteryPercentage)
                                    watch.refreshBattery()
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Detener") { batteryLive.stop() }
                                    .buttonStyle(.bordered)
                            }
                            Text(batteryLive.status)
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Bloqueá el iPhone y buscá la actividad debajo de las notificaciones o en la Dynamic Island. Es diferente al widget fijo debajo del reloj. Las actividades en vivo caducan según iOS y las lecturas solo se actualizan cuando iWatch logra comunicarse con el reloj.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Widget circular/rectangular «iWatch · Prueba»: solo muestra iWatch OK. Sirve para comprobar si Sideloadly registró la extensión; NO muestra una batería inventada.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Spotify Premium") {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Configurá en Spotify Developer Dashboard la Redirect URI EXACTA:")
                                .font(.caption)
                            Text(SpotifyBridge.redirect)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            TextField("Spotify Client ID (no Secret)", text: $spotify.clientID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Button("Autorizar Spotify") { spotify.authorize() }
                                    .buttonStyle(.borderedProminent)
                                Button("Desvincular") { spotify.disconnectSpotify() }
                                    .buttonStyle(.bordered)
                            }
                            Toggle("Activar controles Spotify", isOn: Binding(
                                get: { spotify.controlEnabled },
                                set: { spotify.setEnabled($0) }
                            ))
                            .tint(.green)
                            statusRow("Spotify", spotify.status)
                            statusRow("Reproductor", spotify.playbackAvailability)
                            statusRow("Última canción", spotify.lastSong)
                            statusRow("Última orden", spotify.lastAction)
                            statusRow("Pantalla del reloj", watch.musicSyncStatus)
                            Divider()
                            Text("Spotify iOS SDK · App Remote (experimental)")
                                .font(.headline)
                            Text("Sincroniza cambios más rápido mientras iWatch está abierta. Al bloquear el iPhone seguimos usando la Web API; activar SDK no modifica esa conexión.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Activar SDK Spotify") {
                                    spotifyRemote.authorize(clientID: spotify.clientID.trimmingCharacters(in: .whitespacesAndNewlines))
                                }.buttonStyle(.bordered)
                                Button("Desactivar SDK") { spotifyRemote.disable() }
                                    .buttonStyle(.bordered)
                            }
                            statusRow("Spotify SDK", spotifyRemote.status)
                            HStack {
                                Button("Consultar Spotify") {
                                    Task { await spotify.refreshPlaybackInfo() }
                                }.buttonStyle(.bordered)
                                Button("Forzar metadatos") {
                                    spotify.forceWatchMusicRecovery()
                                }.buttonStyle(.bordered)
                            }
                            Button("Probar pantalla sin música") {
                                spotify.testNoMusicScreen()
                            }.buttonStyle(.bordered)
                            Text("Prueba del paquete Motorola de reposo: si el reloj no vuelve a «No se está reproduciendo música», copiá el registro. El formato todavía es experimental. Una pausa normal no lo activa.")
                                .font(.caption).foregroundStyle(.orange)
                            Text("Título + artista y estado Play/Pausa: 08 02 al cambiar canción, vacío al reproducir, 08 01 al pausar. Refresco automático solo con la app visible; cuando está bloqueada, se actualiza al recibir botones.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Encuentra mi teléfono") {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(finder.status).foregroundStyle(.secondary)
                            statusRow("Búsqueda", finder.searching ? "Solicitada por el reloj" : "Detenida")
                            HStack {
                                Button("Probar alarma") { finder.test() }
                                    .buttonStyle(.borderedProminent)
                                Button("Detener sonido") { finder.stop() }
                                    .buttonStyle(.bordered)
                            }
                            Button("Permitir aviso de respaldo (opcional)") { finder.requestPermission() }
                                .buttonStyle(.bordered)
                            Text("El reloj inicia una alarma en bucle y la detiene cuando salís de «Encuentra mi teléfono». También podés detenerla aquí. Probá primero con la app visible y después con el iPhone bloqueado; iOS puede impedir iniciar audio desde segundo plano.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Comandos detectados") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(watch.lastCommand).font(.title3.bold())
                            HStack {
                                counter("Siguiente", watch.nextCount, "forward.end.fill")
                                counter("Anterior", watch.previousCount, "backward.end.fill")
                                counter("Play/Pausa", watch.toggleCount, "playpause.fill")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Prueba con pantalla bloqueada") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Conectá el reloj y esperá «Escuchando los botones».\n2. Bloqueá el iPhone durante 60 segundos.\n3. Pulsá Siguiente, Anterior y Play/Pausa, espaciados 5 segundos.\n4. Desbloqueá y revisá el registro con las horas.")
                                .font(.subheadline)
                            Text("No cierres la app desde el selector de apps. Spotify y los metadatos en segundo plano dependen de los límites de iOS. La alarma usa notificaciones y requiere permiso.")
                                .font(.caption).foregroundStyle(.orange)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Registro persistente") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Button("Copiar registro") {
                                    UIPasteboard.general.string = watch.report
                                }.buttonStyle(.borderedProminent)
                                Button("Limpiar") { watch.clearLog() }
                                    .buttonStyle(.bordered)
                            }
                            ForEach(Array(watch.events.suffix(55).reversed())) { event in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(event.timestamp.formatted(date: .omitted, time: .standard)) · \(event.kind)")
                                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                                    Text(event.message)
                                        .font(.caption).textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Divider()
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("iWatch usa solo batería Motorola 10/01. La Actividad en vivo no usa App Groups, pero necesita que la extensión WidgetKit quede firmada y registrada. El widget fijo es diagnóstico, no muestra el porcentaje real.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Moto Watch")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                finder.updateAuthorizationStatus()
                connectionAlerts.refreshPermissionStatus()
                watch.autoConnectIfNeeded()
                watch.refreshBattery()
                spotifyRemote.applicationDidBecomeActive()
                if spotify.controlEnabled { Task { await spotify.refreshPlaybackInfo() } }
            }
        }
        .task {
            // No afirmar que hay encuesta continua con el iPhone bloqueado.
            while !Task.isCancelled {
                if UIApplication.shared.applicationState == .active && watch.isConnected && spotify.controlEnabled {
                    await spotify.refreshPlaybackInfo()
                }
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }

    private func counter(_ title: String, _ count: Int, _ symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(.cyan)
            Text("\(count)").font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption2)
        }.frame(maxWidth: .infinity)
    }
}
