import SwiftUI
import UIKit

final class MotoAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Instanciar CoreBluetooth temprano es esencial para la restauración de estado.
        _ = WatchBLEManager.shared
        _ = SpotifyBridge.shared
        _ = PhoneFinder.shared
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        WatchBLEManager.shared.record("SISTEMA", "iPhone: aplicación en segundo plano")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        WatchBLEManager.shared.record("SISTEMA", "iPhone: aplicación vuelve al primer plano")
    }
}

@main
struct MotoWatchBridgeApp: App {
    @UIApplicationDelegateAdaptor(MotoAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(WatchBLEManager.shared)
                .environmentObject(SpotifyBridge.shared)
                .environmentObject(PhoneFinder.shared)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var watch: WatchBLEManager
    @EnvironmentObject private var spotify: SpotifyBridge
    @EnvironmentObject private var finder: PhoneFinder
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PROTOTIPO NATIVO · ETAPA 5")
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
                            Text(BatteryWidgetStore.isAvailable
                                 ? "WidgetKit: almacenamiento compartido disponible"
                                 : "WidgetKit: sin App Group; podría necesitar otra firma")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Batería: exclusivamente protocolo Motorola 10/01. Solo se muestran respuestas con trama y checksum válidos.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
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
                            statusRow("Última canción", spotify.lastSong)
                            statusRow("Última orden", spotify.lastAction)
                            statusRow("Pantalla del reloj", watch.musicSyncStatus)
                            HStack {
                                Button("Consultar Spotify") {
                                    Task { await spotify.refreshPlaybackInfo() }
                                }.buttonStyle(.bordered)
                                Button("Forzar metadatos") {
                                    Task { await spotify.refreshPlaybackInfo(force: true) }
                                }.buttonStyle(.bordered)
                            }
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

                    Text("iWatch usa solo batería Motorola 10/01. Los widgets propios requieren extensión firmada y App Groups autorizados; no aparecerá en el widget Baterías oficial de Apple.")
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
                watch.refreshBattery()
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
