import Foundation

// A fixture written with exactly the fields used before 0.8.4.
struct LegacyDay: Encodable {
    let watchID: String; let dayKey: String; let steps: Int?; let sleepMinutes: Double?
    let heartRate: [WatchHealthReading]; let stress: [WatchHealthReading]; let workouts: [WatchWorkout]
    let workoutsComplete: Bool; let syncedAt: Date
    let stepsExperimental: Bool?; let heartRateExperimental: Bool?; let stepsMeasuredAt: Date?
}

try await MainActor.run {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("health-store-checks-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("history-v1.json")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
    let key = WatchHealthStore.key(date)
    let pulse = WatchHealthReading(id: "31/07:\(Int64(date.timeIntervalSince1970))", timestamp: date, value: 86)
    let legacy = LegacyDay(watchID: "watch-a", dayKey: key, steps: 1885, sleepMinutes: nil,
        heartRate: [pulse], stress: [], workouts: [], workoutsComplete: false, syncedAt: date,
        stepsExperimental: true, heartRateExperimental: true, stepsMeasuredAt: date)
    try JSONEncoder().encode([legacy]).write(to: file)
    let store = WatchHealthStore(fileURL: file)
    expect(store.day(date, watchID: "watch-a")?.steps == 1885, "Legacy steps lost")
    try store.mergeCounter(watchID: "watch-a", metric: .steps, value: 1885, at: date)
    expect(store.day(date, watchID: "watch-a")?.stepsHistory?.count == 1, "Legacy snapshot duplicated")
    try store.mergeCounter(watchID: "watch-a", metric: .steps, value: 2190, at: date.addingTimeInterval(3600))
    try store.mergeCounter(watchID: "watch-a", metric: .steps, value: 1500, at: date.addingTimeInterval(-3600))
    expect(store.day(date, watchID: "watch-a")?.steps == 2190, "Out-of-order steps rolled back daily counter")
    try store.mergeReadings(watchID: "watch-a", metric: .heartRate, readings: [pulse, pulse])
    expect(store.day(date, watchID: "watch-a")?.heartRate.count == 1, "Pulse resync duplicated")
    try store.mergeReadings(watchID: "watch-a", metric: .oxygen, readings: [WatchHealthReading(id: "oxygen-a", timestamp: date, value: 96)])
    try store.mergeReadings(watchID: "watch-a", metric: .stress, readings: [WatchHealthReading(id: "stress-a", timestamp: date, value: 59)])
    try store.mergeCounter(watchID: "watch-a", metric: .activeCalories, value: 967, at: date)
    try store.mergeCounter(watchID: "watch-a", metric: .activeCalories, value: 967, at: date)
    expect(store.day(date, watchID: "watch-a")?.activeCaloriesHistory?.count == 1, "Calories resync duplicated")
    let first = WatchSleepProtocol.Session(startedAt: date.addingTimeInterval(-20000), endedAt: date.addingTimeInterval(-10000), minutes: 180)
    let second = WatchSleepProtocol.Session(startedAt: date.addingTimeInterval(-6000), endedAt: date.addingTimeInterval(-1000), minutes: 77)
    try store.mergeSleep(watchID: "watch-a", sessions: [first, second])
    try store.mergeSleep(watchID: "watch-a", sessions: [first])
    expect(store.day(date, watchID: "watch-a")?.sleepMinutes == 257, "Sleep total must be 4h17 across two sessions without duplication")
    expect(store.day(date, watchID: "watch-a")?.sleepSessions?.count == 2, "Separate sleep sessions lost")
    // Caso observado en dispositivo: el reloj muestra 4h08, pero la app solo
    // recibe una sesión de 2h59. No hay que inventar los 69 min faltantes.
    let otherDay = date.addingTimeInterval(-86400)
    let partial = WatchSleepProtocol.Session(
        startedAt: otherDay.addingTimeInterval(-28800),
        endedAt: otherDay.addingTimeInterval(-18000), minutes: 179)
    let recovered = WatchSleepProtocol.Session(
        startedAt: otherDay.addingTimeInterval(-14400),
        endedAt: otherDay.addingTimeInterval(-10260), minutes: 69)
    try store.mergeSleep(watchID: "watch-a", sessions: [partial], retrievalComplete: false)
    expect(store.day(otherDay, watchID: "watch-a")?.sleepMinutes == 179,
           "Partial sleep must not be automatically inflated to 248 min")
    expect(store.day(otherDay, watchID: "watch-a")?.sleepRetrievalComplete == false,
           "Partial retrieval must be labeled incomplete")
    try store.mergeSleep(watchID: "watch-a", sessions: [recovered], retrievalComplete: true)
    expect(store.day(otherDay, watchID: "watch-a")?.sleepMinutes == 248,
           "2h59 + recovered 1h09 must equal 4h08")
    expect(store.day(otherDay, watchID: "watch-a")?.sleepRetrievalComplete == true,
           "Completed retrieval should mark the day as verified")
    try store.mergeSleep(watchID: "watch-a", sessions: [recovered], retrievalComplete: true)
    expect(store.day(otherDay, watchID: "watch-a")?.sleepMinutes == 248,
           "Resync must not duplicate a recovered session")
    // Regresión confirmada en iPhone: el firmware primero comunica una
    // sesión parcial 179 min, y más tarde una sesión envolvente total 248 min.
    // NO son 2 sesiones independientes: guardar 427 min sería incorrecto.
    let rollingDay = date.addingTimeInterval(-2 * 86400)
    let rollingStart = rollingDay.addingTimeInterval(-20000)
    let initial179 = WatchSleepProtocol.Session(
        startedAt: rollingStart,
        endedAt: rollingStart.addingTimeInterval(3 * 3600), minutes: 179)
    let final248 = WatchSleepProtocol.Session(
        startedAt: rollingStart,
        endedAt: rollingStart.addingTimeInterval(4 * 3600 + 20 * 60), minutes: 248)
    try store.mergeSleep(watchID: "watch-a", sessions: [initial179], retrievalComplete: false)
    expect(store.day(rollingDay, watchID: "watch-a")?.sleepMinutes == 179,
           "Initial partial sleep should keep 179min")
    try store.mergeSleep(watchID: "watch-a", sessions: [final248], retrievalComplete: true)
    expect(store.day(rollingDay, watchID: "watch-a")?.sleepMinutes == 248,
           "Official 248min rollup must REPLACE overlapping 179min")
    expect(store.day(rollingDay, watchID: "watch-a")?.sleepSessions?.count == 1,
           "Superseded 179min sample must not be double-counted")
    expect(store.day(rollingDay, watchID: "watch-a")?.sleepRetrievalComplete == true,
           "Completed 248min retrieval should unlock the graph")
    try store.mergeSleep(watchID: "watch-a", sessions: [initial179], retrievalComplete: false)
    expect(store.day(rollingDay, watchID: "watch-a")?.sleepMinutes == 248,
           "Stale shorter retry must not downgrade the new 248min total")
    expect(store.day(rollingDay, watchID: "watch-a")?.sleepRetrievalComplete == true,
           "A stale partial retry must not reset a completed retrieval")
    let stored = store.latest(.sleep, watchID: "watch-a", dates: [rollingDay])
    expect(stored != nil && Int((stored!.value * 60).rounded()) == 248,
           "The Health screen must read the persisted 248min, not the old 179min")

    try store.mergeCounter(watchID: "watch-b", metric: .steps, value: 50, at: date)
    expect(store.day(date, watchID: "watch-a")?.steps == 2190, "Histories from different watches mixed")
    let reopened = WatchHealthStore(fileURL: file)
    expect(reopened.latest(.heartRate, watchID: "watch-a")?.value == 86, "Latest pulse lost after reload")
    expect(reopened.latest(.oxygen, watchID: "watch-a")?.value == 96, "Oxygen lost after reload")
    expect(reopened.latest(.stress, watchID: "watch-a")?.value == 59, "Stress lost after reload")
    expect(reopened.latest(.activeCalories, watchID: "watch-a")?.value == 967, "Calories lost after reload")
    expect(reopened.day(date, watchID: "watch-a")?.sleepMinutes == 257, "Sleep lost after reload")
    expect(reopened.latest(.heartRate, watchID: "watch-a")?.measuredAt == date, "Synchronization changed measurement timestamp")
    do {
        try store.mergeReadings(watchID: "watch-a", metric: .oxygen, readings: [WatchHealthReading(id: "invalid", timestamp: date, value: .nan)])
        fatalError("Nonfinite oxygen accepted")
    } catch WatchHealthStore.StoreError.invalidReading { }
    let overlap = WatchSleepProtocol.Session(startedAt: first.startedAt.addingTimeInterval(60), endedAt: first.endedAt.addingTimeInterval(600), minutes: 30)
    do { try store.mergeSleep(watchID: "watch-a", sessions: [overlap]); fatalError("Overlapping sleep accepted") }
    catch WatchHealthStore.StoreError.overlappingSleep { }
    expect(store.day(date, watchID: "watch-a")?.sleepMinutes == 257, "Rejected sleep changed persisted data")
    let corrupt = directory.appendingPathComponent("corrupt.json")
    let original = Data("broken-history".utf8); try original.write(to: corrupt)
    let broken = WatchHealthStore(fileURL: corrupt)
    expect(broken.storageDiagnostic?.contains("Formato o fecha inválidos") == true,
           "Unreadable JSON must provide a safe, actionable diagnostic")
    do { try broken.mergeCounter(watchID: "a", metric: .steps, value: 1, at: date); fatalError("Unreadable history overwritten") }
    catch WatchHealthStore.StoreError.unreadableHistory { }
    let preserved = try Data(contentsOf: corrupt)
    expect(preserved == original, "Unreadable history not preserved")
    expect(!broken.retryLoadAfterUnlockIfNeeded(), "Corrupt history must not be treated as recovered")
    try JSONEncoder().encode([legacy]).write(to: corrupt, options: .atomic)
    expect(broken.retryLoadAfterUnlockIfNeeded(), "Retry should recover after valid history becomes readable")
    expect(broken.storageError == nil, "Recovery should clear transient storage warning")
    expect(broken.day(date, watchID: "watch-a")?.steps == 1885,
           "Recovery should restore stored records")

    let leap = calendar.date(from: DateComponents(year: 2024, month: 2, day: 15))!
    let common = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))!
    expect(HealthHistoryPeriod.month.dates(containing: leap, calendar: calendar).count == 29, "Leap month length incorrect")
    expect(HealthHistoryPeriod.month.dates(containing: common, calendar: calendar).count == 28, "February length incorrect")
    expect(HealthHistoryPeriod.month.dates(containing: date, calendar: calendar).count == 31, "October length incorrect")
    let week = HealthHistoryPeriod.week.dates(containing: date, calendar: calendar)
    expect(week.count == 7 && calendar.component(.weekday, from: week[0]) == 2, "Week must begin on Monday")
}
print("History checks passed: legacy migration, persistence, deduplication, daily counters, two sleeps, watch isolation, invalid data and calendar periods")
