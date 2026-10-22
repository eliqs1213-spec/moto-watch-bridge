using System;
using System.Linq;
using Windows.Devices.Bluetooth;
using Windows.Devices.Enumeration;

// Herramienta SOLO de lectura para el Moto Watch Fit.
// Consulta SDP/RFCOMM remoto sin cache; no enlaza, no envia datos,
// no instala themes, no cambia perfiles ni altera el firmware.
if (!OperatingSystem.IsWindows()) {
    Console.WriteLine("Solo se ejecuta en Windows 10/11.");
    return 1;
}
Console.WriteLine("=== Moto Watch Fit | inspeccion SDP RFCOMM remota ===");
Console.WriteLine("Solo lectura: no se envian archivos ni comandos Motorola.");
try {
    var paired = await DeviceInformation.FindAllAsync(
        BluetoothDevice.GetDeviceSelectorFromPairingState(true));
    var watches = paired.Where(d =>
        d.Name.Contains("Moto Watch", StringComparison.OrdinalIgnoreCase) ||
        d.Name.Contains("XT2541", StringComparison.OrdinalIgnoreCase)).ToList();

    if (watches.Count == 0) {
        Console.WriteLine("Sin Moto Watch en los dispositivos Bluetooth Classic emparejados.");
        Console.WriteLine("Esto no demuestra que el reloj carezca de RFCOMM o de temas.");
        return 0;
    }

    var sawService = false;
    foreach (var item in watches) {
        Console.WriteLine("Revisando: " + item.Name);
        // Evitar mostrar direcciones MAC, DeviceId u otra informacion privada.
        using var device = await BluetoothDevice.FromIdAsync(item.Id);
        if (device == null) {
            Console.WriteLine("Windows no dio acceso al dispositivo Classic.");
            continue;
        }
        try {
            var response = await device.GetRfcommServicesAsync(BluetoothCacheMode.Uncached);
            Console.WriteLine("Estado SDP remoto: " + response.Error.ToString());
            Console.WriteLine("Servicios anunciados: " + response.Services.Count);
            foreach (var svc in response.Services) {
                var uuid = svc.ServiceId.Uuid.ToString("D");
                var kind = uuid.StartsWith("00001101-", StringComparison.OrdinalIgnoreCase)
                    ? " (Serial Port Profile)" : "";
                Console.WriteLine("  " + uuid + kind);
                sawService = true;
                svc.Dispose();
            }
        } catch (Exception e) {
            Console.WriteLine("No se pudo leer SDP remoto: " + e.GetType().Name +
                              ", HRESULT=0x" + e.HResult.ToString("X8"));
        }
    }

    Console.WriteLine(sawService
      ? "Se anuncio un servicio RFCOMM. Hace falta verificar el canal de MotoFt antes de transferir temas."
      : "No se anuncio RFCOMM utilizable en esta prueba. Esto NO excluye que se active desde la app Motorola.");
    Console.WriteLine("La transferencia y el formato de temas dinamicos NO estan implementados.");
    return 0;
} catch (Exception e) {
    Console.WriteLine("Prueba inconclusa: " + e.GetType().Name +
                      ", HRESULT=0x" + e.HResult.ToString("X8"));
    return 1;
}
