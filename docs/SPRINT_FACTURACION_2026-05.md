# Sprint Facturación RD — Paridad con Alegra
**Fecha:** 2026-05-09 · **DRI:** Cristian · **Duración estimada:** ~3-4 rounds de trabajo

---

## Objetivo

Llevar Shop+ RD a paridad funcional con sistemas de facturación líderes
en República Dominicana (Alegra, Wilmax, Hidoo). Foco en el flujo POS,
control de caja y experiencia del cliente.

## Backlog (9 features)

### F1 · POS: selector de método de pago + confirmación
- Botones: **Efectivo · Tarjeta · Transferencia** (uno seleccionable a la vez).
- Reemplazar "COBRAR CONTADO" por **COMPLETAR VENTA** (verde).
- Diálogo de confirmación con resumen antes de procesar.
- CRÉDITO sigue como botón separado para venta a plazo.
- **Backend:** ninguno (enum `payment_method` ya cubre).
- **DoD:** seleccionas método → COMPLETAR → confirmas → venta queda en la
  caja con `payment_method` correcto y aparece en cobros.

### F2 · Cotizaciones funcionales end-to-end
- Crear, listar, editar, enviar (compartir PDF), convertir a venta.
- Numeración con prefijo `prefix_quote` de `app_settings`.
- Estados: borrador / enviada / convertida / vencida.
- **Backend:** tablas `quotations`, `quotation_items`, `quotation_events`
  ya existen (migración `20260410_quotations_schema.sql`). Validar
  `convert_quotation_to_sale(...)` RPC.
- **DoD:** ciclo completo desde `/cotizaciones` → crear → convertir → venta.

### F3 · /caja: adición/retiro de efectivo durante la sesión
- Nueva tabla `cash_register_movements` con tipos `deposit` (inyección de
  fondos) y `withdrawal` (retiro/sangría).
- Diálogo en `/caja`: "Agregar efectivo a caja" con monto + motivo.
- Trigger actualiza `expected_amount` de la sesión activa.
- **DoD:** desde `/caja` puedo registrar un depósito; el monto sube en
  el efectivo esperado y queda en el cierre Z.

### F4 · Historial de pagos del cliente — editable
- En `/clientes/<id>` mostrar lista de pagos hechos por el cliente.
- Permitir editar monto/método/notas (con audit trail).
- **Backend:** `payments` ya existe; usar update con `updated_by` para
  el log.
- **DoD:** en la pantalla de un cliente veo todos sus pagos, los puedo
  filtrar por fecha, y un admin puede corregir un monto.

### F5 · /cobros: ver factura y reimprimir
- Botón "Ver" en cada fila → muestra detalle de la venta en un dialog.
- Botón "Reimprimir" → dispara `PrintReceiptDialog`.
- **Backend:** reusar `SalePrintJobPreparationService` existente.
- **DoD:** en `/cobros` puedo abrir una venta pasada y mandarla a imprimir
  con el mismo formato que en el POS.

### F6 · Inventario: campos + historial por producto
- Mostrar **SKU, Referencia (internal_code), Costo, Cantidad** en la
  tabla y formulario.
- Nueva pantalla "Historial del producto": agrupa entradas (compras,
  ajustes positivos) y salidas (ventas, mermas, devoluciones a
  proveedor) por fecha.
- **Backend:** consulta agregada sobre `sale_items` + `purchase_items` +
  `inventory_movements`. Si no existe vista, crearla en SQL.
- **DoD:** desde una fila de inventario click → veo todo el movimiento
  histórico de ese producto.

### F7 · Habilitar cierres Z fiscales desde /caja
- Botón "Sellar cierre Z" en la pantalla de cierre de sesión.
- Llama al RPC `seal_fiscal_z_closure(branch_id, cash_session_id)`.
- Muestra el resultado + opción de imprimir el Z.
- **Backend:** infraestructura ya existe en migración 09. Sólo wiring UI.
- **DoD:** al cerrar la caja del día puedo (opcionalmente) generar el Z
  fiscal y queda guardado inmutable.

### F8 · Módulo de caja chica
- Nuevas tablas: `petty_cash_sessions`, `petty_cash_movements`,
  `petty_cash_categories`.
- Nueva ruta `/caja-chica` con apertura/cierre, registro de gastos
  (transporte, papelería, limpieza, etc.) y arqueo.
- Independiente de la caja principal del POS.
- **DoD:** puedo abrir caja chica con un monto inicial, registrar 5
  gastos durante el día, cerrar y ver el arqueo.

### F9 · Precio por cliente (tier-based pricing)
- Cada cliente tiene `price_tier` (retail / tier_1 / tier_2 / tier_3).
- Cada producto tiene `price` + `price_tier_1/2/3`.
- En POS, al seleccionar un cliente, los precios mostrados y agregados al
  carrito usan el tier correspondiente.
- **Backend:** todas las columnas ya existen; solo wiring Flutter.
- **DoD:** asigno "tier_2" a un cliente mayorista; al venderle en POS los
  productos se cargan con `price_tier_2`.

---

## Plan de rounds

### Round 1 (este turno) — Foundation
- ✅ Sprint plan documentado (este archivo).
- ✅ SQL migration `20260509_16_operational_extensions.sql`:
  - `cash_register_movements` + trigger.
  - `petty_cash_sessions` + `petty_cash_movements` + `petty_cash_categories`.
  - Seed categorías de caja chica.
  - RLS branch-scoped.
- ✅ F1: botones de pago + COMPLETAR VENTA + confirmación.
- ✅ F9: aplicar price_tier del cliente seleccionado en POS.

### Round 2 — Operación / cobros
- F3: UI de adición de efectivo en `/caja`.
- F4: historial de pagos editable por cliente.
- F5: ver factura + reimprimir desde `/cobros`.

### Round 3 — Inventario y cotizaciones
- F6: campos extra + historial de movimientos por producto.
- F2: cotizaciones funcionales (validar y pulir lo existente).

### Round 4 — Caja avanzada
- F7: wiring del botón "Sellar Z fiscal" en `/caja`.
- F8: módulo de caja chica completo (`/caja-chica`).

### Round 5 — QA y release
- Smoke test end-to-end de los 9 features.
- Validación con dataset real.
- Actualizar `STATE_OF_THE_PLATFORM.md`.

> **Estado:** ✅ Cerrado.
> - `STATE_OF_THE_PLATFORM.md` creado en raíz con tabla de migraciones,
>   estado del strangler fig y backlog futuro.
> - Checklist QA detallado en `docs/QA_SPRINT_FACTURACION_2026-05.md` —
>   listo para ejecutar contra el ambiente real.
> - Feature extra **F10** (Import/Export Excel de clientes con plantilla)
>   también entregada en este sprint.

---

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Confusión entre caja principal y caja chica | Modulos en rutas distintas, etiquetas claras, colores diferenciados. |
| `cash_register_movements` se desincroniza con `expected_amount` | Trigger AFTER INSERT/DELETE en la tabla, no lógica en app. |
| Editar pagos rompe la integridad contable | Audit trail con `updated_by` y diff en `app_settings_audit` análogo. |
| Reimpresión usa template viejo | Pipeline ya está testeado en `/ventas`; reusar tal cual. |

---

## Métricas

| Métrica | Baseline | Target post-sprint |
|---|---|---|
| Tiempo promedio para completar una venta en POS | ~12s | <8s con método de pago directo |
| Errores de arqueo (diferencia cierre vs esperado) | sin medir | ≤3% de las sesiones |
| Cotizaciones convertidas vs creadas | n/a | ≥40% en 30 días |
| Adopción caja chica | 0 (no existe) | uso diario en ≥80% sucursales |
