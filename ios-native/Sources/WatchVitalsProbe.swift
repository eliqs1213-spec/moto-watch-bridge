import Foundation
import Combine
import UIKit

@MainActor
final class WatchVitalsProbe: ObservableObject {
    enum Mode: Equatable { case oxygen, calories }
    static let shared = WatchVitalsProbe()
    @Published private(set) var isRunning = false
    @Published private(set) var mode: Mode?
    @Published private(set) var status = "Sin consultar"
    @Published private(set) var readings: [VitalsCandidateProtocol.Reading] = []
    @Published private(set) var counters: [VitalsCandidateProtocol.Counter] = []
    @Published private(set) var counterTime: Date?
    @Published private(set) var messages: [String] = []
    private var watchID = ""
    private var start = Date.distantPast
    private var end = Date.distantPast
    private var channel = 0
    private var selector: UInt64 = 1
    private var trySecond = false
    private var cursor: UInt64 = 0
    private var waitingForIndex = false
    private var timer: Task<Void, Never>?
    private var send: ((Data) -> Bool)?
    private var cleanup: (() -> Void)?

    var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return (["iWatch \(version) · diagnóstico candidatos de oxígeno/calorías", status] + messages).joined(separator: "\n")
    }
    private func note(_ message: String) {
        messages.append(message)
        if messages.count > 45 { messages.removeFirst(messages.count - 45) }
    }
    func begin(mode: Mode, watchID: String, cleanup: @escaping () -> Void, send: @escaping (Data) -> Bool) {
        guard !isRunning, !WatchHealthSync.shared.isRunning, !WatchStressProbe.shared.isRunning,
              UIApplication.shared.applicationState == .active else { return }
        self.mode = mode; self.watchID = watchID; self.cleanup = cleanup; self.send = send
        readings = []; counters = []; counterTime = nil; messages = []
        end = Date(); start = end.addingTimeInterval(-86400)
        channel = 0; selector = 1; trySecond = false; isRunning = true
        if mode == .calories {
            waitingForIndex = false
            status = "Consultando contadores candidatos a calorías"
            guard send(WatchHealthProtocol.encode(group: 0x30, command: 0x06)) else { finish("No se pudo encolar la consulta"); return }
            note("Consulta 30/06 encolada; campo 9 validado como calorías activas, campo 3 sin identificar")
        } else { requestIndex() }
        guard isRunning else { return }
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled, let self = self, self.isRunning else { return }
            self.finish("Tiempo agotado: " + self.status + " · se conservan los candidatos recibidos")
        }
    }
    private var indexCommand: UInt8 { channel == 0 ? 0x0B : 0x11 }
    private var dataCommand: UInt8 { channel == 0 ? 0x0C : 0x12 }
    private func requestIndex() {
        waitingForIndex = true; selector = 1; trySecond = false
        // 31/0B usa la consulta selector/fecha observada; 31/11 usa rango.
        let payload: [UInt8] = channel == 0
            ? [0x08, 0x01, 0x10] + WatchHealthProtocol.varint(UInt64(end.timeIntervalSince1970))
            : [0x08] + WatchHealthProtocol.varint(UInt64(start.timeIntervalSince1970)) + [0x10] + WatchHealthProtocol.varint(UInt64(end.timeIntervalSince1970))
        status = "Esperando índice candidato " + String(format: "31/%02X", indexCommand)
        note(status)
        if send?(WatchHealthProtocol.encode(group: 0x31, command: indexCommand, payload: payload)) != true {
            finish("No se pudo encolar el índice candidato")
        }
    }
    private func requestSamples() {
        let payload: [UInt8] = [0x08] + WatchHealthProtocol.varint(selector) + [0x10] + WatchHealthProtocol.varint(cursor)
        status = String(format: "Esperando candidato 31/%02X selector %d", dataCommand, Int(selector))
        note(status)
        if channel == 0 { note("Lectura 31/0C inferida por pareja de comandos; categoría y formato no confirmados") }
        if send?(WatchHealthProtocol.encode(group: 0x31, command: dataCommand, payload: payload)) != true {
            finish("No se pudo encolar la lectura candidata")
        }
    }
    private func nextChannel() {
        if channel == 0 { channel = 1; requestIndex() }
        else { finish(readings.isEmpty ? "Sin muestras candidatas. Revisá el diagnóstico." : "Lecturas candidatas recibidas; compará valor y hora con el reloj.") }
    }
    func progress(received: Int, expected: Int) {
        guard isRunning, mode == .oxygen, !waitingForIndex else { return }
        status = "Recibiendo candidato: \(received)/\(expected) bytes"
        note(status)
    }
    func rejected(_ reason: String) {
        guard isRunning else { return }
        status = "Reconstrucción rechazada: " + reason; note(status)
    }
    func receive(_ data: Data, watchID: String) {
        guard isRunning, self.watchID == watchID, let route = WatchHealthProtocol.route(data) else { return }
        let relevant = mode == .calories ? (route.group == 0x30 && route.command == 0x06)
            : (route.group == 0x31 && [indexCommand, dataCommand].contains(route.command))
        guard relevant else { return }
        guard let frame = WatchHealthProtocol.decode(data) else {
            status = "Respuesta rechazada: longitud o CRC"; note(status + " (\(data.count) bytes)"); return
        }
        note(String(format: "%02X/%02X válido (%d bytes)", frame.group, frame.command, data.count))
        if mode == .calories {
            guard let result = VitalsCandidateProtocol.counters(frame, now: Date()), result.timestamp >= start else {
                finish("Contadores ausentes, fuera de límites o con fecha inválida"); return
            }
            counters = result.values; counterTime = result.timestamp
            finish("Calorías activas recibidas; el contador alternativo sigue sin identificar.")
            return
        }
        if waitingForIndex {
            guard frame.command == indexCommand else { return }
            guard let fields = WatchHealthProtocol.fields(frame.payload) else { note("Índice Protobuf inválido"); nextChannel(); return }
            let indicator = WatchHealthProtocol.integer(1, in: fields)
            note("Indicador candidato: " + (indicator.map { String($0) } ?? "ausente"))
            guard WatchHealthProtocol.canProbeFirstPulseBlock(indicator),
                  let cursor = VitalsCandidateProtocol.oxygenCursor(fields, indexCommand: indexCommand, start: start, end: end) else {
                note("Índice sin registros/cursor compatibles; se prueba siguiente candidato")
                nextChannel(); return
            }
            note(cursor < 1577836800 ? "Cursor pequeño/ordinal admitido para 31/0B; no es fecha de medición" : "Cursor temporal dentro de la ventana")
            self.cursor = cursor; trySecond = indicator == 2; waitingForIndex = false
            requestSamples(); return
        }
        guard frame.command == dataCommand else { return }
        guard let result = VitalsCandidateProtocol.oxygenCandidates(frame, command: dataCommand, selector: selector, start: start.addingTimeInterval(-1), end: end) else {
            note("Muestras candidatas rechazadas: formato, selector, rango o fechas")
            note("Estructura recibida: " + VitalsCandidateProtocol.schema(frame))
            nextChannel(); return
        }
        var indexed = Dictionary(readings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for row in result where indexed[row.id] == nil { indexed[row.id] = row }
        readings = indexed.values.sorted { $0.timestamp < $1.timestamp }
        note("Candidato \(channel + 1), selector \(selector): \(result.count) muestras")
        if selector == 1 && trySecond { selector = 2; requestSamples() } else { nextChannel() }
    }
    func cancel() {
        guard isRunning else { return }
        finish("Consulta interrumpida por desconexión o error de escritura")
        readings = []; counters = []; counterTime = nil
    }
    private func finish(_ message: String) {
        timer?.cancel(); timer = nil
        cleanup?(); cleanup = nil; send = nil
        isRunning = false; waitingForIndex = false; status = message; note(message)
    }
}

