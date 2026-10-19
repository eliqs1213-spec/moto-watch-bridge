import SwiftUI

struct LabHomeView: View {
    @EnvironmentObject private var lab: FirmwareLabBluetooth

    var body: some View {
        NavigationStack {
            List {
                Section("Seguridad") {
                    Label("Solo lectura · no instala ni modifica firmware", systemImage: "lock.shield")
                        .foregroundStyle(.green)
                    Text("Para evitar conflictos, cerrá iWatch y desconectá el reloj de otras apps durante las pruebas. No desparees el reloj desde Ajustes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Bluetooth") {
                    LabeledContent("Adaptador", value: lab.bluetoothStatus)
                    LabeledContent("Conexión", value: lab.connectionStatus)
                    HStack(spacing: 12) {
                        Button(lab.isScanning ? "Detener búsqueda" : "Buscar relojes BLE") {
                            if lab.isScanning { lab.stopScan() } else { lab.beginScan() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!lab.canScan)
                        if lab.selectedDeviceName != nil {
                            Button("Desconectar") { lab.disconnect() }
                                .buttonStyle(.bordered)
                        }
                    }
                }

                Section("Dispositivos cercanos (\(lab.devices.count))") {
                    if lab.devices.isEmpty {
                        Text("Pulsá «Buscar relojes BLE». Si el reloj ya está conectado, cerrá iWatch antes de escanear.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lab.devices) { device in
                        Button {
                            lab.connect(to: device.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(device.name).font(.headline)
                                    Spacer()
                                    if let rssi = device.rssi {
                                        Text("\(rssi) dBm")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(device.id.uuidString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if let company = device.manufacturerID {
                                    Text("Manufacturer Data: " + company)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let dataSize = device.manufacturerDataSize {
                                    Text("Publicidad de fabricante: \(dataSize) bytes")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if !device.advertisedServices.isEmpty {
                                    Text("Advertidos: " + device.advertisedServices.joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if !device.advertisedServiceData.isEmpty {
                                    Text("Service Data: " + device.advertisedServiceData.joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }

                Section("Detección de perfiles") {
                    let uuids = Set(lab.services.map { $0.uuid.uppercased() })
                    LabeledContent("HID BLE (1812)", value: uuids.contains("1812") ? "Presente" : "No descubierto")
                    LabeledContent("Google Fast Pair (FE2C)", value: uuids.contains("FE2C") ? "Presente" : "No descubierto")
                    LabeledContent("Servicio Motorola", value: uuids.contains("FC9DF9F0-4899-11EE-BE56-0242AC120002") ? "Presente" : "No descubierto")
                    Text("No descubrir HID BLE no descarta otros modos de Bluetooth ni confirma compatibilidad HID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Servicios y características GATT (\(lab.services.count))") {
                    if lab.services.isEmpty {
                        Text("Seleccioná un dispositivo para enumerar sus servicios.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lab.services) { service in
                        DisclosureGroup {
                            Text(service.primary ? "Servicio primario" : "Servicio secundario")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if service.characteristics.isEmpty {
                                Text("Sin características enumeradas")
                                    .font(.caption)
                            }
                            ForEach(service.characteristics) { characteristic in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(characteristic.uuid).font(.subheadline.monospaced())
                                    Text(characteristic.properties)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let value = characteristic.standardValue {
                                        Text(value).font(.caption).textSelection(.enabled)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        } label: {
                            Text(service.uuid).font(.subheadline.monospaced())
                        }
                    }
                }

                Section("Registro (\(lab.logLines.count))") {
                    ForEach(Array(lab.logLines.suffix(80).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Section("Alcance de esta versión") {
                    Text("No descarga firmware, no solicita modo de actualización y no ejecuta OTA. Lee únicamente información estándar, PnP ID y el Model ID público de Google Fast Pair; los demás servicios propietarios solo se enumeran.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Moto Firmware Lab")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: lab.exportedReport) {
                        Label("Exportar diagnóstico", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
