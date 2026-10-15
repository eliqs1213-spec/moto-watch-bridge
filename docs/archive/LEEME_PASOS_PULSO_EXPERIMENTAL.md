> Documento histórico. Sus instrucciones corresponden a una etapa anterior. Consultar la [guía vigente](../../README.md) y el [estado actual](../ESTADO_ACTUAL.md).

# Pasos y pulso experimental — 0.8.3.1 / build 831

En Salud, conectar el reloj y tocar Consultar Moto Watch. Se consulta 30/06 y el índice 31/06 para las últimas 24 horas; si hay un cursor válido se pide 31/07. Las respuestas pasan controles de longitud varint, CRC y límites Protobuf. CoreBluetooth entrega los valores ATT completos tras reconstruir ACL.

La estructura está contrastada con la captura local, pero la interpretación de 30/06 campo 2 como pasos y 31/07 muestras campo 2 como pulso es provisional. Se muestran posibles valores. Solo al tocar Guardar histórico experimental se almacenan con etiquetas experimentales visibles en tarjetas y detalles. No se importó el bugreport ni se publicaron sus datos.

El guardado conserva otras categorías, agrupa por día en la zona horaria actual del iPhone, fusiona muestras por timestamp y conserva el último contador de pasos recibido. No es un histórico remoto completo de pasos: se construye desde las consultas guardadas. Pulso consulta un bloque disponible del período; no hay paginación ni confirmaciones que avancen o borren el cursor del reloj.

Prueba: comparar pasos con el reloj, caminar y consultar nuevamente; comprobar que ambos crezcan juntos. Comparar pulso teniendo en cuenta la hora de la muestra (no es necesariamente pulso en vivo). Guardar, relanzar, consultar día/semana y repetir guardado para comprobar deduplicación. Probar desconexión durante la consulta y reconexión. Spotify no cambia; salud usa la cola BLE existente sin borrar batería/avisos/música.

El workflow ejecuta pruebas sintéticas del protocolo y compila para iPhone. Validación en reloj/iPhone pendiente. No fusionar antes de validar los resultados experimentales.
