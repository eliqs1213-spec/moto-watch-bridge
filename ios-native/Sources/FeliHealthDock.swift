import SwiftUI

/// El compañero vive en el pie de Salud (respetando Safe Area y el scroll),
/// de modo que sigue visible sin superponerse a gráficos, botones ni tarjetas.
/// Solo se crea desde pantallas de Salud, nunca desde Inicio o Ayuno.
struct FeliHealthDock: View {
    let watchID: String
    @ObservedObject var store: WatchHealthStore
    var metric: HealthMetric? = nil

    @AppStorage("motowatch.feli.dock.compact") private var compact = false
    @State private var explanationVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var insight: WatchHealthInsight {
        if let metric {
            return HealthInsights.metric(metric, days: store.days, watchID: watchID)
        }
        if let last = store.latest(.stress, watchID: watchID) {
            let age = Date().timeIntervalSince(last.measuredAt)
            if age >= 0 && age <= 48 * 3600 {
                if last.value >= 70 {
                    return WatchHealthInsight(
                        title: "Feli está atento",
                        message: "La última lectura de estrés del reloj fue elevada. Mirá si vuelve a aparecer, sin sacar conclusiones por un solo dato.",
                        coverage: "Lectura del \(last.measuredAt.formatted(date: .abbreviated, time: .shortened)); escala orientativa de Motorola.",
                        mood: .worried)
                }
                if last.value <= 30 {
                    return WatchHealthInsight(
                        title: "Feli se relajó",
                        message: "La última lectura de estrés fue baja. Feli observa una mariposa y descansa un ratito.",
                        coverage: "Lectura del \(last.measuredAt.formatted(date: .abbreviated, time: .shortened)); no es un diagnóstico.",
                        mood: .calm)
                }
            }
        }
        return HealthInsights.weekly(days: store.days, watchID: watchID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 11) {
                // Feli no es una imagen estática. El toque activa una reacción
                // local y no dispara ninguna lectura inventada del reloj.
                FeliCompanionView(mood: insight.mood, diameter: compact ? 51 : 86)
                    .accessibilityHint("Tocá para saludar a Feli")
                VStack(alignment: .leading, spacing: compact ? 0 : 4) {
                    Text(compact ? "Feli te acompaña" : insight.title)
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
