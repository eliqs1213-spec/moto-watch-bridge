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
        // Varias sesiones breves separadas por despertares pueden constituir
        // la misma noche; el reloj agrupa el descanso por DÍA DE DESPERTAR.
        // Considerar el conjunto, no solo su bloque más largo.
        var byDay: [String: (bed: Int, wake: Int, duration: Double)] = [:]
        for day in days where day.watchID == watchID && day.sleepRetrievalComplete == true {
            let segments = (day.sleepSessions ?? [])
                .filter {
                    $0.endedAt <= now && $0.endedAt >= cutoff &&
                    $0.minutes >= 10 && $0.minutes <= 720 &&
                    $0.endedAt > $0.startedAt &&
                    (4...12).contains(calendar.component(.hour, from: $0.endedAt))
                }
                .sorted { $0.startedAt < $1.startedAt }
            guard let first = segments.first, let last = segments.last else { continue }
            let totalMinutes = segments.reduce(0) { $0 + $1.minutes }
            guard totalMinutes >= 180 && totalMinutes <= 720 &&
                  last.endedAt.timeIntervalSince(first.startedAt) <= 18 * 3600 else { continue }
            // Si hay una pausa muy prolongada entre bloques, podría tratarse de
            // dos descansos independientes. No inferir una rutina de acostarse.
            let longGap = zip(segments, segments.dropFirst()).contains {
                $1.startedAt.timeIntervalSince($0.endedAt) > 4 * 3600
            }
            guard !longGap else { continue }
            let bed = calendar.dateComponents([.hour, .minute], from: first.startedAt)
            let wake = calendar.dateComponents([.hour, .minute], from: last.endedAt)
            guard let bh = bed.hour, let bm = bed.minute,
                  let wh = wake.hour, let wm = wake.minute,
                  (bh >= 18 || bh <= 5), (4...12).contains(wh) else { continue }
            byDay[day.dayKey] = (bh * 60 + bm + (bh < 12 ? 1440 : 0),
                                 wh * 60 + wm, totalMinutes / 60)
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
