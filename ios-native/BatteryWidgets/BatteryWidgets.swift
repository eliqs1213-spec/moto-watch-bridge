import SwiftUI
import WidgetKit
import ActivityKit

// Diagnóstico sin App Groups: sirve para comprobar si iOS reconoce y muestra
// la extensión instalada vía Sideloadly. NO inventa lecturas de batería.
struct DiagnosticEntry: TimelineEntry { let date: Date }
struct DiagnosticProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiagnosticEntry { DiagnosticEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (DiagnosticEntry) -> Void) {
        completion(DiagnosticEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DiagnosticEntry>) -> Void) {
        completion(Timeline(entries: [DiagnosticEntry(date: Date())], policy: .never))
    }
}

struct DiagnosticBatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "iWatchDiagnosticStage7", provider: DiagnosticProvider()) { _ in
            DiagnosticWidgetView()
        }
        .configurationDisplayName("iWatch · Prueba")
        .description("Verifica si iOS registró correctamente los widgets instalados con Sideloadly.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct DiagnosticWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if family == .accessoryCircular {
            VStack(spacing: 2) {
                Image(systemName: "applewatch")
                    .font(.system(size: 18, weight: .semibold))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
            }
            .widgetAccentable()
        } else {
            HStack(spacing: 6) {
                Image(systemName: "applewatch")
                VStack(alignment: .leading, spacing: 0) {
                    Text("iWatch OK").font(.system(size: 14, weight: .bold))
                    Text("Widget instalado").font(.system(size: 10))
                }
            }.widgetAccentable()
        }
    }
}

// Batería REAL de Moto Watch Fit, recibida de la aplicación vía ActivityKit.
// No requiere UserDefaults(suiteName:) ni App Groups.
struct MotoBatteryLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MotoBatteryActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Text("MW")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("iWatch · Moto Watch Fit")
                        .font(.headline)
                    Text(context.state.percentage >= 0
                         ? "Batería del reloj · Motorola 10/01"
                         : "Esperando primera lectura de batería")
                        .font(.caption)
                }
                Spacer(minLength: 0)
                Text(context.state.percentage >= 0 ? "\(context.state.percentage)%" : "—")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .activityBackgroundTint(Color.black.opacity(0.92))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("iWatch").font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.percentage >= 0 ? "\(context.state.percentage)%" : "—")
                        .font(.title3.bold()).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Moto Watch Fit · Batería Motorola 10/01")
                        .font(.caption)
                }
            } compactLeading: {
                Text("MW").font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(context.state.percentage >= 0 ? "\(context.state.percentage)%" : "—")
                    .font(.caption.bold()).monospacedDigit()
            } minimal: {
                Text("MW").font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
    }
}

@main
struct WatchBatteryWidgets: WidgetBundle {
    var body: some Widget {
        DiagnosticBatteryWidget()
        MotoBatteryLiveWidget()
    }
}
