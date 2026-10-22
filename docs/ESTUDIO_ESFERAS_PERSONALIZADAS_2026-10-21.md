# iWatch — Estudio de esferas para Moto Watch Fit

**Fecha:** 21/10/2026. **Build:** 0.8.4.53 (893), rama experimental sin fusión.

## Primera entrega implementada

- iWatch, Inicio → Personalizar esfera: importar una fotografía a través de PhotosPicker (sin permiso general a la fototeca).

- Tres estilos visuales (Grande/Centrado/Compacto), cuatro colores y ejemplo opcional de clima, claramente identificado como maqueta.

- Persistencia local: foto reducida en Application Support y preferencias AppStorage.

- Exportación del fondo limpio en PNG de 390 × 450 y exportación separada de una vista previa que tiene números estáticos.

- Ni el fondo ni la vista previa se envían automáticamente por Bluetooth.

## Evidencia técnica

- Motorola soporta fotografías, estilos y colores para la esfera: https://es-ar.support.motorola.com/app/answers/detail/a_id/186576/

- Motorola Chile publica pantalla 450 × 390: https://www.motorola.cl/moto-watch-fit/p

- APK Moto Watch 2.1.0.017: `assets/watch_face/XT2541-1/base.json` separa `bg.png`, hora y fecha en coordenadas del lienzo de 390 × 450.

- La APK también describe `widget/weather.json` (widget de clima de las esferas compatibles), pero no demuestra soporte de widget dinámico sobre una esfera fotográfica.

- `band/moto_watchface.proto` incluye `AllWatchFace`, `CurrWatchFace`, `AddAlbumWatchFace` y `WatchFaceInstallState`.

- En clases DEX figuran los nombres `/watch_face/file/add_photo`, `/watch_face/file/sync_photo` y métodos `addWatchFaceAlbum`, `setWatchFace`. Indican rutas de fotografía en la app oficial; todavía no se han decodificado su formato de archivo, negociación, ni canal de transferencia real.

## Límites y próximos pasos

- NO se instaló una esfera en el reloj desde iWatch ni se modificaron esferas existentes.

- El botón «Exportar fondo PNG» produce una imagen que puede transportarse manualmente al Motorola Edge y usarse en la función oficial de esfera fotográfica, verificando el encuadre final.

- Para instalar desde iOS: capturar con Android oficial un único cambio de foto; identificar tramas, archivo, canal Classic/BLE, CRC y respuesta final; implementar transporte limitado, abortable y validado.

- No usar la transferencia OTA para modificar el firmware. No subir APK, HCI crudo o fotografías privadas a GitHub.

## Elementos y temas dinámicos (investigación del XT2541-1)
- La APK Moto Watch 2.1.0.017 incluye **60 archivos JSON** específicos de `assets/watch_face/XT2541-1/`: 7 plantillas `base*.json` y 53 widgets/variantes.
- Las plantillas usan componentes tipados, no una sola imagen: `widget_type=1` imagen/elemento, `2` agujas con ángulos y pivote, `3` matriz de imágenes/estados, `5` fecha en texto. Ejemplo: `base_simulant.json` contiene agujas rotatorias; `base.json` usa dígitos independientes.
- `widget/weather.json`: iconografía que elige entre **45 estados/entradas** de condición meteorológica, con acceso interactivo a la app de clima (`jump=10`). `widget/weather_horizontal.json` agrega dígitos de temperatura y unidad.
- `widget/activity.json`: anillos de pasos, calorías y duración de actividad con **11 estados cada uno** (vacío + diez niveles); `jump=8` para abrir la sección relacionada.
- Las demás familias incluyen pasos, pulso, oxígeno, sueño, estrés, humedad, UV, AQI, distancia, entrenamientos, temporizador y cronómetro, con variantes top/bottom/horizontal; su presencia en la APK prueba soporte de *plantilla*, no garantiza que toda esfera pueda usar todos los widgets simultáneamente.
- `band/moto_watchface.proto`: `AllWatchFace`, `WatchFace` con campos `style_id`, `style_index`, `is_editable`, `clock_type`, `clock_color`, índices de hora/minuto/segundo, y `CurrWatchFace` (id, estilo, color). Esto demuestra que el reloj comunica metadatos de estilos editables de esferas.
- **No probado:** transferir e instalar un JSON/tema dinámico nuevo, compatibilidad de GIF/video/Lottie, movimiento continuo del fondo, ni modificación global del sistema. No se encontraron archivos GIF/MP4 en el directorio de plantillas de esferas del XT2541-1. La presencia de motor gráfico en firmware no confirma formatos importables.
- La generación de fondos mediante Moto AI documentada por Motorola produce imágenes de fondo; no se debe presentar como animación real.

### Próximos hitos recomendados
1. Lectura pasiva de catálogo Motorola `26/01`: extraer sólo identificador, nombre, `is_editable`, estilo, color y `clock_type`, sin escribir.
2. Editor local de **esferas de datos vivos**: elegir distribución de hora, condición meteorológica, pasos, pulso y progreso, con preview SwiftUI alimentado por el reloj o el proveedor autorizado.
3. Capturar un cambio oficial de estilo/color de una esfera editable para relacionarlo con el comando `26/04` y sus campos. Recién después habilitar cambios sobre una esfera **ya instalada**.
4. Capturar una instalación oficial de esfera dinámica desde Android para estudiar empaquetado, checksum, transferencia y confirmación. No usar OTA para cargar temas.
