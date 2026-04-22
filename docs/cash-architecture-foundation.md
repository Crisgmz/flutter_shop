# Cash architecture foundation (draft)

Fecha: 2026-04-10

Objetivo: preparar una arquitectura de caja seria para Shop+ RD sin romper el flujo actual del app.

## Estado actual

Hoy el esquema base tiene:

- `cash_sessions`
- `payments`
- `expenses`

Limitaciones importantes del modelo actual:

- solo permite **una caja abierta por sucursal** (`cash_sessions_open_unique` sobre `branch_id`)
- no existe concepto explícito de **ubicación de efectivo**
- no existe una **bitácora unificada de movimientos de efectivo**
- no existe soporte formal para **transferencias entre ubicaciones**
- `payments` y `expenses` apuntan a `cash_session_id`, pero no a una caja física / bóveda / banco / caja chica

## Meta de esta fase

Agregar la base de datos para soportar:

1. `cash_locations`
2. `cash_movements`
3. `cash_transfers`
4. evolución de `cash_sessions` hacia sesiones conscientes de ubicación (`location-aware`)

Sin romper runtime actual:

- **no** se elimina ni reemplaza la restricción actual de una sesión abierta por sucursal
- **no** se cambia la app Flutter en esta fase
- **no** se reescriben los flujos actuales de ventas/gastos/cobros
- todo queda preparado como **draft SQL + plan de migración gradual**

## Diseño propuesto

### 1) `cash_locations`

Representa cualquier lugar donde puede existir saldo operativo.

Ejemplos:

- gaveta de caja
- caja principal / bóveda
- caja chica
- banco
- wallet / cuenta móvil
- ubicación temporal “en tránsito”

Campos clave:

- `branch_id`
- `code`
- `name`
- `location_type`
- `status`
- `parent_location_id` (opcional)
- `allows_sessions`
- `sort_order`
- `metadata`

Reglas:

- `branch_id + code` único
- `parent_location_id` debe pertenecer a la misma sucursal
- una ubicación puede marcarse como operable para sesiones (`allows_sessions = true`)

### 2) `cash_movements`

Libro mayor operativo de efectivo por ubicación.

Cada movimiento afecta **una sola ubicación** y tiene dirección:

- `in`
- `out`

Ejemplos de tipo:

- `opening_float`
- `sale_cash_in`
- `customer_payment`
- `expense_cash_out`
- `supplier_payment`
- `deposit`
- `withdrawal`
- `adjustment`
- `transfer_out`
- `transfer_in`
- `close_reconciliation`
- `refund`
- `change_given`

Campos clave:

- `branch_id`
- `location_id`
- `cash_session_id` (nullable)
- `transfer_id` (nullable)
- `entry_direction`
- `movement_type`
- `amount`
- `effective_at`
- referencias opcionales a `payment_id`, `expense_id`, `sale_id`
- `reference_number`, `notes`, `metadata`

Reglas:

- `amount > 0`
- toda fila pertenece a una sucursal y ubicación válidas
- para `transfer_out` / `transfer_in`, se usa `transfer_id`
- los balances se calculan por suma neta (`in` suma, `out` resta)

### 3) `cash_transfers`

Encapsula el evento de mover dinero entre dos ubicaciones.

Ejemplos:

- gaveta -> bóveda
- bóveda -> caja chica
- gaveta -> banco

Campos clave:

- `branch_id`
- `from_location_id`
- `to_location_id`
- `status`
- `amount`
- `requested_by`
- `approved_by` (nullable)
- `received_by` (nullable)
- timestamps de request / approve / receive / cancel
- `reference_number`, `notes`, `metadata`

Reglas:

- `from_location_id <> to_location_id`
- ambas ubicaciones deben pertenecer a la misma sucursal en esta fase
- al materializar la transferencia, se generan dos movimientos:
  - `transfer_out` en origen
  - `transfer_in` en destino

### 4) Evolución de `cash_sessions`

`cash_sessions` debe migrar de “sesión por sucursal” a “sesión sobre una ubicación operable”.

Campos nuevos propuestos:

- `location_id uuid null`
- `device_id text null`
- `device_name text null`
- `session_label text null`

Punto crítico:

- **no se elimina todavía** `cash_sessions_open_unique` sobre `branch_id`
- primero se agregan columnas y backfill seguro
- luego la app debe empezar a crear sesiones con `location_id`
- solo después, en una fase futura, se reemplaza la unicidad por una regla más fina:
  - por ubicación
  - o por ubicación + usuario
  - o por ubicación + dispositivo

## Decisiones de modelado

### Por qué una tabla `cash_locations`

Porque el efectivo no vive solo en “la caja abierta”.
Un negocio real mueve dinero entre varios sitios y eso debe quedar trazable.

### Por qué `cash_movements` separado de `payments` y `expenses`

`payments` y `expenses` son documentos/operaciones de negocio.
`cash_movements` es el ledger operacional del dinero.

Eso evita mezclar:

- evento comercial
- evento contable/operativo de caja

### Por qué `cash_transfers` y además `cash_movements`

Porque una transferencia tiene dos dimensiones:

- el **documento/evento** de transferencia (`cash_transfers`)
- los **asientos operativos** que afectan balances (`cash_movements`)

Esa separación permite auditoría, aprobación y recepción.

## Referencias observadas en mangospos

En `/Users/cristiangomez/dev/mangospos` ya existe una evolución más madura alrededor de:

- `cash_registers`
- `cash_register_sessions`
- `cash_transactions`
- sesiones atadas a usuario/dispositivo
- funciones dedicadas de apertura/cierre/resumen

Lecciones útiles aplicadas aquí:

- separar caja física / terminal / sesión
- usar una tabla de movimientos para el dinero
- endurecer reglas de unicidad de sesiones gradualmente
- no depender solo de la sesión para representar saldo

## Estrategia de rollout recomendada

### Fase A — foundation no disruptiva

1. crear enums y tablas nuevas draft
2. agregar `location_id` y metadata a `cash_sessions`
3. crear índices y vistas auxiliares
4. no cambiar todavía el flujo Flutter

### Fase B — backfill y defaults

1. crear una `cash_location` default por sucursal, por ejemplo `MAIN_DRAWER`
2. enlazar sesiones históricas a esa ubicación por backfill
3. documentar datos ambiguos o inconsistentes

### Fase C — app adoption

1. apertura de caja exige seleccionar o resolver `location_id`
2. cobros en efectivo generan `cash_movements`
3. gastos pagados en efectivo generan `cash_movements`
4. transferencias usan `cash_transfers` + movimientos espejo

### Fase D — hardening

1. reemplazar unicidad `cash_sessions_open_unique(branch_id)`
2. pasar a una regla por ubicación / usuario / dispositivo
3. mover lógica crítica a RPCs o funciones transaccionales

## Backfill recomendado

### `cash_locations`

Por cada sucursal activa:

- crear una ubicación default operable:
  - `code = 'MAIN_DRAWER'`
  - `name = 'Caja principal'`
  - `location_type = 'register_drawer'`
  - `allows_sessions = true`

### `cash_sessions`

- setear `location_id` de sesiones históricas a la ubicación default de su sucursal
- no imponer `NOT NULL` todavía en `location_id`

### `cash_movements`

No backfillear automáticamente movimientos históricos en esta primera etapa si no hay reglas de negocio claras para:

- cambio entregado
- transferencias previas
- ajustes manuales ya ocurridos fuera del sistema

Mejor arrancar `cash_movements` desde la fecha de activación del nuevo flujo.

## Riesgos evitados en esta propuesta

- romper flujos actuales de ventas/cobros/gastos
- invalidar RLS actual por sucursal
- introducir una migración destructiva sobre `cash_sessions`
- forzar demasiada lógica nueva en el frontend antes de tiempo

## Archivos draft creados

- `supabase/drafts/20260410_cash_architecture_foundation_draft.sql`
- `docs/cash-architecture-foundation.md`

## Próximos pasos sugeridos

1. revisar y aprobar naming final de enums/tipos
2. decidir si Shop+ usará concepto de:
   - caja física
   - usuario
   - dispositivo
   - o combinación de los tres para la unicidad de sesión
3. crear luego una migración ejecutable fase 1 basada en este draft
4. adaptar Flutter para que apertura/cierre de caja use `location_id`
5. después conectar ventas/gastos/transferencias a `cash_movements`
