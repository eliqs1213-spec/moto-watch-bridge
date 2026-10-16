import Foundation

/// Punto por día con UNA agregación representativa. Nunca agrega ceros para
/// días sin registro y nunca suma un contador acumulado más de una vez.
struct SmartDailyPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct SmartSleepTiming: Identifiable {
    let date: Date
    let bedtimeHour: Double // Horario nocturno continuo: 22:30 -> 22.5; 00:30 -> 24.5
    let wakeHour: Double
    var id: Date { date }
}

struct SmartBandCount: Identifiable {
    let label: String
    let count: Int
    var id: String { label }
}

struct SmartTrend {
    let currentAverage: Double
    let previousAverage: Double
    let currentDays: Int
    let previousDays: Int
    var direction: String {
        let difference = currentAverage - previousAverage
        let tolerance = max(abs(previousAverage) * 0.03, 0.01)
        return abs(difference) <= tolerance ? "Similar" : difference > 0 ? "Mayor" : "Menor"
    }
}

/// Cálculo independiente de las vistas. Los promedios son por día registrado,
/// no por cantidad variable de muestras dentro de cada día.
enum SmartHealthChartAnalytics {
    static func dailyPoints(days: [WatchHealthDay], watchID: String,
                            metric: HealthMetric, dates: [Date],
                            calendar: Calendar = .current) -> [SmartDailyPoint] {
        let rows = Dictionary(
            days.filter { $0.watchID == watchID }.map { ($0.dayKey, $0) },
            uniquingKeysWith: { _, new in new })
        return dates.compactMap { date in
            let key = dayKey(date, calendar: calendar)
            guard let day = rows[key] else { return nil }
            // Las sesiones incompletas permanecen en el histórico, pero no
            // entran en gráficos de promedio/regularidad como noches completas.
            if metric == .sleep && day.sleepRetrievalComplete == false { return nil }
            guard let value = day.value(for: metric), value.isFinite else { return nil }
            return SmartDailyPoint(date: calendar.startOfDay(for: date), value: value)
        }
    }

    static func samples(days: [WatchHealthDay], watchID: String,
                        metric: HealthMetric, dates: [Date],
                        calendar: Calendar = .current) -> [WatchHealthReading] {
        let keys = Set(dates.map { dayKey($0, calendar: calendar) })
        return days.filter { $0.watchID == watchID && keys.contains($0.dayKey) }
            .flatMap { $0.readings(for: metric) }
            .filter { $0.value.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
    }

    static func average(_ points: [SmartDailyPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    static func previousDates(for dates: [Date], calendar: Calendar = .current) -> [Date] {
        guard let first = dates.min(), !dates.isEmpty else { return [] }
        // Un período de N fechas se compara con los N días inmediatamente previos.
        return (1...dates.count).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: first)
        }
    }

    static func trend(days: [WatchHealthDay], watchID: String, metric: HealthMetric,
                      dates: [Date], calendar: Calendar = .current) -> SmartTrend? {
        let current = dailyPoints(days: days, watchID: watchID, metric: metric, dates: dates, calendar: calendar)
        let previous = dailyPoints(days: days, watchID: watchID, metric: metric,
                                   dates: previousDates(for: dates, calendar: calendar), calendar: calendar)
        guard current.count >= 3, previous.count >= 3,
              let a = average(current), let b = average(previous) else { return nil }
        return SmartTrend(currentAverage: a, previousAverage: b,
                          currentDays: current.count, previousDays: previous.count)
    }

    /// Los umbrales pertenecen exclusivamente a la escala 0-100 del reloj,
    /// no son rangos clínicos de estrés de una persona.
    static func stressBands(_ readings: [WatchHealthReading]) -> [SmartBandCount] {
        [
            SmartBandCount(label: "Bajo", count: readings.filter { $0.value <= 30 }.count),
            SmartBandCount(label: "Intermedio", count: readings.filter { $0.value > 30 && $0.value < 70 }.count),
            SmartBandCount(label: "Elevado", count: readings.filter { $0.value >= 70 }.count)
        ]
    }

    static func sleepTimings(days: [WatchHealthDay], watchID: String,
                             dates: [Date], calendar: Calendar = .current) -> [SmartSleepTiming] {
        let keys = Set(dates.map { dayKey($0, calendar: calendar) })
        return days.filter { $0.watchID == watchID && keys.contains($0.dayKey) &&
                             dayIsVerifiedForSleepTiming($0) }
            .compactMap { day -> SmartSleepTiming? in
                // Evitar confundir siestas con el horario nocturno. Tomar
                // solamente la sesión principal de cada día de despertar.
                let overnight = (day.sleepSessions ?? []).filter { session in
                    guard session.minutes >= 180 && session.minutes <= 720,
                          session.endedAt > session.startedAt else { return false }
                    let bedtimeHour = calendar.component(.hour, from: session.startedAt)
                    let wakeHour = calendar.component(.hour, from: session.endedAt)
                    return (bedtimeHour >= 18 || bedtimeHour <= 5) && (4...12).contains(wakeHour)
                }
                guard let session = overnight.max(by: { $0.minutes < $1.minutes }),
                      let date = dateFromKey(day.dayKey, calendar: calendar) else { return nil }
                let bedtime = calendar.dateComponents([.hour, .minute], from: session.startedAt)
                let wake = calendar.dateComponents([.hour, .minute], from: session.endedAt)
                guard let bHour = bedtime.hour, let bMinute = bedtime.minute,
                      let wHour = wake.hour, let wMinute = wake.minute else { return nil }
                let bedtimeContinuous = Double(bHour + (bHour < 12 ? 24 : 0)) + Double(bMinute) / 60
                let wakeClock = Double(wHour) + Double(wMinute) / 60
                return SmartSleepTiming(date: date, bedtimeHour: bedtimeContinuous, wakeHour: wakeClock)
            }
            .sorted { $0.date < $1.date }
    }

    private static func dayIsVerifiedForSleepTiming(_ day: WatchHealthDay) -> Bool {
        // Consultas anteriores no incluían una bandera de completitud; no
        // conviene deducir horarios de ayuno de una noche posiblemente parcial.
        day.sleepRetrievalComplete == true
    }

    static func bedtimeVariationMinutes(_ timings: [SmartSleepTiming]) -> Int? {
        guard timings.count >= 3,
              let earliest = timings.map(\.bedtimeHour).min(),
              let latest = timings.map(\.bedtimeHour).max() else { return nil }
        return Int(((latest - earliest) * 60).rounded())
    }

    static func lastSevenDays(ending date: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: date)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func dateFromKey(_ key: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}
