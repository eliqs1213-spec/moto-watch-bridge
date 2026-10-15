import SwiftUI
import Charts

private enum HistoryPeriod: String, CaseIterable {
    case day = "Día", week = "Semana"
}

extension HealthMetric {
    var color: Color {
        switch self {
        case .steps: return .green
        case .heartRate: return .pink
        case .sleep: return .indigo
        case .stress: return .orange
        case .workouts: return .cyan
        }
    }
    func formatted(_ value: Double) -> String {
        switch self {
        case .steps: return "\(Int(value).formatted()) pasos"
        case .heartRate: return "\(Int(value.rounded())) lpm"
        case .sleep:
            let minutes = Int((value * 60).rounded())
            return "\(minutes / 60) h \(minutes % 60) min"
        case .stress: return value.formatted(.number.precision(.fractionLength(0...1)))
        case .workouts: return "\(Int(value)) sesiones"
        }
    }
    var summaryLabel: String {
        switch self {
        case .heartRate, .stress: return "Promedio de mediciones"
        case .sleep: return "Tiempo de sueño"
        default: return "Total del día"
        }
    }
}

struct HealthHistoryView: View {
    @StateObject private var store = WatchHealthStore.shared
    @EnvironmentObject private var watch: WatchBLEManager
    @State private var date = Date()
    @State private var watchID = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tu actividad").font(.largeTitle.bold())
                            Text("Histórico de tu Moto Watch").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "heart.text.square.fill")
                            .font(.largeTitle).foregroundStyle(.pink)
                            .accessibilityHidden(true)
                    }
                    Label(watch.isConnected ? "Moto Watch conectado" : "Moto Watch desconectado",
                          systemImage: watch.isConnected ? "checkmark.circle.fill" : "watch.analog")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if store.watchIDs.count > 1 {
                        Picker("Reloj del histórico", selection: $watchID) {
                            ForEach(store.watchIDs, id: \.self) { id in Text(id).tag(id) }
                        }
                    }
                    HealthSyncPanel()
                    StressProbePanel()
                    VitalsProbePanel()
                    SleepProbePanel()
                    DatePicker("Consultar día", selection: $date, in: ...Date(), displayedComponents: .date)
                    ForEach(HealthMetric.allCases) { metric in
                        NavigationLink {
                            HealthMetricHistoryView(metric: metric, initialDate: date,
                                                    watchID: effectiveWatchID, store: store)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: metric.symbol).font(.title2)
                                    .foregroundStyle(metric.color).frame(width: 36)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(metric.title).font(.headline)
                                    Text(store.day(date, watchID: effectiveWatchID)?.value(for: metric)
                                        .map { metric.formatted($0) } ?? "Sin datos")
                                        .font(.title3.bold()).foregroundStyle(.primary)
                                    if let day = store.day(date, watchID: effectiveWatchID),
                                       (metric == .steps && day.stepsExperimental == true)
                                        || (metric == .heartRate && day.heartRateExperimental == true) {
                                        Text("Experimental").font(.caption).foregroundStyle(.orange)
                                    }
                                    Text("Consultar por día o semana")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(metric.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                    if let error = store.storageError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    Text("Pasos y pulso tienen una consulta experimental. Sueño, estrés y entrenamientos todavía no se sincronizan. Tu histórico se guarda en este iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }.navigationTitle("Salud").navigationBarTitleDisplayMode(.inline)
        }
    }
    private var effectiveWatchID: String {
        store.watchIDs.contains(watchID) ? watchID : (store.watchIDs.first ?? "")
    }
}

private struct HealthMetricHistoryView: View {
    let metric: HealthMetric
    let watchID: String
    @ObservedObject var store: WatchHealthStore
    @State private var date: Date
    @State private var period = HistoryPeriod.day

    init(metric: HealthMetric, initialDate: Date, watchID: String, store: WatchHealthStore) {
        self.metric = metric
        self.watchID = watchID
        self.store = store
        _date = State(initialValue: initialDate)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.firstWeekday = 2
        return value
    }
    private var dates: [Date] {
        let start = period == .day ? calendar.startOfDay(for: date)
            : (calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date)
        return (0..<(period == .day ? 1 : 7)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }
    private var selectedDay: WatchHealthDay? { store.day(date, watchID: watchID) }
    private var records: [WatchHealthDay] { dates.compactMap { store.day($0, watchID: watchID) } }
    private var values: [Double] { records.compactMap { $0.value(for: metric) } }
    private var readings: [WatchHealthReading] {
        let items = metric == .heartRate ? selectedDay?.heartRate : selectedDay?.stress
        return (items ?? []).sorted { $0.timestamp < $1.timestamp }
    }
    private var summary: Double? {
        guard !values.isEmpty else { return nil }
        if metric == .heartRate || metric == .stress || metric == .sleep {
            return values.reduce(0, +) / Double(values.count)
        }
        return values.reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Período", selection: $period) {
                    ForEach(HistoryPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                DatePicker("Fecha", selection: $date, in: ...Date(), displayedComponents: .date)
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Período anterior")
                    Spacer()
                    Text(periodTitle).font(.subheadline.bold())
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(!canMoveForward).accessibilityLabel("Período siguiente")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(summary.map { metric.formatted($0) } ?? "Sin datos")
                        .font(.largeTitle.bold()).foregroundStyle(metric.color)
                    Text(period == .day ? metric.summaryLabel : weeklySummaryLabel)
                        .foregroundStyle(.secondary)
                    if period == .week {
                        Text("\(values.count) de 7 días con registros")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if records.contains(where: { metric == .steps ? $0.stepsExperimental == true : (metric == .heartRate && $0.heartRateExperimental == true) }) {
                    Label("Datos experimentales · interpretación pendiente de validar con el reloj", systemImage: "flask")
                        .font(.caption).foregroundStyle(.orange)
                }
                if values.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: metric.symbol).font(.system(size: 40)).foregroundStyle(metric.color)
                        Text("No hay registros para este período").font(.headline)
                        Text("Podrás consultar aquí los datos que se sincronicen desde tu Moto Watch.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    if period == .week { weeklyChart }
                    if period == .day && (metric == .heartRate || metric == .stress) {
                        Chart(readings) { reading in
                            PointMark(x: .value("Hora", reading.timestamp), y: .value(metric.title, reading.value))
                                .foregroundStyle(metric.color)
                        }.frame(height: 200)
                        if let minimum = readings.map(\.value).min(), let maximum = readings.map(\.value).max() {
                            Text("Mínimo: \(metric.formatted(minimum)) · Máximo: \(metric.formatted(maximum))")
                                .font(.subheadline)
                        }
                        ForEach(readings) { reading in
                            HStack {
                                Text(reading.timestamp.formatted(date: .omitted, time: .shortened))
                                Spacer()
                                Text(metric.formatted(reading.value)).bold()
                            }.font(.subheadline)
                        }
                    }
                    if period == .week { dailyList }
                    if metric == .workouts { workoutList }
                    if metric == .sleep {
                        Text("El sueño se muestra en el día de despertar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let latest = records.map(\.syncedAt).max() {
                        Text("Última sincronización: \(latest.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding()
        }.navigationTitle(metric.title).navigationBarTitleDisplayMode(.inline)
    }

    private var weeklyChart: some View {
        Chart {
            ForEach(dates, id: \.self) { day in
                if let value = store.day(day, watchID: watchID)?.value(for: metric) {
                    BarMark(x: .value("Día", day, unit: .day), y: .value(metric.title, value))
                        .foregroundStyle(metric.color).cornerRadius(4)
                }
            }
        }
        .chartXScale(domain: dates[0]...(calendar.date(byAdding: .day, value: 7, to: dates[0]) ?? dates[6]))
        .chartXAxis { AxisMarks(values: dates) { AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
        .frame(height: 200)
        .accessibilityLabel("\(metric.title) por día. Los días sin registros no tienen barra.")
    }
    private var dailyList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detalle por día").font(.headline)
            ForEach(dates, id: \.self) { day in
                Button {
                    date = day
                    period = .day
                } label: {
                    HStack {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        Spacer()
                        Text(store.day(day, watchID: watchID)?.value(for: metric)
                            .map { metric.formatted($0) } ?? "Sin datos")
                    }.font(.subheadline)
                }.buttonStyle(.plain).disabled(day > Date())
                Divider()
            }
        }
    }
    private var workoutList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sesiones").font(.headline)
            ForEach(records.flatMap(\.workouts).sorted { $0.startedAt > $1.startedAt }) { workout in
                VStack(alignment: .leading, spacing: 5) {
                    Text(workout.name).font(.headline)
                    Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("\(Int(workout.durationMinutes.rounded())) min")
                }.font(.subheadline)
            }
            if records.flatMap(\.workouts).isEmpty {
                Text("No hay entrenamientos registrados.").foregroundStyle(.secondary)
            }
        }
    }
    private var weeklySummaryLabel: String {
        switch metric {
        case .heartRate, .stress: return "Promedio de los promedios diarios disponibles"
        case .sleep: return "Promedio por noche registrada"
        default: return "Total de los días registrados"
        }
    }
    private var periodTitle: String {
        if period == .day { return date.formatted(date: .abbreviated, time: .omitted) }
        return "\(dates[0].formatted(.dateTime.day().month(.abbreviated))) – \(dates[6].formatted(.dateTime.day().month(.abbreviated).year()))"
    }
    private var canMoveForward: Bool {
        let currentStart = period == .day ? calendar.startOfDay(for: Date())
            : (calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date())
        return dates[0] < currentStart
    }
    private func move(_ direction: Int) {
        guard let next = calendar.date(byAdding: .day, value: direction * (period == .day ? 1 : 7), to: date) else { return }
        date = min(next, Date())
    }
}

