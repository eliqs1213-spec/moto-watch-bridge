import Foundation
import CoreBluetooth
import AccessorySetupKit
import UIKit
import Combine
import SwiftUI

// La 902 y la 903 demostraron que ASAccessorySession.init puede abortar el
// proceso en el iPhone real. La 904 NO lo ejecuta durante el arranque normal.
// Por defecto siempre conserva CoreBluetooth y las Live Activities.
// El usuario puede solicitar UNA sola migración, que se realiza al reiniciar
// iWatch: Apple exige no crear CBCentralManager antes de completar la migración.
@available(iOS 18.0, *)
final class MotoAccessorySetupCoordinator: ObservableObject {
    static let shared = MotoAccessorySetupCoordinator()

    @Published private(set) var isAuthorized = false
    @Published private(set) var status = "Bluetooth convencional listo"
    @Published private(set) var needsManualRestart = false

    private var session: ASAccessorySession?
    private var started = false
    private var activated = false
    private var pickerOpen = false
    private var pickerAttemptedThisLaunch = false

    private let manualRequestKey = "motowatch.ask.manual-request.904"
    private let authorizedKey = "motowatch.ask.authorized.904"
    private let initKey = "motowatch.ask.session.init.inflight.904"
    private let knownPeripheralKey = "motowatch.last.peripheral.uuid"

    private init() {}

    private func log(_ message: String) {
        WatchBLEManager.shared.record("ACCESSORY-SETUP", message)
    }

    private func restoreConventionalBluetooth(reason: String) {
        // Nunca llamar a ASAccessorySession cuando la configuración sea dudosa.
        status = reason
        isAuthorized = false
        let ble = WatchBLEManager.shared
        ble.startCentralIfNeeded()
        ble.autoConnectIfNeeded()
        log("CoreBluetooth convencional activo: \(reason)")
    }

    private var plistConfigurationIsValid: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let supports = info["NSAccessorySetupSupports"] as? [String] ?? []
        let legacy = info["NSAccessorySetupKitSupports"] as? [String] ?? []
        let names = info["NSAccessorySetupBluetoothNames"] as? [String] ?? []
        let services = info["NSAccessorySetupBluetoothServices"] as? [String] ?? []
        return supports.contains("Bluetooth") &&
            legacy.contains("Bluetooth") &&
            names.contains("Moto Watch Fit") &&
            services.contains(MotoProtocol.service.uppercased())
    }

    func start() {
        guard !started else { return }
        started = true
        let defaults = UserDefaults.standard

        // La sesión de iOS puede provocar un SIGTRAP no recuperable.
        // Si eso pasó antes, volver a Bluetooth funcional inmediatamente.
        if defaults.bool(forKey: initKey) {
            defaults.set(false, forKey: initKey)
            defaults.set(false, forKey: manualRequestKey)
            defaults.set(false, forKey: authorizedKey)
            restoreConventionalBluetooth(
                reason: "AccessorySetupKit no pudo iniciarse; Bluetooth convencional recuperado"
            )
            return
        }

        let requested = defaults.bool(forKey: manualRequestKey)
        let previouslyAuthorized = defaults.bool(forKey: authorizedKey)
        guard requested || previouslyAuthorized else {
            restoreConventionalBluetooth(reason: "Bluetooth convencional activo · vinculación manual disponible")
            return
        }
        guard plistConfigurationIsValid else {
            defaults.set(false, forKey: manualRequestKey)
            defaults.set(false, forKey: authorizedKey)
            restoreConventionalBluetooth(reason: "Configuración AccessorySetupKit incompleta en la app firmada")
            return
        }

        // Solo se crea la sesión al siguiente arranque DESPUÉS de pulsar
        // «Preparar vinculación» o cuando iOS ya la autorizó anteriormente.
        // En este arranque NO se ha creado CBCentralManager.
        defaults.set(true, forKey: initKey)
        defaults.synchronize()
        let accessory = ASAccessorySession()
        defaults.set(false, forKey: initKey)
        defaults.synchronize()
        session = accessory
        status = "AccessorySetupKit iniciado · esperando autorización de iOS"
        accessory.activate(on: DispatchQueue.main) { [weak self] event in
            self?.handle(event)
        }
        log("Sesión AccessorySetupKit creada tras solicitud manual (no al iniciar normalmente)")
    }

    func prepareManualAuthorization() {
        guard !isAuthorized else { return }
        // No modificar la conexión actual ni abrir el selector en este proceso.
        // Una migración con CBCentralManager ya creado falla según Apple.
        UserDefaults.standard.set(true, forKey: manualRequestKey)
        UserDefaults.standard.set(false, forKey: initKey)
        UserDefaults.standard.synchronize()
        needsManualRestart = true
        status = "Vinculación preparada · cerrá y volvé a abrir iWatch una vez"
        log("El usuario solicitó preparar migración al reiniciar iWatch")
    }

    func cancelPreparedAuthorization() {
        guard needsManualRestart else { return }
        UserDefaults.standard.set(false, forKey: manualRequestKey)
        needsManualRestart = false
        status = "Bluetooth convencional activo · vinculación manual disponible"
        log("Migración pendiente cancelada")
    }

    func becameActive() {
        guard started, activated, !isAuthorized, !pickerOpen,
              !pickerAttemptedThisLaunch, session != nil else { return }
        guard UserDefaults.standard.bool(forKey: manualRequestKey) else { return }
        // La presentación sigue respondiendo al botón que pulsó el usuario;
        // el reinicio es necesario para respetar el orden de migración de Apple.
        requestAuthorization()
    }

    private func requestAuthorization() {
        guard started, activated, !pickerOpen, !isAuthorized, let session else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        pickerAttemptedThisLaunch = true
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = CBUUID(string: MotoProtocol.service)
        descriptor.bluetoothNameSubstring = "Moto Watch Fit"
        let picture = UIImage(systemName: "applewatch") ?? UIImage()
        let entry: ASPickerDisplayItem
        if let raw = UserDefaults.standard.string(forKey: knownPeripheralKey),
           let known = UUID(uuidString: raw) {
            let item = ASMigrationDisplayItem(
                name: "Moto Watch Fit",
                productImage: picture,
                descriptor: descriptor
            )
            item.peripheralIdentifier = known
            entry = item
            status = "Confirmá la migración de Moto Watch Fit en el selector de iOS"
        } else {
            entry = ASPickerDisplayItem(
                name: "Moto Watch Fit",
                productImage: picture,
                descriptor: descriptor
            )
            status = "Seleccioná Moto Watch Fit en el selector de iOS"
        }
        pickerOpen = true
        session.showPicker(for: [entry]) { [weak self] error in
            if let error {
                self?.pickerOpen = false
                self?.log("Selector rechazado: \(error.localizedDescription)")
                UserDefaults.standard.set(false, forKey: self?.manualRequestKey ?? "")
                self?.restoreConventionalBluetooth(
                    reason: "No se completó la autorización de iOS · Bluetooth convencional activo"
                )
            }
        }
    }

    private func handle(_ event: ASAccessoryEvent) {
        switch event.eventType {
        case .activated:
            activated = true
            log("Sesión AccessorySetupKit activada por iOS")
            restoreAuthorizedAccessory()
            if !isAuthorized { becameActive() }
        case .accessoryAdded, .accessoryChanged:
            if !pickerOpen { restoreAuthorizedAccessory() }
        case .migrationComplete:
            log("Migración a AccessorySetupKit completada")
            restoreAuthorizedAccessory()
        case .pickerDidDismiss:
            pickerOpen = false
            restoreAuthorizedAccessory()
            if !isAuthorized {
                UserDefaults.standard.set(false, forKey: manualRequestKey)
                restoreConventionalBluetooth(
                    reason: "Vinculación cancelada · Bluetooth convencional activo"
                )
            }
        case .accessoryRemoved:
            UserDefaults.standard.set(false, forKey: authorizedKey)
            restoreConventionalBluetooth(reason: "Autorización retirada · Bluetooth convencional activo")
        case .invalidated:
            started = false
            activated = false
            UserDefaults.standard.set(false, forKey: manualRequestKey)
            UserDefaults.standard.set(false, forKey: authorizedKey)
            restoreConventionalBluetooth(reason: "Sesión AccessorySetupKit interrumpida · Bluetooth recuperado")
        default:
            break
        }
    }

    private func restoreAuthorizedAccessory() {
        guard let session else { return }
        let known = UserDefaults.standard.string(forKey: knownPeripheralKey)
        guard let accessory = session.accessories.first(where: { item in
            guard let identifier = item.bluetoothIdentifier else { return false }
            return identifier.uuidString == known ||
                item.displayName.localizedCaseInsensitiveContains("Moto Watch")
        }), let identifier = accessory.bluetoothIdentifier else { return }
        isAuthorized = true
        UserDefaults.standard.set(true, forKey: authorizedKey)
        UserDefaults.standard.set(false, forKey: manualRequestKey)
        UserDefaults.standard.set(identifier.uuidString, forKey: knownPeripheralKey)
        needsManualRestart = false
        status = "AccessorySetupKit autorizado · reconexión Bluetooth automática"
        let ble = WatchBLEManager.shared
        ble.startCentralIfNeeded()
        ble.autoConnectIfNeeded()
        log("AccessorySetupKit autorizado; CoreBluetooth iniciado tras migración")
    }
}

@available(iOS 18.0, *)
struct MotoAccessorySetupStatusView: View {
    @ObservedObject private var coordinator = MotoAccessorySetupCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(coordinator.status,
                  systemImage: coordinator.isAuthorized ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.caption)
                .foregroundStyle(coordinator.isAuthorized ? .green : .secondary)

            if !coordinator.isAuthorized && !coordinator.needsManualRestart {
                Button("Preparar vinculación con AccessorySetupKit") {
                    coordinator.prepareManualAuthorization()
                }
                .buttonStyle(.bordered)
                Text("Primero se conserva Bluetooth normal. Para migrar, prepará la autorización, cerrá iWatch desde el selector de apps y abrila de nuevo. iOS mostrará el selector si admite este reloj.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("La inicialización de AccessorySetupKit falló en la 902 y 903. El próximo intento podría cerrar la app una vez; el arranque posterior recuperará Bluetooth convencional.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if coordinator.needsManualRestart && !coordinator.isAuthorized {
                Label("Cerrá iWatch desde el selector de apps y volvé a abrirla para autorizar.", systemImage: "arrow.clockwise")
                    .font(.caption)
                Button("Cancelar vinculación pendiente") {
                    coordinator.cancelPreparedAuthorization()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
