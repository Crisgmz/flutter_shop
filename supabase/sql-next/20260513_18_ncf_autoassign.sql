-- ============================================================
-- F11 — NCF auto-asignación en venta (Sprint Compliance 2026-05)
-- ============================================================
-- Objetivos:
--   1. RPC assign_next_ncf(branch, receipt_type) — lock + increment + return formatted NCF.
--   2. Trigger BEFORE INSERT on sales — asigna NCF automáticamente si status ∈ {completed, credit}.
--   3. Trigger BEFORE UPDATE on sales — asigna NCF cuando una venta pendiente/draft se completa.
--   4. fiscal_documents — registra el comprobante emitido (snapshot).
--   5. vw_ncf_stock — vista para banners/alertas cuando quedan pocos.
--   6. RPC bulk_assign_missing_ncfs — backfill manual desde /configuracion (opcional).
--
-- Idempotente: todos los triggers/funciones usan CREATE OR REPLACE.

-- =====================================================
-- 1) RPC: assign_next_ncf
-- =====================================================
--
-- Lockea la secuencia activa que tenga capacidad para esta sucursal/tipo,
-- avanza el contador y devuelve el NCF formateado (prefix + 8 dígitos).
-- Lanza excepción descriptiva si no hay secuencia disponible.

create or replace function public.assign_next_ncf(
  p_branch_id    uuid,
  p_receipt_type public.receipt_type
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq_id      uuid;
  v_prefix      text;
  v_next_num    bigint;
  v_seq_end     bigint;
  v_ncf         text;
begin
  if p_branch_id is null then
    raise exception 'branch_id requerido' using errcode = '22023';
  end if;

  if not public.has_branch_access(p_branch_id) and not public.is_admin() then
    raise exception 'Sin acceso a la sucursal indicada' using errcode = '42501';
  end if;

  -- Buscar la secuencia activa con capacidad. Si hay varias, usar la que
  -- tenga el contador más bajo (consumir primero la más antigua).
  select id, prefix, next_number, sequence_end
    into v_seq_id, v_prefix, v_next_num, v_seq_end
    from public.ncf_sequences
   where branch_id = p_branch_id
     and receipt_type = p_receipt_type
     and is_active = true
     and coalesce(status, 'active') = 'active'
     and (expires_on is null or expires_on >= current_date)
     and (sequence_end is null or next_number <= sequence_end)
   order by next_number asc nulls last
   limit 1
   for update;

  if v_seq_id is null then
    raise exception 'No hay secuencia NCF disponible para % en esta sucursal. Configúrala en /configuracion › NCF.', p_receipt_type
      using errcode = 'P0001';
  end if;

  if v_next_num is null then
    v_next_num := 1;
  end if;

  if v_seq_end is not null and v_next_num > v_seq_end then
    raise exception 'Secuencia NCF agotada para % (último: %). Crea una nueva o extiéndela.', p_receipt_type, v_seq_end
      using errcode = 'P0001';
  end if;

  -- Avanzar la secuencia
  update public.ncf_sequences
     set current_number = v_next_num,
         next_number    = v_next_num + 1,
         updated_at     = timezone('utc', now())
   where id = v_seq_id;

  v_ncf := v_prefix || lpad(v_next_num::text, 8, '0');
  return v_ncf;
end;
$$;

grant execute on function public.assign_next_ncf(uuid, public.receipt_type) to authenticated;

comment on function public.assign_next_ncf(uuid, public.receipt_type) is
  'Lockea y avanza la secuencia NCF activa para (branch, tipo). Devuelve el NCF formateado.';

-- =====================================================
-- 2) Trigger: BEFORE INSERT on sales
-- =====================================================
--
-- Asigna NCF si:
--   - new.ncf es null
--   - new.status ∈ {completed, credit, pending}
--   - existe secuencia para el receipt_type
-- Para draft/voided se omite (no se emite comprobante fiscal).

create or replace function public.tg_sales_assign_ncf()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.ncf is not null and length(trim(new.ncf)) > 0 then
    return new;  -- ya tiene NCF explícito
  end if;

  if new.status in ('completed'::public.sale_status, 'credit'::public.sale_status) then
    begin
      new.ncf := public.assign_next_ncf(new.branch_id, new.receipt_type);
    exception when others then
      -- No bloqueamos la venta si no hay secuencia; la venta se guarda sin
      -- NCF y queda visible en vw_ncf_stock para que el admin la corrija.
      -- Loguear con raise notice para que aparezca en el log de Postgres.
      raise notice 'No se pudo asignar NCF para venta % (tipo %): %',
        new.id, new.receipt_type, SQLERRM;
    end;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sales_assign_ncf on public.sales;
create trigger trg_sales_assign_ncf
  before insert on public.sales
  for each row
  execute function public.tg_sales_assign_ncf();

-- =====================================================
-- 3) Trigger: BEFORE UPDATE on sales (status transitions)
-- =====================================================
--
-- Si una venta pasa de draft/pending → completed/credit y no tenía NCF,
-- la asigna en ese momento. Útil para suspended sales que se reanudan.

create or replace function public.tg_sales_assign_ncf_on_complete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Solo si pasamos a un estado que requiere NCF
  if new.status not in ('completed'::public.sale_status, 'credit'::public.sale_status) then
    return new;
  end if;

  -- Solo si todavía no tiene NCF
  if new.ncf is not null and length(trim(new.ncf)) > 0 then
    return new;
  end if;

  -- Solo cuando el estado cambió desde draft/pending
  if old.status not in ('draft'::public.sale_status, 'pending'::public.sale_status) then
    return new;
  end if;

  begin
    new.ncf := public.assign_next_ncf(new.branch_id, new.receipt_type);
  exception when others then
    raise notice 'No se pudo asignar NCF al completar venta % (tipo %): %',
      new.id, new.receipt_type, SQLERRM;
  end;

  return new;
end;
$$;

drop trigger if exists trg_sales_assign_ncf_on_complete on public.sales;
create trigger trg_sales_assign_ncf_on_complete
  before update of status on public.sales
  for each row
  when (old.status is distinct from new.status)
  execute function public.tg_sales_assign_ncf_on_complete();

-- =====================================================
-- 4) Trigger: AFTER INSERT on sales — fiscal_documents snapshot
-- =====================================================
--
-- Después de insertar la venta con su NCF, crea el registro espejo en
-- fiscal_documents (cuando aplique). Esto deja un documento fiscal trazable
-- que sobrevive aunque la venta se anule más tarde.

create or replace function public.tg_sales_register_fiscal_document()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq_id        uuid;
  v_seq_number    bigint;
  v_client        record;
  v_settings      record;
begin
  if new.ncf is null or length(trim(new.ncf)) = 0 then
    return new;
  end if;

  -- Localizar la secuencia que produjo este NCF (por prefijo + tipo)
  select id
    into v_seq_id
    from public.ncf_sequences
   where branch_id = new.branch_id
     and receipt_type = new.receipt_type
     and new.ncf like prefix || '%'
   order by current_number desc
   limit 1;

  -- Extraer la parte numérica del NCF
  begin
    v_seq_number := (regexp_replace(new.ncf, '\D', '', 'g'))::bigint;
  exception when others then
    v_seq_number := null;
  end;

  -- Snapshot del cliente
  if new.client_id is not null then
    select c.full_name, c.legal_name, c.document_type, c.document_number, c.address
      into v_client
      from public.clients c
     where c.id = new.client_id
       and c.branch_id = new.branch_id;
  end if;

  -- Snapshot del emisor
  select company_name, company_legal_name, company_tax_id
    into v_settings
    from public.app_settings
   where id = 1;

  insert into public.fiscal_documents (
    branch_id, sale_id, client_id, ncf_sequence_id, receipt_type,
    ncf, sequence_number, fiscal_status, issued_at,
    customer_name, customer_document_type, customer_document_number, customer_address,
    issuer_name, issuer_tax_id,
    subtotal, discount_amount, tax_amount, total_amount,
    payload
  ) values (
    new.branch_id, new.id, new.client_id, v_seq_id, new.receipt_type,
    new.ncf, v_seq_number, 'pending'::public.dgii_status, new.sale_date,
    coalesce(v_client.legal_name, v_client.full_name),
    v_client.document_type::text,
    v_client.document_number,
    v_client.address,
    coalesce(nullif(v_settings.company_legal_name, ''), v_settings.company_name),
    v_settings.company_tax_id,
    new.subtotal, new.discount_amount, new.tax_amount, new.total_amount,
    jsonb_build_object('sale_number', new.sale_number)
  )
  on conflict (branch_id, ncf) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_sales_register_fiscal_document on public.sales;
create trigger trg_sales_register_fiscal_document
  after insert on public.sales
  for each row
  when (new.ncf is not null)
  execute function public.tg_sales_register_fiscal_document();

-- =====================================================
-- 5) Vista: vw_ncf_stock — para banners/alertas
-- =====================================================

create or replace view public.vw_ncf_stock
with (security_invoker = true)
as
select
  ns.id              as sequence_id,
  ns.branch_id,
  ns.receipt_type,
  ns.prefix,
  ns.series,
  ns.current_number,
  ns.next_number,
  ns.sequence_start,
  ns.sequence_end,
  case
    when ns.sequence_end is null then null
    else greatest(ns.sequence_end - coalesce(ns.next_number, ns.current_number + 1) + 1, 0)
  end as remaining,
  ns.warning_threshold,
  ns.expires_on,
  ns.is_active,
  coalesce(ns.status, 'active') as status,
  (ns.expires_on is not null and ns.expires_on < current_date) as is_expired,
  (
    ns.is_active
    and coalesce(ns.status, 'active') = 'active'
    and ns.sequence_end is not null
    and (ns.sequence_end - coalesce(ns.next_number, ns.current_number + 1) + 1) <= coalesce(ns.warning_threshold, 25)
  ) as is_low_stock
from public.ncf_sequences ns;

grant select on public.vw_ncf_stock to authenticated;

comment on view public.vw_ncf_stock is
  'Vista de stock de NCFs disponibles por secuencia. Útil para banners de alerta.';

-- =====================================================
-- 6) RPC: backfill manual (opcional, para admin)
-- =====================================================
--
-- Recorre las ventas completed/credit sin NCF de una sucursal y les asigna
-- el siguiente disponible. Útil si una secuencia se configura tarde.

create or replace function public.bulk_assign_missing_ncfs(p_branch_id uuid)
returns table(sale_id uuid, sale_number text, ncf text, error text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale record;
  v_ncf  text;
begin
  if not public.has_branch_access(p_branch_id) and not public.is_admin() then
    raise exception 'Sin acceso a la sucursal indicada' using errcode = '42501';
  end if;

  for v_sale in
    select s.id, s.sale_number, s.receipt_type
      from public.sales s
     where s.branch_id = p_branch_id
       and s.status in ('completed'::public.sale_status, 'credit'::public.sale_status)
       and (s.ncf is null or length(trim(s.ncf)) = 0)
     order by s.sale_date asc
  loop
    begin
      v_ncf := public.assign_next_ncf(p_branch_id, v_sale.receipt_type);
      update public.sales
         set ncf = v_ncf
       where id = v_sale.id;
      return query select v_sale.id, v_sale.sale_number, v_ncf, null::text;
    exception when others then
      return query select v_sale.id, v_sale.sale_number, null::text, SQLERRM;
    end;
  end loop;
end;
$$;

grant execute on function public.bulk_assign_missing_ncfs(uuid) to authenticated;

-- Reload PostgREST schema cache
notify pgrst, 'reload schema';
