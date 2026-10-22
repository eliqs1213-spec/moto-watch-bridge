using System;
using System.Linq;
using System.Threading.Tasks;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;
using Windows.Foundation;
using Windows.Storage.Streams;

internal static class Program
{
    private static readonly Guid MotorolaGattService =
        Guid.Parse("fc9df9f0-4899-11ee-be56-0242ac120002");
    private static readonly Guid MotorolaNotify =
        Guid.Parse("fc9df8f0-4899-11ee-be56-0242ac120002");
    private static readonly Guid MotorolaWrite =
        Guid.Parse("fc9df8f1-4899-11ee-be56-0242ac120002");

    private static async Task<int> Main(string[] args)
    {
        if (args.Contains("--self-test"))
        {
            byte[] expected = { 0xAA, 0x06, 0x00, 0x00, 0x12, 0x19, 0x08, 0x01, 0x05, 0x04 };
            var actual = BuildOpenSppRequest();
            if (!actual.SequenceEqual(expected))
            {
                Console.WriteLine("FALLO: trama OPEN_SPP: " + Hex(actual));
                return 1;
            }
            Console.WriteLine("OK: trama OPEN_SPP 12/19, payload OperateBt type=1, CRC16-XMODEM.");
            Console.WriteLine("No se establecio conexion Bluetooth ni se envio ningun comando.");
            return 0;
        }

        bool requestSpp = args.Contains("--request-spp");
        Console.WriteLine("=== Moto Watch Fit | diagnostico Bluetooth para temas dinamicos ===");
        Console.WriteLine(requestSpp
            ? "Modo activo: se enviara UNA solicitud Motorola OPEN_SPP por BLE. No se envian archivos."
            : "Modo solo lectura: no se envian comandos ni archivos.");

        var classicSelector = BluetoothDevice.GetDeviceSelectorFromPairingState(true);
        var classicDevices = await DeviceInformation.FindAllAsync(classicSelector);
        var classicWatch = classicDevices.FirstOrDefault(IsWatch);
        if (classicWatch is null)
        {
            Console.WriteLine("No se encontro Moto Watch Fit emparejado por Bluetooth Classic en Windows.");
            return 1;
        }
        Console.WriteLine("Dispositivo Classic: " + classicWatch.Name);

        int? before = await ReadRemoteSdpAsync(classicWatch, "antes");
        if (!requestSpp)
        {
            Console.WriteLine("Diagnostico terminado; no se modifico el estado del reloj.");
            return 0;
        }

        var leSelector = BluetoothLEDevice.GetDeviceSelectorFromPairingState(true);
        var leDevices = await DeviceInformation.FindAllAsync(leSelector);
        var leWatch = leDevices.FirstOrDefault(IsWatch);
        if (leWatch is null)
        {
            // Fallback de descubrimiento: no se conecta a dispositivos que no coincidan por nombre.
            var allLe = await DeviceInformation.FindAllAsync(BluetoothLEDevice.GetDeviceSelector());
            leWatch = allLe.FirstOrDefault(IsWatch);
        }
        if (leWatch is null)
        {
            Console.WriteLine("No se encontro la instancia BLE del reloj. No se envio el comando.");
            Console.WriteLine("Verifica que Windows tenga Bluetooth LE habilitado y el reloj emparejado.");
            return 1;
        }

        using var ble = await BluetoothLEDevice.FromIdAsync(leWatch.Id);
        if (ble is null)
        {
            Console.WriteLine("Windows no pudo abrir la instancia BLE. No se envio el comando.");
            return 1;
        }
        Console.WriteLine("Dispositivo BLE: " + ble.Name);

        // Enumerar servicios completos permite distinguir entre un enlace GATT
        // inaccesible y un servicio Motorola que no aparece en el dispositivo.
        var serviceResult = await ble.GetGattServicesAsync(BluetoothCacheMode.Uncached);
        if (serviceResult.Status == GattCommunicationStatus.Unreachable)
        {
            Console.WriteLine("GATT inaccesible en el primer intento; reintentando una vez...");
            await Task.Delay(1500);
            serviceResult = await ble.GetGattServicesAsync(BluetoothCacheMode.Uncached);
        }
        if (serviceResult.Status != GattCommunicationStatus.Success)
        {
            Console.WriteLine("No se pudo enumerar GATT: " + serviceResult.Status);
            Console.WriteLine("No se envio el comando.");
            Console.WriteLine("Prueba a apagar temporalmente Bluetooth desde Ajustes en el iPhone y el Edge 60 (no solo cerrar las apps),");
            Console.WriteLine("manteniendo Bluetooth en Windows, y vuelve a ejecutar. No desemparejes el reloj.");
            return 1;
        }

        Console.WriteLine("Servicios GATT encontrados: " + serviceResult.Services.Count);
        foreach (var discovered in serviceResult.Services)
            Console.WriteLine("  GATT UUID: " + discovered.Uuid.ToString("D"));

        var service = serviceResult.Services.FirstOrDefault(
            candidate => candidate.ServiceId.Uuid == MotorolaGattService);
        foreach (var discovered in serviceResult.Services)
        {
            if (!ReferenceEquals(discovered, service)) discovered.Dispose();
        }
        if (service is null)
        {
            Console.WriteLine("No aparece el servicio Motorola FC9DF9F0. No se envio el comando.");
            return 1;
        }
        var txResult = await service.GetCharacteristicsForUuidAsync(
            MotorolaWrite, BluetoothCacheMode.Uncached);
        if (txResult.Status != GattCommunicationStatus.Success ||
            txResult.Characteristics.Count == 0)
        {
            Console.WriteLine("No se encontro la caracteristica de escritura F8F1: " + txResult.Status);
            service.Dispose();
            return 1;
        }
        var tx = txResult.Characteristics[0];
        if (!tx.CharacteristicProperties.HasFlag(GattCharacteristicProperties.Write))
        {
            Console.WriteLine("F8F1 no anuncia escritura con respuesta. No se envio el comando.");
            service.Dispose();
            return 1;
        }

        var rxResult = await service.GetCharacteristicsForUuidAsync(
            MotorolaNotify, BluetoothCacheMode.Uncached);
        GattCharacteristic? rx = rxResult.Status == GattCommunicationStatus.Success
            ? rxResult.Characteristics.FirstOrDefault()
            : null;

        TypedEventHandler<GattCharacteristic, GattValueChangedEventArgs>? handler = null;
        if (rx is not null)
        {
            handler = (_, eventArgs) =>
            {
                var reader = DataReader.FromBuffer(eventArgs.CharacteristicValue);
                var bytes = new byte[reader.UnconsumedBufferLength];
                reader.ReadBytes(bytes);
                Console.WriteLine("BLE RX F8F0: " + Hex(bytes));
            };
            rx.ValueChanged += handler;
            var mode = rx.CharacteristicProperties.HasFlag(GattCharacteristicProperties.Notify)
                ? GattClientCharacteristicConfigurationDescriptorValue.Notify
                : rx.CharacteristicProperties.HasFlag(GattCharacteristicProperties.Indicate)
                    ? GattClientCharacteristicConfigurationDescriptorValue.Indicate
                    : GattClientCharacteristicConfigurationDescriptorValue.None;
            if (mode != GattClientCharacteristicConfigurationDescriptorValue.None)
            {
                var notifyStatus = await rx.WriteClientCharacteristicConfigurationDescriptorAsync(mode);
                Console.WriteLine("Suscripcion F8F0: " + notifyStatus);
            }
            else
            {
                Console.WriteLine("F8F0 no admite Notify/Indicate; se enviara la solicitud sin observar respuestas.");
            }
        }
        else
        {
            Console.WriteLine("No se encontro F8F0 para observar respuestas; se enviara solo si F8F1 esta disponible.");
        }

        byte[] request = BuildOpenSppRequest();
        Console.WriteLine("BLE TX F8F1: " + Hex(request));
        Console.WriteLine("Solicitud Motorola OPEN_SPP (GeneralSetting 12/19, type=1).");
        Console.WriteLine("Esta orden solo solicita abrir el canal SPP; no envia imagenes ni instala temas.");
        using (var writer = new DataWriter())
        {
            writer.WriteBytes(request);
            var status = await tx.WriteValueAsync(
                writer.DetachBuffer(), GattWriteOption.WriteWithResponse);
            Console.WriteLine("Resultado escritura ATT: " + status);
            if (status != GattCommunicationStatus.Success)
            {
                Console.WriteLine("La escritura ATT no fue aceptada; no se puede concluir que el reloj proceso el comando.");
                if (handler is not null && rx is not null) rx.ValueChanged -= handler;
                service.Dispose();
                return 1;
            }
        }

        Console.WriteLine("Esperando 2 segundos por respuesta Motorola...");
        await Task.Delay(2000);
        if (handler is not null && rx is not null) rx.ValueChanged -= handler;
        service.Dispose();

        int? after = await ReadRemoteSdpAsync(classicWatch, "despues de OPEN_SPP");
        if (after.GetValueOrDefault() > before.GetValueOrDefault())
            Console.WriteLine("Cambio observado: Windows ahora ve mas servicios RFCOMM. Todavia no se envio ningun archivo.");
        else
            Console.WriteLine("No aparecieron servicios RFCOMM nuevos en esta consulta. Esto no confirma ni descarta una conexion Classic directa por UUID.");
        Console.WriteLine("Fin: sin transferencia de archivos, instalacion de tema ni cambios de firmware.");
        return 0;
    }

    private static bool IsWatch(DeviceInformation d) =>
        d.Name.Contains("Moto Watch", StringComparison.OrdinalIgnoreCase) ||
        d.Name.Contains("XT2541", StringComparison.OrdinalIgnoreCase);

    private static async Task<int?> ReadRemoteSdpAsync(DeviceInformation info, string phase)
    {
        using var device = await BluetoothDevice.FromIdAsync(info.Id);
        if (device is null)
        {
            Console.WriteLine("SDP " + phase + ": Windows no pudo abrir el dispositivo Classic.");
            return null;
        }
        try
        {
            var response = await device.GetRfcommServicesAsync(BluetoothCacheMode.Uncached);
            Console.WriteLine("SDP " + phase + ": " + response.Error +
                              "; servicios anunciados=" + response.Services.Count);
            foreach (var svc in response.Services)
            {
                Console.WriteLine("  RFCOMM UUID: " + svc.ServiceId.Uuid.ToString("D"));
                svc.Dispose();
            }
            return response.Services.Count;
        }
        catch (Exception e)
        {
            Console.WriteLine("SDP " + phase + ": " + e.GetType().Name +
                              ", HRESULT=0x" + e.HResult.ToString("X8"));
            return null;
        }
    }

    private static byte[] BuildOpenSppRequest()
    {
        // Confirmado en Moto Watch 2.1.0.017:
        // ServiceId.GENERAL_SETTING=0x12, GeneralSetting.OPEN_SPP=0x19,
        // MotoSetting.OperateBt.type=1 solicita abrir SPP.
        byte[] prefix = { 0xAA, 0x06, 0x00, 0x00, 0x12, 0x19, 0x08, 0x01 };
        ushort crc = Crc16Xmodem(prefix);
        return prefix.Concat(new[] { (byte)(crc & 0xFF), (byte)(crc >> 8) }).ToArray();
    }

    private static ushort Crc16Xmodem(byte[] bytes)
    {
        ushort crc = 0;
        foreach (byte value in bytes)
        {
            crc ^= (ushort)(value << 8);
            for (int i = 0; i < 8; i++)
                crc = (ushort)((crc & 0x8000) != 0
                    ? (crc << 1) ^ 0x1021
                    : crc << 1);
        }
        return crc;
    }

    private static string Hex(byte[] bytes) => string.Join(" ", bytes.Select(b => b.ToString("X2")));
}
