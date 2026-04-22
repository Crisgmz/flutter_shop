# Cash foundation rollout plan

Fecha: 2026-04-10

## Qué es esto

Este paquete convierte el draft de arquitectura de caja en una **serie ejecutable y aditiva** que todavía no cambia el comportamiento vivo del app.

Archivos creados:

1. `supabase/sql-next/05_cash_foundation_core.sql`
2. `supabase/sql-next/06_cash_foundation_backfill.sql`
3. `supabase/sql-next/07_cash_foundation_views.sql`

## Objetivo de esta fase

Preparar la base para soportar:

- `cash_locations`
- `cash_movements`
- `cash_transfers`
- evolución de `cash_sessions` hacia sesiones por ubicación

Sin romper el runtime actual:

- se mantiene `cash_sessions_open_unique` por `branch_id`
- `cash_sessions.location_id` sigue nullable
- no se obliga todavía a que ventas/gastos/cobros escriban en `cash_movements`
- no se modifica el frontend Flutter en esta etapa

## Orden de aplicación recomendado

1. Ejecutar `supabase/sql/01_schema.sql`
2. Ejecutar `supabase/sql/02_seed.sql`
3. Ejecutar `supabase/sql/03_reports_views.sql`
4. Ejecutar `supabase/sql/04_branch_context.sql`
5. Luego ejecutar manualmente:
   - `supabase/sql-next/05_cash_foundation_core.sql`
   - `supabase/sql-next/06_cash_foundation_backfill.sql`
   - `supabase/sql-next/07_cash_foundation_views.sql`

## Qué hace cada archivo

### 05_cash_foundation_core.sql

Agrega:

- enums nuevos para ubicaciones, movimientos y transferencias
- tabla `cash_locations`
- tabla `cash_transfers`
- tabla `cash_movements`
- columnas nuevas en `cash_sessions`:
  - `location_id`
  - `device_id`
  - `device_name`
  - `session_label`
- FK compuesta de `cash_sessions` hacia `cash_locations`
- índice único de sesión abierta por `location_id` cuando exista
- triggers de `updated_at` y auditoría para tablas nuevas
- RLS + policies alineadas al modelo actual de branch access
- grants explícitos para tablas nuevas

### 06_cash_foundation_backfill.sql

Hace backfill seguro e idempotente:

- crea `MAIN_DRAWER` / `Caja principal` por sucursal si no existe
- enlaza sesiones históricas con esa ubicación default cuando `location_id` está null

### 07_cash_foundation_views.sql

Agrega la vista:

- `cash_location_balances`

Esta vista permite empezar a leer balances derivados sin obligar todavía a migrar todos los flujos operativos.

## Por qué esto sigue siendo seguro

Porque esta fase es solo fundacional:

- no se borran tablas actuales
- no se eliminan columnas actuales
- no se cambia la forma en que ventas, cobros y gastos operan hoy
- no se suelta todavía la restricción global de una sesión abierta por sucursal

En otras palabras: prepara el terreno, pero no cambia el flujo vivo.

## Riesgos todavía pendientes

1. `cash_movements` aún no se llena automáticamente desde `payments` ni `expenses`
2. no existe todavía RPC transaccional para transferencias
3. la app aún abre caja por sucursal, no por ubicación
4. todavía no existe validación de device/user/location como regla operativa final

## Siguiente paso recomendado en DB

El próximo paso concreto debería ser una segunda serie de migraciones para **adopción operativa controlada**, no para rediseño adicional:

1. agregar RPCs transaccionales como:
   - `open_cash_session(...)`
   - `close_cash_session(...)`
   - `create_cash_transfer(...)`
2. hacer que esas RPCs creen los `cash_movements` correctos
3. dejar que el app siga usando una ubicación default primero
4. solo después evaluar reemplazar `cash_sessions_open_unique(branch_id)`

## Siguiente paso recomendado en app

Primero un cambio mínimo y aditivo:

1. leer `location_id`, `device_id`, `device_name`, `session_label` en el módulo de caja
2. resolver automáticamente `MAIN_DRAWER` en apertura de caja si el usuario no elige ubicación
3. no mostrar todavía UI compleja de transferencias ni multi-caja

Ese paso mantiene compatibilidad y reduce el riesgo antes de mover ventas/gastos/cobros al ledger nuevo.
