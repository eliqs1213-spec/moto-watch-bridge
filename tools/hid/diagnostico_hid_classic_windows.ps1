# Diagnóstico HID Classic instalado en Windows para dispositivos ya conocidos.
# Solo lectura. No empareja, no escanea, no escribe en el registro.
param([string]$Nombre = 'Moto Watch')
$ErrorActionPreference = 'Stop'
Write-Host '=== Moto Watch Fit: HID Classic en Windows (solo lectura) ==='
try { $all = @(Get-PnpDevice -ErrorAction Stop) }
catch { Write-Host ('Plug and Play no disponible: ' + $_.Exception.Message); exit 1 }
$watch = @($all | Where-Object { $_.FriendlyName -match [regex]::Escape($Nombre) })
Write-Host ('Relojes conocidos: ' + $watch.Count)
foreach ($d in $watch) {
  Write-Host ('  ' + $d.FriendlyName + ' | ' + $d.Class + ' | ' + $d.Status)
}
$hid = @($all | Where-Object {
  $_.InstanceId -match '(?i)^BTHENUM\\\{00001124-0000-1000-8000-00805F9B34FB\}'
})
$addresses = @($watch | ForEach-Object {
  if ($_.InstanceId -match '(?i)Dev_([a-f0-9]{12})') { $Matches[1].ToUpperInvariant() }
} | Select-Object -Unique)
$matched = @($hid | Where-Object {
  $instance = [string]$_.InstanceId
  @($addresses | Where-Object {
    $instance -match ('(?i)&0&' + [regex]::Escape($_) + '($|_)')
  }).Count -gt 0
})
Write-Host ('Servicios HID Classic BTHENUM en la PC: ' + $hid.Count)
Write-Host ('Servicios HID Classic asociados de forma verificable a Moto Watch: ' + $matched.Count)
if ($matched.Count -gt 0) {
  Write-Host 'RESULTADO: Perfil HID Classic instalado para Moto Watch en Windows.'
  Write-Host 'Esto NO confirma compatibilidad con iOS ni Play/Pause operativo.'
} elseif ($watch.Count -eq 0 -or $addresses.Count -eq 0) {
  Write-Host 'RESULTADO: INCONCLUSO. Reloj no reconocido/identificable por BTHENUM en Windows.'
} else {
  Write-Host 'RESULTADO: HID Classic no identificado entre los servicios instalados de ese reloj.'
  Write-Host 'No demuestra que HID esté deshabilitado en el firmware.'
}
Write-Host 'No se cambiaron dispositivos ni emparejamientos.'