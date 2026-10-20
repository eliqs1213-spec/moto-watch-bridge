import Foundation

func checkEnvironment(_ yes: Bool, _ label: String) {
    if !yes { fatalError("Entorno: " + label) }
}
let a = Data([0xAA,0x04,0,0,0x23,0x0A,0xD3,0x1C])
let b = Data([0xAA,0x04,0,0,0x2A,0x05,0xA4,0x57])
let ack = Data([0xAA,0x06,0,0,0x2A,0x05,0x08,0x01,0x2D,0x9B])
checkEnvironment(WatchEnvironmentalProtocol.identify(a) == .group23Command0A, "23/0A")
checkEnvironment(WatchEnvironmentalProtocol.identify(b) == .group2ACommand05, "2A/05")
checkEnvironment(WatchEnvironmentalProtocol.identify(ack) == nil, "ack no es solicitud")
var broken = a
broken[6] = 0
checkEnvironment(WatchEnvironmentalProtocol.identify(broken) == nil, "CRC incorrecto")
print("Moto entorno: 23/0A y 2A/05 válidos; ACK descartado")
