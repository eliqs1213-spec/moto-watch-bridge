# iWatch 8.2.1 — Hotfix de reconexión y recuperación musical

Corrección experimental sobre 8.2 para Moto Watch Fit, iPhone y Spotify. **Sintaxis Swift comprobada localmente; pendiente compilación macOS con GitHub Actions y prueba en dispositivo real**.

## Problema reportado en 8.2
Al recuperarse una conexión Bluetooth, el botón «Consultar batería» podía no obtener lectura y la pantalla o metadatos musicales podían conservar una canción antigua.

## Cambios

1. Si CoreBluetooth restaura un periférico que ya figura físicamente `connected` pero la sesión iWatch no está lista, **vuelve a descubrir los servicios y características Motorola** en vez de salir anticipadamente.
2. La sesión solo se considera operativa cuando **F8F0 está suscripta** y **F8F1 permite escritura con respuesta**. La batería y Spotify esperan hasta entonces.
3. Al abrir una sesión nueva se invalidan la cola, escrituras y callbacks temporizados de la conexión anterior. No se arrastran estados viejos.
4. La lectura propietaria Motorola `10/01` tiene prioridad sobre metadatos en cola. Si no responde a los 6 segundos, se hace una segunda solicitud; a los 14 segundos se informa la ausencia de lectura sin inventar el valor.
5. «Consultar batería» informa si hay una solicitud enviada recientemente, en vez de no mostrar ningún cambio.
6. Spotify **ya no reenvía a ciegas la canción anterior tras reconectar**. Primero pide el estado actual por Web API y, si está disponible, también por App Remote. Un `404` al emitir un comando **o consultar la Web API** no significa automáticamente que la música haya dejado de sonar; se conserva la pantalla hasta tener evidencia de estado real.
7. Se registra la clase de paquete Bluetooth saliente (BATERIA, MUSICA, AVISO) sin guardar el contenido de WhatsApp/Instagram.

## Instalación

1. Extraer este ZIP y subir **solo `ios-native`** al repositorio en GitHub (sobrescribir la carpeta anterior, conservar `.github/workflows` y archivos web).
2. Confirmar que GitHub Actions termina en `Success`, descargar `MotoWatchNativeProbe-unsigned` e instalar el IPA con Sideloadly, manteniendo el mismo identificador para conservar las preferencias.
3. Probar una conexión inicial, verificar `Escuchando botones · F8F1 listo`, porcentaje Motorola y notificación de conexión.
4. Cortar la conexión alejando el reloj (sin pulsar «Desconectar», que desactiva la reconexión automática), volver a acercarlo y comprobar que se recupera el porcentaje.
5. Poner Spotify, cambiar de canción mientras el reloj está fuera de alcance y verificar que al reconectar aparece el título **actual**; después probar WhatsApp con el iPhone bloqueado.
6. Si la lectura falla, ir a **Registro persistente → Copiar registro**, y enviar las líneas desde `Periférico conectado` o `Conexión BLE establecida` hasta `Respuesta 10/01` o `Sin respuesta` junto con los eventos `BLE-TX` y `ERROR`. **No compartas tokens, credenciales ni mensajes privados.**

## Límites

- iOS puede suspender la aplicación en segundo plano y demorar recuperaciones. «Conexión física» no equivale a «sesión BLE funcional».
- Spotify Web API a veces devuelve 404/204 mientras la reproducción continúa en el iPhone. Sin estado nuevo desde Spotify no podemos adivinar la canción actual.
- No se modificó el protocolo de WhatsApp/Instagram; los widgets y Live Activity siguen siendo experimentales.
