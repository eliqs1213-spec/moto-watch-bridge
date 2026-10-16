import SwiftUI

extension HealthMetric {
    var color: Color {
        switch self {
        case .steps: return .green
        case .heartRate: return .pink
        case .oxygen: return .blue
        case .stress: return .orange
        case .sleep: return .indigo
        case .activeCalories: return Color(red: 0.88, green: 0.48, blue: 0.08)
        case .workouts: return .cyan
        }
    }
    func formatted(_ value: Double) -> String {
        switch self {
        case .steps: return "\(Int(value.rounded()).formatted()) pasos"
        case .heartRate: return "\(Int(value.rounded())) lpm"
        case .oxygen: return "\(Int(value.rounded())) %"
        case .stress: return "\(Int(value.rounded())) / 100"
        case .sleep:
            let minutes = Int((value * 60).rounded())
            return "\(minutes / 60) h \(minutes % 60) min"
        case .activeCalories: return "\(Int(value.rounded()).formatted()) kcal"
        case .workouts: return "\(Int(value)) sesiones"
        }
    }
}

struct HealthHistoryView: View {
    @StateObject private var store = WatchHealthStore.shared
    @StateObject private var sync = HealthDashboardSync.shared
    @EnvironmentObject private var watch: WatchBLEManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var today = Date()
    @AppStorage("motowatch.health.selectedWatch") private var selectedWatch = ""
    private let dashboardColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private var ids: [String] { Array(Set(store.watchIDs + [watch.healthWatchID].compactMap { $0 })).sorted() }
    private var watchID: String {
        ids.contains(selectedWatch) ? selectedWatch : (watch.healthWatchID ?? ids.first ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if ids.count > 1 {
                        Picker("Histórico del reloj", selection: Binding(get: { watchID }, set: { selectedWatch = $0 })) {
                            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                                Text(id == watch.healthWatchID ? "Moto Watch actual" : "Reloj \(index + 1)").tag(id)
                            }
                        }.pickerStyle(.menu)
                    }
                    updatePanel
                    SmartHealthWeeklyOverview(days: store.days, watchID: watchID)
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Últimos registros").font(.title2.bold())
                            Text("Tus mediciones más recientes, incluso de días anteriores.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(today.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: dashboardColumns, spacing: 12) {
                        ForEach(HealthMetric.allCases.filter { $0 != .workouts }) { metric in
                            NavigationLink {
                                HealthMetricHistoryView(metric: metric, watchID: watchID, store: store)
                            } label: {
                                HealthMetricCard(
                                    metric: metric,
                                    snapshot: store.latest(metric, watchID: watchID),
                                    emptyTitle: "Sin registros",
                                    emptyDetail: "Abrir histórico",
                                    compact: true
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Abre el histórico de \(metric.title)")
                        }
                    }
                    Label("Entrenamientos: sincronización pendiente", systemImage: "figure.run")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                    if let error = store.storageError {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                    }
                    Text("Solo datos de tu Moto Watch. El histórico se guarda en este iPhone y crece con cada actualización. Las consultas pueden recuperar hasta 24 horas de mediciones disponibles en el reloj.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FeliHealthDock(watchID: watchID, store: store)
            }
            .navigationTitle("Salud").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavigationLink { HealthDiagnosticsView() } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Diagnóstico de salud")
            }
        }
        .onAppear { today = Date(); visible = true; sync.setVisibility(true, active: scenePhase == .active, watch: watch) }
        .onDisappear { visible = false; sync.setVisibility(false, active: scenePhase == .active, watch: watch) }
        .onChange(of: scenePhase) { phase in
            if phase == .active { today = Date() }
            sync.setVisibility(visible, active: phase == .active, watch: watch)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = Date() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in today = Date() }
        .onChange(of: watch.isConnected) { _ in sync.connectionChanged(watch: watch) }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Tu bienestar")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                Text("Un vistazo a tu actividad y descanso")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label(watch.isConnected ? "Moto Watch conectado" : "Histórico disponible sin conexión",
                      systemImage: watch.isConnected ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(watch.isConnected ? Color.green : Color.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(
                    LinearGradient(colors: [.pink, .red.opacity(0.8)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 19)
                )
                .accessibilityHidden(true)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 24))
    }

    private var updatePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tu reloj, al día").font(.headline)
                    Text("Automático mientras consultás Salud").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { selectedWatch = watch.healthWatchID ?? watchID; sync.update(watch: watch) } label: {
                    Label(sync.isRunning ? "Actualizando" : "Actualizar", systemImage: "arrow.clockwise")
                        .font(.subheadline.bold())
                }.buttonStyle(.borderedProminent).tint(.pink)
                    .disabled(sync.isRunning || !watch.isConnected)
            }
            if sync.isRunning { ProgressView(value: sync.progress).tint(.pink) }
            Text(sync.status).font(.caption).foregroundStyle(.secondary)
            Text("Pasos y calorías: 5 min · Mediciones: 15 min · Sueño: 1 h. Actualizar consulta todo ahora.")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(sync.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct HealthMetricCard: View {
    let metric: HealthMetric
    let snapshot: HealthSnapshot?
    var emptyTitle = "Sin registros"
    var emptyDetail = "Consultá tu reloj para empezar"
    var compact = false

    var body: some View {
        Group {
            if compact { compactContent } else { detailedContent }
        }
        .accessibilityElement(children: .combine)
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: metric.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(metric.color)
                    .frame(width: 40, height: 40)
                    .background(metric.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold()).foregroundStyle(.tertiary)
            }
            Text(metric.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(snapshot.map { metric.formatted($0.value) } ?? emptyTitle)
                .font(.title3.bold()).foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if let snapshot = snapshot {
                Label(snapshot.measuredAt.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(emptyDetail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 166, alignment: .topLeading)
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(metric.color.opacity(0.12), lineWidth: 1)
        }
    }

    private var detailedContent: some View {
        HStack(spacing: 14) {
            Image(systemName: metric.symbol).font(.title2).foregroundStyle(metric.color)
                .frame(width: 48, height: 54)
                .background(metric.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 6) {
                Text(metric.title).font(.subheadline.bold()).foregroundStyle(metric.color)
                Text(snapshot.map { metric.formatted($0.value) } ?? emptyTitle)
                    .font(.title2.bold()).foregroundStyle(.primary)
                if let snapshot = snapshot {
                    Text("\(metric == .sleep ? "Último descanso" : "Medición"): \(snapshot.measuredAt.formatted(date: .abbreviated, time: .shortened))")
                    Text("Actualizado: \(snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                } else { Text(emptyDetail) }
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(metric.color)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(metric.color.opacity(0.12)))
    }
}

private enum MetricDisplayMode: String, CaseIterable {
    case latest = "Última lectura"
    case historical = "Histórico"
}

private struct HealthMetricHistoryView: View {
    let metric: HealthMetric
    let watchID: String
    @ObservedObject var store: WatchHealthStore
    @State private var date: Date
    @State private var period = HealthHistoryPeriod.day
    @State private var viewMode = MetricDisplayMode.latest
    @AppStorage("motowatch.sleep.goal.hours") private var goalHours = 8.0

    init(metric: HealthMetric, watchID: String, store: WatchHealthStore) {
        self.metric = metric
        self.watchID = watchID
        self.store = store
        _date = State(initialValue: Date())
    }

    private var dates: [Date] { period.dates(containing: date) }
    private var records: [WatchHealthDay] { dates.compactMap { store.day($0, watchID: watchID) } }
    private var readings: [WatchHealthReading] {
        records.flatMap { $0.readings(for: metric) }.sorted { $0.timestamp < $1.timestamp }
    }
    private var latest: HealthSnapshot? { store.latest(metric, watchID: watchID) }
    private var dailyPoints: [SmartDailyPoint] {
        SmartHealthChartAnalytics.dailyPoints(days: store.days, watchID: watchID,
                                             metric: metric, dates: dates)
    }
    // Exactamente el mismo promedio por día que usan los gráficos inteligentes.
    // Las noches marcadas como parciales no pueden generar una reacción de Feli.
    private var historyAverage: Double? { SmartHealthChartAnalytics.average(dailyPoints) }
    private var summary: Double? { historyAverage }

    private var title: String {
        if period == .day { return date.formatted(date: .abbreviated, time: .omitted) }
        if period == .month { return date.formatted(.dateTime.month(.wide).year()) }
        guard let first = dates.first, let last = dates.last else { return "Sin fechas" }
        return "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Vista de \(metric.title)", selection: $viewMode) {
                    ForEach(MetricDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Feli cambia entre el último valor del reloj y el promedio del histórico.")

                if viewMode == .latest {
                    latestPanel
                } else {
                    historicalPanel
                }
                if metric == .oxygen {
                    oxygenHelp
                }
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FeliHealthDock(
                watchID: watchID, store: store, metric: metric,
                history: viewMode == .historical
                    ? FeliHistoricalSelection(periodLabel: title, average: historyAverage,
                                              recordedDays: dailyPoints.count) : nil
            )
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var latestPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Último valor del Moto Watch", systemImage: "clock")
                .font(.headline)
                .foregroundStyle(metric.color)
            HealthMetricCard(metric: metric, snapshot: latest)
            if metric == .sleep, let latest, !latestSleepIsComplete(latest) {
                Label("El último descanso todavía puede tener sesiones pendientes. Feli no interpreta esa duración como total definitivo.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("Feli reacciona al valor más reciente que recibió iWatch de esta categoría, con su fecha y hora. No es una medición en tiempo real.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func latestSleepIsComplete(_ snapshot: HealthSnapshot) -> Bool {
        store.day(snapshot.measuredAt, watchID: watchID)?.sleepRetrievalComplete == true
    }

    private var historicalPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Explorar histórico", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(metric.color)
                Picker("Período", selection: $period) {
                    ForEach(HealthHistoryPeriod.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                DatePicker("Consultar fecha", selection: $date,
                           in: ...Date(), displayedComponents: .date)
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Período anterior")
                    Spacer()
                    Text(title).font(.subheadline.bold())
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(dates.first == nil ||
                                  (dates.first ?? Date()) >= (period.dates(containing: Date()).first ?? Date()))
                        .accessibilityLabel("Período siguiente")
                }
                .tint(metric.color)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22))

            VStack(alignment: .leading, spacing: 7) {
                Text("Promedio de \(metric.title.lowercased())")
                    .font(.subheadline.bold())
                    .foregroundStyle(metric.color)
                Text(historyAverage.map { metric.formatted($0) } ?? "Sin datos suficientes")
                    .font(.title2.bold())
                Text("\(dailyPoints.count) día(s) con datos válidos en \(title). Feli reacciona a este promedio y cambia al modificar día, semana o mes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22))

            if metric == .sleep,
               records.contains(where: { $0.sleepMinutes != nil && $0.sleepRetrievalComplete != true }) {
                Label("Hay descansos parciales en este período. Se muestran, pero no se cuentan en el promedio ni en la reacción de Feli.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            SmartHealthChartsView(metric: metric, watchID: watchID, days: store.days,
                                  dates: dates, period: period)
            if summary != nil {
                if period == .day { dayDetail } else { dailyList }
            }
            if metric == .sleep { sleepGoal }
            Text(metric.isSample
                 ? "Promedio: primero se calcula la media de las lecturas de cada día. Cada día registrado tiene igual peso."
                 : "Promedio de los valores diarios guardados; no se suman contadores entre consultas. Los días ausentes no cuentan como cero.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var oxygenHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Oxígeno: lecturas recuperadas del Moto Watch")
                .font(.subheadline.bold())
            Text("iWatch consulta muestras ya guardadas en el reloj; no puede iniciar una medición física por Bluetooth. Si no hay valores, medí primero desde el Moto Watch y volvé a actualizar Salud.")
                .font(.caption).foregroundStyle(.secondary)
            NavigationLink {
                HealthDiagnosticsView()
            } label: {
                Label("Abrir diagnóstico de oxígeno", systemImage: "waveform.path.ecg.rectangle")
                    .font(.subheadline.bold())
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18))
    }
    @ViewBuilder private var dayDetail: some View {
        if metric == .sleep {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tus descansos").font(.headline)
                let sessions = (records.first?.sleepSessions ?? []).sorted { $0.startedAt < $1.startedAt }
                if sessions.count >= 2 {
                    Label("Descanso dividido en \(sessions.count) sesiones", systemImage: "moon.zzz")
                        .font(.subheadline.bold()).foregroundStyle(.indigo)
                    Text("El reloj registró varios bloques de descanso. La app suma solamente los minutos dormidos informados por cada sesión.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(0..<(sessions.count - 1), id: \.self) { index in
                        let gap = max(0, Int(sessions[index + 1].startedAt.timeIntervalSince(sessions[index].endedAt) / 60))
                        if gap > 0 {
                            Label("Entre la sesión \(index + 1) y la \(index + 2): \(gap) min sin sueño registrado", systemImage: "sun.max")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(sessions.reversed()) { session in
                    HStack(alignment: .top) {
                        Image(systemName: "moon.fill").foregroundStyle(metric.color)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(metric.formatted(session.minutes / 60)).bold()
                            Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) → \(session.endedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Se suman los descansos que terminan en este día, incluso si dormiste más de una vez. El tiempo entre sesiones no se suma. La duración es la informada por el reloj.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("Registros del día · \(readings.count)").font(.headline)
                ForEach(Array(readings.reversed())) { row in
                    HStack {
                        Text(row.timestamp.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)
                        Spacer(); Text(metric.formatted(row.value)).bold()
                    }.font(.subheadline)
                    Divider()
                }
            }
        }
    }
    private var dailyList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Detalle por día").font(.headline)
            ForEach(Array(dates.reversed()), id: \.self) { day in
                Button { date = day; period = .day } label: {
                    HStack {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        Spacer()
                        Text(store.day(day, watchID: watchID)?.value(for: metric).map { metric.formatted($0) } ?? "Sin datos")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(metric.color)
                    }.font(.subheadline)
                }.buttonStyle(.plain).disabled(day > Date())
                Divider()
            }
        }
    }
    private var sleepGoal: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("Objetivo diario: \(goalHours.formatted(.number.precision(.fractionLength(0...1)))) h", value: $goalHours, in: 1...16, step: 0.5)
                .font(.subheadline.bold())
            if period == .day, let value = summary {
                ProgressView(value: min(value, max(goalHours, 1)), total: max(goalHours, 1)).tint(.indigo)
                Text("\(Int((value / max(goalHours, 1) * 100).rounded())) % del objetivo").font(.caption)
            }
            Text("Objetivo configurado en esta app. El sueño se muestra en el día de despertar.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
    private func move(_ direction: Int) {
        guard let next = Calendar.current.date(byAdding: period.component, value: direction, to: date) else { return }
        date = min(next, Date())
    }
}

private struct HealthDiagnosticsView: View {
    @StateObject private var sync = HealthDashboardSync.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Consultas individuales de diagnóstico. Para consultar todas las categorías y guardarlas usá Actualizar en Salud.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HealthSyncPanel(); StressProbePanel(); VitalsProbePanel(); SleepProbePanel()
            }.padding().disabled(sync.isRunning)
        }.navigationTitle("Diagnóstico").navigationBarTitleDisplayMode(.inline)
    }
}
