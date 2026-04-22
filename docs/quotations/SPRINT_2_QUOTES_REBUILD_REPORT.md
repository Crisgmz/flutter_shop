# Sprint 2 — Rebuild de cotizaciones

## Qué cambié

### 1) Separé cotizaciones de ventas en la capa Flutter
- `quotation_create_page.dart` ya no depende de `salesProductsProvider`, `salesClientsProvider`, `salesSearchProvider`, `SalesProduct` ni `SaleCartItem`.
- Se crearon modelos propios del módulo:
  - `QuoteCatalogProduct`
  - `QuoteClientOption`
  - `QuoteDraftLine`
  - `QuoteCreateItem`
  - `QuoteConversionResult`
- Se agregaron providers propios:
  - `quotationProductsProvider`
  - `quotationClientsProvider`
  - `quotationsSearchProvider`

### 2) Endurecí el repositorio de cotizaciones
- `QuotationsRepository` ahora:
  - carga productos/clientes directamente desde el módulo de cotizaciones
  - calcula montos con helpers centralizados (`QuotationsMath`)
  - guarda snapshots comerciales del cliente en la cotización
  - guarda snapshots de producto en `quotation_items`
  - cuenta líneas reales por cotización
  - deriva estado efectivo `expired` cuando la vigencia venció aunque el documento no se haya cerrado formalmente
  - restringe eliminación a casos seguros (`draft/rejected/expired` no convertidas)
- La conversión `quote -> sale` ya no se hace con inserciones cliente-side en varios pasos; ahora va por RPC transaccional esperada (`convert_quotation_to_sale`).

### 3) Corregí problemas críticos del flujo quote -> sale
La implementación provisional tenía varios problemas graves:
- `receipt_type` inválido (`consumidor_final` en vez de `consumer_final`)
- creaba venta `completed` sin pago consistente
- descripción genérica en `sale_items`
- sin validación real de estado/vigencia/duplicidad
- sin transacción de backend

Ahora la migración propuesta deja el flujo así:
- solo convierte cotizaciones `approved`
- bloquea cotizaciones vencidas
- bloquea cotizaciones ya convertidas
- valida que existan líneas
- valida stock antes de convertir
- crea venta ligada a la cotización fuente
- crea `sale_items` con snapshots reales de línea
- deja la venta en `pending` con `paid_amount = 0` y `balance_due = total_amount`
- marca la cotización como `converted`
- registra evento de auditoría

### 4) Rehice la SQL additive de cotizaciones
`supabase/sql-next/20260410_quotations_schema.sql` ahora propone una base mucho más seria:
- enum `quote_status`
- columnas de snapshot comercial en `quotations`
- `version_no`, `owner_user_id`, timestamps de ciclo de vida
- `converted_sale_id` y vínculo de `sales` hacia la cotización fuente
- `quotation_items` con `branch_id`, `product_name`, `product_sku`, `description`
- `quotation_events` para auditoría mínima
- triggers de `updated_at` y auditoría
- RLS alineada con `has_branch_access(...)`, `can_operate_pos()` y `can_manage_branch_data()`
- función transaccional `convert_quotation_to_sale(...)`
- backfills básicos para ambientes que tengan la versión provisional

## Validación ejecutada
- `flutter analyze lib/features/quotations test/features/quotations` ✅
- Se agregó test unitario en `test/features/quotations/quotations_models_test.dart`
- `flutter test test/features/quotations/quotations_models_test.dart` ⚠️ falló por problema del entorno local al lanzar `flutter_tester`:
  - error: `Resource deadlock avoided`

## Gaps que quedan
- no hay editor/gestión formal de cambios de estado (`sent`, `under_review`, `approved`, `rejected`) desde UI
- el versionado quedó preparado solo a nivel estructural (`version_no`, `source_quotation_id`), no con workflow completo de nuevas versiones
- no hay approvals internas ni permisos finos por acción todavía
- no hay impresión/PDF de cotización conectada al flujo final
- no hay reportes comerciales específicos ni seguimiento/follow-ups
- el módulo sigue siendo joven; falta integrarlo con la futura capa transversal de documentos comerciales

## Juicio final
**Sí: cotizaciones queda bastante más creíble estructuralmente que antes.**

Todavía no está “terminado”, pero ya deja de ser un MVP peligroso o demasiado maquillado:
- tiene identidad de módulo propia
- la seguridad SQL ya no queda abierta en modo `USING (true)`
- el flujo quote -> sale deja de ser una cadena frágil de inserts desde Flutter
- el documento conserva mejores snapshots y trazabilidad

Mi veredicto: **ahora es una base estructuralmente seria para seguir iterando**, aunque todavía no es un módulo comercial completo de nivel final.
