-- ============================================================================
-- Migración 65 — RPC dashboard_hero_kpis: KPIs del panel sin timeout
-- ============================================================================
-- Contexto: aun con la vista acotada al mes (migración 64), el panel seguía
-- cancelando por statement_timeout (57014) en instalaciones con datos. La
-- vista es security_invoker: la RLS ejecuta has_branch_access() FILA POR FILA
-- sobre products, clients y sales (cada llamada = users_branches ⋈ profiles),
-- y products/clients ni siquiera tienen índice por branch_id.
--
-- Fix definitivo para el panel:
--   1. RPC `dashboard_hero_kpis()` SECURITY DEFINER: valida el acceso UNA vez
--      y luego hace consultas directas por sucursal (sin RLS por fila).
--   2. Índices parciales por sucursal para los contadores de products/clients.
-- La vista dashboard_kpis_by_branch queda para compatibilidad/reportes, pero
-- el panel deja de usarla.
--
-- Ejecutar en el SQL Editor (idempotente). La app usa el RPC si existe y cae
-- a la vista si no (compatible con DBs sin migrar).
-- ============================================================================

begin;

-- Contadores del panel: contar activos de UNA sucursal sin seq scan.
create index if not exists products_branch_active_idx
  on public.products (branch_id)
  where is_active;

create index if not exists clients_branch_active_idx
  on public.clients (branch_id)
  where is_active;

create or replace function public.dashboard_hero_kpis(p_branch_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_branch       uuid := coalesce(p_branch_id, public.current_branch_id());
  v_month_start  timestamptz := date_trunc('month', timezone('utc', now()));
  v_today        date := timezone('utc', now())::date;
  v_sales_today_amount numeric := 0;
  v_sales_today_count  bigint  := 0;
  v_sales_month_amount numeric := 0;
  v_sales_month_count  bigint  := 0;
  v_ecf_issued_month   bigint  := 0;
  v_products_active    bigint  := 0;
  v_clients_active     bigint  := 0;
begin
  if v_branch is null then
    return '{}'::jsonb;
  end if;

  -- Un solo chequeo de acceso (en la vista la RLS lo hacía por cada fila).
  if not public.has_branch_access(v_branch) and not public.is_admin() then
    raise exception 'Sin acceso a la sucursal indicada' using errcode = '42501';
  end if;

  -- Ventas del mes corriente: range scan sobre sales_date_idx (branch, fecha).
  select
    coalesce(sum(case when s.sale_date::date = v_today then s.total_amount else 0 end), 0),
    coalesce(sum(case when s.sale_date::date = v_today then 1 else 0 end), 0),
    coalesce(sum(s.total_amount), 0),
    count(*),
    coalesce(sum(case when s.ncf is not null then 1 else 0 end), 0)
    into v_sales_today_amount, v_sales_today_count,
         v_sales_month_amount, v_sales_month_count, v_ecf_issued_month
  from public.sales s
  where s.branch_id = v_branch
    and s.sale_date >= v_month_start
    and s.sale_date <  v_month_start + interval '1 month'
    and s.status not in ('voided'::public.sale_status, 'pending'::public.sale_status);

  select count(*) into v_products_active
  from public.products where branch_id = v_branch and is_active;

  select count(*) into v_clients_active
  from public.clients where branch_id = v_branch and is_active;

  return jsonb_build_object(
    'branch_id',          v_branch,
    'sales_today_amount', v_sales_today_amount,
    'sales_today_count',  v_sales_today_count,
    'sales_month_amount', v_sales_month_amount,
    'sales_month_count',  v_sales_month_count,
    'ecf_issued_month',   v_ecf_issued_month,
    'products_active',    v_products_active,
    'clients_active',     v_clients_active
  );
end;
$$;

grant execute on function public.dashboard_hero_kpis(uuid) to authenticated;

comment on function public.dashboard_hero_kpis(uuid) is
  'KPIs del panel para una sucursal (default: la actual). SECURITY DEFINER: valida acceso una vez y consulta por índices, sin RLS por fila. Reemplaza a dashboard_kpis_by_branch en el panel.';

commit;

notify pgrst, 'reload schema';
