using System;
using System.Linq;
using System.Threading.Tasks;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Bluetooth.Rfcomm;
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
            byte[] expectedFileRequest = { 0xAA, 0x0A, 0x00, 0x00, 0x20, 0x05, 0x08, 0x01, 0x20, 0x80, 0x80, 0x01, 0x0F, 0x79 };
            if (!BuildFileTransmissionRequest().SequenceEqual(expectedFileRequest))
            {
                Console.WriteLine("FALLO: trama FILE/TRANSMISSION: " + Hex(BuildFileTransmissionRequest()));
                return 1;
            }
            byte[] observedReply = { 0xAA, 0x06, 0x00, 0x00, 0x12, 0x19, 0x08, 0x04, 0xA0, 0x54 };
            if (!IsOpenSppReply(observedReply))
            {
                Console.WriteLine("FALLO: no se reconoce la respuesta OPEN_SPP observada.");
                return 1;
            }
            Console.WriteLine("OK: trama OPEN_SPP 12/19 type=1 y CRC16-XMODEM.");
            Console.WriteLine("OK: trama FILE/TRANSMISSION 20/05 version=1 max_data_size=16384 y CRC16-XMODEM.");
            Console.WriteLine("OK: respuesta 12/19 type=4 con CRC valida; su semantica no se da por confirmada.");
            Console.WriteLine("No se establecio conexion Bluetooth ni se envio ningun comando.");
            return 0;
        }

        bool requestSpp = args.Contains("--request-spp");
        Console.WriteLine("=== Moto Watch Fit | diagnostico Bluetooth para temas dinamicos ===");
        Console.WriteLine(requestSpp
            ? "Modo activo: OPEN_SPP y, solo tras respuesta correlacionada, solicitud de negociacion FILE/TRANSMISSION 20/05. No se envian archivos."
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
            candidate => candidate.Uuid == MotorolaGattService);
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

        var sppReply = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
        var fileReply = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
        TypedEventHandler<GattCharacteristic, GattValueChangedEventArgs>? handler = null;
        if (rx is not null)
        {
            handler = (_, eventArgs) =>
            {
                var reader = DataReader.FromBuffer(eventArgs.CharacteristicValue);
                var bytes = new byte[reader.UnconsumedBufferLength];
                reader.ReadBytes(bytes);
                Console.WriteLine("BLE RX F8F0: " + Hex(bytes));
                if (IsOpenSppReply(bytes))
                {
                    Console.WriteLine("Respuesta correlacionada 12/19 recibida (OperateBt type=4). La semantica de type=4 aun no esta confirmada; no se asume exito.");
                    sppReply.TrySetResult(bytes);
                }
                if (IsFileTransmissionReply(bytes))
                {
                    Console.WriteLine("Respuesta FILE/TRANSMISSION 20/85 con longitud y CRC validos.");
                    fileReply.TrySetResult(bytes);
                }
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

        Console.WriteLine("Esperando hasta 3 segundos por respuesta 12/19...");
        var sppWait = await Task.WhenAny(sppReply.Task, Task.Delay(3000));
        if (sppWait == sppReply.Task && sppReply.Task.IsCompletedSuccessfully)
        {
            byte[] fileRequest = BuildFileTransmissionRequest();
            Console.WriteLine("BLE TX F8F1: " + Hex(fileRequest));
            Console.WriteLine("Solicitud de negociacion FILE/TRANSMISSION 20/05; no contiene datos de archivo.");
            using var fileWriter = new DataWriter();
            fileWriter.WriteBytes(fileRequest);
            var fileStatus = await tx.WriteValueAsync(
                fileWriter.DetachBuffer(), GattWriteOption.WriteWithResponse);
            Console.WriteLine("Resultado escritura ATT 20/05: " + fileStatus);
            if (fileStatus == GattCommunicationStatus.Success)
            {
                Console.WriteLine("Esperando hasta 12 segundos por respuesta 20/85...");
                var fileWait = await Task.WhenAny(fileReply.Task, Task.Delay(12000));
                if (fileWait == fileReply.Task && fileReply.Task.IsCompletedSuccessfully)
                    Console.WriteLine("Respuesta de negociacion recibida: " + Hex(fileReply.Task.Result));
                else
                    Console.WriteLine("Sin respuesta 20/85 en 12 segundos. No se envio ningun archivo.");
            }
            else
            {
                Console.WriteLine("ATT no acepto 20/05; no se envio ningun archivo.");
            }
        }
        else
        {
            Console.WriteLine("No llego respuesta correlacionada 12/19 en 3 segundos; no se envia 20/05.");
        }

        if (handler is not null && rx is not null) rx.ValueChanged -= handler;
        service.Dispose();

        int? after = await ReadRemoteSdpAsync(classicWatch, "despues de OPEN_SPP y 20/05");
        if (after.GetValueOrDefault() > before.GetValueOrDefault())
            Console.WriteLine("Cambio observado en los servicios RFCOMM consultados.");
        else
            Console.WriteLine("El SDP sigue sin anunciar un servicio nuevo en estas consultas.");
        Console.WriteLine("Fin: solo OPEN_SPP y solicitud de negociacion 20/05; no hay transferencia de datos, instalacion de tema ni cambios de firmware.");
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
            Console.WriteLine("SDP " + phase + " general: " + response.Error +
                              "; servicios anunciados=" + response.Services.Count);
            foreach (var svc in response.Services)
            {
                Console.WriteLine("  RFCOMM UUID general: " + svc.ServiceId.Uuid.ToString("D"));
                svc.Dispose();
            }

            // La APK oficial reutiliza FC9DF9F0 como UUID de su servicio SPP.
            // Consultarlo explícitamente por SDP aunque la lista general esté vacía.
            var targetId = RfcommServiceId.FromUuid(MotorolaGattService);
            var target = await device.GetRfcommServicesForIdAsync(
                targetId, BluetoothCacheMode.Uncached);
            Console.WriteLine("SDP " + phase + " UUID Motorola FC9DF9F0: " + target.Error +
                              "; servicios coincidentes=" + target.Services.Count);
            foreach (var svc in target.Services)
            {
                Console.WriteLine("  RFCOMM UUID objetivo: " + svc.ServiceId.Uuid.ToString("D") +
                                  "; canal=" + svc.ConnectionServiceName);
                svc.Dispose();
            }
            return response.Services.Count + target.Services.Count;
        }
        catch (Exception e)
        {
            Console.WriteLine("SDP " + phase + ": " + e.GetType().Name +
                              ", HRESULT=0x" + e.HResult.ToString("X8"));
            return null;
        }
    }

    private static byte[] BuildFileTransmissionRequest()
    {
        // MotoFt.FileTransmission: version=1, max_data_size=16384.
        // Esta solicitud solo negocia; no incluye JPEG, PNG ni payload de tema.
        byte[] prefix = { 0xAA, 0x0A, 0x00, 0x00, 0x20, 0x05, 0x08, 0x01, 0x20, 0x80, 0x80, 0x01 };
        ushort crc = Crc16Xmodem(prefix);
        return prefix.Concat(new[] { (byte)(crc & 0xFF), (byte)(crc >> 8) }).ToArray();
    }

    private static bool IsValidFrame(byte[] bytes)
    {
        if (bytes.Length < 8 || bytes[0] != 0xAA) return false;
        int length = bytes[1] | (bytes[2] << 8);
        if (length + 4 != bytes.Length) return false;
        ushort expected = (ushort)(bytes[^2] | (bytes[^1] << 8));
        return Crc16Xmodem(bytes.Take(bytes.Length - 2).ToArray()) == expected;
    }

    private static bool IsFileTransmissionReply(byte[] bytes) =>
        bytes.Length >= 8 && bytes[4] == 0x20 && bytes[5] == 0x85 && IsValidFrame(bytes);

    private static bool IsOpenSppReply(byte[] bytes)
    {
        if (bytes.Length != 10 || bytes[0] != 0xAA ||
            bytes[1] != 0x06 || bytes[2] != 0x00 ||
            bytes[4] != 0x12 || bytes[5] != 0x19 ||
            bytes[6] != 0x08 || bytes[7] != 0x04)
            return false;
        ushort expected = (ushort)(bytes[^2] | (bytes[^1] << 8));
        return Crc16Xmodem(bytes.Take(bytes.Length - 2).ToArray()) == expected;
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
