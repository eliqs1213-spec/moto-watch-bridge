import Foundation

func assertProbe(_ condition: Bool, _ label: String) {
    guard condition else { fatalError("Spotify BG probe: \(label)") }
}

let base: UInt64 = 5
let launch = Date(timeIntervalSince1970: 200)
func can(_ inBackground: Bool = true,
         _ enabled: Bool = true,
         _ cancelled: Bool = false,
         _ fromEpoch: UInt64 = base,
         _ epoch: UInt64 = base,
         _ startedAt: Date = launch,
         _ acceptedAt: Date? = nil) -> Bool {
    SpotifyBackgroundProbePolicy.shouldApplyHTTPResult(
        inBackground: inBackground, enabled: enabled,
        cancelled: cancelled,
        startedEpoch: fromEpoch, currentEpoch: epoch,
        startedAt: startedAt, latestAcceptedAt: acceptedAt)
}
assertProbe(can(), "GET vigente durante bloqueo es aplicable")
assertProbe(!can(false), "GET al volver al foreground no escribe")
assertProbe(!can(true, false), "controles Spotify apagados no escriben")
assertProbe(!can(true, true, true), "consulta cancelada no escribe")
assertProbe(!can(true, true, false, base, base + 1), "nueva sesión invalida HTTP")
assertProbe(!can(true, true, false, base, base, launch,
                 launch.addingTimeInterval(2)),
            "cualquier fuente posterior al inicio del GET lo invalida")
assertProbe(can(true, true, false, base, base, launch,
                launch.addingTimeInterval(-2)),
            "dato anterior no impide una respuesta Web nueva")
assertProbe(can(true, true, false, base, base, launch, launch),
            "dos observaciones simultáneas son conciliables")
print("Spotify background HTTP probe checks: OK")
