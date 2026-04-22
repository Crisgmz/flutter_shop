begin;

create extension if not exists pgcrypto;

-- =========================================================
-- Quotations status enum
-- =========================================================
do $$
begin
  if not exists (select 1 from pg_type where typname = 'quote_status') then
    create type public.quote_status as enum (
      'draft',
      'sent',
      'under_review',
      'approved',
      'rejected',
      'expired',
      'converted'
    );
  end if;
end $$;

-- =========================================================
-- Sales linkage back to quotation source (additive)
-- =========================================================
alter table public.sales
  add column if not exists source_quotation_id uuid,
  add column if not exists source_quotation_code text;

create index if not exists sales_source_quotation_idx
  on public.sales (source_quotation_id)
  where source_quotation_id is not null;

-- =========================================================
-- Quotations master table
-- =========================================================
create table if not exists public.quotations (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  client_id uuid,
  converted_sale_id uuid,
  source_quotation_id uuid,
  code text not null,
  status public.quote_status not null default 'draft',
  version_no integer not null default 1 check (version_no >= 1),
  owner_user_id uuid references auth.users(id),
  valid_until timestamptz not null,
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  notes text,
  client_display_name text,
  client_legal_name text,
  client_email text,
  client_phone text,
  client_document_type text,
  client_document_number text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  sent_at timestamptz,
  approved_at timestamptz,
  rejected_at timestamptz,
  expired_at timestamptz,
  converted_at timestamptz,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  converted_by uuid references auth.users(id),
  unique (id, branch_id),
  constraint quotations_client_branch_fk
    foreign key (client_id, branch_id)
    references public.clients(id, branch_id)
    on delete restrict,
  constraint quotations_sale_branch_fk
    foreign key (converted_sale_id, branch_id)
    references public.sales(id, branch_id)
    on delete restrict,
  constraint quotations_parent_fk
    foreign key (source_quotation_id)
    references public.quotations(id)
    on delete restrict
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.quotations'::regclass
      and contype = 'u'
      and conname = 'quotations_id_branch_unique'
  ) then
    alter table public.quotations add constraint quotations_id_branch_unique unique (id, branch_id);
  end if;
end $$;

alter table public.quotations
  add column if not exists branch_id uuid,
  add column if not exists client_id uuid,
  add column if not exists converted_sale_id uuid,
  add column if not exists source_quotation_id uuid,
  add column if not exists code text,
  add column if not exists version_no integer not null default 1,
  add column if not exists owner_user_id uuid references auth.users(id),
  add column if not exists valid_until timestamptz,
  add column if not exists subtotal numeric(14,2) not null default 0,
  add column if not exists discount_amount numeric(14,2) not null default 0,
  add column if not exists tax_amount numeric(14,2) not null default 0,
  add column if not exists total_amount numeric(14,2) not null default 0,
  add column if not exists notes text,
  add column if not exists client_display_name text,
  add column if not exists client_legal_name text,
  add column if not exists client_email text,
  add column if not exists client_phone text,
  add column if not exists client_document_type text,
  add column if not exists client_document_number text,
  add column if not exists sent_at timestamptz,
  add column if not exists approved_at timestamptz,
  add column if not exists rejected_at timestamptz,
  add column if not exists expired_at timestamptz,
  add column if not exists converted_at timestamptz,
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists updated_by uuid references auth.users(id),
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists converted_by uuid references auth.users(id);

alter table public.quotations
  add column if not exists status text default 'draft';

 do $$
 declare
   v_status_type text;
 begin
   select c.udt_name
     into v_status_type
   from information_schema.columns c
   where c.table_schema = 'public'
     and c.table_name = 'quotations'
     and c.column_name = 'status';

   if v_status_type is distinct from 'quote_status' then
     alter table public.quotations
       alter column status drop default;
     alter table public.quotations
       alter column status type public.quote_status
       using coalesce(nullif(status::text, ''), 'draft')::public.quote_status;
     alter table public.quotations
       alter column status set default 'draft'::public.quote_status;
   end if;
 end $$;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'quotations'
      and column_name = 'sale_id'
  ) then
    execute 'update public.quotations set converted_sale_id = sale_id where converted_sale_id is null and sale_id is not null';
  end if;
end $$;

update public.quotations q
   set client_display_name = coalesce(q.client_display_name, c.full_name)
  from public.clients c
 where q.client_id = c.id
   and q.branch_id = c.branch_id
   and q.client_display_name is null;

create unique index if not exists quotations_branch_code_unique
  on public.quotations (branch_id, code);

create index if not exists quotations_branch_status_idx
  on public.quotations (branch_id, status, valid_until desc);

create index if not exists quotations_owner_idx
  on public.quotations (owner_user_id, created_at desc);

-- =========================================================
-- Quotation lines with commercial snapshots
-- =========================================================
create table if not exists public.quotation_items (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null,
  branch_id uuid not null,
  product_id uuid not null,
  product_name text not null,
  product_sku text,
  description text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_rate numeric(5,2) not null default 18.00 check (tax_rate >= 0 and tax_rate <= 100),
  line_subtotal numeric(14,2) not null check (line_subtotal >= 0),
  line_tax numeric(14,2) not null default 0 check (line_tax >= 0),
  line_total numeric(14,2) not null check (line_total >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint quotation_items_quotation_fk
    foreign key (quotation_id, branch_id)
    references public.quotations(id, branch_id)
    on delete cascade,
  constraint quotation_items_product_fk
    foreign key (product_id, branch_id)
    references public.products(id, branch_id)
    on delete restrict
);

alter table public.quotation_items
  add column if not exists quotation_id uuid,
  add column if not exists branch_id uuid,
  add column if not exists product_id uuid,
  add column if not exists product_name text,
  add column if not exists product_sku text,
  add column if not exists description text,
  add column if not exists quantity numeric(14,3) not null default 1,
  add column if not exists unit_price numeric(14,2) not null default 0,
  add column if not exists discount_amount numeric(14,2) not null default 0,
  add column if not exists tax_rate numeric(5,2) not null default 18.00,
  add column if not exists line_subtotal numeric(14,2) not null default 0,
  add column if not exists line_tax numeric(14,2) not null default 0,
  add column if not exists line_total numeric(14,2) not null default 0,
  add column if not exists updated_at timestamptz not null default timezone('utc', now()),
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists updated_by uuid references auth.users(id);

update public.quotation_items qi
   set branch_id = q.branch_id
  from public.quotations q
 where qi.quotation_id = q.id
   and qi.branch_id is null;

update public.quotation_items qi
   set product_name = coalesce(qi.product_name, p.name),
       product_sku = coalesce(qi.product_sku, p.sku),
       description = coalesce(qi.description, p.name)
  from public.products p
 where qi.product_id = p.id
   and qi.branch_id = p.branch_id
   and (qi.product_name is null or qi.description is null);

create index if not exists quotation_items_quotation_idx
  on public.quotation_items (quotation_id);

-- =========================================================
-- Quotations event log / audit trail
-- =========================================================
create table if not exists public.quotation_events (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null,
  branch_id uuid not null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  constraint quotation_events_quotation_fk
    foreign key (quotation_id, branch_id)
    references public.quotations(id, branch_id)
    on delete cascade
);

create index if not exists quotation_events_quotation_idx
  on public.quotation_events (quotation_id, created_at desc);

-- =========================================================
-- Triggers
-- =========================================================
drop trigger if exists trg_quotations_updated_at on public.quotations;
create trigger trg_quotations_updated_at
before update on public.quotations
for each row execute function public.set_updated_at();

drop trigger if exists trg_quotation_items_updated_at on public.quotation_items;
create trigger trg_quotation_items_updated_at
before update on public.quotation_items
for each row execute function public.set_updated_at();

drop trigger if exists trg_quotations_audit_fields on public.quotations;
create trigger trg_quotations_audit_fields
before insert or update on public.quotations
for each row execute function public.set_audit_fields();

drop trigger if exists trg_quotation_items_audit_fields on public.quotation_items;
create trigger trg_quotation_items_audit_fields
before insert or update on public.quotation_items
for each row execute function public.set_audit_fields();

-- =========================================================
-- Permissions / RLS aligned with main schema
-- =========================================================
alter table public.quotations enable row level security;
alter table public.quotation_items enable row level security;
alter table public.quotation_events enable row level security;

drop policy if exists quotations_select on public.quotations;
create policy quotations_select
on public.quotations
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists quotations_insert on public.quotations;
create policy quotations_insert
on public.quotations
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists quotations_update on public.quotations;
create policy quotations_update
on public.quotations
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists quotations_delete on public.quotations;
create policy quotations_delete
on public.quotations
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists quotation_items_select on public.quotation_items;
create policy quotation_items_select
on public.quotation_items
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists quotation_items_insert on public.quotation_items;
create policy quotation_items_insert
on public.quotation_items
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists quotation_items_update on public.quotation_items;
create policy quotation_items_update
on public.quotation_items
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists quotation_items_delete on public.quotation_items;
create policy quotation_items_delete
on public.quotation_items
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists quotation_events_select on public.quotation_events;
create policy quotation_events_select
on public.quotation_events
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists quotation_events_insert on public.quotation_events;
create policy quotation_events_insert
on public.quotation_events
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists quotation_events_delete on public.quotation_events;
create policy quotation_events_delete
on public.quotation_events
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

-- =========================================================
-- Transactional quote -> sale conversion
-- =========================================================
create or replace function public.convert_quotation_to_sale(
  target_quotation_id uuid,
  requested_receipt_type public.receipt_type default 'consumer_final',
  requested_sale_status public.sale_status default 'pending'
)
returns table (sale_id uuid, sale_number text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_quote public.quotations%rowtype;
  v_sale_id uuid;
  v_sale_number text;
  v_note_suffix text;
  v_missing_stock_item text;
begin
  if v_user_id is null then
    raise exception 'No hay sesión activa.';
  end if;

  if not public.can_operate_pos() then
    raise exception 'El usuario no tiene permisos para convertir cotizaciones en ventas.';
  end if;

  select *
    into v_quote
  from public.quotations q
  where q.id = target_quotation_id
  for update;

  if not found then
    raise exception 'La cotización no existe.';
  end if;

  if not public.has_branch_access(v_quote.branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta cotización.';
  end if;

  if v_quote.converted_sale_id is not null or v_quote.status = 'converted' then
    raise exception 'La cotización ya fue convertida previamente.';
  end if;

  if v_quote.status <> 'approved' then
    raise exception 'Solo las cotizaciones aprobadas pueden convertirse en venta.';
  end if;

  if v_quote.valid_until < timezone('utc', now()) then
    update public.quotations
      set status = 'expired',
          expired_at = timezone('utc', now())
    where id = v_quote.id;
    raise exception 'La cotización está vencida y no puede convertirse sin revalidación.';
  end if;

  if not exists (
    select 1
    from public.quotation_items qi
    where qi.quotation_id = v_quote.id
  ) then
    raise exception 'La cotización no tiene líneas para convertir.';
  end if;

  select qi.product_name
    into v_missing_stock_item
  from public.quotation_items qi
  join public.products p
    on p.id = qi.product_id
   and p.branch_id = qi.branch_id
  where qi.quotation_id = v_quote.id
    and p.stock < qi.quantity
  limit 1;

  if v_missing_stock_item is not null then
    raise exception 'No hay stock suficiente para convertir la cotización. Producto bloqueante: %', v_missing_stock_item;
  end if;

  v_sale_number := format(
    'VTA-Q-%s',
    to_char(clock_timestamp(), 'YYYYMMDD-HH24MISSMS')
  );

  v_note_suffix := coalesce(v_quote.notes || E'\n\n', '') ||
    format('Origen: cotización %s', v_quote.code);

  insert into public.sales (
    branch_id,
    sale_number,
    client_id,
    cashier_id,
    receipt_type,
    status,
    sale_date,
    due_date,
    notes,
    subtotal,
    discount_amount,
    tax_amount,
    total_amount,
    paid_amount,
    balance_due,
    source_quotation_id,
    source_quotation_code
  )
  values (
    v_quote.branch_id,
    v_sale_number,
    v_quote.client_id,
    v_user_id,
    requested_receipt_type,
    requested_sale_status,
    timezone('utc', now()),
    current_date,
    v_note_suffix,
    v_quote.subtotal,
    v_quote.discount_amount,
    v_quote.tax_amount,
    v_quote.total_amount,
    0,
    v_quote.total_amount,
    v_quote.id,
    v_quote.code
  )
  returning id into v_sale_id;

  insert into public.sale_items (
    sale_id,
    branch_id,
    product_id,
    description,
    quantity,
    unit_price,
    discount_amount,
    tax_rate,
    line_subtotal,
    line_tax,
    line_total
  )
  select
    v_sale_id,
    qi.branch_id,
    qi.product_id,
    qi.description,
    qi.quantity,
    qi.unit_price,
    qi.discount_amount,
    qi.tax_rate,
    qi.line_subtotal,
    qi.line_tax,
    qi.line_total
  from public.quotation_items qi
  where qi.quotation_id = v_quote.id;

  update public.quotations
     set status = 'converted',
         converted_sale_id = v_sale_id,
         converted_at = timezone('utc', now()),
         converted_by = v_user_id
   where id = v_quote.id;

  insert into public.quotation_events (
    quotation_id,
    branch_id,
    event_type,
    payload,
    created_by
  )
  values (
    v_quote.id,
    v_quote.branch_id,
    'converted_to_sale',
    jsonb_build_object(
      'sale_id', v_sale_id,
      'sale_number', v_sale_number,
      'requested_receipt_type', requested_receipt_type,
      'requested_sale_status', requested_sale_status
    ),
    v_user_id
  );

  return query select v_sale_id, v_sale_number;
end;
$$;

grant execute on function public.convert_quotation_to_sale(uuid, public.receipt_type, public.sale_status) to authenticated;

-- =========================================================
-- Transactional quotation update (header + lines + expiry/status)
-- =========================================================
create or replace function public.update_quotation_document(
  target_quotation_id uuid,
  requested_client_id uuid,
  requested_status public.quote_status,
  requested_valid_until timestamptz,
  requested_notes text,
  requested_items jsonb
)
returns table (quotation_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_quote public.quotations%rowtype;
  v_branch_id uuid;
  v_subtotal numeric(14,2) := 0;
  v_tax numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_item jsonb;
  v_client public.clients%rowtype;
begin
  if v_user_id is null then
    raise exception 'No hay sesión activa.';
  end if;

  if not public.can_operate_pos() then
    raise exception 'El usuario no tiene permisos para editar cotizaciones.';
  end if;

  if requested_status = 'converted' then
    raise exception 'No se puede forzar estado convertido desde edición manual.';
  end if;

  if requested_valid_until <= timezone('utc', now()) then
    raise exception 'La vigencia debe estar en el futuro.';
  end if;

  if requested_items is null or jsonb_typeof(requested_items) <> 'array' or jsonb_array_length(requested_items) = 0 then
    raise exception 'La cotización debe conservar al menos una línea.';
  end if;

  select *
    into v_quote
  from public.quotations q
  where q.id = target_quotation_id
  for update;

  if not found then
    raise exception 'La cotización no existe.';
  end if;

  if v_quote.status = 'converted' or v_quote.converted_sale_id is not null then
    raise exception 'La cotización convertida ya no se puede editar.';
  end if;

  if not public.has_branch_access(v_quote.branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta cotización.';
  end if;

  v_branch_id := v_quote.branch_id;

  if requested_client_id is not null then
    select *
      into v_client
    from public.clients c
    where c.id = requested_client_id
      and c.branch_id = v_branch_id;

    if not found then
      raise exception 'El cliente seleccionado no existe en esta sucursal.';
    end if;
  end if;

  for v_item in select value from jsonb_array_elements(requested_items)
  loop
    v_subtotal := v_subtotal + coalesce((v_item->>'line_subtotal')::numeric, 0);
    v_tax := v_tax + coalesce((v_item->>'line_tax')::numeric, 0);
    v_total := v_total + coalesce((v_item->>'line_total')::numeric, 0);
  end loop;

  update public.quotations
     set client_id = requested_client_id,
         status = requested_status,
         valid_until = requested_valid_until,
         notes = nullif(btrim(requested_notes), ''),
         subtotal = round(v_subtotal, 2),
         tax_amount = round(v_tax, 2),
         total_amount = round(v_total, 2),
         client_display_name = case when requested_client_id is null then 'Cliente general' else v_client.full_name end,
         client_legal_name = case when requested_client_id is null then null else nullif(v_client.legal_name, '') end,
         client_email = case when requested_client_id is null then null else nullif(v_client.email, '') end,
         client_phone = case when requested_client_id is null then null else nullif(v_client.phone, '') end,
         client_document_type = case when requested_client_id is null then null else nullif(v_client.document_type, '') end,
         client_document_number = case when requested_client_id is null then null else nullif(v_client.document_number, '') end,
         sent_at = case
           when requested_status = 'sent' and sent_at is null then timezone('utc', now())
           else sent_at
         end,
         approved_at = case
           when requested_status = 'approved' and approved_at is null then timezone('utc', now())
           when requested_status <> 'approved' then null
           else approved_at
         end,
         rejected_at = case
           when requested_status = 'rejected' and rejected_at is null then timezone('utc', now())
           when requested_status <> 'rejected' then null
           else rejected_at
         end,
         expired_at = case
           when requested_status = 'expired' then timezone('utc', now())
           else null
         end,
         updated_by = v_user_id
   where id = target_quotation_id;

  delete from public.quotation_items
  where quotation_id = target_quotation_id;

  insert into public.quotation_items (
    quotation_id,
    branch_id,
    product_id,
    product_name,
    product_sku,
    description,
    quantity,
    unit_price,
    discount_amount,
    tax_rate,
    line_subtotal,
    line_tax,
    line_total,
    created_by,
    updated_by
  )
  select
    target_quotation_id,
    v_branch_id,
    (item->>'product_id')::uuid,
    coalesce(nullif(item->>'product_name', ''), item->>'description'),
    nullif(item->>'product_sku', ''),
    coalesce(nullif(item->>'description', ''), item->>'product_name'),
    coalesce((item->>'quantity')::numeric, 0),
    coalesce((item->>'unit_price')::numeric, 0),
    coalesce((item->>'discount_amount')::numeric, 0),
    coalesce((item->>'tax_rate')::numeric, 0),
    coalesce((item->>'line_subtotal')::numeric, 0),
    coalesce((item->>'line_tax')::numeric, 0),
    coalesce((item->>'line_total')::numeric, 0),
    v_user_id,
    v_user_id
  from jsonb_array_elements(requested_items) as item;

  insert into public.quotation_events (
    quotation_id,
    branch_id,
    event_type,
    payload,
    created_by
  )
  values (
    target_quotation_id,
    v_branch_id,
    'updated',
    jsonb_build_object(
      'status', requested_status,
      'valid_until', requested_valid_until,
      'items_count', jsonb_array_length(requested_items),
      'total_amount', round(v_total, 2)
    ),
    v_user_id
  );

  return query select target_quotation_id;
end;
$$;

grant execute on function public.update_quotation_document(uuid, uuid, public.quote_status, timestamptz, text, jsonb) to authenticated;

commit;

