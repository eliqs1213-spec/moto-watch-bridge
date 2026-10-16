import SwiftUI
import Charts

/// Gráficos específicos por métrica. Todo se deriva del histórico local
/// validado, sin rellenar días ausentes ni extrapolar estados de salud.
struct SmartHealthChartsView: View {
    let metric: HealthMetric
    let watchID: String
    let days: [WatchHealthDay]
    let dates: [Date]
    let period: HealthHistoryPeriod

    private var daily: [SmartDailyPoint] {
        SmartHealthChartAnalytics.dailyPoints(days: days, watchID: watchID,
                                              metric: metric, dates: dates)
    }
    private var samples: [WatchHealthReading] {
        SmartHealthChartAnalytics.samples(days: days, watchID: watchID,
                                          metric: metric, dates: dates)
    }
    private var mean: Double? { SmartHealthChartAnalytics.average(daily) }
    private var trend: SmartTrend? {
        period == .day ? nil : SmartHealthChartAnalytics.trend(
            days: days, watchID: watchID, metric: metric, dates: dates)
    }
    private var recordedDates: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return dates.filter { $0 <= today }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(chartTitle, systemImage: "chart.xyaxis.line")
                    .font(.headline).foregroundStyle(metric.color)
                Spacer()
                Text(period.rawValue).font(.caption.bold()).foregroundStyle(.secondary)
            }
            if daily.isEmpty {
                Label("No hay registros en el período elegido", systemImage: "calendar.badge.exclamationmark")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(period == .day ? "Valor del día" : "Promedio por día registrado")
                            .font(.caption).foregroundStyle(.secondary)
                        if let mean {
                            Text(metric.formatted(mean))
                                .font(.title2.bold()).foregroundStyle(metric.color)
                                .minimumScaleFactor(0.75).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Cobertura").font(.caption).foregroundStyle(.secondary)
                        Text("\(daily.count) de \(recordedDates) días")
                            .font(.subheadline.bold())
                    }
                }

                if period == .day && metric != .sleep {
                    if metric.isSample {
                        sampleScatter
                    } else {
                        counterTimeline
                    }
                } else {
                    dailyBars
                }
                if let trend {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: trend.direction == "Similar" ? "equal.circle" :
                                trend.direction == "Mayor" ? "arrow.up.right.circle" : "arrow.down.right.circle")
                            .foregroundStyle(metric.color)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Comparación con el período anterior: \(trend.direction.lowercased())")
                                .font(.subheadline.bold())
                            Text("\(metric.formatted(trend.currentAverage)) vs. \(metric.formatted(trend.previousAverage)) · \(trend.currentDays) y \(trend.previousDays) días con datos.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else if period != .day {
                    Text("Para comparar períodos se necesitan al menos tres días registrados en cada uno.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                switch metric {
                case .sleep:
                    sleepRegularity
                case .stress:
                    stressDistribution
                case .heartRate, .oxygen:
                    sampleRange
                case .steps, .activeCalories:
                    Text("Contador acumulado del reloj: se usa su último valor de cada día, no la suma de las consultas.")
                        .font(.caption).foregroundStyle(.secondary)
                case .workouts:
                    Text("Entrenamientos: todavía no hay sincronización validada.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(dataFootnote)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22))
    }

    private var chartTitle: String {
        switch metric {
        case .sleep: return "Duración y horarios de sueño"
        case .stress: return "Estrés: lecturas y distribución"
        case .heartRate: return "Pulso: evolución registrada"
        case .oxygen: return "Oxígeno: evolución registrada"
        case .steps: return "Actividad diaria"
        case .activeCalories: return "Calorías activas por día"
        case .workouts: return "Entrenamientos"
        }
    }

    private var dataFootnote: String {
        if metric.isSample {
            return "Cada punto representa una lectura. El promedio entre días calcula primero el promedio de cada día; no implica vigilancia continua."
        }
        if metric == .sleep {
            return "Sueño por día de despertar. Las barras corresponden a duraciones guardadas; los días sin datos no se completan con cero."
        }
        return "Se muestran únicamente datos recibidos del Moto Watch. Los días sin registro no se cuentan como cero."
    }

    private var dailyBars: some View {
        Chart {
            ForEach(daily) { point in
                BarMark(x: .value("Día", point.date, unit: .day),
                        y: .value(metric.title, point.value))
                    .foregroundStyle(metric.color.gradient)
                    .cornerRadius(4)
            }
            if let mean, daily.count >= 3 {
                RuleMark(y: .value("Media de días registrados", mean))
                    .foregroundStyle(metric.color.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Promedio").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 205)
        .accessibilityLabel("Gráfico de \(metric.title): \(daily.count) días con datos; barra ausente significa sin medición")
    }

    private var sampleScatter: some View {
        Chart {
            ForEach(samples) { point in
                PointMark(x: .value("Hora", point.timestamp),
                          y: .value(metric.title, point.value))
                    .symbolSize(42)
                    .foregroundStyle(metric.color)
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 205)
        .accessibilityLabel("\(samples.count) mediciones puntuales de \(metric.title) durante el día")
        .overlay(alignment: .bottomLeading) {
            if samples.count == 1 {
                Text("Una medición").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var counterTimeline: some View {
        Chart {
            ForEach(samples) { point in
                LineMark(x: .value("Hora", point.timestamp),
                         y: .value(metric.title, point.value))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(metric.color)
                PointMark(x: .value("Hora", point.timestamp),
                          y: .value(metric.title, point.value))
                    .foregroundStyle(metric.color)
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 205)
        .accessibilityLabel("Evolución de un contador diario; no se suman consultas")
    }

    @ViewBuilder private var sampleRange: some View {
        if let low = samples.map(\.value).min(),
           let high = samples.map(\.value).max() {
            HStack {
                Label("Mínimo \(metric.formatted(low))", systemImage: "arrow.down")
                Spacer(minLength: 10)
                Label("Máximo \(metric.formatted(high))", systemImage: "arrow.up")
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("\(samples.count) lecturas guardadas en este período. No son valores en reposo ni permiten diagnosticar condiciones médicas.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var stressDistribution: some View {
        let bands = SmartHealthChartAnalytics.stressBands(samples)
        if samples.count >= 3 {
            VStack(alignment: .leading, spacing: 7) {
                Text("Distribución de las muestras").font(.subheadline.bold())
                Chart {
                    ForEach(bands) { band in
                        BarMark(x: .value("Rango Motorola", band.label),
                                y: .value("Muestras", band.count))
                            .foregroundStyle(band.label == "Elevado" ? Color.orange :
                                             band.label == "Bajo" ? Color.green : Color.yellow)
                            .cornerRadius(4)
                    }
                }
                .frame(height: 123)
                .accessibilityLabel("Distribución de \(samples.count) muestras de la escala de estrés Motorola")
                Text("Bajo ≤30 · Intermedio 31–69 · Elevado ≥70. Es una clasificación visual de la escala del reloj, no un diagnóstico de estrés.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var sleepRegularity: some View {
        let timings = SmartHealthChartAnalytics.sleepTimings(days: days, watchID: watchID, dates: dates)
        if let spread = SmartHealthChartAnalytics.bedtimeVariationMinutes(timings) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Regularidad del horario de acostarte").font(.subheadline.bold())
                Chart {
                    ForEach(timings) { night in
                        PointMark(x: .value("Día", night.date, unit: .day),
                                  y: .value("Hora de dormir", night.bedtimeHour))
                            .symbolSize(75)
                            .foregroundStyle(Color.indigo)
                    }
                }
                .chartYScale(domain: 18.0...30.0)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [18.0, 21.0, 24.0, 27.0, 30.0]) { mark in
                        AxisGridLine()
                        AxisValueLabel {
                            if let value = mark.as(Double.self) {
                                Text(String(format: "%02d:00", Int(value) % 24))
                            }
                        }
                    }
                }
                .frame(height: 145)
                Text("La hora de acostarte varió \(spread) minutos entre las \(timings.count) noches principales registradas. Las siestas se excluyen de este gráfico.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Regularidad: necesitás al menos tres noches con horario principal identificado. Las siestas no definen la hora de acostarse.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Dos gráficos de portada independientes del personaje Feli, que tiene su
/// propia tarjeta discreta de Salud.
struct SmartHealthWeeklyOverview: View {
    let days: [WatchHealthDay]
    let watchID: String

    private let grid = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private var dates: [Date] { SmartHealthChartAnalytics.lastSevenDays() }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Tu semana en gráficos").font(.title3.bold())
                Spacer()
                Image(systemName: "chart.bar.xaxis").foregroundStyle(.indigo)
            }
            Text("Promedios y tendencias basados solamente en días sincronizados.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: grid, spacing: 10) {
                miniChart(metric: .sleep)
                miniChart(metric: .steps)
            }
        }
    }

    private func miniChart(metric: HealthMetric) -> some View {
        let points = SmartHealthChartAnalytics.dailyPoints(days: days, watchID: watchID,
                                                           metric: metric, dates: dates)
        let mean = SmartHealthChartAnalytics.average(points)
        return VStack(alignment: .leading, spacing: 9) {
            Label(metric.title, systemImage: metric.symbol)
                .font(.caption.bold())
                .foregroundStyle(metric.color)
            Text(mean.map { metric.formatted($0) } ?? "Sin registros")
                .font(.subheadline.bold())
                .lineLimit(2).minimumScaleFactor(0.76)
            if points.isEmpty {
                Image(systemName: "chart.bar").font(.largeTitle)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity).frame(height: 84)
            } else {
                Chart(points) { row in
                    BarMark(x: .value("Día", row.date, unit: .day),
                            y: .value(metric.title, row.value))
                        .foregroundStyle(metric.color.gradient)
                        .cornerRadius(2)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 84)
                .accessibilityLabel("\(metric.title): \(points.count) de 7 días con registro")
            }
            Text("\(points.count) de 7 días registrados")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18))
    }
}
