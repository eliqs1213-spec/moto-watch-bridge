import SwiftUI
import UIKit

final class MotoAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Instanciar CoreBluetooth temprano es esencial para la restauración de estado.
        _ = WatchBLEManager.shared
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
            ContentView().environmentObject(WatchBLEManager.shared)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var watch: WatchBLEManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRUEBA NATIVA · ETAPA 1")
                            .font(.caption.bold()).foregroundStyle(.cyan)
                        Text("Moto Watch Bridge")
                            .font(.largeTitle.bold())
                        Text("Bluetooth directo con iPhone. Esta versión registra los botones para comprobar si siguen llegando con la pantalla bloqueada.")
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
                            Text("No cierres la aplicación desde el selector de apps. Esta prueba aún no controla Spotify.")
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

                    Text("Prototipo no oficial. No lee notificaciones privadas ni controla Spotify en esta etapa.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Moto Watch")
            .navigationBarTitleDisplayMode(.inline)
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
