import SwiftUI

/// Ayuno voluntario. El horario se adapta a la rutina de sueño registrada,
/// pero la duración NO se prescribe usando sensores del reloj.
struct FastingView: View {
    @EnvironmentObject private var watch: WatchBLEManager
    @StateObject private var fasting = FastingStore.shared
    @StateObject private var reminders = FastingReminderManager.shared
    @StateObject private var health = WatchHealthStore.shared
    @AppStorage("iwatch.fasting.duration.hours") private var duration = 12
    @AppStorage("iwatch.fasting.start.minutes") private var startMinutes = 20 * 60
    @AppStorage("iwatch.fasting.reminders.enabled") private var remindersEnabled = false

    private var sleepSuggestion: SleepScheduleSuggestion? {
        let id = watch.healthWatchID ?? health.watchIDs.last ?? ""
        return SleepScheduleAdvisor.suggest(days: health.days, watchID: id)
    }
    private var nextPlannedStart: Date {
        let components = DateComponents(hour: startMinutes / 60, minute: startMinutes % 60)
        return Calendar.current.nextDate(after: Date(), matching: components,
                                         matchingPolicy: .nextTime) ??
            Date().addingTimeInterval(86400)
    }
    private var nextPlannedEnd: Date {
        nextPlannedStart.addingTimeInterval(Double(duration) * 3600)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Ayuno").font(.largeTitle.bold())
                        Text("Organizá tus horarios de manera flexible.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    timerCard
                    scheduleCard
                    recommendationCard
                    notificationsCard
                    historyCard
                    Text("El sueño orienta el horario, no la duración del ayuno. Podés terminar cuando quieras. Si tenés alguna condición médica, tomás medicación que requiere comida, estás embarazada o tenés antecedentes de trastornos alimentarios, consultá antes de ayunar.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Ayuno").navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: remindersEnabled) { _ in configureReminders() }
        .onChange(of: duration) { _ in configureReminders() }
        .onChange(of: startMinutes) { _ in configureReminders() }
        .onAppear { if remindersEnabled { configureReminders() } }
    }

    private var timerCard: some View {
        VStack(spacing: 14) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let active = fasting.active
                let elapsed = active.map { max(0, timeline.date.timeIntervalSince($0.startedAt)) } ?? 0
                let target = active.map { max(1, $0.targetEndAt.timeIntervalSince($0.startedAt)) } ?? Double(duration * 3600)
                let fraction = min(1, elapsed / target)
                ZStack {
                    Circle().stroke(Color.orange.opacity(0.12), lineWidth: 13)
                    Circle().trim(from: 0, to: CGFloat(fraction))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 7) {
                        Text(active == nil ? "Sin sesión activa" : elapsed >= target ? "Objetivo de tiempo alcanzado" : "Ayuno en curso")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(Self.elapsedString(elapsed))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.8).lineLimit(1)
                        Text("Objetivo: \(active?.durationHours ?? duration) h")
                            .font(.subheadline.bold()).foregroundStyle(.orange)
                    }
                }
                .frame(width: 222, height: 222)
                if let active {
                    Text("Inicio real: \(active.startedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Fin previsto: \(active.targetEndAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if fasting.active == nil {
                Button {
                    fasting.start(hours: duration, plannedStart: nextPlannedStart)
                    if remindersEnabled, let session = fasting.active {
                        reminders.schedule(start: session.startedAt, end: session.targetEndAt, includeStart: false)
                    }
                } label: {
                    Label("Iniciar ayuno ahora", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(.orange)
            } else {
                Button {
                    fasting.finish()
                    if remindersEnabled { configureReminders() }
                    else { reminders.cancel() }
                } label: {
                    Label("Cortar ayuno y guardar hora real", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(.orange)
            }
            Text(fasting.status).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 24))
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Mi horario", systemImage: "clock").font(.headline)
            Stepper("Duración elegida: \(duration) horas", value: $duration, in: 8...18, step: 1)
                .font(.subheadline)
            DatePicker("Inicio previsto", selection: Binding(
                get: {
                    Calendar.current.startOfDay(for: Date())
                        .addingTimeInterval(TimeInterval(startMinutes * 60))
                },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    startMinutes = (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
                }
            ), displayedComponents: .hourAndMinute)
            .font(.subheadline)
            HStack {
                Text("Fin previsto").foregroundStyle(.secondary)
                Spacer()
                Text(nextPlannedEnd.formatted(date: .abbreviated, time: .shortened)).bold()
            }.font(.subheadline)
            Text("El reloj no comienza ni detiene sesiones automáticamente: solo registra tus acciones.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16).background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 20))
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sugerencia según tu sueño", systemImage: "moon.stars.fill")
                .font(.headline).foregroundStyle(.indigo)
            if let suggested = sleepSuggestion {
                let window = suggested.suggestedWindow(fastingHours: duration)
                Text("En \(suggested.nights) noches de las últimas dos semanas, el reloj registró un descanso medio de \(String(format: "%.1f", suggested.meanSleepHours)) h.")
                    .font(.subheadline)
                Text("Hora habitual aproximada de dormir: \(SleepScheduleSuggestion.clock(suggested.typicalBedtimeMinutes)). Despertar: \(SleepScheduleSuggestion.clock(suggested.typicalWakeMinutes)).")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Para la duración que elegiste, podrías comenzar a las \(SleepScheduleSuggestion.clock(window.start)) y terminar a las \(SleepScheduleSuggestion.clock(window.end)).")
                    .font(.subheadline)
                Button("Usar horario sugerido") { startMinutes = window.start }
                    .buttonStyle(.bordered).tint(.indigo)
                Text("Es una propuesta de horario, no una recomendación médica de ayunar \(duration) horas.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Todavía faltan al menos tres noches completas y recientes para estimar tus horarios habituales. Podés configurar el ayuno manualmente.")
                    .font(.subheadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recordatorios de inicio y fin", systemImage: "bell")
                .font(.headline)
            Toggle("Notificaciones locales", isOn: $remindersEnabled)
                .tint(.orange)
            Text("Al activarlas, iOS avisará a la hora prevista de comienzo y finalización. Cuando inicies una sesión real, el aviso de fin se ajustará al inicio registrado.")
                .font(.caption).foregroundStyle(.secondary)
            Text(reminders.status).font(.caption2).foregroundStyle(.secondary)
        }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground),
                                 in: RoundedRectangle(cornerRadius: 20))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Últimas sesiones", systemImage: "calendar")
                .font(.headline)
            if fasting.sessions.isEmpty {
                Text("Todavía no registraste ayunos.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(fasting.sessions.prefix(6))) { session in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Inicio real: \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline.bold())
                        Text("Fin previsto: \(session.targetEndAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(session.endedAt.map { "Corte real: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "En curso · todavía sin corte real")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if session.id != fasting.sessions.prefix(6).last?.id { Divider() }
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20))
    }

    private func configureReminders() {
        guard remindersEnabled else { reminders.cancel(); return }
        if let active = fasting.active {
            reminders.schedule(start: active.startedAt, end: active.targetEndAt, includeStart: false)
        } else {
            reminders.schedule(start: nextPlannedStart, end: nextPlannedEnd)
        }
    }

    private static func elapsedString(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}
