import SwiftUI
import UIKit

/// Portada independiente de la depuración avanzada. Los estados vienen de los
/// ObservableObject existentes y no se simulan lecturas de batería ni de música.
struct WatchHomeView: View {
    let isSelected: Bool
    @EnvironmentObject private var watch: WatchBLEManager
    @EnvironmentObject private var spotify: SpotifyBridge
    @StateObject private var remote = SpotifyAppRemoteBridge.shared
    @StateObject private var health = WatchHealthStore.shared
    @StateObject private var sync = HealthDashboardSync.shared
    let openWatch: () -> Void
    let openHealth: () -> Void
    @State private var showMeasurements = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Inicio").font(.largeTitle.bold())
                        Text("Tu reloj, música y salud en un solo lugar.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    watchCard
                    statusGrid
                    spotifyPanel
                    measurementPanel
                    recommendationPanel
                    Button(action: openWatch) {
                        Label("Controles y diagnóstico del reloj", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                    Text("Carátula ilustrativa: la identificación del tema instalado sigue pendiente.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("iWatch").navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showMeasurements) {
            GuidedWatchReadingView(openHealth: openHealth)
                .environmentObject(watch)
        }
        .onAppear {
            watch.autoConnectIfNeeded()
            watch.refreshBattery(force: false)
        }
        // Mismo criterio de recuperación de Spotify existente en ContentView:
        // únicamente en primer plano; iOS puede suspender la app bloqueada.
        .task {
            while !Task.isCancelled {
                if isSelected && UIApplication.shared.applicationState == .active && spotify.controlEnabled {
                    if remote.isConnected {
                        remote.requestCurrentPlayerState(fallbackToWeb: true)
                        if !remote.nativeMetadataIsFresh && watch.isConnected {
                            await spotify.refreshPlaybackInfo(allowSDKFallback: true)
                        }
                    } else if watch.isConnected {
                        await spotify.refreshPlaybackInfo()
                    }
                }
                do { try await Task.sleep(nanoseconds: 6_000_000_000) }
                catch { return }
            }
        }
    }

    private var watchCard: some View {
        HStack(spacing: 16) {
            WatchFacePreview(battery: watch.isConnected ? watch.batteryPercentage : nil)
                .frame(width: 130, height: 184)
            VStack(alignment: .leading, spacing: 8) {
                Text("Moto Watch Fit").font(.title3.bold())
                Label(watch.isConnected ? "Conectado" : "Sin conexión",
                      systemImage: watch.isConnected ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(watch.isConnected ? .green : .secondary)
                    .font(.subheadline.bold())
                Text(watch.connectionStatus)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3)
                if !watch.isConnected {
                    Button("Conectar reloj") { watch.connectToWatch() }
                        .buttonStyle(.borderedProminent).tint(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
    }

    private var statusGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            statusTile("Batería", value: watch.isConnected ? watch.batteryPercentage.map { "\($0) %" } ?? "Sin lectura" : "Sin conexión",
                       symbol: "battery.75percent", color: .green)
            statusTile("Bluetooth", value: watch.isConnected ? "Conectado" : watch.bluetoothStatus,
                       symbol: "bluetooth", color: .blue)
            statusTile("Spotify SDK", value: remote.isConnected ? "Conectado" : remote.enabled ? "No disponible" : "Desactivado",
                       symbol: "music.note", color: .orange)
            statusTile("Música", value: spotify.controlEnabled ? (remote.isConnected ? "SDK prioritario" : "Web API de respaldo") : "Controles apagados",
                       symbol: "play.circle.fill", color: .indigo)
        }
    }

    private func statusTile(_ title: String, value: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(color)
                .frame(width: 27)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.bold()).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .padding(.horizontal, 10).background(Color(uiColor: .secondarySystemGroupedBackground),
                                             in: RoundedRectangle(cornerRadius: 16))
    }

    private var spotifyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Spotify", systemImage: "music.note").font(.headline)
                Spacer()
                Text(remote.isConnected ? "SDK conectado" : "Respaldo Web")
                    .font(.caption.bold())
                    .foregroundStyle(remote.isConnected ? Color.green : Color.secondary)
            }
            Text(spotify.lastSong).font(.subheadline.bold()).lineLimit(2)
            Text(spotify.playbackAvailability).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button {
                    remote.retryConnection()
                } label: {
                    Label("Reconectar SDK", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(!remote.enabled)
                Spacer(minLength: 8)
                Button("Actualizar música") { spotify.forceWatchMusicRecovery() }
                    .buttonStyle(.bordered).font(.caption)
                    .disabled(!spotify.controlEnabled)
            }
            Text(remote.status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(16).background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 20))
    }

    private var measurementPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mediciones del reloj").font(.headline)
                Spacer()
                Button("Ver Salud", action: openHealth).font(.caption.bold())
            }
            Text("Consultá mediciones disponibles y seguí una guía antes de medir desde tu reloj.")
                .font(.caption).foregroundStyle(.secondary)
            Button { showMeasurements = true } label: {
                Label("Guía de mediciones", systemImage: "heart.text.square")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(.pink)
            Text("La consulta BLE recupera datos del reloj; no inicia por sí sola el sensor manual.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16).background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 20))
    }

    private var recommendationPanel: some View {
        let id = watch.healthWatchID ?? health.watchIDs.last ?? ""
        let insight = HealthInsights.weekly(days: health.days, watchID: id)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Resumen de bienestar", systemImage: "sparkles")
                .font(.headline).foregroundStyle(.orange)
            Text(insight.message).font(.subheadline)
            Text(insight.coverage).font(.caption).foregroundStyle(.secondary)
            Button("Ver estadísticas", action: openHealth)
                .font(.caption.bold())
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }
}

/// La hora viene del iPhone. No pretende conocer ni reflejar la esfera real.
private struct WatchFacePreview: View {
    let battery: Int?
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.8))
                .frame(width: 53, height: 19)
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [.indigo.opacity(0.83), .black, .teal.opacity(0.5)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 120, height: 146)
                .overlay {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(spacing: 7) {
                            Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
                            Text(context.date.formatted(.dateTime.hour().minute()))
                                .font(.system(size: 29, weight: .semibold, design: .rounded))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1).foregroundStyle(.white)
                            Label(battery.map { "\($0)%" } ?? "—", systemImage: "battery.75percent")
                                .font(.system(size: 10)).foregroundStyle(.green)
                        }.padding(12)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.gray.opacity(0.5), lineWidth: 3))
            RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.8))
                .frame(width: 53, height: 19)
        }
        .accessibilityLabel("Vista ilustrativa del reloj con hora actual")
    }
}

/// Guía para no confundir leer un registro previo con disparar un sensor.
private struct GuidedWatchReadingView: View {
    let openHealth: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var watch: WatchBLEManager
    @StateObject private var sync = HealthDashboardSync.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Mediciones manuales").font(.title2.bold())
                    Text("Acomodá el reloj sobre la muñeca, quedate quieto y elegí la medición en el propio reloj. Después, consultá sus registros desde iWatch.")
                        .font(.subheadline)
                    ForEach([HealthMetric.heartRate, .oxygen, .stress, .sleep], id: \.self) { metric in
                        HStack(spacing: 12) {
                            Image(systemName: metric.symbol).foregroundStyle(metric.color).frame(width: 27)
                            VStack(alignment: .leading) {
                                Text(metric.title).font(.headline)
                                Text(metric == .sleep ? "Se consulta como descanso registrado, no en vivo." :
                                     "Iniciá el sensor desde el Moto Watch si buscás una lectura nueva.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 15))
                    }
                    Button {
                        sync.update(watch: watch)
                    } label: {
                        Label(sync.isRunning ? "Consultando…" : "Recuperar mediciones", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sync.isRunning || !watch.isConnected)
                    if sync.isRunning { ProgressView(value: sync.progress) }
                    Text(sync.status).font(.caption).foregroundStyle(.secondary)
                    Button("Abrir Salud") {
                        dismiss()
                        openHealth()
                    }.frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                }.padding(20)
            }
            .navigationTitle("Guía")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
    }
}
