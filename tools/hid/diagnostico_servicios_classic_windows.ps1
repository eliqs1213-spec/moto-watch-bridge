# Moto Watch Fit | Windows: servicios Bluetooth Classic habilitados (solo lectura)
# Usa BluetoothGetDeviceInfo y BluetoothEnumerateInstalledServices (API Microsoft).
# No realiza SDP remoto, emparejamientos ni cambios de configuracion.
param([string]$Nombre = 'Moto Watch')
$ErrorActionPreference = 'Stop'
Write-Host '=== Moto Watch: servicios Classic conocidos por Windows ==='
$devices = @(Get-PnpDevice | Where-Object {
    ([string]$_.FriendlyName -like ('*' + $Nombre + '*')) -and
    ([string]$_.InstanceId -match '(?i)^BTHENUM\\')
})
if ($devices.Count -eq 0) {
    Write-Host 'RESULTADO: sin dispositivo BTHENUM identificado. Inconcluso.'
    exit 0
}
$addresses = @($devices | ForEach-Object {
    $id = [string]$_.InstanceId
    if ($id -match '(?i)BLUETOOTHDEVICE_([0-9a-f]{12})') { $Matches[1].ToUpperInvariant() }
    elseif ($id -match '(?i)DEV_([0-9a-f]{12})') { $Matches[1].ToUpperInvariant() }
} | Select-Object -Unique)
if ($addresses.Count -ne 1) {
    Write-Host ('RESULTADO: ' + $addresses.Count + ' direcciones Classic identificadas; seleccion ambigua. No se consulta nada.')
    exit 0
}
# Wrapper nativo: exactamente las estructuras y APIs de bluetoothapis.h.
$source = @'
using System;
using System.Runtime.InteropServices;
public static class MotoClassicServices {
    [StructLayout(LayoutKind.Sequential)]
    public struct SystemTime {
        public ushort Year, Month, DayOfWeek, Day, Hour, Minute, Second, Milliseconds;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct DeviceInfo {
        public UInt32 dwSize;
        public UInt64 Address;
        public UInt32 ulClassofDevice;
        [MarshalAs(UnmanagedType.Bool)] public bool fConnected;
        [MarshalAs(UnmanagedType.Bool)] public bool fRemembered;
        [MarshalAs(UnmanagedType.Bool)] public bool fAuthenticated;
        public SystemTime stLastSeen;
        public SystemTime stLastUsed;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=248)]
        public string szName;
    }
    [DllImport("bthprops.cpl", ExactSpelling=true)]
    public static extern UInt32 BluetoothGetDeviceInfo(IntPtr hRadio, ref DeviceInfo info);
    [DllImport("bthprops.cpl", ExactSpelling=true)]
    public static extern UInt32 BluetoothEnumerateInstalledServices(
        IntPtr hRadio, ref DeviceInfo info, ref UInt32 count,
        [Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex=2)] Guid[] services);
    public static string ReadState(string address) {
        var d = new DeviceInfo();
        d.dwSize = (UInt32)Marshal.SizeOf(typeof(DeviceInfo));
        d.Address = Convert.ToUInt64(address, 16);
        UInt32 error = BluetoothGetDeviceInfo(IntPtr.Zero, ref d);
        if (error != 0) throw new Exception("BluetoothGetDeviceInfo error Win32 " + error);
        return "Classic Windows: conectado=" + d.fConnected
            + "; recordado=" + d.fRemembered + "; autenticado=" + d.fAuthenticated;
    }
    public static string[] Read(string address) {
        var d = new DeviceInfo();
        d.dwSize = (UInt32)Marshal.SizeOf(typeof(DeviceInfo));
        d.Address = Convert.ToUInt64(address, 16);
        UInt32 error = BluetoothGetDeviceInfo(IntPtr.Zero, ref d);
        if (error != 0) throw new Exception("BluetoothGetDeviceInfo error Win32 " + error);
        UInt32 count = 0;
        error = BluetoothEnumerateInstalledServices(IntPtr.Zero, ref d, ref count, null);
        if (error != 0 && error != 234) throw new Exception("Enumerate count error Win32 " + error);
        if (count == 0) return new string[0];
        int n = checked((int)count);
        var values = new Guid[n];
        error = BluetoothEnumerateInstalledServices(IntPtr.Zero, ref d, ref count, values);
        if (error != 0) throw new Exception("Enumerate list error Win32 " + error);
        string[] output = new string[n];
        for (int i=0; i<n; i++) output[i] = values[i].ToString("D").ToUpperInvariant();
        return output;
    }
}
'@
try {
    Add-Type -TypeDefinition $source -ErrorAction Stop
    Write-Host ([MotoClassicServices]::ReadState($addresses[0]))
    $services = @([MotoClassicServices]::Read($addresses[0]))
    Write-Host ('Dispositivo Classic encontrado: ' + $devices[0].FriendlyName)
    Write-Host ('Servicios habilitados en Windows: ' + $services.Count)
    foreach ($g in $services) {
        $suffix = ''
        switch -Regex ($g) {
            '^00001124-' { $suffix = ' | HID Classic (0x1124)' }
            '^00001101-' { $suffix = ' | Serial Port (0x1101)' }
            '^0000110C-' { $suffix = ' | AVRCP Target (0x110C)' }
            '^0000110E-' { $suffix = ' | AVRCP (0x110E)' }
            '^0000110F-' { $suffix = ' | AVRCP Controller (0x110F)' }
        }
        Write-Host ('  ' + $g + $suffix)
    }
    if ($services -match '^00001124-') {
        Write-Host 'RESULTADO: Windows tiene HID Classic habilitado para ESTE reloj.'
    } else {
        Write-Host 'RESULTADO: Windows no tiene HID Classic 0x1124 habilitado para este reloj.'
        Write-Host 'La ausencia NO excluye que el firmware anuncie HID por SDP en otro estado.'
    }
} catch {
    Write-Host ('RESULTADO INCONCLUSO: ' + $_.Exception.Message)
}
Write-Host 'Solo lectura; no se solicito nuevo emparejamiento ni modificacion.'
