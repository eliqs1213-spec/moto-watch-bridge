# Moto Watch Fit XT2541-1 — personalización de clima, paneles y esferas
Fecha: 21/10/2026. Investigación **solo lectura**, sin conexión al reloj, instalación de archivos, comandos de servicio, reempaquetado OTA ni modificación del firmware.

## Objetivo
Determinar si iWatch puede cambiar la estética de la aplicación nativa **El tiempo**, del panel lateral de clima y de una esfera con widget meteorológico. Son tres interfaces diferentes y no se deben confundir.

## Evidencia oficial
- Guía Motorola (Moto Watch Fit): https://es-ar.support.motorola.com/app/answers/detail/a_id/186576/ . En «El tiempo» solo documenta la unidad °F/°C y el auto-refresco (Nunca, 1, 3, 6, 12 horas); no ofrece cambiar fondos de pantalla de El tiempo.
- La personalización oficial de imagen/foto, estilo y color es de la **esfera del reloj**. Los paneles se pueden agregar, quitar y reordenar, no personalizar gráficamente desde esa pantalla.

## Análisis de APK Moto Watch 2.1.0.017, XT2541-1
Archivos inspeccionados localmente; no publicar APK ni recursos binarios propietarios.

- `assets/watch_face/XT2541-1/base.json`: describe un `bg.png` con reloj y elementos.
- `assets/watch_face/XT2541-1/widget/weather.json`: componente climático con **`ic_weather_bg.png`**, iconos condicionados (sunny/rain/etc.), y `jump: 10`. Este JSON corresponde al **widget meteorológico de una esfera**, no al fondo de la aplicación independiente El tiempo.
- `widget/weather_horizontal.json`: componente con **`weather_horizontal_bg.png`**, iconos y dígitos. Las variantes `weather_top.json` y `weather_bottom.json` permiten distintas disposiciones.
- `band/moto_watchface.proto`: catálogo, selección, estilos, álbum de fotografías y entidades de fondos, independientes del protocolo meteorológico.
- `band/moto_weather.proto`: `AttendCity`, `DailyWeather`, `HourlyWeather`, unidades y refresco. **No se ha encontrado campo para enviar un bitmap/tema/fondo de la aplicación El tiempo**.
- Código actual de iWatch/captura previa: `26/01` consulta esferas y `26/04` selecciona una de catálogo. **No prueban carga de esfera/imagen nueva**.

## Análisis offline de OTA reconstruida (archivo de usuario)
- En el firmware recuperado aparece `P:/nand/system/image/app_weather.res` y las funciones `app_weather_init`, `weather_page_init`, `app_weatherforcast_edit_init`: evidencia de interfaz meteorológica nativa renderizada por el reloj.
- El paquete OTA contiene **`app_weather.res`** separado de **`app_tile.res`** y `common.res`. Se descomprimió una copia local de solo lectura, sin publicar bytes originales.
- `app_weather.res` contiene **70 imágenes indexadas IDX8**. Tamaños derivados de encabezados LVGL: **26 × 128×128, 22 × 96×96, 22 × 48×40**. **Ninguna equivale a un fondo de pantalla completa**; esto sugiere iconos/sprites y una composición de fondo dibujada por código. No demuestra imposibilidad absoluta de temas alternativos.
- `app_tile.res` contiene **26 imágenes**, entre ellas **12 × 288×330**, además de iconos 96×96/144×144, plausiblemente fondos de paneles. Su presencia separada tampoco establece un comando de sustitución por BLE.
- La ruta de actualización OTA de Motorola transfiere archivos de sistema; esa vía **no equivale** a una API de personalización segura. No hay evidencia de reemplazo autorizado de `app_weather.res` desde iWatch.
- Atención: la imagen OTA inspeccionada deriva de la captura previa y no constituye una confirmación byte a byte del contenido de todas las variantes/actualizaciones de firmware.

## Estado de factibilidad
| Objetivo | Resultado | Siguiente paso seguro |
| --- | --- | --- |
| Cambiar foto/fondo de esfera | Motorola lo admite oficialmente, **pendiente implementar carga desde iOS** | Analizar el empaquetado y transferencia de esferas con capturas controladas de Android |
| Crear esfera temática del clima con fondo elegido y temperatura dinámica | **Candidato sólido**: JSON de `widget/weather` con `img_path` y `img_path_arr` | Generar una **vista previa local** en iWatch; validar luego formato real antes de transferir |
| Reordenar/añadir/quitar panel lateral El tiempo | Soportado oficialmente en el reloj | Leer y comparar el catálogo de paneles y sus comandos, sin escribir hasta validar |
| Sustituir fondo del panel lateral nativo | **No demostrado**; recursos `app_tile.res` integrados en el firmware | Identificar selector de apariencia o transferencia de recursos, si existe |
| Sustituir fondo de la pantalla interna El tiempo | **Sin mecanismo BLE/documentado identificado**; renderización integrada en firmware | Continuar análisis estático del renderer y referencia a `app_weather.res`, solo lectura |

## Decisión de ingeniería
1. No enviar comandos no documentados ni escribir `/nand/system/image/*.res`; riesgo de dejar el reloj inutilizable.
2. Priorizar un **Editor de esferas climáticas** dentro de iWatch con fondo (imagen/color) e iconografía y temperatura del protocolo ya implementado.
3. Mantener por separado el objetivo de modificar la **pantalla nativa El tiempo**: a día de hoy **no hay una vía segura y verificada** para reemplazar su fondo.
4. No afirmar que una maqueta o JPEG enviado al reloj equivale a reemplazar la aplicación meteorológica.
