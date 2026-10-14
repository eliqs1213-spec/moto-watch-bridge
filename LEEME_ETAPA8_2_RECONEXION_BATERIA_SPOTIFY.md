# iWatch — Etapa 8.2: Reconexión BLE + Aviso de batería + Recuperación de Spotify

**Versión experimental** construida sobre iWatch 8.1, probada anteriormente por el usuario con Spotify (SDK/Web API) y WhatsApp por Atajos. Esta versión **todavía requiere compilación en GitHub Actions y pruebas reales en iPhone**.

## Lo nuevo

1. **Reconexión automática del reloj**: intenta reconectarse al último Moto Watch Fit conocido al iniciar iWatch, al volver al primer plano y cuando iOS entrega un evento BLE de desconexión. Mantiene CoreBluetooth `bluetooth-central` y restauración de estado. Si iOS suspende la app o corta Bluetooth, no se garantiza que los reintentos temporizados se ejecuten hasta reanudarla.
2. **Aviso de conexión con batería real**: cuando la suscripción BLE F8F0 está activa, envía de inmediato la consulta propietaria Motorola `10/01`; al recibir un porcentaje válido de esa misma conexión, genera una **notificación local** `⌚ Moto Watch Fit conectado — Conexión establecida · Batería del reloj: XX%`.
3. **Sin datos inventados**: si no hay respuesta 10/01 en 14 segundos, el aviso dice `Batería todavía sin lectura`, nunca toma un porcentaje de otra sesión. No utiliza el servicio 180F.
4. **Menos molestias**: limita los avisos automáticos a uno cada 90 segundos para evitar ráfagas por microcortes BLE. Hay un botón **Probar aviso** (no sujeto al límite) y un interruptor para desactivarlos.
5. **Permiso explícito**: tocar **Permitir avisos** en la sección Conexión y autorizar las notificaciones de iWatch en el iPhone. También se puede autorizar desde los ajustes del sistema. Si no hay permiso, simplemente no aparecen avisos.
6. **Spotify 8.2**: al reconectar Bluetooth intenta reanunciar la canción, reutiliza metadatos cacheados y consulta App Remote si está activo; el botón **Forzar metadatos** ya no depende exclusivamente de la Web API. El paquete `08 02` se vuelve a enviar incluso si es la misma canción.
7. **Cola BLE más segura**: actualizar música ya no elimina notificaciones de WhatsApp/Instagram ni consultas de batería pendientes; conserva los grupos `25/02`, `10/01`, `24/01` y los comandos de búsqueda de teléfono.

## Instalación

1. Guardar respaldo de Etapa 8.1, que ya funciona.
2. Extraer el ZIP y reemplazar **solo `ios-native/`** en el repositorio `eliqs1213-spec/moto-watch-bridge`; conservar `index.html` y `.github/workflows/build-ios-native.yml`.
3. Esperar GitHub Actions `Compilar Moto Watch Bridge iOS`; descargar `MotoWatchNativeProbe-unsigned` y extraer IPA.
4. Instalar con Sideloadly. Al firmar, mantener el identificador estable para conservar datos y atajos.
5. Abrir iWatch y en **Conexión** activar `Reconectar reloj automáticamente` y `Avisar conexión y batería`. Tocar **Permitir avisos**.
6. Para comprobar, tocar `Desconectar`, luego `Conectar reloj`; mirar porcentaje y alerta. El botón **Probar aviso** sirve para verificar permisos sin generar una desconexión.
7. Apagar y volver a encender Bluetooth o alejar/acercar el reloj. El test debe confirmar una reconexión sin intervención, cuando iOS permita el evento; si tarda o falla copiar el registro de diagnóstico.
8. Probar Spotify con misma canción después del estado «No se está reproduciendo música»; utilizar **Forzar metadatos** sin cambiar de canción, y luego verificar recuperación automática.
9. Probar WhatsApp por Atajos con iPhone bloqueado para comprobar que no existan regresiones.

## Limitaciones conocidas

- Las notificaciones locales dependen de permiso del usuario, modo de concentración y ajustes de iOS. La app no puede forzar su presentación.
- La reconexión de un periférico Bluetooth guardado mediante CoreBluetooth puede seguir pendiente y completarse cuando el reloj reaparece, pero iOS **no garantiza** ejecución continua tras cierre forzado de iWatch desde el selector de aplicaciones.
- App Remote de Spotify funciona mejor en primer plano; con pantalla bloqueada se conserva la Web API. El reloj no confirma por ACK que haya dibujado cada canción.
- WidgetKit y Live Activities siguen siendo experimentales y esta etapa **no afirma corregir su firma con Sideloadly**.
- No hay firmware modificado ni acceso a notificaciones de WhatsApp por lectura directa de iOS; se sigue usando Atajos.

### Privacidad

No subir a GitHub registros de notificaciones personales, claves Apple, tokens Spotify ni bugreports originales del teléfono. El origen, título y texto de notificaciones enviadas por Atajos no se guardan en el registro de iWatch.
