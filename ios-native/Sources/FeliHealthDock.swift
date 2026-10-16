import SwiftUI

/// El compañero vive en el pie de Salud (respetando Safe Area y el scroll),
/// de modo que sigue visible sin superponerse a gráficos, botones ni tarjetas.
/// Esta barra solo se crea desde Salud; Ayuno tiene su propio FeliFastingDock
/// con escenas dependientes del temporizador. Inicio sigue sin mascota.
struct FeliHistoricalSelection {
    let periodLabel: String
    let average: Double?
    let recordedDays: Int
}

struct FeliHealthDock: View {
    let watchID: String
    @ObservedObject var store: WatchHealthStore
    var metric: HealthMetric? = nil
    var history: FeliHistoricalSelection? = nil

    @AppStorage("motowatch.feli.dock.compact") private var compact = false
    @State private var explanationVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var insight: WatchHealthInsight {
        if let metric {
            if let history {
                return HealthInsights.historical(metric: metric, average: history.average,
                                                 recordedDays: history.recordedDays,
                                                 periodLabel: history.periodLabel)
            }
            let last = store.latest(metric, watchID: watchID)
            return HealthInsights.latest(metric: metric, snapshot: last,
                                         sleepComplete: metric != .sleep || sleepIsComplete(last))
        }
        // En el resumen de Salud, Feli reacciona a la última medición entre
        // las categorías disponibles, no al promedio semanal de sueño.
        let metrics: [HealthMetric] = [.stress, .heartRate, .oxygen, .sleep, .steps, .activeCalories]
        let candidate = metrics.compactMap { metric -> (HealthMetric, HealthSnapshot)? in
            guard let latest = store.latest(metric, watchID: watchID) else { return nil }
            return (metric, latest)
        }.max { $0.1.measuredAt < $1.1.measuredAt }
        guard let candidate else {
            return HealthInsights.latest(metric: .stress, snapshot: nil)
        }
        return HealthInsights.latest(metric: candidate.0, snapshot: candidate.1,
                                     sleepComplete: candidate.0 != .sleep || sleepIsComplete(candidate.1))
    }

    private func sleepIsComplete(_ snapshot: HealthSnapshot?) -> Bool {
        guard let snapshot, let day = store.day(snapshot.measuredAt, watchID: watchID) else {
            return false
        }
        return day.sleepRetrievalComplete == true
    }

    private var compactLabel: String {
        guard let metric, let history else { return "Feli te acompaña" }
        if let average = history.average {
            return "Promedio: " + metric.formatted(average)
        }
        return "Sin promedio disponible"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 11) {
                // Feli no es una imagen estática. El toque activa una reacción
                // local y no dispara ninguna lectura inventada del reloj.
                FeliCompanionView(mood: insight.mood, diameter: compact ? 51 : 86)
                    // Reproduce el saludo al abrir una métrica, entrar en
                    // Histórico, cambiar el período o recibir una nueva lectura.
                    .id(insight.title + "|" + insight.message + "|" + (history?.periodLabel ?? "último"))
                    .accessibilityHint("Tocá para saludar a Feli")
                VStack(alignment: .leading, spacing: compact ? 0 : 4) {
                    Text(compact ? compactLabel : insight.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if !compact {
                        Text(insight.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Tocá a Feli para acariciarlo")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 8) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                            compact.toggle()
                            if compact { explanationVisible = false }
                        }
                    } label: {
                        Image(systemName: compact ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .font(.system(size: 23))
                    }
                    .accessibilityLabel(compact ? "Expandir Feli" : "Reducir Feli")
                    if !compact {
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                                explanationVisible.toggle()
                            }
                        } label: {
                            Image(systemName: explanationVisible ? "info.circle.fill" : "info.circle")
                                .font(.system(size: 22))
                        }
                        .accessibilityLabel(explanationVisible ? "Ocultar explicación" : "Explicar reacción de Feli")
                    }
                }
                .foregroundStyle(.orange)
                .buttonStyle(.plain)
                .padding(.trailing, 2)
            }
            if explanationVisible && !compact {
                Divider()
                Text(insight.coverage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Sus gestos acompañan los datos disponibles; no son una medición nueva ni un diagnóstico.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 4 : 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.orange.opacity(0.12), lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 7)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).opacity(0.94))
    }
}
