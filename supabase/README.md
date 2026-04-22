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
