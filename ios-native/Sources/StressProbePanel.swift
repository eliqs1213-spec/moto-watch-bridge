import SwiftUI
import UIKit

struct StressProbePanel: View {
    @EnvironmentObject private var watch: WatchBLEManager
    @StateObject private var stress = WatchStressProbe.shared
    @StateObject private var health = WatchHealthSync.shared
    var body: some View {
        GroupBox("Estrés · validar lectura del reloj") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Consulta candidata: compará los valores y sus horas con una medición guardada en el reloj. Estas lecturas no se guardan en el histórico.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button(stress.isRunning ? "Consultando…" : "Consultar candidato de estrés") {
                    watch.refreshStressProbe()
                }.buttonStyle(.borderedProminent)
                    .disabled(!watch.isConnected || stress.isRunning || health.isRunning)
                Text(stress.status).font(.caption).foregroundStyle(.secondary)
                if !stress.samples.isEmpty {
                    Text("\(stress.samples.count) muestras · últimas 20").font(.caption.bold())
                    ForEach(Array(stress.samples.suffix(20).reversed())) { sample in
                        HStack {
                            Text(sample.timestamp.formatted(date: .abbreviated, time: .standard))
                            Spacer()
                            Text("\(sample.value)").bold().monospacedDigit()
                        }.font(.caption)
                    }
                }
                Button("Copiar diagnóstico de estrés") {
                    UIPasteboard.general.string = stress.report
                }.buttonStyle(.bordered)
                Text("El diagnóstico copia estados y tamaños, sin valores de las mediciones ni identificadores del reloj. La lectura se pierde al volver a consultar o cerrar la app.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

