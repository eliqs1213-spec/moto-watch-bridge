import SwiftUI

@main
struct MotoFirmwareLabApp: App {
    @StateObject private var bluetooth = FirmwareLabBluetooth()

    var body: some Scene {
        WindowGroup {
            LabHomeView()
                .environmentObject(bluetooth)
        }
    }
}
