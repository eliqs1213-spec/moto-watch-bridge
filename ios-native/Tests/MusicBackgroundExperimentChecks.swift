import Foundation

func requireTrial(_ ok: @autoclosure () -> Bool, _ desc: String) {
    if !ok() { fatalError(desc) }
}
func ble(_ enabled: Bool = true, _ background: Bool = true,
         _ ready: Bool = true, _ spotify: Bool = true,
         _ music: Bool = false, _ busy: Bool = false,
         _ elapsed: TimeInterval = 40) -> Bool {
    MusicBackgroundExperimentPolicy.canProbeFromBLE(
        enabled: enabled, inBackground: background, watchReady: ready,
        spotifyEnabled: spotify, isMusicCommand: music,
        isBusy: busy, secondsSinceLastAttempt: elapsed)
}
requireTrial(ble(), "Real BLE event in background should allow occasional fetch")
requireTrial(!ble(false), "Experiment must be opt-in")
requireTrial(!ble(true, false), "No duplicate polling in foreground")
requireTrial(!ble(true, true, false), "No calls when watch disconnected")
requireTrial(!ble(true, true, true, false), "No calls if Spotify controls off")
requireTrial(!ble(true, true, true, true, true), "Watch music commands have their own refresh")
requireTrial(!ble(true, true, true, true, false, true), "No concurrent Web fetch")
requireTrial(!ble(true, true, true, true, false, false, 34.9), "BLE cooldown required")
requireTrial(ble(true, true, true, true, false, false, 35), "BLE cooldown boundary")
requireTrial(MusicBackgroundExperimentPolicy.foregroundExitOffsets == [0, 9, 18],
             "Finite foreground-exit window, not permanent polling")
requireTrial(MusicBackgroundExperimentPolicy.canContinueShortWindow(
    remainingTime: 7, enabled: true, background: true), "Short window allowed")
requireTrial(!MusicBackgroundExperimentPolicy.canContinueShortWindow(
    remainingTime: 5, enabled: true, background: true), "Insufficient remaining time")
requireTrial(!MusicBackgroundExperimentPolicy.canContinueShortWindow(
    remainingTime: 10, enabled: false, background: true), "No probe when disabled")
requireTrial(MusicBackgroundExperimentPolicy.remainingTimeLabel(27.9) == "27 s",
             "Finite remaining seconds should display safely")
requireTrial(MusicBackgroundExperimentPolicy.remainingTimeLabel(.greatestFiniteMagnitude)
                .contains("valor especial"),
             "Never Int-convert iOS unlimited sentinel: this can terminate the iPhone process")
requireTrial(MusicBackgroundExperimentPolicy.remainingTimeLabel(.infinity) == "no disponible",
             "Infinity is not a valid integer")
requireTrial(MusicBackgroundExperimentPolicy.remainingTimeLabel(.nan) == "no disponible",
             "NaN is not a valid integer")
requireTrial(MusicBackgroundExperimentPolicy.remainingTimeLabel(-1) == "no disponible",
             "Negative values not valid")

// Datos sintéticos: identificar solo cabecera Motorola; nunca registrar salud completa.
requireTrial(MusicBackgroundExperimentPolicy.bleFrameType(
    Data([0xAA, 0x04, 0x00, 0x00, 0x12, 0x04, 0xB9, 0xCB])) == "12/04",
    "Clasificar F8F0 real 12/04 sin incluir payload")
requireTrial(MusicBackgroundExperimentPolicy.bleFrameType(
    Data([0xAA, 0x06, 0x00, 0x00, 0x10, 0x81, 0x08, 0x59, 0x08, 0xE3])) == "10/81",
    "Clasificar F8F0 10/81")
requireTrial(MusicBackgroundExperimentPolicy.bleFrameType(
    Data([0xAA, 0x08, 0x00, 0x00, 0x12, 0x04])) == "12/04 (fragmento)",
    "Fragmento BLE distinguible sin inventar trama completa")
requireTrial(MusicBackgroundExperimentPolicy.bleFrameType(Data([0x01])) == "fragmento/no-AA",
    "Un fragmento sin cabecera no debe leerse como protocolo válido")
requireTrial(MusicBackgroundExperimentPolicy.shouldLogBLEFrame(
    firstOfType: true, queryEligible: false, secondsSinceLastLog: 0),
    "Primer evento de un tipo se registra")
requireTrial(MusicBackgroundExperimentPolicy.shouldLogBLEFrame(
    firstOfType: false, queryEligible: true, secondsSinceLastLog: 1),
    "Un disparador HTTP legítimo siempre se registra")
requireTrial(!MusicBackgroundExperimentPolicy.shouldLogBLEFrame(
    firstOfType: false, queryEligible: false, secondsSinceLastLog: 44),
    "No saturar registro en ráfagas")
requireTrial(MusicBackgroundExperimentPolicy.shouldLogBLEFrame(
    firstOfType: false, queryEligible: false, secondsSinceLastLog: 45),
    "Registrar muestra cada 45 segundos")

print("Background music trial policy checks passed: opt-in, real BLE only, cooldown, finite window, safe time")
