# iWatch · Etapa 8.1 — Notificaciones + Spotify híbrido

## Qué incluye

1. Se conserva la Etapa 8 y la acción «Enviar notificación al Moto Watch» de Atajos (Motorola 25/02).
2. Spotify Web API y OAuth PKCE existentes siguen siendo el mecanismo principal de controles desde el reloj.
3. Se agrega Spotify iOS SDK **App Remote**, como opción voluntaria: en iWatch > Spotify > «Activar SDK Spotify».
   - El SDK usa una autorización propia para `app-remote-control`. No sustituye ni reutiliza el token PKCE anterior.
   - Requiere aplicación Spotify instalada en el iPhone y el Client ID propio habilitado para iOS SDK en Spotify Developer Dashboard.
   - Debe coincidir el redirect URI `motowatchbridgeeliqs://callback` y el Bundle ID registrado para la app (ojo con el Bundle ID que reescribe Sideloadly).
   - Si se conecta, recibe los cambios de canción/pausa y envía metadatos al reloj, sin esperar el sondeo Web API.
   - En segundo plano se **desconecta intencionalmente**, siguiendo la recomendación de Spotify. La Web API continúa como respaldo para eventos BLE, no hay garantía de actualización periódica con pantalla bloqueada.
   - Desactivar SDK no modifica la sesión Web API.
4. Se elimina el parámetro `device_id` antiguo de los controles Web API para evitar un error frecuente `HTTP 404 Device not found` después de cambiar de reproductor.
5. Cuando la Web API no informa ningún reproductor, empieza una tolerancia de 30 segundos (aproximados, mientras pueda consultar). Después vuelve a «No se está reproduciendo música». **Advertencia:** Spotify a veces devuelve 204 aun estando pausado; por eso una pausa prolongada sin reproductor visible podría interpretarse como reposo después de 30 segundos.
6. No se modifica la lectura Motorola 10/01, los comandos BLE de música, Encontrar iPhone ni los experimentos de Widgets.

## Para instalar

- Reemplazar **solo** `ios-native/` en GitHub. Se conserva `index.html`.
- La compilación GitHub Actions es **sin firmar**. La dependencia SpotifyiOS se descarga con Swift Package Manager desde `https://github.com/spotify/ios-sdk`.
- Revisar los logs de Actions: la compilación aún no se probó en una Mac dentro de esta sesión. Si Xcode o la firma fallan, no desinstalar la Etapa 7/8 anterior.
- Instalar IPA con Sideloadly; si el SDK no consigue autorización, desactivarlo y seguir usando la Web API. La integración SDK es experimental.

## Plan de prueba

1. Verificar batería y Buscar iPhone; no deben tener cambios.
2. Verificar Spotify **sin activar SDK**, controles y título en reloj bloqueado: debe seguir igual.
3. Probar notificación propia en la pestaña Notificaciones; luego asignar variables de Atajos (remitente y contenido de WhatsApp).
4. Con Spotify sonando, habilitar SDK voluntariamente en iWatch. Aprobar conexión con Spotify, volver a iWatch y observar estado «SDK conectado».
5. Cambiar canción y pausar desde Spotify con iWatch visible: verificar metadatos.
6. Bloquear iPhone: probar controles anteriores y posteriores del reloj; el SDK no garantiza eventos en fondo.
7. Cerrar Spotify y observar el contador de espera: tras ~30 segundos de ausencia confirmada debe enviar pantalla sin música.

## Límites conocidos

- WidgetKit/ActivityKit sigue sin aparecer o mostrarse bien con la firma actual Sideloadly. Etapa 8.1 **no** intenta resolverlo.
- iOS no permite a la app leer notificaciones de WhatsApp/Instagram sin Atajos u otra integración autorizada. La ejecución en bloqueo de una automatización sigue pendiente de validar.
- El SDK App Remote es **opcional** y requiere una autorización independiente; su empaquetado binario mediante SPM podría necesitar ajustes de firma Sideloadly.
- El cambio de esferas queda para más adelante.

## Fuentes

- Spotify SDK oficial: https://github.com/spotify/ios-sdk
- Spotify autenticación App Remote: https://github.com/spotify/ios-sdk/blob/master/docs/auth.md
- XcodeGen para paquetes SPM: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md
