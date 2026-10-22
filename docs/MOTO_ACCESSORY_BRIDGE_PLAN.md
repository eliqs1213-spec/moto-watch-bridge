# MotoAccessoryBridgeKit — organización (fase 1)

## Propósito
Separar los eventos autorizados del iPhone de la codificación propietaria Motorola y del transporte BLE existente. Este cambio **no activa nuevas funciones BLE**; es el primer paso para incorporar clima, ubicación y notificaciones sin modificar Spotify, ANCS ni el firmware.

## Navegación iWatch
- **Inicio:** portada de lectura (estado, música, salud); todos los controles técnicos de música y Bluetooth pasan a Reloj. Se eliminó el sondeo de Spotify duplicado cada seis segundos; permanece el de la raíz de la app.
- **Reloj:** único lugar para conectar/reconectar, consultar batería, activar controles Spotify, actualizar canción y probar/detener alarma del teléfono.
- **Avisos:** filtros y prueba; WhatsApp por Atajos permanece intacto.
- **Salud y Ayuno:** se conservan.
- **Ajustes avanzados:** autorizaciones, extensiones, Live Activity, diagnóstico BLE y pruebas; sin repetir acciones de uso diario.

## Entradas y canales
| Entrada | Fuente iOS | Grupo Motorola | Estado |
| --- | --- | --- | --- |
| WhatsApp | Automatización de Atajos ya probada | 25/02 | Funciona, no se modifica |
| Otras apps | Atajos, si expone el disparador y los campos | 25/02 | Pendiente por aplicación |
| Clima | Proveedor de clima autorizado | 23/01 | Esquema conocido; envío deshabilitado |
| Ubicación del iPhone | Core Location con permiso explícito | 2A/04 | Esquema conocido; envío deshabilitado |
| Ruta deportiva del reloj | Requiere identificar capturas reloj → teléfono | 30/31 por investigar | No se simula |

### Evidencia APK Motorola 2.1.0.017
- band/moto_notification.proto define NotificationPostedNormal: phone_state=1, has_remote_input=2, notification_type=3, notification_id=4, notification_time_stamp=5, notification_title=6, notification_content=7, notification_app_name=8, notification_package=9 y notification_tag=10. No alterar el codificador WhatsApp operativo sin pruebas funcionales de regresión.
- band/moto_weather.proto define CityListResponse, AttendCity, DailyWeather y HourlyWeather. Las capturas 23/01 incluyen localidad, zona horaria, seis días y veinticuatro horas; hay que verificar unidades y traducción de códigos de condición antes de enviar paquetes.
- band/moto_gps.proto define GpsDataTransfer: timestamp=1, signal_strength=2, longitude=3, latitude=4, altitude=5, gpsSpeed=6 y gpsAccuracy=7, con coordenadas tipo float. Las capturas 2A/04 fueron **teléfono → reloj**, no una exportación de ruta.
- band/moto_sport.proto define SportGps por punto de actividad, pero no hay captura confirmada de esa información transferida desde el reloj al teléfono.

## Diseño modular
MotoAccessoryBridgeKit.swift normaliza tres tipos de evento. No tiene referencia a WatchBLEManager, CoreLocation, claves, datos privados ni operaciones de escritura BLE. Tampoco obtiene eventos por sí mismo ni crea tareas en segundo plano.

Los futuros adaptadores necesitarán permisos, vigencia y procedencia de datos, codificación protobuf, segmentación ATT, checksum y confirmación funcional de la pantalla del reloj.

Mantener intactos:
1. SpotifyBridge y coordinador SDK + Web API sin prioridad fija.
2. SendWatchNotificationIntent → WatchBLEManager.sendNotification como ruta WhatsApp.
3. BatteryLiveActivityManager exclusivamente para batería.
4. Moto Firmware Lab independiente, de solo lectura.

## Pendientes
1. Compilar la rama y probar Inicio/Reloj/Ajustes en una IPA cuando haya posibilidad de instalación.
2. Añadir pruebas de normalización y deduplicación antes de conectar el kit a las rutas existentes.
3. Implementar clima y ubicación en cambios aislados y con proveedores autorizados, sin enviar paquetes experimentales automáticamente.
4. Mantener ANCS/HID y firmware en investigación separada.

No subir APK, capturas HCI completas, ubicaciones precisas ni mensajes reales al repositorio.

## Build 883: clima iPhone + diagnóstico ambiental
- Open-Meteo: descarga sólo tras toque del usuario y autorización de ubicación, con coordenadas redondeadas a dos decimales. 6 días, 24 horas, unidad Celsius; sin sincronización automática.
- Clima visible en Inicio (iPhone); todavía NO se envía el pronóstico `23/01` al reloj. Hace falta validar codificación, fragmentación y unidades con un paquete completo real.
- `23/0A` y `2A/05` se etiquetan pasivamente como `MOTO-ENTORNO`, con validación CRC. La app oficial refleja `23/0A` y responde `2A/05` con `08 01`: no se asume que pidan clima/GPS.
- Mantener Spotify, batería, notificaciones y diagnóstico HID intactos. CI verifica el parser y el reconocimiento de señales.
