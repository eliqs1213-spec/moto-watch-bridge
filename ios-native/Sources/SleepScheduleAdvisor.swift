import Foundation

/// Orientación horaria, no prescripción nutricional. Solo se deducen horas de
/// sueño de sesiones validadas. Nunca se infiere una duración de ayuno óptima.
struct SleepScheduleSuggestion {
    let nights: Int
    let typicalBedtimeMinutes: Int
    let typicalWakeMinutes: Int
    let meanSleepHours: Double

    func suggestedWindow(fastingHours: Int) -> (start: Int, end: Int) {
        // Terminar una hora después del despertar habitual. El usuario puede
        // mover este horario y elegir la duración; no se auto-inicia un ayuno.
        let end = (typicalWakeMinutes + 60) % 1440
        let start = (end - fastingHours * 60 + 1440 * 2) % 1440
        return (start, end)
    }

    static func clock(_ minutes: Int) -> String {
        let value = (minutes % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

enum SleepScheduleAdvisor {
    static func suggest(days: [WatchHealthDay], watchID: String,
                        now: Date = Date(), calendar: Calendar = .current) -> SleepScheduleSuggestion? {
        let cutoff = now.addingTimeInterval(-14 * 86400)
        // La siesta y los fragmentos cortos NO determinan el horario habitual.
        let candidates = days.filter { $0.watchID == watchID && $0.sleepRetrievalComplete == true }
            .flatMap { $0.sleepSessions ?? [] }
            .filter { $0.endedAt <= now && $0.endedAt >= cutoff &&
                      $0.minutes >= 180 && $0.minutes <= 720 }
            .compactMap { session -> (day: Date, bed: Int, wake: Int, duration: Double)? in
                let bed = calendar.dateComponents([.hour, .minute], from: session.startedAt)
                let wake = calendar.dateComponents([.hour, .minute], from: session.endedAt)
                guard let bh = bed.hour, let bm = bed.minute,
                      let wh = wake.hour, let wm = wake.minute,
                      (bh >= 18 || bh <= 5), (4...12).contains(wh) else { return nil }
                let bedtime = bh * 60 + bm + (bh < 12 ? 1440 : 0)
                return (calendar.startOfDay(for: session.endedAt), bedtime,
                        wh * 60 + wm, session.minutes / 60)
            }
        // Una sola noche puede tener varios segmentos: conservar la sesión
        // nocturna de mayor duración, sin contarla varias veces.
        var byDay: [Date: (bed: Int, wake: Int, duration: Double)] = [:]
        for item in candidates {
            if item.duration > (byDay[item.day]?.duration ?? 0) {
                byDay[item.day] = (item.bed, item.wake, item.duration)
            }
        }
        let rows = Array(byDay.values)
        guard rows.count >= 3 else { return nil }
        return SleepScheduleSuggestion(
            nights: rows.count,
            typicalBedtimeMinutes: Int((Double(rows.map(\.bed).reduce(0, +)) / Double(rows.count)).rounded()) % 1440,
            typicalWakeMinutes: Int((Double(rows.map(\.wake).reduce(0, +)) / Double(rows.count)).rounded()) % 1440,
            meanSleepHours: rows.map(\.duration).reduce(0, +) / Double(rows.count))
    }
}
