import Foundation

func verifyWeatherUnit(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError("Unidad meteorológica: " + message) }
}

let setCelsius = WatchWeatherUnitProtocol.set(.celsius)
let setFahrenheit = WatchWeatherUnitProtocol.set(.fahrenheit)
let getUnit = WatchWeatherUnitProtocol.get()
verifyWeatherUnit(Array(setCelsius)[0...7] == [0xAA, 0x06, 0, 0, 0x23, 0x04, 0x08, 0x01],
    "23/04 usa campo protobuf #1 = 1 Celsius")
verifyWeatherUnit(Array(setFahrenheit)[7] == 0, "Fahrenheit codificado como 0")
verifyWeatherUnit(Array(getUnit)[0...5] == [0xAA, 0x04, 0, 0, 0x23, 0x05],
    "23/05 consulta unidad sin payload")
func crcCorrect(_ data: Data) -> Bool {
    let bytes = Array(data)
    return MotoProtocol.crc16Xmodem(bytes.dropLast(2)) ==
        (UInt16(bytes[bytes.count - 2]) | UInt16(bytes[bytes.count - 1]) << 8)
}
verifyWeatherUnit(crcCorrect(setCelsius), "CRC set Celsius")
verifyWeatherUnit(crcCorrect(setFahrenheit), "CRC set Fahrenheit")
verifyWeatherUnit(crcCorrect(getUnit), "CRC consulta")
var response = Array(setCelsius)
response[5] = 0x05
var crc = MotoProtocol.crc16Xmodem(response.dropLast(2))
response[8] = UInt8(crc & 0xff)
response[9] = UInt8(crc >> 8)
verifyWeatherUnit(WatchWeatherUnitProtocol.unitFromGetResponse(Data(response)) == .celsius,
    "respuesta Celsius")
response[7] = 0
crc = MotoProtocol.crc16Xmodem(response.dropLast(2))
response[8] = UInt8(crc & 0xff)
response[9] = UInt8(crc >> 8)
verifyWeatherUnit(WatchWeatherUnitProtocol.unitFromGetResponse(Data(response)) == .fahrenheit,
    "respuesta Fahrenheit")
response[9] ^= 0x01
verifyWeatherUnit(WatchWeatherUnitProtocol.unitFromGetResponse(Data(response)) == nil,
    "rechazo de trama CRC adulterado")
verifyWeatherUnit(WatchWeatherUnitProtocol.unitFromGetResponse(getUnit) == nil,
    "solicitud vacía no es lectura")
print("WatchWeatherUnitProtocol: SET/GET 23/04-05, CRC y readback OK")
