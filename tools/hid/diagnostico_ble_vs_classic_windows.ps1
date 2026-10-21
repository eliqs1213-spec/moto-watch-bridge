# Fase 14 - identificacion pasiva de transporte Windows
# No escanea Bluetooth, no empareja, no toca configuraciones.
param([string]$Nombre = 'Moto Watch')
$ErrorActionPreference = 'Stop'
Write-Host '=== Moto Watch: BLE vs Bluetooth Classic en Windows ==='
$known = @(Get-PnpDevice | Where-Object { [string]$_.FriendlyName -like ('*' + $Nombre + '*') })
Write-Host ('Entradas PnP conocidas: ' + $known.Count)
$ble = 0; $classic = 0; $other = 0
foreach ($d in $known) {
    $id = [string]$d.InstanceId
    $kind = if ($id -match '(?i)^BTHENUM\\') {
        $classic++; 'BTHENUM (Bluetooth Classic)'
    } elseif ($id -match '(?i)^BTHLE(DEVICE)?\\') {
        $ble++; 'BTHLE (Bluetooth LE)'
    } else {
        $other++; 'Otro o desconocido'
    }
    # No divulgar las direcciones MAC / Dev_xxxxxxxxxxxx del dispositivo.
    $safeId = $id -replace '(?i)(Dev_|&0&)[0-9a-f]{12}', '$1XXXXXXXXXXXX'
    Write-Host ('  ' + $d.FriendlyName + ' | ' + $kind + ' | ' + $d.Status)
    Write-Host ('    InstanceId: ' + $safeId)
}
Write-Host ('BLE=' + $ble + '; Classic=' + $classic + '; otro=' + $other)
if ($classic -eq 0) {
    Write-Host 'RESULTADO: No hay entrada BTHENUM nominal del reloj.'
    Write-Host 'Si solo hay BTHLE, el reloj es conocido por BLE; HID Classic sigue INCONCLUSO.'
} else {
    Write-Host 'RESULTADO: Hay al menos una entrada BTHENUM nominal del reloj.'
    Write-Host 'Eso NO confirma un servicio HID/0x1124. Requiere consulta SDP aparte.'
}
Write-Host 'Sin cambios en reloj, PC o emparejamientos.'
