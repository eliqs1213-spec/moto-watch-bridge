import Foundation
import Combine
import UIKit

// Prueba de lectura; nunca escribe en WatchHealthStore ni inicia mediciones.
@MainActor
final class WatchStressProbe: ObservableObject {
    static let shared = WatchStressProbe()
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Sin consultar"
    @Published private(set) var samples: [WatchStressProtocol.Sample] = []
    @Published private(set) var messages: [String] = []
    private var watchID = ""
    private var start = Date.distantPast
    private var end = Date.distantPast
    private var selector: UInt64 = 1
    private var trySecond = false
    private var cursor: UInt64 = 0
    private var waitingForIndex = false
    private var send: ((Data) -> Bool)?
    private var cleanup: (() -> Void)?
    private var timer: Task<Void, Never>?

    var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return (["iWatch \(version) · diagnóstico de consulta candidata a estrés", status] + messages).joined(separator: "\n")
    }
    private func note(_ message: String) {
        messages.append(message)
        if messages.count > 35 { messages.removeFirst(messages.count - 35) }
    }
    func begin(watchID: String, cleanup: @escaping () -> Void, send: @escaping (Data) -> Bool) {
        guard !isRunning, !WatchHealthSync.shared.isRunning,
              UIApplication.shared.applicationState == .active else { return }
        self.watchID = watchID; self.cleanup = cleanup; self.send = send
        samples = []; messages = []; selector = 1; trySecond = false
        isRunning = true; waitingForIndex = true
        end = Date(); start = end.addingTimeInterval(-86400)
        status = "Esperando índice candidato 31/0D"
        let payload: [UInt8] = [0x08] + WatchHealthProtocol.varint(UInt64(start.timeIntervalSince1970))
            + [0x10] + WatchHealthProtocol.varint(UInt64(end.timeIntervalSince1970))
        guard send(WatchHealthProtocol.encode(group: 0x31, command: 0x0D, payload: payload)) else {
            finish("No se pudo encolar la consulta")
            return
        }
        note("31/0D encolado; ventana de 24 horas")
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled, let self = self, self.isRunning else { return }
            self.finish("Tiempo agotado: " + self.status + (self.samples.isEmpty ? "" : " · lecturas parciales conservadas"))
        }
    }
    func progress(received: Int, expected: Int) {
        guard isRunning, !waitingForIndex else { return }
        status = "Recibiendo candidato: \(received)/\(expected) bytes"
        note("31/0E selector \(selector): \(received)/\(expected) bytes")
    }
    func rejected(_ reason: String) {
        guard isRunning else { return }
        status = "Reconstrucción rechazada: " + reason
        note(status)
    }
    func receive(_ data: Data, watchID: String) {
        guard isRunning, self.watchID == watchID,
              let route = WatchHealthProtocol.route(data), route.group == 0x31,
              [0x0D, 0x0E].contains(route.command) else { return }
        guard let frame = WatchHealthProtocol.decode(data) else {
            status = "Respuesta candidata rechazada: longitud o CRC"
            note(String(format: "%02X/%02X inválido (%d bytes)", route.group, route.command, data.count))
            return
        }
        note(String(format: "%02X/%02X válido (%d bytes)", frame.group, frame.command, data.count))
        if frame.command == 0x0D {
            guard waitingForIndex else { return }
            waitingForIndex = false
            guard let fields = WatchHealthProtocol.fields(frame.payload) else { finish("Índice con formato inválido"); return }
            let indicator = WatchHealthProtocol.integer(1, in: fields)
            note("Indicador: " + (indicator.map { String($0) } ?? "ausente"))
            guard WatchHealthProtocol.canProbeFirstPulseBlock(indicator) else {
                finish("Índice recibido; indicador no admitido o sin registros")
                return
            }
            guard let cursor = WatchHealthProtocol.integer(2, in: fields),
                  Double(cursor) >= start.timeIntervalSince1970 - 1,
                  Double(cursor) <= end.timeIntervalSince1970 else {
                finish("Cursor del índice ausente o fuera de las últimas 24 horas")
                return
            }
            self.cursor = cursor; trySecond = indicator == 2
            request(1)
            return
        }
        guard !waitingForIndex else { return }
        guard let decoded = WatchStressProtocol.decode(frame, selector: selector,
                                                      start: start.addingTimeInterval(-1), end: end) else {
            status = "31/0E rechazado: selector, estructura, rango o fecha no compatibles"
            if let fields = WatchHealthProtocol.fields(frame.payload) {
                note("Selector recibido: " + (WatchHealthProtocol.integer(1, in: fields).map { String($0) } ?? "ausente"))
            }
            note(status)
            return
        }
        var indexed = Dictionary(samples.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for sample in decoded where indexed[sample.id] == nil { indexed[sample.id] = sample }
        samples = indexed.values.sorted { $0.timestamp < $1.timestamp }
        note("Selector \(selector): \(decoded.count) muestras decodificadas; total único \(samples.count)")
        if selector == 1 && trySecond { request(2); return }
        finish(samples.isEmpty ? "Respuesta válida; sin muestras candidatas" : "\(samples.count) lecturas candidatas recibidas. Compará valor y hora con el reloj.")
    }
    private func request(_ selector: UInt64) {
        self.selector = selector
        let payload: [UInt8] = [0x08] + WatchHealthProtocol.varint(selector)
            + [0x10] + WatchHealthProtocol.varint(cursor)
        guard send?(WatchHealthProtocol.encode(group: 0x31, command: 0x0E, payload: payload)) == true else {
            finish("No se pudo encolar el selector \(selector)")
            return
        }
        status = "Esperando candidato 31/0E selector \(selector)"
        note("31/0E selector \(selector) encolado; lectura sin confirmaciones de borrado")
    }
    func cancel() {
        guard isRunning else { return }
        finish("Consulta interrumpida por desconexión o error de escritura")
        samples = []
    }
    private func finish(_ message: String) {
        timer?.cancel(); timer = nil
        cleanup?(); cleanup = nil; send = nil
        isRunning = false; waitingForIndex = false
        status = message; note(message)
    }
}

