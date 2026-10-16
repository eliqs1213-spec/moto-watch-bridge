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
print("Background music trial policy checks passed: opt-in, real BLE only, cooldown, finite window")
