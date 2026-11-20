# Reproducibilidad, límites y seguridad

## Fuentes y procedimiento
- Registrar versión iOS, build iWatch, reloj/firmware, fecha UTC, estado bloqueado/desbloqueado y permisos AccessorySetupKit.
- Conservar originales sin edición; registrar SHA-256, tamaño y procedencia; analizar copias de trabajo.
- Distinguir observaciones del usuario, logs de la app, resultados CI, análisis estático y capturas HCI.
- Para OTA: documentar offset `0xF349B`, método DEFLATE, CRC-32 y SHA-256 de cada objeto reconstruido. Comparar con hashes del [inventario](INVENTARIO_EVIDENCIA.md).
- Para HID: separar cadenas/funciones estáticas de anuncios SDP y reportes capturados. No asumir que un descriptor presente implica soporte habilitado.
- Para AMS: búsqueda de UUID en componentes recuperados es evidencia negativa limitada; requiere captura de descubrimiento GATT del lado correcto.
- Para música: correlacionar `24/07` y `24/01` con F8F0/F8F1 y respuesta real de Spotify; registrar `404 NO_ACTIVE_DEVICE` y expiración del SDK por separado.
- Para clima: comparar paquete `23/01` original del Edge y generado por iWatch, con escala de viento y recepción efectiva del reloj.
- Para Live Activity: probar creación en foreground, actualizaciones en background y reingreso a foreground sin duplicar solicitudes.

## Matriz de resultados
| Prueba | Fuente | Estado |
|---|---|---|
| Migración ASK + BLE 920 | Log en dispositivo | Confirmado |
| Restauración automática ASK 922 | Usuario en dispositivo | Confirmado |
| Build 922 | GitHub Actions | Compilación exitosa |
| Inicio Live Activity 922 | Error iOS | Fallo `Target is not foreground` |
| Viento 8 km/h -> reloj | Observación reloj | `0 mph`; causa no demostrada |
| AMS en firmware | Análisis de 84 entradas OTA | UUID no hallados; alcance limitado |
| HID Classic utilizable con iPhone | Análisis estático | No demostrado |
| Flasheo de firmware propio | Sin pruebas seguras | No intentado/recomendado |

## Redacción y privacidad antes de publicación
Eliminar tokens OAuth, claves, certificados, UDID, números de serie, MAC de dispositivos no propios, SSID, coordenadas, nombres de personas, títulos musicales y contenidos de notificaciones. Conservar hashes del original y de la copia redactada y documentar qué se suprimió. No publicar datos interceptados de terceros ni material protegido sin permiso. Mantener originales privados para auditoría autorizada.

## Precauciones
No modificar ni flashear el reloj sin imagen recuperable, firma compatible y método de restauración demostrado. No atribuir a Apple, Motorola o Spotify soporte que no haya sido observado. CI y análisis estático no sustituyen pruebas en dispositivo.
