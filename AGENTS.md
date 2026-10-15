# Trabajo en Moto Watch Bridge

- La fuente de la app es `ios-native/`. No crear copias Swift ni `project.yml` en la raíz. Mantener `index.html` como puente web independiente salvo pedido explícito sobre la web.
- Leer `docs/ESTADO_ACTUAL.md` y `docs/PENDIENTES.md` al retomar. Las notas de `docs/archive/` son históricas y no definen el comportamiento vigente.
- Prioridad del usuario: notificaciones. No desconectar BLE, cancelar su suscripción ni sacrificar avisos para ahorrar batería. Distinguir encolado, escritura confirmada y visualización.
- Conservar el funcionamiento de Spotify restaurado en 0.8.4.4. No volver a espaciar consultas ni alterar sus reenvíos por ahorro sin una petición explícita. SDK prioritario, Web API de respaldo; evitar comandos duplicados.
- Salud: solo Moto Watch. Portada de hoy, histórico día/semana/mes y JSON existente compatibles. No usar cero ni datos de ayer como reemplazo de ausencia. Oxígeno solo A; calorías activas campo 9; sueño por día de despertar y sesiones independientes. Entrenamientos/etapas no identificados siguen pendientes.
- No subir bugreports, tráfico crudo, mensajes, mediciones reales, tokens ni credenciales. Las pruebas usan fixtures sintéticos.
- La versión de app y extensión se mantiene en `ios-native/project.yml`. Un cambio solo de documentación/limpieza sin comportamiento no requiere otra versión.
- Para cambios funcionales o de rutas usadas al compilar, ejecutar las comprobaciones y build definidos en `.github/workflows/build-ios-native.yml`. No afirmar validación de radio, Atajos o apariencia por pasar pruebas sintéticas.
- Actualizar documentación según el comportamiento final y las limitaciones observadas. Mantener visibles las bases/dependencias de PR apilados; no asumir que `main` contiene todas las ramas.
