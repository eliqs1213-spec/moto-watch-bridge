# iWatch 0.8.4.17 / build 857 — diagnóstico de WidgetKit instalado

## Síntoma
En el iPhone con iOS 27.2, iWatch muestra correctamente **90%** de batería
Motorola 10/01, y ActivityKit informa actividad iniciada/actualizada,
pero la Dynamic Island se expande negra, no aparece el widget de batería
y «iWatch» no figura en la lista de widgets incluso tras reiniciar iOS.

## Evidencia previa
- Xcode 16.4 compiló la app-extension `MotoBatteryWidgets.appex`, copió
  el ejecutable a `MotoWatchNativeProbe.app/PlugIns/`, y ejecutó
  `ValidateEmbeddedBinary` sin fallos de compilación.
- Sideloadly 0.70.1: `Dropping 0 of 1 plug-ins`, `Use automatic bundle ID`
  activo, `iOS version 27.2, will mangle bundleID`; firma/instalación
  reportadas como completadas.
- Ninguna de esas líneas demuestra que el .appex haya quedado
  instalado, firmado y registrado en WidgetKit. El mensaje de
  ActivityKit tampoco valida la interfaz del widget.

## Diagnóstico incorporado
Ajustes y diagnóstico → **Diagnóstico de extensión WidgetKit instalada**:
`Comprobar extensión` y `Copiar diagnóstico`. Lee SOLO recursos locales
de la app instalada:
- Bundle ID final de la app, versión y build.
- Existencia del directorio `PlugIns` y de
  `MotoBatteryWidgets.appex` en ese directorio.
- ID real de la extensión, nombre, `NSExtensionPointIdentifier` y
  relación por prefijo entre identificadores de app y widget.
- Estado de permiso ActivityKit y cantidad de actividades activas.

**No** permite consultar el registro interno de WidgetKit ni probar
la integridad de la firma/provisioning; la salida lo advierte.

## CI
Después del IPA generado, verifica que estén presentes y conservados
`Payload/MotoWatchNativeProbe.app/PlugIns/MotoBatteryWidgets.appex/`,
`Info.plist`, el ejecutable y `com.apple.widgetkit-extension`.
Esto valida el IPA SIN FIRMAR, no la instalación posterior con Sideloadly.

## Próximo diagnóstico físico
1. Instalar build 857 desde el workflow; conservar 8.4.13 de referencia.
2. iWatch → Ajustes y diagnóstico → Comprobar extensión → Copiar diagnóstico.
3. **Si falta `.appex`:** revisar reglas/firma de instalación de Sideloadly
   y sus capacidades; no modificar la lectura Motorola o Spotify.
4. **Si los IDs son incoherentes:** inspeccionar remapeo automático de
   Sideloadly y firma de cada app extension.
5. **Si todo figura presente y coherente:** el bundle no es suficiente.
   Continuar con diagnóstico de registro en iOS / firmas de
   `MotoBatteryWidgets.appex`, sin afirmar causa.

La versión no cambia Bluetooth, comandos Spotify, Music Auto Sync,
widgets ni notificaciones; es una herramienta de diagnóstico aislada.
