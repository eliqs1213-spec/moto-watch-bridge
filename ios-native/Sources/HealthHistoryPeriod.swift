import Foundation

enum HealthHistoryPeriod: String, CaseIterable {
    case day = "Día", week = "Semana", month = "Mes"
    var component: Calendar.Component {
        switch self { case .day: return .day; case .week: return .weekOfYear; case .month: return .month }
    }
    func dates(containing date: Date, calendar input: Calendar = .current) -> [Date] {
        var calendar = input; calendar.firstWeekday = 2
        guard let interval = calendar.dateInterval(of: component, for: date) else { return [calendar.startOfDay(for: date)] }
        var result: [Date] = []; var cursor = interval.start
        while cursor < interval.end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return result
    }
}
