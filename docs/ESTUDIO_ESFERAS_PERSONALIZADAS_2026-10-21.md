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
