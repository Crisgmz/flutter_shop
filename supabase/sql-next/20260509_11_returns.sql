-- 20260509_11_returns.sql
-- Shop+ RD - PRD Dashboard 06 sub-fase 6: tabla `returns` y RPC para
-- procesar devoluciones desde el POS.
--
-- Ejecutar después de:
--   supabase/sql/01_schema.sql
--   supabase/sql/04_branch_context.sql
--   supabase/sql-next/20260421_structural_backoffice_foundation.sql
--   supabase/sql-next/20260509_10_dashboard_v2.sql
--
-- Diseño:
--   - Aditivo: ninguna tabla existente se altera destructivamente.
--   - `returns` referencia opcionalmente `sales(original_sale_id)` y
--     `clients(client_id)` cuando aplica; admite devolución sin cliente.
--   - Trigger `apply_return_item_stock` suma stock al insertar líneas
--     (espejo de `apply_sale_item_stock`).
--   - RPC `process_return(...)` SECURITY DEFINER que:
--       1. Genera return_number con prefijo de app_settings.prefix_credit_note.
--       2. Inserta `returns` + `return_items` en transacción.
--       3. Si la venta original era a crédito y hay cliente,
--          descuenta `clients.balance_due`.
--   - RLS branch-scoped (mismo patrón que `sales`).

begin;

-- =====================================================
-- 1) Tablas
-- =====================================================

create table if not exists public.returns (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  return_number text,
  client_id uuid,
  original_sale_id uuid,
  cashier_id uuid references auth.users(id),
  return_date timestamptz not null default timezone('utc', now()),
  notes text,
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id),
  constraint returns_client_branch_fk
    foreign key (client_id, branch_id)
    references public.clients(id, branch_id)
    on delete restrict,
  constraint returns_sale_branch_fk
    foreign key (original_sale_id, branch_id)
    references public.sales(id, branch_id)
    on delete set null
);

create unique index if not exists returns_number_unique
  on public.returns (branch_id, return_number)
  where return_number is not null;

create index if not exists returns_branch_date_idx
  on public.returns (branch_id, return_date desc);

create index if not exists returns_original_sale_idx
  on public.returns (original_sale_id)
  where original_sale_id is not null;

create table if not exists public.return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null,
  branch_id uuid not null,
  product_id uuid not null,
  description text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  tax_rate numeric(5,2) not null default 18.00,
  line_subtotal numeric(14,2) not null default 0,
  line_tax numeric(14,2) not null default 0,
  line_total numeric(14,2) not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint return_items_return_fk
    foreign key (return_id, branch_id)
    references public.returns(id, branch_id)
    on delete cascade,
  constraint return_items_product_fk
    foreign key (product_id, branch_id)
    references public.products(id, branch_id)
    on delete restrict
);

create index if not exists return_items_return_idx
  on public.return_items (return_id);

-- =====================================================
-- 2) Trigger de stock: devolución suma stock
-- =====================================================

create or replace function public.apply_return_item_stock()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    update public.products
      set stock = stock + new.quantity
    where id = new.product_id
      and branch_id = new.branch_id;
    return new;
  end if;

  if tg_op = 'DELETE' then
    update public.products
      set stock = stock - old.quantity
    where id = old.product_id
      and branch_id = old.branch_id;
    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_return_items_stock on public.return_items;
create trigger trg_return_items_stock
after insert or delete on public.return_items
for each row execute function public.apply_return_item_stock();

drop trigger if exists trg_returns_updated_at on public.returns;
create trigger trg_returns_updated_at
before update on public.returns
for each row execute function public.set_updated_at();

drop trigger if exists trg_returns_audit on public.returns;
create trigger trg_returns_audit
before insert or update on public.returns
for each row execute function public.set_audit_fields();

drop trigger if exists trg_return_items_updated_at on public.return_items;
create trigger trg_return_items_updated_at
before update on public.return_items
for each row execute function public.set_updated_at();

drop trigger if exists trg_return_items_audit on public.return_items;
create trigger trg_return_items_audit
before insert or update on public.return_items
for each row execute function public.set_audit_fields();

-- =====================================================
-- 3) RLS
-- =====================================================

alter table public.returns enable row level security;
alter table public.return_items enable row level security;

drop policy if exists returns_select on public.returns;
create policy returns_select
on public.returns
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists returns_insert on public.returns;
create policy returns_insert
on public.returns
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists returns_update on public.returns;
create policy returns_update
on public.returns
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists returns_delete on public.returns;
create policy returns_delete
on public.returns
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.is_admin());

drop policy if exists return_items_select on public.return_items;
create policy return_items_select
on public.return_items
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists return_items_insert on public.return_items;
create policy return_items_insert
on public.return_items
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists return_items_update on public.return_items;
create policy return_items_update
on public.return_items
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists return_items_delete on public.return_items;
create policy return_items_delete
on public.return_items
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.is_admin());

-- =====================================================
-- 4) RPC: process_return — todo en una transacción
-- =====================================================
--
-- Input shape:
--   p_branch_id        uuid     (opcional; si null usa current_branch_id)
--   p_client_id        uuid     (opcional)
--   p_original_sale_id uuid     (opcional)
--   p_notes            text
--   p_items            jsonb    array de {product_id, quantity, unit_price, tax_rate}
--
-- Output:
--   jsonb { return_id, return_number, total_amount, items_count }
--
-- Side-effects:
--   - Inserta returns + return_items.
--   - Triggers de inventory suman stock automáticamente.
--   - Si la venta original era a crédito y hay cliente, descuenta
--     clients.balance_due por el total de la devolución (capped a 0).

create or replace function public.process_return(
  p_branch_id uuid default null,
  p_client_id uuid default null,
  p_original_sale_id uuid default null,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_user uuid;
  v_return_id uuid;
  v_return_number text;
  v_subtotal numeric(14,2) := 0;
  v_tax numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_items_count integer := 0;
  v_item jsonb;
  v_qty numeric(14,3);
  v_price numeric(14,2);
  v_tax_rate numeric(5,2);
  v_line_subtotal numeric(14,2);
  v_line_tax numeric(14,2);
  v_line_total numeric(14,2);
  v_product_name text;
  v_was_credit_sale boolean := false;
  v_prefix text;
  v_seq bigint;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  v_user := auth.uid();

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada al usuario';
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'Una devolución requiere al menos un artículo';
  end if;

  -- Si hay venta original: validar que pertenece a la sucursal y guardar
  -- si fue a crédito (para ajustar balance_due).
  if p_original_sale_id is not null then
    select status = 'credit'::public.sale_status
      into v_was_credit_sale
      from public.sales
     where id = p_original_sale_id
       and branch_id = v_branch_id;
    if not found then
      raise exception 'La venta original no existe en esta sucursal';
    end if;
  end if;

  -- Insertar la cabecera con totales en 0; los recalculamos al final.
  insert into public.returns (
    branch_id, client_id, original_sale_id, cashier_id, notes,
    subtotal, tax_amount, total_amount
  ) values (
    v_branch_id, p_client_id, p_original_sale_id, v_user, p_notes,
    0, 0, 0
  ) returning id into v_return_id;

  -- Asignar return_number con prefijo de app_settings + correlativo por sucursal.
  select coalesce(prefix_credit_note, 'NC') into v_prefix
    from public.app_settings where id = 1;
  v_prefix := coalesce(v_prefix, 'NC');

  select coalesce(count(*), 0) + 1 into v_seq
    from public.returns
   where branch_id = v_branch_id
     and id <> v_return_id;

  v_return_number := v_prefix || '-' || lpad(v_seq::text, 5, '0');
  update public.returns set return_number = v_return_number where id = v_return_id;

  -- Insertar líneas
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::numeric(14,3);
    v_price := (v_item->>'unit_price')::numeric(14,2);
    v_tax_rate := coalesce((v_item->>'tax_rate')::numeric(5,2), 18.00);

    if v_qty is null or v_qty <= 0 then
      raise exception 'La cantidad de cada línea debe ser mayor que cero';
    end if;
    if v_price is null or v_price < 0 then
      raise exception 'El precio unitario es inválido';
    end if;

    select name into v_product_name
      from public.products
     where id = (v_item->>'product_id')::uuid
       and branch_id = v_branch_id;
    if not found then
      raise exception 'Producto no encontrado en la sucursal';
    end if;

    v_line_subtotal := round(v_qty * v_price, 2);
    v_line_tax := round(v_line_subtotal * v_tax_rate / 100.0, 2);
    v_line_total := v_line_subtotal + v_line_tax;

    insert into public.return_items (
      return_id, branch_id, product_id, description, quantity,
      unit_price, tax_rate, line_subtotal, line_tax, line_total
    ) values (
      v_return_id, v_branch_id, (v_item->>'product_id')::uuid, v_product_name, v_qty,
      v_price, v_tax_rate, v_line_subtotal, v_line_tax, v_line_total
    );

    v_subtotal := v_subtotal + v_line_subtotal;
    v_tax := v_tax + v_line_tax;
    v_total := v_total + v_line_total;
    v_items_count := v_items_count + 1;
  end loop;

  update public.returns
     set subtotal = v_subtotal,
         tax_amount = v_tax,
         total_amount = v_total
   where id = v_return_id;

  -- Si la venta original fue a crédito y hay cliente, ajustar saldo.
  if v_was_credit_sale and p_client_id is not null then
    update public.clients
       set balance_due = greatest(0, balance_due - v_total)
     where id = p_client_id
       and branch_id = v_branch_id;
  end if;

  return jsonb_build_object(
    'return_id', v_return_id,
    'return_number', v_return_number,
    'total_amount', v_total,
    'items_count', v_items_count,
    'credit_balance_adjusted', v_was_credit_sale and p_client_id is not null
  );
end;
$$;

grant execute on function public.process_return(uuid, uuid, uuid, text, jsonb) to authenticated;

-- =====================================================
-- 5) Grants
-- =====================================================

grant select, insert, update, delete on public.returns to authenticated;
grant select, insert, update, delete on public.return_items to authenticated;

commit;
