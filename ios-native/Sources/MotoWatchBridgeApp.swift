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
    @State private var widgetInstallReport = WidgetExtensionDiagnostics.report()
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
    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsHeader
                    appearanceSettings
                    settingsSection("Conexión y dispositivos", subtitle: "Reloj, avisos y energía", symbol: "applewatch")
                    GroupBox("Conexión") {
                        VStack(alignment: .leading, spacing: 10) {
                            statusRow("Bluetooth", watch.bluetoothStatus)
                            statusRow("Reloj", watch.watchName)
                            statusRow("Estado", watch.connectionStatus)
                            Button("Desconectar reloj") { watch.disconnect() }
                                .buttonStyle(.bordered)
                                .disabled(!watch.isConnected)
                            Text("Para conectar o activar la reconexión automática, usá la pantalla Reloj.")
                                .font(.caption).foregroundStyle(.secondary)
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

                    settingsSection("Pantalla de bloqueo", subtitle: "Widgets y Actividades en vivo", symbol: "rectangle.on.rectangle")
                    GroupBox("Diagnóstico de extensión WidgetKit instalada") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Si el widget iWatch no aparece en la galería o la Dynamic Island queda negra, inspeccioná la extensión efectivamente instalada en el iPhone.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Comprobar extensión") {
                                    widgetInstallReport = WidgetExtensionDiagnostics.report()
                                    watch.record("WIDGET-DIAG", "Inspección local del bundle instalada; revisar informe copiado para los detalles")
                                }.buttonStyle(.borderedProminent)
                                Button("Copiar diagnóstico") {
                                    UIPasteboard.general.string = widgetInstallReport
                                }.buttonStyle(.bordered)
                            }
                            Text(widgetInstallReport)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                            Text("La presencia de MotoBatteryWidgets.appex y un ID coherente NO certifica que iOS haya registrado la extensión ni que Sideloadly la haya firmado correctamente. La app no puede consultar el catálogo interno de WidgetKit.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                                Button("Reiniciar prueba") {
                                    batteryLive.restart(percentage: watch.batteryPercentage)
                                    widgetInstallReport = WidgetExtensionDiagnostics.report()
                                }.buttonStyle(.bordered)
                                Button("Detener") { batteryLive.stop() }
                                    .buttonStyle(.bordered)
                            }
                            Text(batteryLive.status)
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Bloqueá el iPhone y buscá la actividad debajo de las notificaciones o en la Dynamic Island. Es diferente al widget fijo debajo del reloj. Las actividades en vivo caducan según iOS y las lecturas solo se actualizan cuando iWatch logra comunicarse con el reloj.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Si la Dynamic Island queda como una barra negra vacía, comprobá si el widget «iWatch · Prueba» aparece en la galería. Si tampoco aparece, priorizar la firma de MotoBatteryWidgets.appex; Reiniciar prueba no corrige CODESIGNING. Buscá un informe MotoBatteryWidgets en Datos de análisis y compartí su causa de terminación.")
                                .font(.caption).foregroundStyle(.orange)
                            Text("Widget circular/rectangular «iWatch · Prueba»: solo muestra iWatch OK. Sirve para comprobar si Sideloadly registró la extensión; NO muestra una batería inventada.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    settingsSection("Música", subtitle: "Conexión y sincronización con Spotify", symbol: "music.note")
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

                            statusRow("Spotify", spotify.status)
                            statusRow("Reproductor", spotify.playbackAvailability)
                            statusRow("Última canción", spotify.lastSong)
                            statusRow("Fuente de metadatos", spotify.metadataSource)
                            statusRow("Última orden", spotify.lastAction)
                            statusRow("Pantalla del reloj", watch.musicSyncStatus)
                            Divider()
                            Text("Spotify · SDK y Web API")
                                .font(.headline)
                            Text("El coordinador acepta observaciones recientes de ambas fuentes, sin prioridad absoluta. Con el iPhone bloqueado, la detección de cambios depende del tiempo de ejecución que conceda iOS. La resincronización puntual por Atajos permanece experimental.")
                                .font(.caption).foregroundStyle(.secondary)
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
                            statusRow("Eventos del SDK", spotifyRemote.metadataEventsActive ? "Suscripto" : "Sin suscripción")
                            statusRow("Último dato nativo", spotifyRemote.lastNativeEvent)
                            statusRow("Metadatos SDK vigentes", spotifyRemote.nativeMetadataIsFresh ? "Sí" : "No · respaldo Web API")
                            Text("Si el SDK queda en reconectando, esperá hasta 12 s. La Web API sigue funcionando y no hace falta desvincularla. Para reintentar, dejá Spotify abierto reproduciendo, regresá a iWatch y tocá Reintentar SDK una sola vez.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Consultar Spotify (diagnóstico)") {
                                Task { await spotify.refreshPlaybackInfo() }
                            }.buttonStyle(.bordered)
                            Divider()
                            Text("Music Auto Sync · recuperación")
                                .font(.headline)
                            statusRow("Auto Sync", musicAutoSync.status)
                            Text("Activado por defecto: sincroniza cambios de pista, reanuncia al reconectar y al volver a iWatch cuando hace falta, y realiza una recuperación preventiva como máximo cada 3 minutos con la app visible. No garantiza ejecución periódica cuando iOS suspende la app.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button {
                                spotify.resyncWatchMusicManually()
                            } label: {
                                Label("Resincronizar reproductor", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!watch.isConnected || !spotify.controlEnabled)
                            Text("Consulta una canción actual y fuerza un anuncio 24/01 con su estado. Guarda hasta dos paquetes en HEX durante 20 segundos en el registro persistente. El HEX revela títulos/artistas; compartilo solo si querés. La escritura BLE no confirma la pantalla del reloj.")
                                .font(.caption).foregroundStyle(.secondary)
                            Divider()
                            Button("Probar pantalla sin música") {
                                spotify.testNoMusicScreen()
                            }.buttonStyle(.bordered)
                            Text("Prueba del paquete Motorola de reposo: si el reloj no vuelve a «No se está reproduciendo música», copiá el registro. El formato todavía es experimental. Una pausa normal no lo activa.")
                                .font(.caption).foregroundStyle(.orange)
                            Text("Título + artista y estado Play/Pausa: 08 02 al cambiar canción, vacío al reproducir, 08 01 al pausar. Refresco automático solo con la app visible; cuando está bloqueada, se actualiza al recibir botones.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    settingsSection("Utilidades y diagnóstico", subtitle: "Herramientas avanzadas de iWatch", symbol: "wrench.adjustable")
                    GroupBox("Encuentra mi teléfono") {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(finder.status).foregroundStyle(.secondary)
                            statusRow("Búsqueda", finder.searching ? "Solicitada por el reloj" : "Detenida")

                            Button("Permitir aviso de respaldo (opcional)") { finder.requestPermission() }
                                .buttonStyle(.bordered)
                            Text("Probá y detené el sonido desde Reloj. La autorización de respaldo se gestiona aquí; iOS puede impedir iniciar audio desde segundo plano.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Bluetooth Motorola · inspección de F8F2") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(watch.motorolaCharacteristicsStatus)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Button {
                                watch.inspectMotorolaCharacteristics()
                            } label: {
                                Label("Inspeccionar características", systemImage: "antenna.radiowaves.left.and.right")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!watch.isConnected)
                            Text("Solo descubre UUID y permisos. No lee, no se suscribe y no escribe en F8F2. La presencia de F8F2 tampoco demuestra soporte HID.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
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

                    GroupBox("Music Auto Sync · experimento de segundo plano") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Optativo · iOS 26 o posterior")
                                .font(.subheadline.bold())
                            Text("Prueba una Actividad en vivo ANTES de bloquear y registra si iOS concede tiempo al bloquear o despierta la app ante eventos F8F0 reales. NO garantiza sincronización continua: si iOS suspende iWatch y no hay eventos BLE, Spotify no enviará cambios naturales a esta app.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Iniciar prueba") {
                                    backgroundExperiment.start()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(backgroundExperiment.enabled)
                                Button("Detener prueba") {
                                    backgroundExperiment.stop()
                                }
                                .buttonStyle(.bordered)
                                .disabled(!backgroundExperiment.enabled)
                            }
                            Text(backgroundExperiment.status)
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Para probar: iniciá con el reloj listo y Spotify reproduciendo; esperá a ver la Actividad en vivo, bloqueá sin cerrar iWatch y dejá terminar una canción. Desbloqueá, copiá el registro y buscá BG-EXPERIMENTO. Detener la prueba también detiene la Actividad en vivo de batería. No se reproducirá audio falso ni se consultará la batería periódicamente.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                .navigationTitle("Configuración").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { showSettings = false } } }
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
                Text("Ajustes avanzados").font(.title2.bold())
                Text("Personalizá iWatch sin perder tus conexiones ni registros.")
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
