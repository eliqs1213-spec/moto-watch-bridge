import Foundation

func verify(_ ok: @autoclosure () -> Bool, _ why: String) {
    if !ok() { fatalError("BLE capabilities: " + why) }
}
let normal = WatchBLECapabilityProbe.summarize(serviceUUIDs: [
    "FC9DF9F0-4899-11EE-BE56-0242AC120002", "1800", "180F"
])
verify(normal.contains("Motorola=true"), "servicio Motorola")
verify(normal.contains("BLE-HID 1812=false"), "no inventar HID")
verify(normal.contains("Bluetooth Classic/HID/AVRCP no verificados"), "no inferir AVRCP")
let hid = WatchBLECapabilityProbe.summarize(serviceUUIDs: [
    "00001812-0000-1000-8000-00805F9B34FB", "1848", "1849", "1849"
])
verify(hid.contains("GATT services=3"), "normalización y deduplicación")
verify(hid.contains("BLE-HID 1812=true"), "HID por UUID completo")
verify(hid.contains("MCS 1848=true"), "media control service")
verify(hid.contains("GMCS 1849=true"), "generic media control service")
let charProbe = WatchBLECapabilityProbe.summarizeMotorolaCharacteristics([
    .init(uuid: "FC9DF8F0-4899-11EE-BE56-0242AC120002", properties: 0x10),
    .init(uuid: "FC9DF8F1-4899-11EE-BE56-0242AC120002", properties: 0x08),
    .init(uuid: "FC9DF8F2-4899-11EE-BE56-0242AC120002", properties: 0x12)
])
verify(charProbe.contains("Características Motorola=3"), "conteo Motorola")
verify(charProbe.contains("F8F0=presente [notify]"), "F8F0 notify")
verify(charProbe.contains("F8F1=presente [write]"), "F8F1 write")
verify(charProbe.contains("F8F2=presente [read+notify]"), "F8F2 read/notify detectado")
verify(charProbe.contains("lectura/escritura F8F2 NO ejecutadas"), "prueba pasiva")
let noF8F2 = WatchBLECapabilityProbe.summarizeMotorolaCharacteristics([
    .init(uuid: "FC9DF8F0-4899-11EE-BE56-0242AC120002", properties: 0x10),
    .init(uuid: "FC9DF8F1-4899-11EE-BE56-0242AC120002", properties: 0x08)
])
verify(noF8F2.contains("F8F2=ausente"), "ausencia no es falso positivo")

print("WatchBLECapabilityProbe: diagnósticos GATT pasivos verificados")
