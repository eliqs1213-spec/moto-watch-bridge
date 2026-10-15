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
        WatchBLEManager.shared.pauseAuxiliaryWork()
        SpotifyAppRemoteBridge.shared.applicationDidEnterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        WatchBLEManager.shared.record("SISTEMA", "iPhone: aplicación vuelve al primer plano")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        WatchBLEManager.shared.resumeAuxiliaryWork()
        SpotifyAppRemoteBridge.shared.applicationDidBecomeActive()
    }
}

@main
struct MotoWatchBridgeApp: App {
    @UIApplicationDelegateAdaptor(MotoAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            TabView {
                HealthHistoryView()
                    .tabItem { Label("Salud", systemImage: "heart.text.square") }
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

    private var stageVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.2.5"
        return version.hasPrefix("0.") ? String(version.dropFirst(2)) : version
    }

    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    watchHero
                    connectionCard
                    batteryCard
                    musicCard
                    finderCard
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge.fill").foregroundStyle(.pink)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tus avisos, primero").font(.subheadline.bold())
                            Text(watch.notificationStatus).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(16).background(Color.pink.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                    Button { showSettings = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3").foregroundStyle(.indigo)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ajustes y diagnóstico").font(.headline)
                                Text("Spotify, avisos, pantalla de bloqueo y registro").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                        }.padding(18).watchCard()
                    }.buttonStyle(.plain)
                    Text("iWatch · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("iWatch").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Ajustes de iWatch")
            }
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                finder.updateAuthorizationStatus()
                connectionAlerts.refreshPermissionStatus()
                watch.autoConnectIfNeeded()
                watch.refreshBattery(force: false)
                spotifyRemote.applicationDidBecomeActive()
                if spotify.controlEnabled {
                    if spotifyRemote.isConnected {
                        spotifyRemote.requestCurrentPlayerState(fallbackToWeb: true)
                    } else {
                        Task { await spotify.refreshPlaybackInfo() }
                    }
                }
            }
        }
        .task {
            // No afirmar que hay encuesta continua con el iPhone bloqueado.
            while !Task.isCancelled {
                if UIApplication.shared.applicationState == .active && spotify.controlEnabled {
                    if spotifyRemote.isConnected {
                        // Recupera cambios aun cuando la suscripción del SDK no emita el evento.
                        spotifyRemote.requestCurrentPlayerState(fallbackToWeb: true)
                    } else if watch.isConnected {
                        await spotify.refreshPlaybackInfo()
                    }
                }
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
        }
    }

    private var watchHero: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tu reloj,\na tu ritmo").font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                Text("Todo conectado, en un solo lugar.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 30).fill(Color.cyan.opacity(0.12)).frame(width: 94, height: 112)
                Image(systemName: "watch.analog").font(.system(size: 70, weight: .light)).foregroundStyle(.cyan)
            }.accessibilityHidden(true)
        }.padding(.vertical, 8)
    }
    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeading("Tu Moto Watch", symbol: "antenna.radiowaves.left.and.right", color: .cyan)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(watch.watchName).font(.title3.bold())
                    Text(watch.connectionStatus).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Label(watch.isConnected ? "Conectado" : "Sin conexión", systemImage: watch.isConnected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.caption.bold()).foregroundStyle(watch.isConnected ? Color.green : Color.secondary)
            }
            if !watch.isConnected {
                Button { watch.connectToWatch() } label: { Label("Conectar reloj", systemImage: "link").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.cyan)
            }
            Toggle("Reconexión automática", isOn: Binding(get: { watch.autoReconnectEnabled }, set: { watch.setAutoReconnect($0) }))
                .font(.subheadline).tint(.cyan)
        }.padding(18).watchCard()
    }
    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeading("Energía para tu día", symbol: "battery.75percent", color: .green)
            HStack(spacing: 22) {
                ZStack {
                    Circle().stroke(Color.green.opacity(0.12), lineWidth: 9)
                    if let percentage = watch.batteryPercentage, watch.isConnected {
                        Circle().trim(from: 0, to: CGFloat(min(max(percentage, 0), 100)) / 100)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    Text(watch.isConnected ? watch.batteryPercentage.map { "\($0)%" } ?? "—" : "—")
                        .font(.title2.bold()).monospacedDigit()
                }.frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Batería del reloj").font(.headline)
                    Text(watch.batteryStatus).font(.caption).foregroundStyle(.secondary)
                    Button("Consultar batería") { watch.refreshBattery() }
                        .font(.caption.bold()).buttonStyle(.bordered).tint(.green).disabled(!watch.isConnected)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(18).watchCard()
    }
    private var musicCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeading("Tu música", symbol: "music.note", color: .green)
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "music.note.list").font(.system(size: 30))
                    .foregroundStyle(.green).frame(width: 64, height: 72)
                    .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(spotify.lastSong).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(spotify.playbackAvailability).font(.caption).foregroundStyle(.secondary)
                    Text(spotifyRemote.isConnected ? "Conectado con Spotify" : spotify.status)
                        .font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("Controles desde el reloj", isOn: Binding(get: { spotify.controlEnabled }, set: { spotify.setEnabled($0) }))
                .font(.subheadline).tint(.green)
            HStack {
                Button { spotify.forceWatchMusicRecovery() } label: { Label("Actualizar canción", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).tint(.green)
                Spacer(minLength: 0)
                Button("Configurar") { showSettings = true }.font(.subheadline)
            }
            Text("Siguiente, anterior y reproducir/pausar desde tu Moto Watch.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).watchCard()
    }
    private var finderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeading("Siempre a mano", symbol: "iphone.radiowaves.left.and.right", color: .indigo)
            Text("Encontrá tu iPhone").font(.title3.bold())
            Text(finder.status).font(.caption).foregroundStyle(.secondary)
            Text("Hacelo sonar desde la función de búsqueda del reloj.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button { finder.test() } label: { Label("Probar sonido", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(.borderedProminent).tint(.indigo)
                Button("Detener") { finder.stop() }.buttonStyle(.bordered).tint(.indigo)
            }
        }.padding(18).watchCard()
    }
    private func cardHeading(_ title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol).font(.subheadline.bold()).foregroundStyle(color)
    }
    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
                            statusRow("Fuente de metadatos", spotify.metadataSource)
                            statusRow("Última orden", spotify.lastAction)
                            statusRow("Pantalla del reloj", watch.musicSyncStatus)
                            Divider()
                            Text("Spotify iOS SDK · App Remote (prioritario)")
                                .font(.headline)
                            Text("SDK prioritario para controles y metadatos (título, artista, álbum, duración y reproducción). La Web API respalda los dos cuando el SDK no está conectado o falla la lectura nativa. Con el iPhone bloqueado, iWatch usa los eventos y tiempos de ejecución que iOS permita. Sin Atajos para Spotify.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Activar SDK Spotify") {
                                    spotifyRemote.authorize(clientID: spotify.clientID.trimmingCharacters(in: .whitespacesAndNewlines))
                                }.buttonStyle(.bordered)
                                Button("Desactivar SDK") { spotifyRemote.disable() }
                                    .buttonStyle(.bordered)
                            }
                            statusRow("Spotify SDK", spotifyRemote.status)
                            statusRow("SDK conectado", spotifyRemote.isConnected ? "Sí" : "No")
                            statusRow("Eventos del SDK", spotifyRemote.metadataEventsActive ? "Suscripto" : "Sin suscripción")
                            statusRow("Último dato nativo", spotifyRemote.lastNativeEvent)
                            Text("Si aparece Web API con iWatch abierta, mirá estas tres líneas. SDK conectado: No indica un problema de sesión, no del reloj. Para autorizar, tocá Activar SDK Spotify una vez con Spotify instalado.")
                                .font(.caption).foregroundStyle(.secondary)
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
                }.padding(20).groupBoxStyle(WatchSettingsGroupStyle())
            }.background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Ajustes y diagnóstico").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { showSettings = false } } }
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

private extension View {
    func watchCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.04)))
    }
}
private struct WatchSettingsGroupStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            configuration.label.font(.headline).foregroundStyle(.indigo)
            configuration.content
        }.padding(18).watchCard()
    }
}
