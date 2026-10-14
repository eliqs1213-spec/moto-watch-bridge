import Foundation
import Combine
import UIKit

@MainActor
final class WatchHealthSync: ObservableObject {
    static let shared = WatchHealthSync()
    @Published private(set) var status = "Listo para consultar pasos y pulso"
    @Published private(set) var isRunning = false
    @Published private(set) var steps: WatchHealthProtocol.StepCandidate?
    @Published private(set) var pulse: [WatchHealthProtocol.PulseCandidate] = []
    @Published private(set) var saved = false
    private var watchID = ""
    private var start = Date.distantPast
    private var end = Date.distantPast
    private var waitingForIndex = false
    private var waitingForPulse = false
    private var waitingForSteps = false
    private var requestID = UUID()
    private var deadline: Task<Void, Never>?
    private var send: ((Data) -> Bool)?
    private var clearPending: (() -> Void)?

    var canSave: Bool { !isRunning && !saved && (steps != nil || !pulse.isEmpty) }

    func begin(watchID: String, clearPending: @escaping () -> Void, send: @escaping (Data) -> Bool) {
        guard !isRunning, UIApplication.shared.applicationState == .active else { return }
        self.watchID = watchID
        self.send = send
        self.clearPending = clearPending
        steps = nil; pulse = []; saved = false
        end = Date()
        start = end.addingTimeInterval(-86400)
        isRunning = true
        waitingForIndex = true; waitingForSteps = true; waitingForPulse = false
        requestID = UUID()
        status = "Consultando pasos y las últimas 24 horas de pulso…"
        let payload: [UInt8] = [0x08] + WatchHealthProtocol.varint(UInt64(start.timeIntervalSince1970))
            + [0x10] + WatchHealthProtocol.varint(UInt64(end.timeIntervalSince1970))
        guard send(WatchHealthProtocol.encode(group: 0x30, command: 0x06)),
              send(WatchHealthProtocol.encode(group: 0x31, command: 0x06, payload: payload)) else {
            cancel(message: "Conectá el Moto Watch para consultar salud")
            return
        }
        let id = requestID
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled, let self = self, self.requestID == id, self.isRunning else { return }
            self.finish(timedOut: true)
        }
    }

    // CoreBluetooth ya reconstruye fragmentos HCI/ACL y entrega el valor ATT.
    // Aquí se comprueba el mensaje Motorola completo, incluso si su longitud
    // necesita más de un byte varint.
    func receive(_ data: Data, watchID: String) -> Bool {
        guard let frame = WatchHealthProtocol.decode(data),
              (frame.group == 0x30 && frame.command == 0x06)
                || (frame.group == 0x31 && [0x06, 0x07].contains(frame.command)) else { return false }
        guard isRunning, self.watchID == watchID else { return true }
        if frame.group == 0x30 {
            guard waitingForSteps else { return true }
            waitingForSteps = false
            if let candidate = WatchHealthProtocol.steps(frame), candidate.timestamp >= start,
               candidate.timestamp <= Date().addingTimeInterval(300) {
                steps = candidate
            }
        } else if frame.command == 0x06 {
            guard waitingForIndex else { return true }
            waitingForIndex = false
            guard let fields = WatchHealthProtocol.fields(frame.payload),
                  WatchHealthProtocol.integer(1, in: fields) == 1,
                  let cursor = WatchHealthProtocol.integer(2, in: fields),
                  Double(cursor) >= start.timeIntervalSince1970 - 1,
                  Double(cursor) <= end.timeIntervalSince1970 else {
                finishIfReady()
                return true
            }
            // Reproduce la petición 31/07 observada. No envía confirmaciones
            // de borrado/avance de cursor ni realiza paginación no validada.
            let payload: [UInt8] = [0x08, 0x01, 0x10] + WatchHealthProtocol.varint(cursor)
            waitingForPulse = send?(WatchHealthProtocol.encode(group: 0x31, command: 0x07, payload: payload)) ?? false
        } else {
            guard waitingForPulse else { return true }
            guard let candidates = WatchHealthProtocol.pulse(frame, start: start.addingTimeInterval(-1), end: end) else {
                status = "Respuesta de pulso no válida; esperando hasta finalizar la consulta"
                return true
            }
            waitingForPulse = false
            var byTime: [Date: WatchHealthProtocol.PulseCandidate] = [:]
            for candidate in candidates { byTime[candidate.timestamp] = candidate }
            pulse = byTime.values.sorted { $0.timestamp < $1.timestamp }
        }
        finishIfReady()
        return true
    }

    func cancel(message: String = "Consulta interrumpida por desconexión del reloj") {
        clearPending?(); clearPending = nil
        deadline?.cancel(); deadline = nil
        isRunning = false; waitingForIndex = false; waitingForPulse = false; waitingForSteps = false
        steps = nil; pulse = []; saved = false; send = nil
        status = message
        requestID = UUID()
    }
    private func finishIfReady() {
        if !waitingForIndex && !waitingForPulse && !waitingForSteps { finish(timedOut: false) }
    }
    private func finish(timedOut: Bool) {
        clearPending?(); clearPending = nil
        deadline?.cancel(); deadline = nil
        isRunning = false; send = nil
        waitingForIndex = false; waitingForPulse = false; waitingForSteps = false
        if steps == nil && pulse.isEmpty {
            status = timedOut ? "Sin respuesta válida a tiempo. Podés volver a consultar."
                : "El reloj no entregó pasos o pulso para esta consulta"
        } else {
            status = timedOut ? "Consulta parcial: hay lecturas experimentales disponibles"
                : "Lecturas recibidas; interpretación pendiente de comprobar con el reloj"
        }
    }
    func saveExperimentalHistory() {
        guard canSave else { return }
        do {
            try WatchHealthStore.shared.mergeExperimental(watchID: watchID, steps: steps, pulse: pulse)
            saved = true
            status = "Lecturas guardadas como experimentales en el histórico"
        } catch {
            status = "No se pudieron guardar las lecturas. Podés reintentar."
        }
    }
}

