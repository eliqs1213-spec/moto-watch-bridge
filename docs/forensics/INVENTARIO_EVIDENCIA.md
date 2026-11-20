# Inventario de evidencia y estado de respaldo

**Fecha:** 2026-11-20. Los hashes abajo proceden del informe técnico del 30/10. No se deben confundir con hashes del ZIP contenedor.

| Objeto | Tamaño documentado | SHA-256 | Estado |
|---|---:|---|---|
| OTA reconstruida | 20.538.246 B | `d2970669988cf049fb38b90cfb7ae52d127f0cf47afe8c15982876647abe0f77` | En archivo histórico externo; **no cargada** aquí |
| `best1502x_b275_user.bin` | 2.651.448 B | `c51b2e4bdcdaa244dbd562b16c3893438dd16d97568ef71d2635d4b659bd5071` | En archivo histórico externo; **no cargado** aquí |
| `base.apk` | No especificado en informe | `342097b6171f744cafa8f56babf3f5e49640d1d0e3d47b903cdf896b0bdb1ef7` | En archivo histórico externo; **no cargado** aquí |
| Archivo histórico `iWatch-Proyecto-Completo-2026-10-22-CAPTURAS-EDGE-OTA.zip` | 237.189.822 B | Consultar manifiesto del respaldo local | **No cargado** aquí |
| `Informe_investigacion_AMS_HID_iWatch_2026-10-30.md` | 9.793 B | Ver respaldo local | Resumido y referenciado; original **no cargado** |
| `iwatch-898-experimental.patch` | 25.279 B | Ver respaldo local | **No cargado** |
| `iWatch-build-898-codigo-experimental.zip` | 325.185 B | Ver respaldo local | **No cargado** |
| `iWatch-build-900-icono-spotify-viento.zip` | 1.185.711 B | Ver respaldo local | **No cargado** |
| IPA 897, 900, 902, 903, 904, 906, 922 | ~1.4–2.2 MB por IPA | Ver manifiesto del respaldo local | Algunos en GitHub Actions; **no publicados aquí** |
| Código fuente, tests y workflows | Versionado en Git | Historial de Git | **En repositorio** |
| Logs, capturas HCI/Edge, fotos y diagnósticos privados | Variable | No todos verificados | **No publicados**, revisión pendiente |

## Índices de código y compilaciones
- [Rama con build 922](https://github.com/eliqs1213-spec/moto-watch-bridge/tree/feature/iwatch-922-accessory-auto-restore)
- [Código ZIP de la rama 922](https://github.com/eliqs1213-spec/moto-watch-bridge/archive/refs/heads/feature/iwatch-922-accessory-auto-restore.zip)
- [Build 922 exitosa](https://github.com/eliqs1213-spec/moto-watch-bridge/actions/runs/42943917880)
- [Build 920 exitosa](https://github.com/eliqs1213-spec/moto-watch-bridge/actions/runs/42424772446)
- [Archivo histórico empaquetado, ejecución](https://github.com/eliqs1213-spec/moto-watch-bridge/actions/runs/39710543327) (la retención de artifacts puede vencer).

## Para completar respaldo binario
Publicar **sólo después** de revisar privacidad, derechos y secretos:
1. Crear un GitHub Release de investigación con assets separados (OTA, BIN, APK, capturas depuradas y ZIP de preservación) si la redistribución es apropiada.
2. Registrar SHA-256 y tamaño **del archivo efectivamente subido**, fecha, fuente, herramientas y cadena de custodia.
3. Comprobar descarga independiente y hash posterior.
4. Enlazar Release aquí; evitar introducir archivos de cientos de MB al historial Git.
5. Mantener las trazas con identificadores personales, direcciones MAC privadas, UDID, tokens y certificados fuera del repositorio público.

**Estado actual: respaldo documental público parcial, no respaldo binario completo.**
