import Foundation

func assertProbe(_ condition: Bool, _ label: String) {
    guard condition else { fatalError("Spotify BG probe: \(label)") }
}

let base: UInt64 = 5
func can(_ inBackground: Bool = true,
         _ enabled: Bool = true,
         _ cancelled: Bool = false,
         _ fromEpoch: UInt64 = base,
         _ epoch: UInt64 = base,
         _ fromNative: UInt64 = base,
         _ native: UInt64 = base) -> Bool {
    SpotifyBackgroundProbePolicy.shouldApplyHTTPResult(
        inBackground: inBackground, enabled: enabled,
        cancelled: cancelled,
        startedEpoch: fromEpoch, currentEpoch: epoch,
        startedNativeRevision: fromNative, currentNativeRevision: native)
}
assertProbe(can(), "GET vigente durante bloqueo es aplicable")
assertProbe(!can(false), "GET al volver al foreground no escribe")
assertProbe(!can(true, false), "controles Spotify apagados no escriben")
assertProbe(!can(true, true, true), "consulta cancelada no escribe")
assertProbe(!can(true, true, false, base, base + 1), "nueva sesión invalida HTTP")
assertProbe(!can(true, true, false, base, base, base, base + 1),
            "SDK posterior al GET conserva prioridad")
assertProbe(can(true, true, false, base, base, base, base),
            "caché SDK previo NO impide consulta válida")
print("Spotify background HTTP probe checks: OK")
