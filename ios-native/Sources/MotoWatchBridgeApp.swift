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
        // Única lectura Web al bloquear, solo si iOS concede ejecución.
        SpotifyLockMetadataHandoff.shared.didEnterBackground()
        MusicBackgroundExperiment.shared.didEnterBackground(source: "UIApplicationDelegate")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        WatchBLEManager.shared.record("SISTEMA", "iPhone: aplicación vuelve al primer plano")
        MusicBackgroundExperiment.shared.willEnterForeground(source: "UIApplicationDelegate")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        WatchBLEManager.shared.resumeAuxiliaryWork()
        SpotifyLockMetadataHandoff.shared.didBecomeActive()
        SpotifyAppRemoteBridge.shared.applicationDidBecomeActive()
        SpotifyBridge.shared.resetTransientWebFailureAfterResume()
        if WatchBLEManager.shared.isConnected {
            BatteryLiveActivityManager.shared.start(
                percentage: WatchBLEManager.shared.batteryPercentage
            )
        }
        Task { @MainActor in
            await SpotifyBridge.shared.verifyCurrentMetadataForWatch()
            WatchWeatherService.shared.automaticRefreshIfNeeded(reason: "aplicación activa")
        }
    }
}

@main
struct MotoWatchBridgeApp: App {
    init() {
        // Anunciar acción a Atajos sin crear automatizaciones por el usuario.
        IWatchNotificationShortcuts.updateAppShortcutParameters()
    }

    @UIApplicationDelegateAdaptor(MotoAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var appScenePhase
    @AppStorage("motowatch.appearance") private var appearanceRawValue = AppAppearance.automatic.rawValue
    @State private var selectedTab = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                WatchHomeView(isSelected: selectedTab == 0,
                              openWatch: { selectedTab = 3 },
                              openHealth: { selectedTab = 1 })
                    .tabItem { Label("Inicio", systemImage: "house.fill") }
                    .tag(0)
                HealthHistoryView()
                    .tabItem { Label("Salud", systemImage: "heart.text.square") }
                    .tag(1)
                FastingView()
                    .tabItem { Label("Ayuno", systemImage: "timer") }
                    .tag(2)
                ContentView(isSelected: selectedTab == 3)
                    .tabItem { Label("Reloj", systemImage: "watch.analog") }
                    .tag(3)
                NotificationsView()
                    .tabItem { Label("Avisos", systemImage: "bell.badge") }
                    .tag(4)
            }
                .preferredColorScheme(AppAppearance(rawValue: appearanceRawValue)?.colorScheme)
                // App con ciclo SwiftUI: algunos estados de escena NO pasan por
                // UIApplicationDelegate. Observar acá, en la raíz, incluso si
                // el usuario navega a Salud o Notificaciones.
                .onChange(of: appScenePhase) { phase in
                    switch phase {
                    case .background:
                        WatchBLEManager.shared.record("BG-LIFECYCLE", "ScenePhase raíz: background")
                        WatchBLEManager.shared.record("SPOTIFY-ORIGEN",
                            "SwiftUI background: SDK conectado=\(SpotifyAppRemoteBridge.shared.isConnected); eventos=\(SpotifyAppRemoteBridge.shared.metadataEventsActive); estadoApp=\(UIApplication.shared.applicationState.rawValue)")
                        MusicBackgroundExperiment.shared.didEnterBackground(source: "SwiftUI scenePhase")
                        WatchBLEManager.shared.flushLog()
                    case .inactive:
                        WatchBLEManager.shared.record("BG-LIFECYCLE", "ScenePhase raíz: inactive")
                    case .active:
                        WatchBLEManager.shared.record("BG-LIFECYCLE", "ScenePhase raíz: active")
                        MusicBackgroundExperiment.shared.willEnterForeground(source: "SwiftUI scenePhase")
                    @unknown default:
                        break
                    }
                }
                .onOpenURL { url in
                    SpotifyAppRemoteBridge.shared.handleOpenURL(url)
                }
                // Comprobación global y acotada a primer plano; no mantiene iOS despierto.
                .task {
                    while !Task.isCancelled {
                        await SpotifyBridge.shared.verifyCurrentMetadataForWatch()
                        await MainActor.run {
                            // Revisión ligera: sólo consulta GPS/Internet si la hora
                            // está vencida, hay permiso y el reloj está conectado.
                            WatchWeatherService.shared.automaticRefreshIfNeeded(reason: "control periódico")
                        }
                        do { try await Task.sleep(nanoseconds: 7_000_000_000) }
                        catch { break }
                    }
                }
                .environmentObject(WatchBLEManager.shared)
                .environmentObject(SpotifyBridge.shared)
                .environmentObject(PhoneFinder.shared)
        }
    }
}

struct ContentView: View {
    var isSelected = true
    @EnvironmentObject private var watch: WatchBLEManager
    @EnvironmentObject private var spotify: SpotifyBridge
    @StateObject private var spotifyRemote = SpotifyAppRemoteBridge.shared
    @StateObject private var musicAutoSync = MusicSyncEngine.shared
    @EnvironmentObject private var finder: PhoneFinder
    @StateObject private var batteryLive = BatteryLiveActivityManager.shared
    @StateObject private var backgroundExperiment = MusicBackgroundExperiment.shared
    @StateObject private var connectionAlerts = WatchConnectionAlerts.shared
    @Environment(\.scenePhase) private var scenePhase

    private var stageVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.2.5"
        return version.hasPrefix("0.") ? String(version.dropFirst(2)) : version
    }

    @State private var showSettings = false
    @AppStorage("motowatch.appearance") private var appearanceRawValue = AppAppearance.automatic.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    connectionCard
                    batteryCard
                    musicCard
                    finderCard
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
                    musicAutoSync.requestForegroundRecovery()
                    if spotifyRemote.isConnected {
                        spotifyRemote.requestCurrentPlayerState(fallbackToWeb: true)
                    } else {
                        Task { await spotify.refreshPlaybackInfo() }
                    }
                }
            }
        }

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
    // Configuración de uso diario. Las herramientas experimentales siguen en el
    // código para diagnóstico, pero no ocupan espacio en la interfaz normal.
    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsHeader
                    appearanceSettings

                    settingsSection("Reloj", subtitle: "Conexión y avisos", symbol: "applewatch")
                    GroupBox("Moto Watch Fit") {
                        VStack(alignment: .leading, spacing: 12) {
                            statusRow("Conexión", watch.connectionStatus)
                            Toggle("Avisos de conexión y batería", isOn: $connectionAlerts.enabled)
                                .tint(.green)
                            if !watch.isConnected {
                                Button("Conectar reloj") { watch.connectToWatch() }
                                    .buttonStyle(.borderedProminent)
                            }
                            Button("Desconectar reloj") { watch.disconnect() }
                                .buttonStyle(.bordered)
                                .disabled(!watch.isConnected)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    settingsSection("Spotify", subtitle: "Autorización, SDK y sincronización", symbol: "music.note")
                    GroupBox("Spotify Premium") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Redirect URI para Spotify Developer Dashboard")
                                .font(.caption).foregroundStyle(.secondary)
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
                            statusRow("Spotify", spotify.status)
                            statusRow("Reproductor", spotify.playbackAvailability)
                            Toggle("Controles desde el reloj", isOn: Binding(
                                get: { spotify.controlEnabled },
                                set: { spotify.setEnabled($0) }
                            )).tint(.green)
                            Divider()
                            Text("Conexión SDK").font(.headline)
                            HStack {
                                Button("Activar SDK Spotify") {
                                    spotifyRemote.authorize(clientID: spotify.clientID.trimmingCharacters(in: .whitespacesAndNewlines))
                                }.buttonStyle(.bordered)
                                Button("Desactivar SDK") { spotifyRemote.disable() }
                                    .buttonStyle(.bordered)
                                Button("Reintentar SDK") { spotifyRemote.retryConnection() }
                                    .buttonStyle(.bordered)
                                    .disabled(!spotifyRemote.enabled)
                            }
                            statusRow("Spotify SDK", spotifyRemote.status)
                            statusRow("SDK conectado", spotifyRemote.isConnected ? "Sí" : "No")
                            statusRow("Eventos SDK", spotifyRemote.metadataEventsActive ? "Activos" : "Inactivos")
                            statusRow("Fuente de metadatos", spotify.metadataSource)
                            statusRow("Última canción", spotify.lastSong)
                            Divider()
                            Text("Sincronización").font(.headline)
                            statusRow("Auto Sync", musicAutoSync.status)
                            statusRow("Pantalla del reloj", watch.musicSyncStatus)
                            Button {
                                spotify.resyncWatchMusicManually()
                            } label: {
                                Label("Resincronizar reproductor", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!watch.isConnected || !spotify.controlEnabled)
                            Button("Consultar Spotify") {
                                Task { await spotify.refreshPlaybackInfo() }
                            }.buttonStyle(.bordered)
                            Text("El SDK y la Web API se complementan. Con el iPhone bloqueado, iOS puede limitar la actualización automática.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    settingsSection("Diagnóstico", subtitle: "Solo cuando necesitemos revisar un problema", symbol: "waveform.path.ecg")
                    GroupBox("Registro de actividad") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("La conexión, el clima, la batería y la sincronización funcionan automáticamente. Si surge un problema, podés compartir el registro.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Copiar registro") {
                                    UIPasteboard.general.string = watch.report
                                }.buttonStyle(.borderedProminent)
                                Button("Limpiar registro") { watch.clearLog() }
                                    .buttonStyle(.bordered)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(20).groupBoxStyle(WatchSettingsGroupStyle())
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Configuración")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { showSettings = false }
                }
            }
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(
                    LinearGradient(colors: [.indigo, .blue],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Configuración").font(.title2.bold())
                Text("Solo los ajustes que necesitás.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 6)
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.title3).foregroundStyle(.indigo)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apariencia").font(.headline)
                    Text("Se aplica a Salud, iWatch y Notificaciones.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Picker("Apariencia de la aplicación", selection: $appearanceRawValue) {
                ForEach(AppAppearance.allCases) { appearance in
                    Label(appearance.title, systemImage: appearance.symbol).tag(appearance.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Apariencia de toda iWatch")
            HStack(spacing: 8) {
                Image(systemName: AppAppearance(rawValue: appearanceRawValue)?.symbol ?? "circle.lefthalf.filled")
                    .foregroundStyle(.indigo)
                Text(AppAppearance(rawValue: appearanceRawValue)?.explanation ??
                     AppAppearance.automatic.explanation)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18).watchCard()
    }

    private func settingsSection(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.indigo)
                .font(.headline)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.top, 12).padding(.horizontal, 2)
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
        VStack(alignment: .leading, spacing: 14) {
            configuration.label
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            configuration.content
        }
        .padding(18).watchCard()
    }
}
