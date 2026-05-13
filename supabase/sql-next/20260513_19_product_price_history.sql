-- ============================================================
-- F15 — Historial de precios (Sprint Compliance 2026-05)
-- ============================================================
-- Objetivos:
--   1. Tabla product_price_history: snapshot inmutable de cada cambio de
--      precio/costo de un producto.
--   2. Trigger AFTER UPDATE OF price, cost ON products: registra el cambio.
--   3. Trigger AFTER INSERT ON products: registra el precio/costo inicial.
--   4. Vista vw_product_price_history_recent: últimos N cambios por producto.
--   5. RPC fetch_product_price_history(p_product_id, p_limit) para detalle.

-- =====================================================
-- 1) Tabla product_price_history
-- =====================================================

create table if not exists public.product_price_history (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  product_id uuid not null,
  changed_at timestamptz not null default timezone('utc', now()),
  changed_by uuid references auth.users(id),
  old_price numeric(14,2),
  new_price numeric(14,2),
  old_cost numeric(14,2),
  new_cost numeric(14,2),
  price_delta numeric(14,2),
  cost_delta numeric(14,2),
  price_pct_change numeric(7,2),
  cost_pct_change numeric(7,2),
  change_reason text,
  source text not null default 'manual',  -- manual | bulk_import | api | system
  constraint product_price_history_product_fk
    foreign key (product_id, branch_id)
    references public.products(id, branch_id)
    on delete cascade
);

create index if not exists product_price_history_product_idx
  on public.product_price_history (product_id, changed_at desc);

create index if not exists product_price_history_branch_idx
  on public.product_price_history (branch_id, changed_at desc);

comment on table public.product_price_history is
  'Snapshot inmutable de cambios de precio/costo por producto. Append-only.';

-- =====================================================
-- 2) Trigger AFTER INSERT ON products — precio inicial
-- =====================================================

create or replace function public.tg_products_log_initial_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.product_price_history (
    branch_id, product_id, changed_by,
    old_price, new_price, old_cost, new_cost,
    price_delta, cost_delta, source, change_reason
  )
  values (
    new.branch_id, new.id, auth.uid(),
    null, new.price, null, new.cost,
    null, null, 'system', 'Precio inicial'
  );
  return new;
end;
$$;

drop trigger if exists trg_products_log_initial_price on public.products;
create trigger trg_products_log_initial_price
  after insert on public.products
  for each row
  execute function public.tg_products_log_initial_price();

-- =====================================================
-- 3) Trigger AFTER UPDATE OF price, cost ON products
-- =====================================================

create or replace function public.tg_products_log_price_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_price_changed boolean := (new.price is distinct from old.price);
  v_cost_changed  boolean := (new.cost is distinct from old.cost);
  v_price_pct numeric(7,2);
  v_cost_pct  numeric(7,2);
begin
  if not v_price_changed and not v_cost_changed then
    return new;
  end if;

  -- Calcular % de cambio (NULL si valor anterior es 0 o NULL)
  if v_price_changed and old.price is not null and old.price <> 0 then
    v_price_pct := round((((new.price - old.price) / old.price) * 100)::numeric, 2);
  end if;
  if v_cost_changed and old.cost is not null and old.cost <> 0 then
    v_cost_pct := round((((new.cost - old.cost) / old.cost) * 100)::numeric, 2);
  end if;

  insert into public.product_price_history (
    branch_id, product_id, changed_by,
    old_price, new_price, old_cost, new_cost,
    price_delta, cost_delta,
    price_pct_change, cost_pct_change,
    source
  )
  values (
    new.branch_id, new.id, auth.uid(),
    old.price, new.price, old.cost, new.cost,
    case when v_price_changed then new.price - old.price end,
    case when v_cost_changed then new.cost - old.cost end,
    v_price_pct, v_cost_pct,
    'manual'
  );

  return new;
end;
$$;

drop trigger if exists trg_products_log_price_change on public.products;
create trigger trg_products_log_price_change
  after update of price, cost on public.products
  for each row
  when (new.price is distinct from old.price or new.cost is distinct from old.cost)
  execute function public.tg_products_log_price_change();

-- =====================================================
-- 4) Vista vw_product_price_history_recent
-- =====================================================
-- Devuelve los últimos 365 días de cambios con datos del producto y del
-- usuario. Útil para el reporte global.

create or replace view public.vw_product_price_history_recent
with (security_invoker = true)
as
select
  h.id,
  h.branch_id,
  h.product_id,
  p.name as product_name,
  p.sku as product_sku,
  h.changed_at,
  h.changed_by,
  prof.full_name as changed_by_name,
  h.old_price,
  h.new_price,
  h.old_cost,
  h.new_cost,
  h.price_delta,
  h.cost_delta,
  h.price_pct_change,
  h.cost_pct_change,
  h.change_reason,
  h.source
from public.product_price_history h
join public.products p
  on p.id = h.product_id and p.branch_id = h.branch_id
left join public.profiles prof
  on prof.id = h.changed_by
where h.changed_at >= timezone('utc', now()) - interval '365 days';

grant select on public.vw_product_price_history_recent to authenticated;

comment on view public.vw_product_price_history_recent is
  'Últimos 365 días de cambios de precio/costo por producto, con nombre del usuario.';

-- =====================================================
-- 5) RLS
-- =====================================================

alter table public.product_price_history enable row level security;

drop policy if exists product_price_history_select on public.product_price_history;
create policy product_price_history_select
on public.product_price_history
for select
to authenticated
using (public.has_branch_access(branch_id));

-- Solo el sistema (vía triggers) escribe; los usuarios no insertan/editan
-- directamente. Pero permitimos a admin/supervisor para casos edge.
drop policy if exists product_price_history_insert on public.product_price_history;
create policy product_price_history_insert
on public.product_price_history
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

-- =====================================================
-- 6) RPC fetch_product_price_history (detalle por producto)
-- =====================================================

create or replace function public.fetch_product_price_history(
  p_product_id uuid,
  p_limit integer default 50
)
returns table (
  id uuid,
  changed_at timestamptz,
  changed_by_name text,
  old_price numeric,
  new_price numeric,
  old_cost numeric,
  new_cost numeric,
  price_delta numeric,
  cost_delta numeric,
  price_pct_change numeric,
  cost_pct_change numeric,
  source text,
  change_reason text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
begin
  select branch_id into v_branch_id
    from public.products
   where id = p_product_id
   limit 1;

  if v_branch_id is null then
    raise exception 'Producto no encontrado' using errcode = '23503';
  end if;

  if not public.has_branch_access(v_branch_id) and not public.is_admin() then
    raise exception 'Sin acceso a la sucursal del producto' using errcode = '42501';
  end if;

  return query
    select
      h.id, h.changed_at,
      prof.full_name,
      h.old_price, h.new_price, h.old_cost, h.new_cost,
      h.price_delta, h.cost_delta,
      h.price_pct_change, h.cost_pct_change,
      h.source, h.change_reason
    from public.product_price_history h
    left join public.profiles prof on prof.id = h.changed_by
    where h.product_id = p_product_id
    order by h.changed_at desc
    limit greatest(p_limit, 1);
end;
$$;

grant execute on function public.fetch_product_price_history(uuid, integer) to authenticated;

-- Reload PostgREST schema cache
notify pgrst, 'reload schema';
