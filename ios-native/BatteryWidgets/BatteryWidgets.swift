import SwiftUI
import WidgetKit

struct WatchBatteryEntry: TimelineEntry {
    var date: Date
    var percentage: Int?
    var measuredAt: Date?
}

struct WatchBatteryProvider: TimelineProvider {
    func entry() -> WatchBatteryEntry {
        let data = BatteryWidgetStore.load()
        return WatchBatteryEntry(date: Date(), percentage: data?.percentage, measuredAt: data?.date)
    }

    func placeholder(in context: Context) -> WatchBatteryEntry {
        WatchBatteryEntry(date: Date(), percentage: nil, measuredAt: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchBatteryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchBatteryEntry>) -> Void) {
        let current = entry()
        // iOS decide el intervalo real; no promete actualización al segundo.
        completion(Timeline(entries: [current], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct WatchBatteryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchBatteryEntry

    private var percent: String { entry.percentage.map { "\($0)%" } ?? "—" }
    private var lastUpdate: String {
        guard let date = entry.measuredAt else { return "Sin lectura" }
        return "Última: " + date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 1) {
                    Image(systemName: "applewatch")
                        .font(.system(size: 13, weight: .semibold))
                    Text(percent)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                }
                .widgetAccentable()
            case .accessoryRectangular:
                HStack(spacing: 7) {
                    Image(systemName: "applewatch")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Moto Watch · " + percent)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(lastUpdate)
                            .font(.system(size: 10))
                            .lineLimit(1)
                        if let charge = entry.percentage {
                            ProgressView(value: Double(charge), total: 100)
                                .tint(.primary)
                        }
                    }
                }
                .widgetAccentable()
            default:
                Text(percent)
            }
        }
    }
}

struct WatchBatteryWidget: Widget {
    let kind = BatteryWidgetStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchBatteryProvider()) { entry in
            WatchBatteryView(entry: entry)
        }
        .configurationDisplayName("Batería Moto Watch")
        .description("Último porcentaje Motorola 10/01 leído por iWatch.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

@main
struct WatchBatteryWidgets: WidgetBundle {
    var body: some Widget { WatchBatteryWidget() }
}
