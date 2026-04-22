# Sprint 1 — POS transactional core hardening

## Qué cambié

### 1) Checkout POS ahora pasa por una sola operación transaccional
Se agregó la migración aditiva:
- `supabase/sql-next/20260410_pos_transactional_core.sql`

Incluye:
- `public.normalize_receipt_type(text)`
- `public.checkout_sale_transactional(...)`

La nueva RPC hace en una sola transacción de DB:
- validación de sesión/rol/sucursal
- normalización canónica de `receipt_type`
- validación de cliente cuando la venta es a crédito o fiscal
- validación de líneas y cantidades
- bloqueo `FOR UPDATE` de productos para evitar carreras de stock
- validación de stock antes de insertar líneas
- inserción consistente de `sales`
- inserción de `sale_items`
- creación de `payments` solo si la venta es de contado
- exigencia de caja abierta para cobrar ventas completadas
- actualización de `clients.balance_due` solo en ventas a crédito
- respuesta estructurada con ids/totales/estado

### 2) El repositorio de ventas dejó el flujo parcial por pasos
Archivo tocado:
- `lib/features/sales/data/sales_repository.dart`

Antes el checkout hacía:
1. insert `sales`
2. insert `sale_items`
3. insert `payments`
4. update cliente
5. preparar impresión

Eso podía dejar ventas parciales si algo fallaba a mitad.

Ahora:
- valida y normaliza en una capa de servicio local
- llama a la RPC transaccional
- solo prepara impresión después de que la venta quedó confirmada

### 3) Se agregó una capa de servicio para reglas del checkout
Archivo nuevo:
- `lib/features/sales/domain/sale_checkout_service.dart`

Resuelve:
- consolidación de líneas repetidas
- validación previa de stock en cliente
- validación de precios/impuestos básicos
- validación de cliente para crédito y comprobantes fiscales
- normalización de aliases de `receipt_type`
  - ejemplo crítico: `consumidor_final` -> `consumer_final`
  - también normaliza variantes como `Crédito Fiscal`, `gubernamental`, `exportación`, etc.

### 4) Cobertura mínima de la lógica nueva
Archivos nuevos:
- `test/features/sales/domain/sale_checkout_service_test.dart`
- `tool/sale_checkout_service_smoke.dart`

## Inconsistencias críticas corregidas

### Corregido
- El checkout POS ya no puede crear una cabecera de venta y luego fallar dejando la operación incompleta en app logic.
- El `receipt_type` ahora se normaliza a valores canónicos del enum.
- Una venta completada ya no puede registrar pago sin sesión de caja abierta.
- Una venta fiscal o a crédito ahora exige cliente.
- La validación de stock se rehace en DB bajo lock, no solo en UI.

### Todavía pendiente
- `quote -> sale` sigue necesitando endurecimiento estructural propio; no lo rehice aquí para no mezclar Sprint 2 con Sprint 1.
- No implementé asignación/consumo automático de NCF ni snapshot fiscal del cliente; eso corresponde al bloque fiscal siguiente.
- No convertí impresiones en dispatch real; solo se mantiene la preparación de impresión post-checkout.
- No resolví deuda histórica global de `flutter analyze` fuera del alcance POS.

## Qué tan seguro quedó ahora el flujo POS

### Mucho más seguro que antes
Porque ahora el camino principal de checkout:
- valida antes
- revalida en DB
- usa transacción única
- evita estados intermedios típicos (`sale` sin `sale_items`, `sale` sin `payment`, etc.)

### Riesgos que ya no deberían ocurrir en el checkout POS principal
- venta creada sin líneas por fallo intermedio
- venta cobrada sin caja abierta
- venta fiscal con `receipt_type` roto por alias español
- doble carrera simple de stock por validación solo en frontend

### Riesgos que siguen fuera de Sprint 1
- endurecimiento completo de conversión de cotizaciones
- emisión fiscal real/NCF
- anulaciones reversibles con política formal
- trazabilidad monetaria/cash architecture más profunda

## Validación ejecutada

### Analyze dirigido a lo nuevo
Comando:
- `dart analyze lib/features/sales/data/sales_repository.dart lib/features/sales/domain/sale_checkout_service.dart test/features/sales/domain/sale_checkout_service_test.dart`

Resultado:
- OK, sin issues

### Analyze global del repo
Comando:
- `flutter analyze`

Resultado:
- sigue reportando issues preexistentes en otras áreas del repo, no introducidos por este cambio

### Tests / smoke
Intenté:
- `flutter test test/features/sales/domain/sale_checkout_service_test.dart`

Resultado:
- bloqueado por problema del runner Flutter en esta máquina: `Resource deadlock avoided` al lanzar `flutter_tester`

Ejecuté además:
- `dart run tool/sale_checkout_service_smoke.dart`

Resultado:
- OK

## Recomendación inmediata de despliegue
1. revisar la migración `supabase/sql-next/20260410_pos_transactional_core.sql`
2. aplicarla en entorno de dev/staging
3. probar checkout contado, crédito, fiscal y falta de caja abierta
4. luego sí mover el frontend POS a depender de este flujo en el ambiente desplegado
