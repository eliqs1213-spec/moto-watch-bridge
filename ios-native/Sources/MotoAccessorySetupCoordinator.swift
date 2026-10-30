import Foundation
import CoreBluetooth
import AccessorySetupKit
import UIKit
import Combine
import SwiftUI

// iOS 18+: AccessorySetupKit está SIEMPRE iniciado desde el arranque.
// iOS requiere consentimiento UNA VEZ para registrar/migrar el reloj.
// CoreBluetooth debe crearse DESPUÉS de completar la migración.
@available(iOS 18.0, *)
final class MotoAccessorySetupCoordinator: ObservableObject {
    static let shared = MotoAccessorySetupCoordinator()
    @Published private(set) var isAuthorized = false
    @Published private(set) var status = "Preparando la autorización del Moto Watch Fit"

    private var session: ASAccessorySession?
    private var started = false
    private var activated = false
    private var pickerOpen = false
    private var pickerAttemptedThisLaunch = false
    private let knownPeripheralKey = "motowatch.last.peripheral.uuid"

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let info = Bundle.main.infoDictionary ?? [:]
        let supports = info["NSAccessorySetupSupports"] as? [String] ?? []
        let legacy = info["NSAccessorySetupKitSupports"] as? [String] ?? []
        let names = info["NSAccessorySetupBluetoothNames"] as? [String] ?? []
        let services = info["NSAccessorySetupBluetoothServices"] as? [String] ?? []
        guard supports.contains("Bluetooth"), legacy.contains("Bluetooth"),
              names.contains("Moto Watch Fit"),
              services.contains(MotoProtocol.service.uppercased()) else {
            status = "AccessorySetupKit incompleto; iniciando Bluetooth convencional"
            WatchBLEManager.shared.record("ACCESSORY-SETUP", "Configuración plist insuficiente; evitando cierre")
            WatchBLEManager.shared.startCentralIfNeeded()
            WatchBLEManager.shared.autoConnectIfNeeded()
            return
        }
        let accessory = ASAccessorySession()
        session = accessory
        accessory.activate(on: DispatchQueue.main) { [weak self] event in
            self?.handle(event)
        }
        log("Sesión AccessorySetupKit iniciada automáticamente")
    }

    func becameActive() {
        guard started, activated, !isAuthorized,
              !pickerOpen, !pickerAttemptedThisLaunch else { return }
        pickerAttemptedThisLaunch = true
        // La solicitud del sistema aparece una sola vez y requiere confirmación del usuario.
        // No se vuelve a mostrar si el usuario la descarta.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, !self.isAuthorized, !self.pickerOpen,
                  UIApplication.shared.applicationState == .active else { return }
            self.requestAuthorization()
        }
    }

    func requestAuthorization() {
        guard started, activated, !pickerOpen, !isAuthorized, let session else { return }
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = CBUUID(string: MotoProtocol.service)
        descriptor.bluetoothNameSubstring = "Moto Watch Fit"
        // Ambos filtros aparecen exactamente en el Info.plist de iWatch.
        let picture = UIImage(systemName: "applewatch") ?? UIImage(systemName: "circle")!
        let entry: ASPickerDisplayItem
        if let raw = UserDefaults.standard.string(forKey: knownPeripheralKey),
           let known = UUID(uuidString: raw) {
            let migration = ASMigrationDisplayItem(
                name: "Moto Watch Fit", productImage: picture, descriptor: descriptor)
            migration.peripheralIdentifier = known
            entry = migration
            status = "Confirmá una vez la migración de Moto Watch Fit a iOS"
        } else {
            entry = ASPickerDisplayItem(
                name: "Moto Watch Fit", productImage: picture, descriptor: descriptor)
            status = "Seleccioná una vez Moto Watch Fit en el selector de iOS"
        }
        pickerOpen = true
        session.showPicker(for: [entry]) { [weak self] error in
            if let error {
                self?.pickerOpen = false
                self?.status = "iOS no autorizó el reloj: \(error.localizedDescription)"
                self?.log("Selector de accesorios: \(error.localizedDescription)")
            }
        }
    }

    private func handle(_ event: ASAccessoryEvent) {
        switch event.eventType {
        case .activated:
            activated = true
            log("Sesión AccessorySetupKit activada")
            restoreAuthorizedAccessory()
            if !isAuthorized { becameActive() }
        case .accessoryAdded:
            // No crear CBCentralManager hasta que el selector haya terminado.
            log("Dispositivo seleccionado; esperando cierre del selector")
            if !pickerOpen { restoreAuthorizedAccessory() }
        case .accessoryChanged:
            if !pickerOpen { restoreAuthorizedAccessory() }
        case .migrationComplete:
            // La migración de CoreBluetooth a AccessorySetupKit ha terminado.
            log("Migración de Moto Watch Fit completada")
            restoreAuthorizedAccessory()
        case .pickerDidDismiss:
            pickerOpen = false
            restoreAuthorizedAccessory()
            if !isAuthorized {
                status = "Falta confirmar Moto Watch Fit; tocá Vincular reloj"
            }
        case .accessoryRemoved:
            isAuthorized = false
            status = "Se quitó la autorización de Moto Watch Fit"
        case .invalidated:
            started = false
            activated = false
            isAuthorized = false
            status = "Sesión de accesorios interrumpida"
            // No crear una segunda sesión repetidamente dentro del callback.
        default:
            break
        }
    }

    private func restoreAuthorizedAccessory() {
        guard let session else { return }
        let known = UserDefaults.standard.string(forKey: knownPeripheralKey)
        guard let accessory = session.accessories.first(where: { item in
            guard let id = item.bluetoothIdentifier else { return false }
            return id.uuidString == known ||
                item.displayName.localizedCaseInsensitiveContains("Moto Watch")
        }), let id = accessory.bluetoothIdentifier else {
            if !isAuthorized { status = "Requiere vincular Moto Watch Fit con iOS" }
            return
        }

        isAuthorized = true
        status = "AccessorySetupKit activo · Bluetooth automático"
        UserDefaults.standard.set(id.uuidString, forKey: knownPeripheralKey)
        // Se inicia el central SOLO después de la autorización/migración.
        let ble = WatchBLEManager.shared
        ble.startCentralIfNeeded()
        ble.autoConnectIfNeeded()
        log("Moto Watch autorizado; restauración CoreBluetooth habilitada")
    }

    private func log(_ message: String) {
        WatchBLEManager.shared.record("ACCESSORY-SETUP", message)
    }
}

@available(iOS 18.0, *)
struct MotoAccessorySetupStatusView: View {
    @ObservedObject private var coordinator = MotoAccessorySetupCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(coordinator.status,
                  systemImage: coordinator.isAuthorized ? "checkmark.shield.fill" : "lock.shield")
                .font(.caption)
                .foregroundStyle(coordinator.isAuthorized ? .green : .secondary)
            if !coordinator.isAuthorized {
                Button("Autorizar reloj en iOS (una sola vez)") {
                    coordinator.requestAuthorization()
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
    }
}
