import Foundation
import Combine
import UIKit

@MainActor
final class WatchHealthSync: ObservableObject {
    static let shared = WatchHealthSync()
    @Published private(set) var status = "Listo para consultar pasos y ritmo cardíaco"
    @Published private(set) var isRunning = false
    @Published private(set) var steps: WatchHealthProtocol.StepCandidate?
    @Published private(set) var pulse: [WatchHealthProtocol.PulseCandidate] = []
    @Published private(set) var saved = false
    @Published private(set) var stepsDetail = "Sin consultar"
    @Published private(set) var heartRateDetail = "Sin consultar"
    @Published private(set) var diagnostics: [String] = []

    var diagnosticReport: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return (["iWatch " + version + " · diagnóstico de salud",
                 "Pasos: " + stepsDetail, "Ritmo cardíaco: " + heartRateDetail] + diagnostics).joined(separator: "\n")
    }
    private func note(_ text: String) {
        diagnostics.append(text)
        if diagnostics.count > 25 { diagnostics.removeFirst(diagnostics.count - 25) }
    }
    private var watchID = ""
    private var start = Date.distantPast
    private var end = Date.distantPast
    private var waitingForIndex = false
    private var waitingForPulse = false
    private var waitingForSteps = false
    private var requestedSelector: UInt64 = 1
    private var probeSecondSelector = false
    private var pulseCursor: UInt64 = 0
    private var secondSelectorCompleted = false
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
        diagnostics = []
        requestedSelector = 1
        probeSecondSelector = false
        pulseCursor = 0
        secondSelectorCompleted = false
        stepsDetail = "Esperando respuesta 30/06"
        heartRateDetail = "Esperando índice 31/06"
        end = Date()
        start = end.addingTimeInterval(-86400)
        isRunning = true
        waitingForIndex = true; waitingForSteps = true; waitingForPulse = false
        requestID = UUID()
        status = "Consultando pasos y las últimas 24 horas de ritmo cardíaco…"
        let payload: [UInt8] = [0x08] + WatchHealthProtocol.varint(UInt64(start.timeIntervalSince1970))
            + [0x10] + WatchHealthProtocol.varint(UInt64(end.timeIntervalSince1970))
        guard send(WatchHealthProtocol.encode(group: 0x30, command: 0x06)),
              send(WatchHealthProtocol.encode(group: 0x31, command: 0x06, payload: payload)) else {
            cancel(message: "Conectá el Moto Watch para consultar salud")
            return
        }
        note("Consultas 30/06 y 31/06 encoladas; ventana de 24 horas")
        let id = requestID
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled, let self = self, self.requestID == id, self.isRunning else { return }
            self.finish(timedOut: true)
        }
    }

    func transferProgress(received: Int, expected: Int) {
        guard isRunning, waitingForPulse else { return }
        heartRateDetail = "Recibiendo mensaje: \(received) de \(expected) bytes"
        note("31/07 fragmentado: \(received)/\(expected) bytes")
    }
    func transferRejected(_ reason: String) {
        guard isRunning, waitingForPulse else { return }
        heartRateDetail = "Reconstrucción rechazada: " + reason
        note("31/07: " + reason)
    }

    // CoreBluetooth reconstruye HCI/ACL; WatchHealthFrameAssembler reúne las
    // notificaciones ATT antes de validar el mensaje Motorola completo.
    // Aquí se comprueba el mensaje Motorola completo, incluso si su longitud
    // necesita más de un byte varint.
    func receive(_ data: Data, watchID: String) -> Bool {
        guard let route = WatchHealthProtocol.route(data),
              (route.group == 0x30 && route.command == 0x06)
                || (route.group == 0x31 && [0x06, 0x07].contains(route.command)) else { return false }
        guard isRunning, self.watchID == watchID else { return true }
        guard let frame = WatchHealthProtocol.decode(data) else {
            let message = String(format: "%02X/%02X: longitud o CRC inválido (%d bytes)", route.group, route.command, data.count)
            note(message)
            if route.group == 0x30 { stepsDetail = "Respuesta rechazada: longitud o CRC" }
            else { heartRateDetail = "Respuesta rechazada: longitud o CRC" }
            return true
        }
        note(String(format: "Respuesta %02X/%02X válida (%d bytes)", frame.group, frame.command, data.count))
        if frame.group == 0x30 {
            guard waitingForSteps else { return true }
            waitingForSteps = false
            if let candidate = WatchHealthProtocol.steps(frame), candidate.timestamp >= start,
               candidate.timestamp <= Date().addingTimeInterval(300) {
                steps = candidate
                stepsDetail = "Contador recibido y decodificado"
            } else {
                stepsDetail = "Respuesta recibida; contador o fecha no válidos"
            }
        } else if frame.command == 0x06 {
            guard waitingForIndex else { return true }
            waitingForIndex = false
            guard let fields = WatchHealthProtocol.fields(frame.payload) else {
                heartRateDetail = "Índice recibido; formato Protobuf inválido"
                note("31/06: no se pudo interpretar Protobuf")
                finishIfReady()
                return true
            }
            let flag = WatchHealthProtocol.integer(1, in: fields)
            note("31/06: indicador de registros=" + (flag.map { String($0) } ?? "ausente"))
            guard WatchHealthProtocol.canProbeFirstPulseBlock(flag) else {
                heartRateDetail = "Índice recibido; indicador de registros " + (flag.map { String($0) } ?? "ausente")
                finishIfReady()
                return true
            }
            guard let cursor = WatchHealthProtocol.integer(2, in: fields) else {
                heartRateDetail = "Índice con registros; falta cursor válido"
                note("31/06: cursor ausente o duplicado")
                finishIfReady()
                return true
            }
            guard Double(cursor) >= start.timeIntervalSince1970 - 1,
                  Double(cursor) <= end.timeIntervalSince1970 else {
                heartRateDetail = "Cursor del índice fuera de las últimas 24 horas"
                note("31/06: cursor fuera de la ventana solicitada")
                finishIfReady()
                return true
            }
            pulseCursor = cursor
            probeSecondSelector = flag == 2
            // El indicador podría representar varios bloques; no está probado.
            // Solo se sondean los selectores 1 y, si se anunció 2, el selector 2.
            // No se envían confirmaciones que avancen o borren registros.
            requestedSelector = 1
            waitingForPulse = requestPulseSelector(1)

        } else {
            guard waitingForPulse else { return true }
            guard let candidates = WatchHealthProtocol.pulse(frame, start: start.addingTimeInterval(-1), end: end, expectedSelector: requestedSelector) else {
                heartRateDetail = WatchHealthProtocol.pulseRejectionReason(frame, start: start.addingTimeInterval(-1), end: end, expectedSelector: requestedSelector)
                note("31/07 selector \(requestedSelector) rechazado: " + heartRateDetail)
                status = "Respuesta de ritmo cardíaco no válida; esperando hasta finalizar la consulta"
                return true
            }
            waitingForPulse = false
            var byTime: [Date: WatchHealthProtocol.PulseCandidate] = [:]
            for candidate in pulse { byTime[candidate.timestamp] = candidate }
            var conflicts = 0
            for candidate in candidates {
                if let previous = byTime[candidate.timestamp], previous.bpm != candidate.bpm {
                    conflicts += 1 // No sobreescribir una muestra con un selector aún no validado.
                } else { byTime[candidate.timestamp] = candidate }
            }
            if conflicts > 0 { note("Selector \(requestedSelector): \(conflicts) timestamps con valores distintos; se conserva el primero") }
            pulse = byTime.values.sorted { $0.timestamp < $1.timestamp }
            heartRateDetail = pulse.isEmpty ? "Respuesta válida; cero muestras" : "\(pulse.count) muestras decodificadas"
            note("31/07 selector \(requestedSelector): \(candidates.count) muestras; total único \(pulse.count)")
            if let latest = pulse.last {
                note("Última muestra recibida: " + latest.timestamp.formatted(date: .abbreviated, time: .standard))
            }
            if requestedSelector == 2 { secondSelectorCompleted = true }
            if requestedSelector == 1 && probeSecondSelector {
                requestedSelector = 2
                waitingForPulse = requestPulseSelector(2)
                if !waitingForPulse { note("Selector 2 no pudo consultarse; se conservan las muestras del selector 1") }
            }
        }
        finishIfReady()
        return true
    }

    private func requestPulseSelector(_ selector: UInt64) -> Bool {
        let payload: [UInt8] = [0x08] + WatchHealthProtocol.varint(selector)
            + [0x10] + WatchHealthProtocol.varint(pulseCursor)
        let enqueued = send?(WatchHealthProtocol.encode(group: 0x31, command: 0x07, payload: payload)) ?? false
        heartRateDetail = enqueued ? "Esperando muestras 31/07 selector \(selector)" : "No se pudo encolar el selector \(selector)"
        note(enqueued ? "31/07 selector \(selector) encolado con cursor válido" : "31/07 selector \(selector) no se pudo encolar")
        return enqueued
    }

    func cancel(message: String = "Consulta interrumpida por desconexión del reloj") {
        clearPending?(); clearPending = nil
        deadline?.cancel(); deadline = nil
        isRunning = false; waitingForIndex = false; waitingForPulse = false; waitingForSteps = false
        steps = nil; pulse = []; saved = false; send = nil
        status = message
        stepsDetail = message
        heartRateDetail = message
        note(message)
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
        if timedOut {
            if stepsDetail == "Esperando respuesta 30/06" { stepsDetail = "Sin respuesta 30/06 en 25 segundos" }
            if heartRateDetail == "Esperando índice 31/06" { heartRateDetail = "Sin respuesta del índice 31/06 en 25 segundos" }
            if heartRateDetail.hasPrefix("Esperando muestras 31/07") { heartRateDetail = "Sin respuesta de muestras 31/07 selector \(requestedSelector) en 25 segundos" }
            note("Consulta finalizada por timeout")
        }
        if probeSecondSelector && !secondSelectorCompleted && !pulse.isEmpty {
            note("Consulta parcial: selector 2 no completado; las muestras recibidas se conservan")
            heartRateDetail += " · \(pulse.count) muestras previas conservadas"
        }
        if steps == nil && pulse.isEmpty {
            status = timedOut ? "Sin respuesta válida a tiempo. Podés volver a consultar."
                : "El reloj no entregó pasos o pulso para esta consulta"
        } else {
            if probeSecondSelector && !secondSelectorCompleted && !pulse.isEmpty {
                status = "Ritmo cardíaco parcial: falta completar selector 2. Revisá el diagnóstico."
                return
            }
            status = pulse.isEmpty ? "Pasos recibidos; ritmo cardíaco sin muestras. Revisá el diagnóstico."
                : (steps == nil ? "Ritmo cardíaco recibido; pasos no disponibles." : "Pasos y ritmo cardíaco recibidos.")
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

