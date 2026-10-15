> Documento histórico. Sus instrucciones corresponden a una etapa anterior. Consultar la [guía vigente](../../README.md) y el [estado actual](../ESTADO_ACTUAL.md).

# iWatch · Etapa 8.2.5 · Recuperación de Spotify App Remote

Esta entrega corrige la etiqueta de versión 8.2.1 que estaba escrita a mano, añade diagnóstico de conexión nativa, conserva el SDK como fuente prioritaria si entrega datos y consulta `getPlayerState` cada 6 segundos mientras iWatch está visible. La Spotify Web API es respaldo cuando App Remote no tiene conexión ni estado. La Web API ya no reemplaza una lectura nativa válida mientras el SDK esté conectado.

## Activación y sesión

La autorización App Remote sigue necesitando la acción inicial **Activar SDK Spotify** y una cuenta/cliente autorizado en Spotify Developer. La sesión `SPTSession` del SDK ahora se guarda localmente en **Keychain**, no en UserDefaults ni en registros, y se recupera al relanzar iWatch. La sesión vencida intenta renovarse mediante SPTSessionManager; si no se puede renovar, el usuario debe reautorizar. La opción **Desactivar SDK** borra la sesión del Keychain.

El SDK solo puede estar conectado mientras iWatch está activa, según las restricciones de iOS y la guía de Spotify. Al abrir Spotify, iWatch pasa a segundo plano y App Remote se desconecta; al volver a iWatch intenta reconectar. No es posible tener ambas aplicaciones en primer plano simultáneamente en un iPhone.

## Cómo probar

1. Descomprimir en la raíz del repositorio, conservando las rutas `ios-native/...` (no crear dos carpetas `ios-native`).
2. Subir a GitHub y esperar el workflow **Compilar Moto Watch Bridge iOS**. Instalar el IPA nuevo (versión 0.8.2.5, build 825); un ZIP subido no instala automáticamente el IPA en el iPhone.
3. Abrir Spotify e iniciar una canción; volver a iWatch.
4. En iWatch, autorizar Web API si no lo estaba, activar controles y tocar **Activar SDK Spotify** una vez si la sesión no pudo recuperarse.
5. Comprobar las líneas **Spotify SDK**, **SDK conectado**, **Eventos del SDK**, **Último dato nativo** y **Fuente de metadatos**.
6. Con iWatch visible, cambiar de canción con el reloj. Si el SDK está conectado, el estado debería pasar a **Spotify iOS SDK · App Remote** tras el siguiente evento o lectura (aprox. 6 s). Si el SDK no se conecta, anotar el error del campo Spotify SDK para revisar Client ID, Redirect URI y autorización.

## Límites y validación

Esta versión se validó mediante comparación textual y análisis sintáctico de Swift sin el SDK Apple en Linux. **No se ha compilado en Xcode ni probado en iPhone** en esta entrega. La compilación real debe confirmarse en GitHub Actions después de subirla.

Se preservan batería Motorola 10/01, reconexión BLE, notificaciones, controles next/previous corregidos y los recursos de la etapa anterior. No hay atajos de iOS.
