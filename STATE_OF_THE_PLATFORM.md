# STATE OF THE PLATFORM — Shop+ RD
**Fecha:** 2026-05-13 · **Versión:** Sprint Facturación 2026-05 cerrado

Documento vivo. Resume el estado real de la plataforma tras la serie de
PRDs y el Sprint Facturación. Se actualiza cuando se cierra cualquier
módulo, migración o feature mayor.

---

## 1. PRDs y sprints completados

| Iniciativa | Estado | Notas |
|---|---|---|
| **PRD 06 — Settings Module** | ✅ Funcional | Tabla singleton `app_settings`, ~120 opciones, audit, strangler fig en formatters / checkout / prefijos. Pendientes menores: logo upload directo, denominaciones, audit log UI. |
| **PRD 07 — Reports Module** | ✅ Round 1+2+3 entregados | Sidebar 24 categorías + navegación fullscreen con back; reportes operativos, empleados, productos, financieros, clientes, fiscal DGII (606/607/IT-1, Cierre Z, Impuestos). Vistas en tiempo real. Pendiente: export PDF/XLSX nativo, query builder, validación piloto 606/607. |
| **PRD Dashboard 06** | ✅ Funcional | KPIs hero a colores, gráfico Mes/Semana, cierre del día dedicado, F5 toggle Venta/Devolución + tabla `returns` + historial. |
| **Sprint Facturación 2026-05** | ✅ 10 features cerradas | F1-F10. Ver tabla §3. |

---

## 2. Migraciones SQL aplicadas

Orden de ejecución (post `01-04` del baseline). Cada migración es idempotente.

| # | Archivo | Resumen | Crítica para |
|---|---|---|---|
| Base | `sql/01_schema.sql` | Esquema MVP: 15 tablas + RLS + triggers de stock | Todo |
| Base | `sql/02_seed.sql` | Datos demo opcionales | Dev |
| Base | `sql/03_reports_views.sql` | 7 vistas legacy de reportes | Dashboard legacy, settings_repository |
| Base | `sql/04_branch_context.sql` | `current_branch_id()` RPC + `set_current_branch()` | Multi-sucursal |
| 1 | `sql-next/20260410_pos_transactional_core.sql` | `checkout_sale_transactional` RPC | POS |
| 2 | `sql-next/20260410_quotations_schema.sql` | Tablas `quotations`, `quotation_items`, `quotation_events` | Cotizaciones |
| 3 | `sql-next/20260421_structural_backoffice_foundation.sql` | Permissions, branch_fiscal_settings, fiscal_documents, report_exports | Permisos, fiscal |
| 4 | `sql-next/20260422_fix_permissions_final.sql` | Hardening de RLS | Auth |
| 5 | `sql-next/20260509_08_app_settings.sql` | Singleton `app_settings` + audit | PRD 06 |
| 6 | `sql-next/20260509_09_reports_schema.sql` | MVs, `inventory_movements`, `fiscal_z_closures`, `fiscal_dgii_reports`, `custom_reports`, `seal_fiscal_z_closure` | PRD 07 |
| 7 | `sql-next/20260509_10_dashboard_v2.sql` | `dashboard_v2_kpis`, `_sales_chart`, `_closeout` | Dashboard |
| 8 | `sql-next/20260509_11_returns.sql` | `returns` + `return_items` + `process_return` RPC | Devoluciones |
| 9 | `sql-next/20260509_12_closeout_returns_fix.sql` | Apunta cierre de día a `returns` real | Dashboard cierre |
| 10 | `sql-next/20260509_13_reports_round2_views.sql` | 9 vistas + 2 RPCs para reportes round 2 | PRD 07 round 2 |
| 11 | `sql-next/20260509_14_dgii_reports.sql` | `dgii_606_data`, `dgii_607_data`, `dgii_it1_summary`, `is_valid_ncf` | Fiscal DGII |
| 12 | `sql-next/20260509_15_realtime_report_views.sql` | Reescribe 6 vistas para real-time (no envolver MVs) | Fix datos del día |
| 13 | `sql-next/20260509_16_operational_extensions.sql` | `cash_register_movements`, módulo caja chica, `resolve_product_price` | Sprint F3/F8/F9 |
| 14 | `sql-next/20260509_17_quotations_fix_and_autoexpire.sql` | Fix ambigüedad + `expire_overdue_quotations` + pg_cron | Cotizaciones |

**Total:** 14 migraciones aditivas. Cero migraciones destructivas. Esquema base intacto.

---

## 3. Sprint Facturación 2026-05 — Features entregadas

| ID | Feature | Pantalla | Backend |
|---|---|---|---|
| F1 | Selector método pago (Efectivo/Tarjeta/Transferencia) + COMPLETAR VENTA + confirmación | `/ventas` | Sin cambios |
| F2 | Cotizaciones: fix `update_quotation_document` ambigüedad + auto-expirar vencidas | `/cotizaciones` | Migración 17 |
| F3 | Adición/sangría de efectivo en sesión activa | `/caja` | Migración 16 (`cash_register_movements`) |
| F4 | Historial editable de pagos por cliente | `/clientes` (dialog) | Sin cambios |
| F5 | Ver factura + reimprimir desde cobros | `/cobros` (dialog) | Sin cambios (reusa `prepareCompletedSalePrintJob`) |
| F6 | Inventario: SKU + Referencia + Costo + historial unificado | `/inventario` | Sin cambios (queries cliente) |
| F7 | Sellar Cierre Z fiscal | `/caja` (botón Sellar Z) | RPC `seal_fiscal_z_closure` (mig. 09) |
| F8 | Módulo caja chica con apertura/cierre/movimientos | `/caja-chica` nueva | Migración 16 (`petty_cash_*`) |
| F9 | Precio por cliente (tier-based) en POS | `/ventas` | Sin cambios (columnas ya existían) |
| F10 | Importar/exportar Excel de clientes con plantilla | `/clientes` (menú Excel) | Sin cambios |

---

## 4. Strangler fig en marcha

Estado de migraciones de call-sites legacy hacia el sistema unificado:

| Call-site / valor | Origen | Destino | Estado |
|---|---|---|---|
| Símbolo de moneda `RD$` | `formatters.dart` hardcoded | `LiveSettings.currencySymbol` ← `app_settings` | ✅ |
| Decimales / separadores | `formatters.dart` hardcoded | `LiveSettings.*` | ✅ |
| Formato de fecha / hora | `formatters.dart` hardcoded | `LiveSettings.dateFormat/timeFormat` | ✅ |
| Auto-imprimir tras venta | siempre true | `app_settings.receipt_print_after_sale` | ✅ |
| Confirmación de venta | siempre dialog | `app_settings.sale_disable_complete_confirmation` | ✅ |
| Bloqueo por sin stock | siempre false | `app_settings.inv_disallow_no_stock` | ✅ (en sale_checkout_service) |
| Cliente requerido para venta | siempre false | `app_settings.customer_required_for_sale` | ✅ |
| Permitir venta a crédito | siempre true | `app_settings.credit_allow_sales` | ✅ |
| Prefijos de documentos | hardcoded `FA/NC/...` | `app_settings.prefix_*` (sólo leídos al sellar Z) | ⚠️ Parcial — el cálculo del `sale_number` aún viene de migraciones legacy; el prefijo del cierre Z y del return_number sí los lee. |
| Logo / sello / firma | n/a | `app_settings.company_*_url` | ⚠️ Sólo URL pegada, no upload a Storage |
| Denominaciones de moneda | `[2000, 1000, ...]` constante | `app_settings.currency_denominations` JSONB | ⚠️ Editor visual pendiente |

---

## 5. Multi-sucursal y RLS

Todas las tablas nuevas creadas en este sprint tienen RLS branch-scoped:
- `cash_register_movements`, `petty_cash_*`, `returns`, `return_items`
- `app_settings` es singleton global (no branch-scoped por diseño).
- `fiscal_z_closures` y `fiscal_dgii_reports` son branch-scoped pero
  consultados desde reportes con `has_branch_access()`.

Estado del `is_admin` bypass del shell: el admin (dueño) tiene acceso
universal a cualquier ruta del sidebar y a sub-rutas no listadas
(`/configuracion/global`, `/panel/cierre`, `/devoluciones`, `/caja-chica`).

---

## 6. Gaps conocidos y backlog futuro

| Item | Origen | Impacto |
|---|---|---|
| Upload directo de logo/sello/firma a Supabase Storage | PRD 06 sub-fase 6.D | Bajo (URL pegada funciona como workaround) |
| Editor visual de denominaciones, métodos de pago, audit log UI | PRD 06 sub-fases 6.G, 6.I, 6.L | Bajo |
| Export PDF/XLSX nativo (paquetes `pdf`, `excel`) en reportes | PRD 07 sub-fase 7.D | Medio — hoy se copia TXT al clipboard para DGII |
| Query builder visual para reportes personalizados | PRD 07 sub-fase 7.K | Bajo |
| Etiquetas (tags) en productos | Reporte "Etiquetas" placeholder | Bajo |
| Validación piloto 606/607 byte-a-byte con declaración cliente | PRD 07 sub-fase 7.J | Alto antes de release público |
| Smoke test automatizado (script Dart o Playwright) | Round 5 sprint | Medio |
| Beneficio por entregas, Conduces, Delivery (modelos de datos) | PRD 07 Ventas sub-reportes | Bajo |
| pg_cron habilitado para auto-expirar cotizaciones server-side | Migración 17 | Bajo (la app llama la función al cargar) |

---

## 7. Próximas iniciativas sugeridas

Por orden de impacto comercial:

1. **Validación piloto DGII** con un cliente real: generar 606 y 607 de un
   mes ya declarado, comparar contra la declaración manual.
2. **Export PDF nativo** en módulo de Reportes (paquetes `pdf` +
   `printing`). Hoy sólo TXT al portapapeles.
3. **Subida de logo/sello a Storage** desde `/configuracion`. Habilita
   recibos térmicos con identidad visual completa.
4. **Comprobantes electrónicos (e-CF)**: arquitectura ya prevista en
   `DATABASE.md` §9.4; no implementada. Es el siguiente diferenciador vs
   Alegra para el mercado RD.
5. **Tests E2E** del flujo POS (abrir caja → venta con cliente → cobro →
   devolución → cierre → Z fiscal). Reduciría regresiones a la mitad.
