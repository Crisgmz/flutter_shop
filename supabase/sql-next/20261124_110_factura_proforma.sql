-- ============================================================================
-- Migración 110 — Factura proforma (venta completa sin NCF, convertible)
-- ============================================================================
-- Pedido del dueño (24 nov 2026): poder vender "haciendo proforma". La
-- proforma es una venta NORMAL —ITBIS, cobro, caja, crédito, inventario,
-- devoluciones— con tres diferencias:
--   1) No consume NCF ni exige cliente con RNC.
--   2) Lleva su propio número por sucursal: PRF-000001, PRF-000002…
--   3) Quien tenga el permiso `sales.convert_proforma` (de fábrica solo el
--      admin) puede convertirla después en comprobante fiscal (B02, B01…).
--      Ahí toma el NCF siguiente, se registra en `fiscal_documents` y, si el
--      negocio es electrónico, la e-CF sale sola por la cola de siempre.
--      Para el 607 cuenta la fecha de la conversión (`proforma_converted_at`),
--      que es cuando se emite el comprobante.
--
-- Se modela con un valor nuevo del enum receipt_type: 'proforma'. NO se usa
-- 'none' (sin comprobante): ese valor cobra ITBIS 0 en los RPC de venta.
--
-- BASE COMPARTIDA con shop-plus. Las funciones compartidas se PARCHEAN sobre
-- su versión viva (pg_get_functiondef), igual que la migración 97: solo se
-- agrega 'proforma' donde ya estaba 'none'. shop-plus no usa 'proforma', así
-- que para él nada cambia. Si alguna función viva no tiene el texto esperado,
-- la migración aborta sin tocar nada.
--
-- CÓMO CORRERLA (dos pasos, en el SQL Editor de Supabase):
--   PASO 1 — sola, en su propia ejecución:
--     alter type public.receipt_type add value if not exists 'proforma';
--   PASO 2 — todo este archivo.
-- (Postgres no deja usar un valor de enum en la misma transacción que lo
-- agrega.)
--
-- Idempotente: se puede correr varias veces.
-- ============================================================================

do $$
begin
  if not exists (
    select 1
      from pg_enum e
      join pg_type t on t.oid = e.enumtypid
     where t.typname = 'receipt_type' and e.enumlabel = 'proforma'
  ) then
    raise exception 'Falta el tipo proforma. Corre primero, sola: alter type public.receipt_type add value if not exists ''proforma'';';
  end if;
end $$;

begin;

-- ── 1) Columnas ─────────────────────────────────────────────────────────────
alter table public.sales
  add column if not exists proforma_number text,
  add column if not exists proforma_converted_at timestamptz;

comment on column public.sales.proforma_number is
  'Número de la factura proforma (PRF-000001), por sucursal. Se queda aunque la proforma se convierta en comprobante.';
comment on column public.sales.proforma_converted_at is
  'Cuándo la proforma se convirtió en comprobante fiscal. Es la fecha que cuenta para el 607.';

create unique index if not exists sales_branch_proforma_number_uidx
  on public.sales (branch_id, proforma_number)
  where proforma_number is not null;

create index if not exists sales_branch_proforma_converted_idx
  on public.sales (branch_id, proforma_converted_at)
  where proforma_converted_at is not null;

-- ── 2) Número PRF al crear la proforma ──────────────────────────────────────
create or replace function public.tg_sales_assign_proforma_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next bigint;
begin
  if new.receipt_type::text <> 'proforma' or new.proforma_number is not null then
    return new;
  end if;

  -- Una proforma a la vez por sucursal: sin esto dos cajas podían sacar el
  -- mismo número.
  perform pg_advisory_xact_lock(hashtext('proforma_number:' || new.branch_id::text));

  select coalesce(max(substring(s.proforma_number from '(\d+)$')::bigint), 0) + 1
    into v_next
    from public.sales s
   where s.branch_id = new.branch_id
     and s.proforma_number is not null;

  new.proforma_number := 'PRF-' || lpad(v_next::text, 6, '0');
  return new;
end;
$$;

drop trigger if exists trg_sales_assign_proforma_number on public.sales;
create trigger trg_sales_assign_proforma_number
  before insert on public.sales
  for each row
  execute function public.tg_sales_assign_proforma_number();

-- ── 3) Funciones compartidas: 'proforma' donde ya estaba 'none' ─────────────
-- Reemplaza [p_old] por [p_new] en la definición viva de [p_fn]. Exige que
-- [p_old] aparezca exactamente una vez; si ya tiene 'proforma', no hace nada.
create or replace function pg_temp.patch_fn(
  p_fn text,
  p_old text,
  p_new text,
  p_required boolean default true
)
returns void
language plpgsql
as $$
declare
  v_proc regprocedure := to_regprocedure(p_fn);
  v_def text;
  v_hits integer;
begin
  if v_proc is null then
    raise exception 'No existe %. No se cambia nada.', p_fn;
  end if;
  v_def := pg_get_functiondef(v_proc);
  if position('proforma' in v_def) > 0 then
    raise notice '% ya acepta proforma: nada que hacer.', p_fn;
    return;
  end if;
  v_hits := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_hits = 0 and not p_required then
    raise notice '% no tiene el texto "%": no se toca.', p_fn, p_old;
    return;
  end if;
  if v_hits <> 1 then
    raise exception '% no es la versión esperada (% coincidencias de "%"). No se cambia nada.',
      p_fn, v_hits, p_old;
  end if;
  execute replace(v_def, p_old, p_new);
  raise notice '%: ahora acepta proforma.', p_fn;
end;
$$;

-- 3a) Los RPC de venta pasan el tipo por aquí.
select pg_temp.patch_fn(
  'public.normalize_receipt_type(text)',
  $o$when '', 'consumer_final', 'consumidor_final' then$o$,
  $n$when 'proforma', 'factura_proforma' then
      return 'proforma'::public.receipt_type;
    when '', 'consumer_final', 'consumidor_final' then$n$
);

-- 3b) La proforma nunca consume NCF: ni al crearse ni al completarse una
-- cuenta guardada.
select pg_temp.patch_fn(
  'public.tg_sales_assign_ncf()',
  $o$if new.receipt_type::text = 'none' then$o$,
  $n$if new.receipt_type::text in ('none', 'proforma') then$n$
);
select pg_temp.patch_fn(
  'public.tg_sales_assign_ncf_on_complete()',
  $o$if new.receipt_type::text = 'none' then$o$,
  $n$if new.receipt_type::text in ('none', 'proforma') then$n$
);

-- 3c) No exige cliente con RNC (como Consumidor Final).
select pg_temp.patch_fn(
  'public.tg_sales_assert_fiscal_client()',
  $o$if new.receipt_type::text in ('consumer_final', 'none') then$o$,
  $n$if new.receipt_type::text in ('consumer_final', 'none', 'proforma') then$n$
);

-- 3d) Editar una proforma no exige cliente con RNC. Solo existe en las
-- versiones de la edición con el CAMBIO 97 de shop-plus; si la viva no lo
-- tiene, tampoco valida el cliente y no hay nada que parchear.
select pg_temp.patch_fn(
  'public.edit_sale_transactional(uuid, jsonb, uuid, boolean, text, boolean, boolean)',
  $o$if v_sale.receipt_type::text not in ('consumer_final', 'none') then$o$,
  $n$if v_sale.receipt_type::text not in ('consumer_final', 'none', 'proforma') then$n$,
  false
);

-- ── 4) Registrar el comprobante al convertir ────────────────────────────────
-- `tg_sales_register_fiscal_document` solo corre al INSERTAR una venta con
-- NCF. La conversión le pone el NCF con un UPDATE, así que se reusa la MISMA
-- función (la viva, sea cual sea su versión) en un trigger limitado a las
-- proformas: ningún otro flujo cambia.
drop trigger if exists trg_sales_register_fiscal_document_proforma on public.sales;
create trigger trg_sales_register_fiscal_document_proforma
  after update of ncf on public.sales
  for each row
  when (
    old.receipt_type::text = 'proforma'
    and old.ncf is null
    and new.ncf is not null
  )
  execute function public.tg_sales_register_fiscal_document();

-- ── 5) Convertir la proforma en comprobante ─────────────────────────────────
create or replace function public.convert_proforma_to_receipt(
  p_sale_id uuid,
  p_receipt_type text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale   record;
  v_target public.receipt_type;
  v_doc    text;
  v_name   text;
  v_ncf    text;
begin
  if auth.uid() is null then
    raise exception 'La sesión no es válida. Inicia sesión de nuevo.'
      using errcode = '42501';
  end if;

  select s.id, s.branch_id, s.status, s.receipt_type, s.ncf, s.client_id,
         s.proforma_number
    into v_sale
    from public.sales s
   where s.id = p_sale_id
   for update;
  if not found then
    raise exception 'La venta no existe.' using errcode = 'P0002';
  end if;

  if not (public.has_branch_access(v_sale.branch_id) or public.is_admin()) then
    raise exception 'No tienes acceso a esta sucursal.' using errcode = '42501';
  end if;
  if not public.has_permission('sales.convert_proforma', v_sale.branch_id) then
    raise exception 'No tienes permiso para convertir proformas en comprobante.'
      using errcode = '42501';
  end if;

  if v_sale.receipt_type::text <> 'proforma' then
    raise exception 'Esta venta no es una proforma.' using errcode = '22023';
  end if;
  if nullif(trim(coalesce(v_sale.ncf, '')), '') is not null then
    raise exception 'Esta proforma ya tiene comprobante (%).', v_sale.ncf
      using errcode = '22023';
  end if;
  if v_sale.status::text not in ('completed', 'credit') then
    raise exception 'Solo se convierte una proforma cobrada o a crédito (esta está %).',
      v_sale.status
      using errcode = '22023';
  end if;

  v_target := public.normalize_receipt_type(p_receipt_type);
  if v_target::text not in (
    'consumer_final', 'fiscal_credit', 'governmental', 'special', 'export'
  ) then
    raise exception 'Elige un comprobante fiscal para convertir la proforma.'
      using errcode = '22023';
  end if;

  -- Misma regla que tg_sales_assert_fiscal_client: todo comprobante que no
  -- sea Consumidor Final necesita un cliente con RNC/cédula y nombre.
  if v_target::text <> 'consumer_final' then
    if v_sale.client_id is null then
      raise exception 'Para este comprobante la venta debe tener un cliente con RNC/cédula. Edita la venta y elige el cliente.'
        using errcode = '22023';
    end if;
    select nullif(trim(coalesce(c.document_number, '')), ''),
           nullif(trim(coalesce(c.legal_name, c.full_name, '')), '')
      into v_doc, v_name
      from public.clients c
     where c.id = v_sale.client_id
       and c.branch_id = v_sale.branch_id;
    if v_doc is null then
      raise exception 'El cliente de la venta no tiene RNC/cédula registrado.'
        using errcode = '22023';
    end if;
    if v_name is null then
      raise exception 'El cliente de la venta no tiene razón social o nombre registrado.'
        using errcode = '22023';
    end if;
  end if;

  -- Si no hay secuencia, assign_next_ncf aborta y no se consume nada.
  v_ncf := public.assign_next_ncf(v_sale.branch_id, v_target);
  if nullif(trim(coalesce(v_ncf, '')), '') is null then
    raise exception 'No hay secuencia NCF disponible para este comprobante.'
      using errcode = '22023';
  end if;

  -- El trigger trg_sales_register_fiscal_document_proforma registra el
  -- comprobante en fiscal_documents (y encola la e-CF si aplica).
  update public.sales
     set receipt_type = v_target,
         ncf = v_ncf,
         proforma_converted_at = now()
   where id = v_sale.id;

  -- El comprobante se emite HOY, no el día de la venta: es la fecha de la
  -- e-CF y la del 607.
  update public.fiscal_documents
     set issued_at = now()
   where sale_id = v_sale.id
     and ncf = v_ncf;

  return jsonb_build_object(
    'sale_id', v_sale.id,
    'receipt_type', v_target,
    'ncf', v_ncf,
    'proforma_number', v_sale.proforma_number
  );
end;
$$;

grant execute on function public.convert_proforma_to_receipt(uuid, text) to authenticated;

-- ── 6) Permiso ──────────────────────────────────────────────────────────────
insert into public.permissions (
  code, name, module, action_type, description, sort_order
)
values
  (
    'sales.convert_proforma',
    'Convertir proforma en comprobante',
    'sales',
    'update',
    'Ponerle comprobante fiscal (B02, B01…) a una factura proforma ya '
    'vendida. Toma el NCF siguiente de la secuencia.',
    12
  )
on conflict (code) do update set
  name = excluded.name,
  module = excluded.module,
  action_type = excluded.action_type,
  description = excluded.description,
  sort_order = excluded.sort_order,
  updated_at = timezone('utc', now());

-- Solo admin (que además pasa siempre por is_admin()). `do nothing` para no
-- re-otorgar un permiso revocado a mano.
insert into public.role_permissions (role_key, permission_id, allowed)
select 'admin', p.id, true
  from public.permissions p
 where p.code = 'sales.convert_proforma'
on conflict (role_key, permission_id) do nothing;

commit;

notify pgrst, 'reload schema';

-- ── Verificación (solo lectura) ─────────────────────────────────────────────
-- select position('proforma' in pg_get_functiondef('public.normalize_receipt_type(text)'::regprocedure)) > 0 as normalize_ok,
--        position('proforma' in pg_get_functiondef('public.tg_sales_assign_ncf()'::regprocedure)) > 0 as ncf_ok,
--        position('proforma' in pg_get_functiondef('public.tg_sales_assert_fiscal_client()'::regprocedure)) > 0 as fiscal_ok;
