import Foundation

/// Interpretaciones descriptivas; nunca un diagnóstico ni una evaluación médica.
struct WatchHealthInsight {
    let title: String
    let message: String
    let coverage: String
    let mood: FeliMood
}

enum HealthInsights {
    /// La pestaña de una métrica interpreta únicamente su última lectura real.
    /// Nunca confunde la media de varias muestras con el valor más reciente.
    static func latest(metric: HealthMetric, snapshot: HealthSnapshot?,
                       sleepComplete: Bool = true) -> WatchHealthInsight {
        guard let snapshot, snapshot.value.isFinite else {
            return WatchHealthInsight(title: "Feli espera una lectura",
                                      message: "Todavía no hay una medición guardada de \(metric.title.lowercased()).",
                                      coverage: "Sin registro recuperado del Moto Watch.", mood: .curious)
        }
        let value = snapshot.value
        let time = snapshot.measuredAt.formatted(date: .abbreviated, time: .shortened)
        let coverage = "Último registro real: \(time). No es una lectura continua."
        if metric == .sleep && !sleepComplete {
            return WatchHealthInsight(
                title: "Sueño aún incompleto",
                message: "Por ahora se recuperaron \(metric.formatted(value)). Feli espera más sesiones antes de sacar conclusiones.",
                coverage: "Último registro: \(time). Todavía no está comprobado contra el total que muestra el reloj.",
                mood: .curious)
        }
        let result = reaction(metric: metric, value: value)
        return WatchHealthInsight(
            title: "Última lectura · \(metric.title)",
            message: "\(metric.formatted(value)). \(result.message)",
            coverage: coverage,
            mood: result.mood)
    }

    /// Histórico: se usa el promedio de UN valor por día registrado. No se
    /// ponderan los días con más muestras, no se suman pasos entre consultas y
    /// las noches de sueño marcadas como parciales quedan fuera.
    static func historical(metric: HealthMetric, average: Double?,
                           recordedDays: Int, periodLabel: String) -> WatchHealthInsight {
        guard let average, average.isFinite, recordedDays > 0 else {
            return WatchHealthInsight(
                title: "Sin promedio para \(periodLabel)",
                message: "Feli necesita mediciones reales del período seleccionado para reaccionar.",
                coverage: "0 días con datos válidos. Días sin datos no equivalen a cero.",
                mood: .curious)
        }
        let result = reaction(metric: metric, value: average)
        return WatchHealthInsight(
            title: "Promedio · \(metric.title)",
            message: "\(metric.formatted(average)) · \(periodLabel). \(result.message)",
            coverage: "\(recordedDays) día(s) con registros válidos. Se promedia cada día registrado una sola vez.",
            mood: result.mood)
    }

    private static func reaction(metric: HealthMetric, value: Double) -> (mood: FeliMood, message: String) {
        switch metric {
        case .stress:
            if value >= 70 { return (.worried, "Feli está atento a la escala de estrés de Motorola; no es una evaluación clínica.") }
            if value <= 30 { return (.calm, "Feli se relaja y mira una mariposa.") }
            return (.curious, "Feli observa cómo cambia esta lectura del reloj.")
        case .sleep:
            if value < 7 { return (.sleepy, "Feli bosteza y descansa. Conviene revisar las sesiones antes de interpretar tu noche.") }
            return (.calm, "Feli descansa tranquilo. El dato describe duración, no calidad del sueño.")
        case .steps:
            if value >= 6000 { return (.active, "Feli mueve la cola y ofrece una patita.") }
            return (.curious, "Feli está atento a la actividad registrada.")
        case .activeCalories:
            if value >= 250 { return (.active, "Feli se anima y mueve la cola.") }
            return (.curious, "Feli observa la actividad que registró el reloj.")
        case .heartRate:
            return (.curious, "Feli mira la medición sin interpretar si es normal o anormal.")
        case .oxygen:
            return (.curious, "Feli observa la medición. No se interpreta como diagnóstico ni controla el sensor.")
        case .workouts:
            return (.curious, "Las sesiones de entrenamiento todavía necesitan sincronización validada.")
        }
    }

    static func weekly(days: [WatchHealthDay], watchID: String, now: Date = Date(),
                       calendar: Calendar = .current) -> WatchHealthInsight {
        guard !watchID.isEmpty else { return missing }
        let recent = rows(days: days, watchID: watchID, metric: .sleep, now: now, calendar: calendar)
        let steps = rows(days: days, watchID: watchID, metric: .steps, now: now, calendar: calendar)
        if recent.count >= 3 {
            let average = recent.map(\.value).reduce(0, +) / Double(recent.count)
            let hours = Int(average)
            let minutes = Int(((average - Double(hours)) * 60).rounded())
            return WatchHealthInsight(
                title: "Descanso de la semana",
                message: "Dormiste un promedio de \(hours) h \(minutes) min en las noches registradas. Revisá los horarios para identificar si tu rutina fue constante.",
                coverage: "\(recent.count) de 7 días con sueño · \(steps.count) de 7 con pasos",
                mood: .sleepy)
        }
        if steps.count >= 3 {
            let average = Int((steps.map(\.value).reduce(0, +) / Double(steps.count)).rounded())
            return WatchHealthInsight(
                title: "Actividad semanal",
                message: "Promedio de \(average.formatted()) pasos en los días registrados. Una caminata breve puede ayudarte a sumar movimiento a tu rutina.",
                coverage: "\(steps.count) de 7 días con pasos · el resto no se cuenta como cero",
                mood: .active)
        }
        return missing
    }

    static func metric(_ metric: HealthMetric, days: [WatchHealthDay], watchID: String,
                       now: Date = Date(), calendar: Calendar = .current) -> WatchHealthInsight {
        let current = rows(days: days, watchID: watchID, metric: metric, now: now, calendar: calendar)
        guard !current.isEmpty else {
            return WatchHealthInsight(
                title: "Feli está esperando datos",
                message: "Todavía no hay registros recientes de \(metric.title.lowercased()). Actualizá Salud cuando tengas el reloj conectado.",
                coverage: "0 de 7 días con datos", mood: .curious)
        }
        let average = current.map(\.value).reduce(0, +) / Double(current.count)
        let previousStart = calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: now)) ?? now
        let previousEnd = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        let previous = days.filter { $0.watchID == watchID &&
            (metric != .sleep || $0.sleepRetrievalComplete == true) &&
            ((DateFormatterDay.day($0.dayKey, calendar: calendar)).map { $0 >= previousStart && $0 < previousEnd } ?? false) }
            .compactMap { $0.value(for: metric) }
        let trend: String
        if previous.count >= 3 && current.count >= 3 {
            let old = previous.reduce(0, +) / Double(previous.count)
            let delta = average - old
            let tolerance = max(0.01, abs(old) * 0.03)
            trend = abs(delta) <= tolerance ? "Parecido al período anterior."
                : delta > 0 ? "Promedio mayor que el período anterior."
                : "Promedio menor que el período anterior."
        } else {
            trend = "Aún faltan días comparables para analizar la tendencia."
        }

        switch metric {
        case .sleep:
            let keys = Set(current.map { DateFormatterDay.key($0.date, calendar: calendar) })
            let dividedNights = days.filter { $0.watchID == watchID &&
                keys.contains($0.dayKey) && $0.sleepRetrievalComplete == true &&
                ($0.sleepSessions?.count ?? 0) >= 2 }.count
            let phrase = average < 7 ? "El descanso registrado fue menor a siete horas en promedio. Intentá mantener horarios regulares."
                : "Observá la constancia de tus horarios para conocer mejor tu descanso."
            let interruption = dividedNights > 0 ?
                "Hubo \(dividedNights) día(s) con varios bloques de sueño registrados; el tiempo entre sesiones no se suma." : ""
            return WatchHealthInsight(title: "Tu descanso", message: "\(phrase) \(interruption) \(trend)",
                                      coverage: "\(current.count) de 7 días con sueño completo", mood: .sleepy)
        case .stress:
            // Se utiliza la escala que comunica Motorola, no umbrales clínicos.
            let mood: FeliMood = average >= 70 ? .worried : average <= 30 ? .calm : .curious
            let intro = average >= 70 ? "La escala de estrés del reloj mostró lecturas elevadas entre las muestras disponibles."
                : average <= 30 ? "Las lecturas de la escala de estrés del reloj fueron bajas en promedio."
                : "Las lecturas de estrés del reloj variaron durante la semana."
            return WatchHealthInsight(title: "Estrés registrado",
                                      message: "\(intro) \(trend) No es una medición clínica.",
                                      coverage: "\(current.count) de 7 días con lecturas", mood: mood)
        case .steps:
            return WatchHealthInsight(title: "Tu actividad",
                                      message: "Promedio de \(Int(average.rounded()).formatted()) pasos en los días registrados. \(trend)",
                                      coverage: "\(current.count) de 7 días con pasos", mood: .active)
        case .heartRate:
            return WatchHealthInsight(title: "Ritmo cardíaco",
                                      message: "Promedio de \(Int(average.rounded())) lpm entre las mediciones guardadas. \(trend) No representa tu pulso en reposo.",
                                      coverage: "\(current.count) de 7 días con lecturas", mood: .curious)
        case .oxygen:
            return WatchHealthInsight(title: "Oxígeno registrado",
                                      message: "Promedio de \(Int(average.rounded())) % entre las lecturas disponibles. No sustituye una medición médica ni evalúa tu estado de salud.",
                                      coverage: "\(current.count) de 7 días con lecturas", mood: .curious)
        case .activeCalories:
            return WatchHealthInsight(title: "Calorías activas",
                                      message: "Promedio diario registrado: \(Int(average.rounded()).formatted()) kcal. \(trend) Son estimaciones del reloj.",
                                      coverage: "\(current.count) de 7 días con datos", mood: .active)
        case .workouts:
            return WatchHealthInsight(title: "Entrenamientos pendientes",
                                      message: "La sincronización de sesiones de entrenamiento todavía no está validada.",
                                      coverage: "Sin importar sesiones", mood: .curious)
        }
    }

    private static var missing: WatchHealthInsight {
        WatchHealthInsight(title: "Faltan registros",
                           message: "Conectá el Moto Watch y actualizá Salud para que aparezca un resumen basado en tus datos.",
                           coverage: "Sin información suficiente · no se inventan mediciones", mood: .curious)
    }

    private static func rows(days: [WatchHealthDay], watchID: String, metric: HealthMetric,
                             now: Date, calendar: Calendar) -> [(date: Date, value: Double)] {
        let first = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let limit = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return days.filter { $0.watchID == watchID &&
                             (metric != .sleep || $0.sleepRetrievalComplete == true) }
            .compactMap { day -> (date: Date, value: Double)? in
                guard let date = DateFormatterDay.day(day.dayKey, calendar: calendar),
                      date >= first && date < limit,
                      let value = day.value(for: metric) else { return nil }
                return (date, value)
            }
    }
}

private enum DateFormatterDay {
    static func key(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func day(_ key: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}
