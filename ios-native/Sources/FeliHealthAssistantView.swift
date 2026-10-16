import SwiftUI

/// Chibi discreto que aparece únicamente dentro de Salud. El toque revela
/// por qué se eligió una reacción; no flota encima de gráficas ni controles.
struct FeliHealthAssistantView: View {
    let watchID: String
    @ObservedObject var store: WatchHealthStore
    @State private var expanded = false

    private var insight: WatchHealthInsight {
        if let last = store.latest(.stress, watchID: watchID),
           Date().timeIntervalSince(last.measuredAt) >= 0,
           Date().timeIntervalSince(last.measuredAt) <= 48 * 3600 {
            if last.value >= 70 {
                return WatchHealthInsight(
                    title: "Una lectura de estrés elevada",
                    message: "La última lectura del reloj fue \(Int(last.value.rounded()))/100. Feli está inquieto; observá si se repite antes de sacar conclusiones.",
                    coverage: "Medida el \(last.measuredAt.formatted(date: .abbreviated, time: .shortened)). Escala orientativa, no clínica.",
                    mood: .worried)
            }
            if last.value <= 30 {
                return WatchHealthInsight(
                    title: "Un momento tranquilo",
                    message: "La última lectura del reloj fue \(Int(last.value.rounded()))/100. Feli se sienta y espera una mariposa.",
                    coverage: "Medida el \(last.measuredAt.formatted(date: .abbreviated, time: .shortened)). Escala orientativa, no clínica.",
                    mood: .calm)
            }
        }
        return HealthInsights.weekly(days: store.days, watchID: watchID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                FeliCompanionView(mood: insight.mood, diameter: 84)
                VStack(alignment: .leading, spacing: 5) {
                    Label("Feli te acompaña", systemImage: "pawprint.fill")
                        .font(.subheadline.bold()).foregroundStyle(.orange)
                    Text(insight.title).font(.headline)
                    Text(insight.message).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 3)
                }
                Spacer(minLength: 0)
            }
            Button(expanded ? "Ocultar explicación" : "¿Por qué Feli reacciona así?") {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            }.font(.caption.bold())
            if expanded {
                Text(insight.coverage)
                    .font(.caption).foregroundStyle(.secondary)
                Text("Feli interpreta tendencias disponibles, no diagnósticos. No se cuentan días sin datos como cero.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }
}

struct FeliHealthMetricNote: View {
    let metric: HealthMetric
    let days: [WatchHealthDay]
    let watchID: String
    private var insight: WatchHealthInsight {
        HealthInsights.metric(metric, days: days, watchID: watchID)
    }
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FeliCompanionView(mood: insight.mood, diameter: 79)
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.title).font(.headline)
                Text(insight.message).font(.subheadline)
                Text(insight.coverage).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
    }
}
