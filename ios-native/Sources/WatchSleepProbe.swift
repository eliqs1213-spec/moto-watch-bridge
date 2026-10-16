import Foundation
import Combine
import UIKit

@MainActor
final class WatchSleepProbe: ObservableObject {
    static let shared = WatchSleepProbe()
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Sin consultar"
    @Published private(set) var sessions: [WatchSleepProtocol.Session] = []
    @Published private(set) var messages: [String] = []
    @Published private(set) var requestedDay = Date()
    // Indica solo que la búsqueda temporal terminó, no que coincida con el
    // total calculado por el firmware. Una salida por timeout es incompleta.
    @Published private(set) var scanCompleted = false
    private var watchID = ""
    private var lowerBound = Date.distantPast
    private var cursor = Date.distantPast
    private var upperBound = Date.distantPast
    private var recoveringEarlier = false
    private var recoveryUpperBound = Date.distantPast
    private var waitingForIndex = false
    private var pages = 0
    private var timer: Task<Void, Never>?
    private var send: ((Data) -> Bool)?
    private var cleanup: (() -> Void)?
    var daySessions: [WatchSleepProtocol.Session] {
        sessions.filter { Calendar.current.isDate($0.endedAt, inSameDayAs: requestedDay) }
    }
    var totalMinutes: Double { daySessions.reduce(0) { $0 + $1.minutes } }
    var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return (["iWatch \(version) · diagnóstico de sueño", status] + messages).joined(separator: "\n")
    }
    private func note(_ message: String) {
        messages.append(message)
        if messages.count > 45 { messages.removeFirst(messages.count - 45) }
    }
    func begin(day: Date, watchID: String, cleanup: @escaping () -> Void, send: @escaping (Data) -> Bool) {
        guard !isRunning, !WatchHealthSync.shared.isRunning, !WatchStressProbe.shared.isRunning,
              !WatchVitalsProbe.shared.isRunning, UIApplication.shared.applicationState == .active else { return }
        self.watchID = watchID; self.cleanup = cleanup; self.send = send
        requestedDay = day; sessions = []; messages = []; pages = 0
        recoveringEarlier = false; scanCompleted = false
        let midnight = Calendar.current.startOfDay(for: day)
        lowerBound = Calendar.current.date(byAdding: .day, value: -1, to: midnight) ?? midnight
        cursor = lowerBound
        upperBound = min(Calendar.current.date(byAdding: .day, value: 1, to: midnight) ?? Date(), Date())
        guard cursor < upperBound else { finish("Fecha sin período consultable"); return }
        isRunning = true
        requestIndex()
        guard isRunning else { return }
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled, let self = self, self.isRunning else { return }
            self.finish("Consulta parcial por tiempo agotado; se conservan las sesiones recibidas")
        }
    }
    private func finishNormally() {
        scanCompleted = true
        finish(sessions.isEmpty ? "Sin sesiones compatibles en el rango consultado"
              : "Recorrido temporal finalizado: \(daySessions.count) sesiones · \(Int(totalMinutes.rounded())) min. Compará con el total del reloj.")
    }
    private func searchEarlierIfNeeded() {
        guard let first = sessions.min(by: { $0.startedAt < $1.startedAt }) else {
            finishNormally(); return
        }
        // Un firmware que devuelve primero la sesión MÁS RECIENTE provoca que
        // la paginación hacia delante omita sesiones anteriores. Intentamos
        // una búsqueda retrospectiva acotada, sin duplicar ni crear registros.
        recoveryUpperBound = first.startedAt.addingTimeInterval(-1)
        recoveringEarlier = true
        note("31/08: búsqueda retrospectiva de sesiones previas a \(first.startedAt)")
        requestIndex()
    }
    private func requestIndex() {
        guard pages < 16 else {
            finish("Consulta parcial: límite preventivo de 16 sesiones")
            return
        }
        if recoveringEarlier && recoveryUpperBound <= lowerBound {
            finishNormally(); return
        }
        if !recoveringEarlier && cursor >= upperBound {
            searchEarlierIfNeeded(); return
        }
        let start = recoveringEarlier ? lowerBound : cursor
        let end = recoveringEarlier ? recoveryUpperBound : upperBound
        guard start < end else { finishNormally(); return }
        waitingForIndex = true
        let payload: [UInt8] = [0x08] + WatchHealthProtocol.varint(UInt64(start.timeIntervalSince1970))
            + [0x10] + WatchHealthProtocol.varint(UInt64(end.timeIntervalSince1970))
        status = recoveringEarlier ? "Buscando sesiones anteriores 31/08" : "Consultando índice de sueño 31/08"
        note("31/08 encolado; modo=\(recoveringEarlier ? "anterior" : "siguiente"), inicio=\(Int(start.timeIntervalSince1970)), fin=\(Int(end.timeIntervalSince1970)), sesiones=\(sessions.count)")
        if send?(WatchHealthProtocol.encode(group: 0x31, command: 0x08, payload: payload)) != true {
            finish("No se pudo encolar el índice de sueño")
        }
    }
    func progress(received: Int, expected: Int) {
        guard isRunning, !waitingForIndex else { return }
        status = "Recibiendo sesión de sueño: \(received)/\(expected) bytes"
        note("31/09 fragmentado: \(received)/\(expected) bytes")
    }
    func rejected(_ reason: String) {
        guard isRunning else { return }
        status = "Sesión rechazada: " + reason; note(status)
    }
    func receive(_ data: Data, watchID: String) {
        guard isRunning, self.watchID == watchID, let route = WatchHealthProtocol.route(data),
              route.group == 0x31, [0x08, 0x09].contains(route.command) else { return }
        guard let frame = WatchHealthProtocol.decode(data) else {
            status = "Sueño rechazado: longitud o CRC"; note(status + " (\(data.count) bytes)"); return
        }
        note(String(format: "%02X/%02X válido (%d bytes)", frame.group, frame.command, data.count))
        if waitingForIndex {
            guard frame.command == 0x08, let fields = WatchHealthProtocol.fields(frame.payload) else { return }
            let indicator = WatchHealthProtocol.integer(1, in: fields)
            note("Indicador del índice: " + (indicator.map { String($0) } ?? "ausente"))
            guard WatchHealthProtocol.canProbeFirstPulseBlock(indicator) else {
                if let indicator = indicator, indicator != 0 {
                    finish("Consulta parcial: indicador de sueño no admitido")
                } else {
                    if recoveringEarlier { finishNormally() }
                    else { searchEarlierIfNeeded() }
                }
                return
            }
            waitingForIndex = false
            status = "Esperando sesión de sueño 31/09"
            // Lectura observada: solo selector 1, sin cursor añadido.
            if send?(WatchHealthProtocol.encode(group: 0x31, command: 0x09, payload: [0x08, 0x01])) != true {
                finish("No se pudo encolar la lectura de sueño")
            }
            return
        }
        guard frame.command == 0x09 else { return }
        guard let session = WatchSleepProtocol.decode(frame, start: lowerBound, end: upperBound) else {
            note("31/09 rechazado: fechas, duración o formato no compatibles")
            note("Estructura recibida: " + VitalsCandidateProtocol.schema(frame))
            finish("Sesión de sueño no compatible; revisá el diagnóstico")
            return
        }
        // Comprobar que el firmware respetó el rango solicitado. Si ignora el
        // tope de búsqueda retrospectiva, no fingir que recuperamos otra sesión.
        if recoveringEarlier && session.endedAt > recoveryUpperBound.addingTimeInterval(1) {
            note("Sesión recibida fuera del rango retrospectivo solicitado")
            finish("Consulta parcial: el reloj no devolvió una sesión anterior")
            return
        }
        guard (recoveringEarlier || session.endedAt >= cursor),
              !sessions.contains(where: { $0.id == session.id }) else {
            finish("Consulta parcial: el reloj repitió una sesión sin avanzar")
            return
        }
        // No sumar sesiones que se superpongan; aún no se conoce la semántica
        // de posibles revisiones o resúmenes globales del firmware.
        guard !sessions.contains(where: { $0.startedAt < session.endedAt && session.startedAt < $0.endedAt }) else {
            finish("Consulta parcial: sesiones superpuestas pendientes de interpretar")
            return
        }
        sessions.append(session)
        sessions.sort { $0.startedAt < $1.startedAt }
        pages += 1
        note("Sesión aceptada: inicio=\(Int(session.startedAt.timeIntervalSince1970)), fin=\(Int(session.endedAt.timeIntervalSince1970)), minutos=\(session.minutes); total del día=\(Int(totalMinutes.rounded())) min")
        if recoveringEarlier {
            recoveryUpperBound = session.startedAt.addingTimeInterval(-1)
        } else {
            cursor = session.endedAt.addingTimeInterval(1)
        }
        requestIndex()
    }
    func cancel() {
        guard isRunning else { return }
        finish("Consulta de sueño interrumpida por desconexión o error de escritura")
        sessions = []
    }
    private func finish(_ message: String) {
        timer?.cancel(); timer = nil
        cleanup?(); cleanup = nil; send = nil
        isRunning = false; waitingForIndex = false; status = message; note(message)
    }
}

