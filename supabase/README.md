# Supabase Setup (Shop+ RD)

Estos scripts se basan en `HANDOFF_REACT_A_FLUTTER_PRD.TXT` y en los modulos actuales de Flutter.

## Orden de ejecucion

1. `supabase/sql/01_schema.sql`
2. `supabase/sql/02_seed.sql`
3. `supabase/sql/03_reports_views.sql`
4. `supabase/sql/04_branch_context.sql`

Ejecutalos en Supabase SQL Editor en ese orden.

## Drafts no ejecutables aun

- `supabase/drafts/20260410_cash_architecture_foundation_draft.sql`
  - draft conceptual base de la arquitectura de caja
  - sirvio como base para la serie ejecutable en `supabase/sql-next/`

## Serie ejecutable siguiente (manual, fuera del 01-04 actual)

Cuando se apruebe el rollout de caja, ejecutar manualmente en este orden:

1. `supabase/sql-next/05_cash_foundation_core.sql`
2. `supabase/sql-next/06_cash_foundation_backfill.sql`
3. `supabase/sql-next/07_cash_foundation_views.sql`

Objetivo de esta serie:
- introducir `cash_locations`, `cash_movements`, `cash_transfers`
- evolucionar `cash_sessions` hacia sesiones por ubicacion
- mantener compatibilidad con el runtime actual mientras el app aun opera por sucursal

## Configuración global y reportes (PRD 06 + PRD 07)

Tras la base estructural (`20260421_structural_backoffice_foundation.sql`), ejecutar:

1. `supabase/sql-next/20260509_08_app_settings.sql` — PRD 06: tabla singleton `app_settings` con ~120 opciones tipadas, audit log y RLS (admin escribe, autenticados leen).
2. `supabase/sql-next/20260509_09_reports_schema.sql` — PRD 07: `inventory_movements` (mermas), `fiscal_z_closures` (inmutable), `fiscal_dgii_reports` (606/607/IT-1), `custom_reports`, 6 materialized views, vistas con RLS, función `seal_fiscal_z_closure`.
3. `supabase/sql-next/20260509_10_dashboard_v2.sql` — PRD Dashboard 06 (sub-fase 2): 3 RPCs `dashboard_v2_kpis`, `dashboard_v2_sales_chart`, `dashboard_v2_closeout` (6 bloques), todas SECURITY DEFINER + branch-scoped.
4. `supabase/sql-next/20260509_11_returns.sql` — PRD Dashboard 06 (sub-fase 6 + F5): tablas `returns` y `return_items` con trigger de stock, RPC `process_return(...)` que inserta cabecera + líneas y ajusta `clients.balance_due` si la venta original fue a crédito. RLS branch-scoped.
5. `supabase/sql-next/20260509_12_closeout_returns_fix.sql` — fix del bloque "Devoluciones" del RPC `dashboard_v2_closeout`: ahora lee de la tabla `returns` real (antes proxy con `sales.voided`). Marca `returns_table_available: true`.
6. `supabase/sql-next/20260509_13_reports_round2_views.sql` — PRD 07 Round 2: vistas + RPCs para 11 reportes operativos (Empleados, Comisión, Inventario, Precios, P&L, Crédito aging, Gastos, Compras, Proveedores, Clientes, Descuentos). Todas con `security_invoker = true` para RLS por sucursal.
7. `supabase/sql-next/20260509_14_dgii_reports.sql` — PRD 07 Round 3 (★ fiscal): RPCs `dgii_606_data`, `dgii_607_data`, `dgii_it1_summary`, vista `report_tax_breakdown_view` para Impuestos, helper `record_dgii_report(...)` para persistir el reporte generado en `fiscal_dgii_reports`. Solo admin/accountant pueden ejecutar.
8. `supabase/sql-next/20260509_15_realtime_report_views.sql` — Fix crítico: `sales_daily_view`, `sales_by_item_view`, `sales_by_category_view`, `purchases_daily_view`, `inventory_movements_daily_view`, `cash_session_summary_view` ahora leen directo de tablas (real-time) en vez de envolver materialized views que requerían refresh manual. Las MVs siguen disponibles para analítica futura.
9. `supabase/sql-next/20260509_16_operational_extensions.sql` — Sprint Facturación 2026-05: tabla `cash_register_movements` (inyección/sangría de caja activa) con trigger que ajusta `expected_amount`; módulo caja chica completo (`petty_cash_sessions`, `petty_cash_movements`, `petty_cash_categories` con seed); función `resolve_product_price(product_id, client_id)` para tier-based pricing. RLS branch-scoped en todas las tablas nuevas.
10. `supabase/sql-next/20260509_17_quotations_fix_and_autoexpire.sql` — Fix de ambigüedad en `update_quotation_document` (calificación explícita de `quotation_items.quotation_id`); nueva función `expire_overdue_quotations()` que marca como `expired` cotizaciones vencidas; intenta agendar pg_cron cada 15 min si la extensión está disponible.

Notas:
- `app_settings` se inicializa con la fila `id=1` y copia `name/legal_name/tax_id/website/logo_url` desde la sucursal principal si existe.
- Los cierres Z son inmutables: el trigger `trg_fiscal_z_closures_block_update` rechaza cualquier UPDATE.
- Las MVs (`mv_sales_daily`, `mv_sales_by_item`, `mv_sales_by_category`, `mv_purchases_daily`, `mv_inventory_movements_daily`, `mv_cash_session_summary`) se refrescan vía `refresh_business_reports()` o, programado, `refresh_business_reports_concurrently()`.


## Que incluye

- Auth + `profiles` sincronizado con `auth.users`
- Multi-sucursal: `branches`, `users_branches`
- Catalogo: `product_categories`, `products`
- CRM/Compras: `clients`, `suppliers`, `purchases`, `purchase_items`
- POS/Cobros/Caja: `sales`, `sale_items`, `payments`, `cash_sessions`, `expenses`
- Fiscal base: `ncf_sequences`, `receipt_type`, `dgii_status`
- RLS por sucursal y rol (`admin`, `supervisor`, `cashier`, `accountant`)
- Triggers de auditoria (`created_by`, `updated_by`, `updated_at`)
- Triggers de inventario (compra suma stock, venta descuenta stock)

## Verificacion rapida

```sql
select count(*) as branches from public.branches;
select count(*) as products from public.products;
select count(*) as clients from public.clients;
select count(*) as sales from public.sales;
select count(*) as payments from public.payments;

select * from public.dashboard_kpis_by_branch;
select * from public.sales_monthly_summary where branch_code = 'MAIN' order by period_start;
select * from public.latest_sales_view limit 10;
select * from public.inventory_low_stock_view;
select * from public.ncf_usage_summary where branch_code = 'MAIN';
```

## Usuario de prueba esperado

Si ya creaste el usuario de auth:

- `admin@shopplusrd.test`
- `Admin123456!`

el seed lo vincula a `Sucursal Principal` y le asigna rol `admin`.
