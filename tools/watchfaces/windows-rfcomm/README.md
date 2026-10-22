# Diagnóstico de conexión para temas dinámicos (Windows)

El objetivo del proyecto es instalar **esferas dinámicas del Moto Watch Fit XT2541-1**: hora real, clima, pasos, indicadores de salud y recursos gráficos independientes. **Todavía no es un instalador**.

La aplicación Moto Watch oficial utiliza el protocolo de archivos `MotoFt` por Bluetooth Classic/SPP, y las dos pruebas LE de iWatch (895/896) no devolvieron respuesta válida. El diagnóstico anterior de Windows mediante `BluetoothEnumerateInstalledServices` mostró **0 servicios instalados localmente**. Esta herramienta hace una prueba distinta: consulta el SDP **remoto y sin caché** mediante la API pública de Microsoft.

## Uso

Requiere Windows 10/11 y .NET SDK 8 instalado desde https://dotnet.microsoft.com/download/dotnet/8.0 .

En PowerShell, desde la raíz del repositorio:

```powershell
dotnet run --project tools/watchfaces/windows-rfcomm/RfcommProbe.csproj
```

Debe haber un Moto Watch Fit ya emparejado en Windows. Idealmente, cerrá la aplicación Moto Watch del teléfono mientras hacés el diagnóstico, para evitar que otra sesión Classic utilice el canal. **No elimines el emparejamiento** ni cambies la configuración del reloj por este test.

Resultados esperados:
- **Servicios RFCOMM anunciados:** se confirma un servicio Classic accesible por SDP en ese estado. Hace falta identificar si corresponde a MotoFt y las restricciones de acceso.
- **Cero servicios:** no hay servicio anunciado a Windows en esa condición. No basta para afirmar que es imposible; quizá Motorola lo active al iniciar una transferencia de esfera.
- **Acceso rechazado/inconcluso:** comprobar permisos Bluetooth y estado de conexión, sin forzar dispositivos ni enviar datos.

No publicar DeviceId, direcciones MAC, bugreport completo ni fotografías personales. La herramienta oculta la información identificatoria.

## Para crear e instalar temas dinámicos

Los recursos en la APK XT2541-1 incluyen `base*.json` con agujas/dígitos y `widget/*.json` (clima, anillos de actividad, pasos, salud), pero son **plantillas de la aplicación**: no hay evidencia de que simplemente copiar JSON + PNG al reloj instale una esfera. Se necesita reconstruir el empaquetado final y el protocolo MotoFt de instalación/activación.

Plan: (1) comprobar RFCOMM con esta herramienta; (2) extraer de una captura oficial la instalación de una esfera dinámica, no OTA; (3) editor PC con validación de recursos/plantillas; (4) cargador con confirmación de archivo y esfera, sin flashear firmware.

Esta herramienta no escribe en el dispositivo. **No usar firmware OTA ni alterar `*.res` del sistema**.
