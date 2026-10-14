# iWatch — Etapa 8.2.4 · Corrección de compilación de Spotify SDK

## Qué se corrigió

El workflow de GitHub Actions del 14/10/2026, ejecución 38617445390,
falló en `ios-native/Sources/SpotifyAppRemoteBridge.swift` líneas 194 y 195.
Swift importa los selectores del protocolo iOS SDK de Spotify como:

```swift
case .next: playerAPI.skip(toNext: callback)
case .previous: playerAPI.skip(toPrevious: callback)
```

Reemplazan las llamadas `skipToNext(callback)` y `skipToPrevious(callback)`;
ambas producían el error `has been renamed to ...` en ese proyecto.

También se actualizó la versión de los targets a 0.8.2.4 (build 824).

## Qué se conserva

- Prioridad de Spotify App Remote de iOS para controles y metadatos.
- Spotify Web API como alternativa si App Remote no está disponible.
- Consulta automática Motorola `10/01` para batería en la reconexión BLE.
- Actualización de metadatos, notificación de conexión y porcentaje de batería.
- Notificaciones WhatsApp/Instagram, widget, Find Phone y recursos de audio.
- Sin Atajos para el control de Spotify.

## Cómo instalar en el repositorio

1. Descomprimí este ZIP.
2. Abrí tu repositorio `eliqs1213-spec/moto-watch-bridge` en GitHub.
3. En `Add file` > `Upload files`, arrastrá la carpeta `ios-native` **con todo su
   contenido** y este documento desde la carpeta descomprimida. Confirmá
   la sustitución de archivos existentes y hacé commit en `main`.
   Alternativa segura desde PC: copiar `ios-native` encima de tu clon local
   y hacer commit/push de los cambios.
4. Comprobá el workflow **Compilar Moto Watch Bridge iOS** en la pestaña Actions.
5. Si compila, descargá `MotoWatchNativeProbe-unsigned` y firmalo/instalalo
   como venías haciendo.

**Importante:** no subas directamente el .zip pensando que GitHub lo va a
extraer. Hay que subir los archivos de la carpeta descomprimida.

## Validación

Se verificó que el ZIP contiene todos los archivos iOS de la Etapa 8.2.3
más esta corrección. Se ejecutó `swiftc -frontend -parse` con Swift 6.2.1
para verificar la sintaxis. No se realizó una compilación en Xcode ni una
prueba sobre iPhone/Moto Watch; el workflow Actions confirmará eso.

## Prueba después de instalar

1. Activar App Remote, Play/Pausa, Siguiente y Anterior desde el reloj.
2. Dejar Spotify pausado unos minutos y probar Play (App Remote o respaldo Web).
3. Alejar/acercar el reloj: reconexión, consulta de batería `10/01` y
   recuperación de los metadatos.
4. Bloquear el iPhone y verificar el comportamiento de notificaciones.

No se garantiza que iOS permita reactivar Spotify cuando está suspendido
por completo: es una limitación del sistema y de los SDK, no de estas líneas.
