-- 20260421_structural_backoffice_foundation.sql
-- Shop+ RD
--
-- Ejecutar después de:
--   01_schema.sql
--   02_seed.sql (opcional)
--   03_reports_views.sql
--   04_branch_context.sql
--
-- Objetivo:
--   Evolución estructural aditiva para soportar dashboard/comercial,
--   clientes, inventario, compras, empleados/permisos, fiscal/NCF,
--   configuración del negocio y exportación de reportes.
--
-- Reglas de esta migración:
--   - NO rompe el esquema actual.
--   - NO elimina ni renombra tablas/columnas existentes.
--   - Se apoya en branch_id / current_branch_id() / has_branch_access().
--   - Todo lo nuevo es aditivo y compatible con la UI actual.

begin;

create extension if not exists pgcrypto;
create extension if not exists citext;

-- =====================================================
-- 1) Enums: ampliaciones no destructivas
-- =====================================================

do $$
begin
  begin
    alter type public.purchase_status add value if not exists 'pending';
  exception when others then null;
  end;

  begin
    alter type public.purchase_status add value if not exists 'partial';
  exception when others then null;
  end;

  begin
    alter type public.purchase_status add value if not exists 'received';
  exception when others then null;
  end;

  if not exists (select 1 from pg_type where typname = 'report_export_format') then
    create type public.report_export_format as enum ('pdf', 'xlsx', 'csv');
  end if;

  if not exists (select 1 from pg_type where typname = 'report_export_status') then
    create type public.report_export_status as enum (
      'pending',
      'processing',
      'completed',
      'failed',
      'expired'
    );
  end if;
end $$;

-- =====================================================
-- 2) Sucursal / negocio / configuración operativa
-- =====================================================

alter table public.branches add column if not exists legal_name text;
alter table public.branches add column if not exists trade_name text;
alter table public.branches add column if not exists tax_id text;
alter table public.branches add column if not exists fiscal_regime text;
alter table public.branches add column if not exists email citext;
alter table public.branches add column if not exists website text;
alter table public.branches add column if not exists whatsapp text;
alter table public.branches add column if not exists logo_url text;
alter table public.branches add column if not exists invoice_footer text;
alter table public.branches add column if not exists quote_terms text;
alter table public.branches add column if not exists city text;
alter table public.branches add column if not exists province text;
alter table public.branches add column if not exists country_code text not null default 'DO';
alter table public.branches add column if not exists postal_code text;
alter table public.branches add column if not exists currency_code text not null default 'DOP';
alter table public.branches add column if not exists timezone_name text not null default 'America/Santo_Domingo';
alter table public.branches add column if not exists tax_included_by_default boolean not null default false;
alter table public.branches add column if not exists default_tax_rate numeric(5,2) not null default 18.00;
alter table public.branches add column if not exists default_service_charge_rate numeric(5,2) not null default 10.00;
alter table public.branches add column if not exists business_hours_json jsonb not null default '{}'::jsonb;
alter table public.branches add column if not exists settings_json jsonb not null default '{}'::jsonb;

comment on column public.branches.tax_id is 'RNC o identificador fiscal principal de la sucursal/negocio.';
comment on column public.branches.default_service_charge_rate is 'Tasa por defecto para ley/servicio cuando aplique.';

create index if not exists branches_tax_id_idx
  on public.branches (lower(tax_id))
  where tax_id is not null;

create table if not exists public.branch_fiscal_settings (
  branch_id uuid primary key references public.branches(id) on delete cascade,
  taxpayer_name text,
  taxpayer_rnc text,
  commercial_name text,
  fiscal_address text,
  invoice_city text,
  invoice_province text,
  country_code text not null default 'DO',
  email citext,
  phone text,
  website text,
  logo_url text,
  default_receipt_type public.receipt_type not null default 'consumer_final',
  service_charge_enabled boolean not null default true,
  service_charge_rate numeric(5,2) not null default 10.00,
  tax_enabled boolean not null default true,
  default_tax_rate numeric(5,2) not null default 18.00,
  allow_credit_sales boolean not null default true,
  quote_valid_days integer not null default 15,
  invoice_footer text,
  terms_and_conditions text,
  email_settings_json jsonb not null default '{}'::jsonb,
  print_settings_json jsonb not null default '{}'::jsonb,
  extra_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id)
);

comment on table public.branch_fiscal_settings is 'Configuración fiscal y comercial rica por sucursal; complementa branches sin romper la app actual.';

-- =====================================================
-- 3) Empleados / perfiles / permisos
-- =====================================================

alter table public.profiles add column if not exists employee_code text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists job_title text;
alter table public.profiles add column if not exists hire_date date;
alter table public.profiles add column if not exists pin_code text;
alter table public.profiles add column if not exists notes text;
alter table public.profiles add column if not exists metadata jsonb not null default '{}'::jsonb;

create unique index if not exists profiles_employee_code_unique
  on public.profiles (lower(employee_code))
  where employee_code is not null;

alter table public.users_branches add column if not exists display_order integer not null default 0;
alter table public.users_branches add column if not exists can_open_cash boolean not null default false;
alter table public.users_branches add column if not exists can_close_cash boolean not null default false;
alter table public.users_branches add column if not exists pos_pin_override text;
alter table public.users_branches add column if not exists notes text;

create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  module text not null,
  action_type text not null,
  description text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id)
);

create table if not exists public.role_permissions (
  id uuid primary key default gen_random_uuid(),
  role_key text not null,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  allowed boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (role_key, permission_id)
);

create table if not exists public.user_permissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  granted boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (user_id, branch_id, permission_id)
);

comment on table public.permissions is 'Catálogo canónico de permisos funcionales para backoffice/POS.';
comment on table public.user_permissions is 'Overrides por usuario, opcionalmente por sucursal.';

create index if not exists permissions_module_action_idx
  on public.permissions (module, action_type);

create index if not exists role_permissions_role_idx
  on public.role_permissions (role_key);

create index if not exists user_permissions_user_branch_idx
  on public.user_permissions (user_id, branch_id);

-- =====================================================
-- 4) Clientes / CRM / datos fiscales y comerciales
-- =====================================================

alter table public.clients add column if not exists first_name text;
alter table public.clients add column if not exists last_name text;
alter table public.clients add column if not exists company_name text;
alter table public.clients add column if not exists secondary_phone text;
alter table public.clients add column if not exists address_line_1 text;
alter table public.clients add column if not exists address_line_2 text;
alter table public.clients add column if not exists city text;
alter table public.clients add column if not exists province text;
alter table public.clients add column if not exists country_code text not null default 'DO';
alter table public.clients add column if not exists postal_code text;
alter table public.clients add column if not exists google_maps_url text;
alter table public.clients add column if not exists birthday date;
alter table public.clients add column if not exists avatar_url text;
alter table public.clients add column if not exists comments text;
alter table public.clients add column if not exists credit_invoice_limit integer not null default 0;
alter table public.clients add column if not exists default_receipt_type public.receipt_type;
alter table public.clients add column if not exists price_tier text not null default 'retail';
alter table public.clients add column if not exists tax_exempt boolean not null default false;
alter table public.clients add column if not exists charge_itbis boolean not null default true;
alter table public.clients add column if not exists metadata jsonb not null default '{}'::jsonb;

create index if not exists clients_email_idx
  on public.clients (branch_id, lower(email::text))
  where email is not null;

create index if not exists clients_phone_idx
  on public.clients (branch_id, phone)
  where phone is not null;

-- =====================================================
-- 5) Categorías / productos / inventario comercial
-- =====================================================

alter table public.product_categories add column if not exists parent_id uuid;
alter table public.product_categories add column if not exists color_hex text;
alter table public.product_categories add column if not exists icon_name text;
alter table public.product_categories add column if not exists sort_order integer not null default 0;
alter table public.product_categories add column if not exists purchase_enabled boolean not null default true;
alter table public.product_categories add column if not exists sales_enabled boolean not null default true;
alter table public.product_categories add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.product_categories
  drop constraint if exists product_categories_parent_fk;

alter table public.product_categories
  add constraint product_categories_parent_fk
  foreign key (parent_id)
  references public.product_categories(id)
  on delete set null;

alter table public.products add column if not exists internal_code text;
alter table public.products add column if not exists image_url text;
alter table public.products add column if not exists brand text;
alter table public.products add column if not exists model text;
alter table public.products add column if not exists size_label text;
alter table public.products add column if not exists variant_name text;
alter table public.products add column if not exists purchase_unit text;
alter table public.products add column if not exists sale_unit text;
alter table public.products add column if not exists reorder_level numeric(14,3) not null default 0;
alter table public.products add column if not exists max_stock numeric(14,3) not null default 0;
alter table public.products add column if not exists track_inventory boolean not null default true;
alter table public.products add column if not exists allow_negative_stock boolean not null default false;
alter table public.products add column if not exists is_service boolean not null default false;
alter table public.products add column if not exists is_tax_exempt boolean not null default false;
alter table public.products add column if not exists price_tier_1 numeric(14,2);
alter table public.products add column if not exists price_tier_2 numeric(14,2);
alter table public.products add column if not exists price_tier_3 numeric(14,2);
alter table public.products add column if not exists notes text;
alter table public.products add column if not exists metadata jsonb not null default '{}'::jsonb;

update public.products
set price_tier_1 = price
where price_tier_1 is null;

create unique index if not exists products_internal_code_unique
  on public.products (branch_id, internal_code)
  where internal_code is not null;

create index if not exists products_category_active_idx
  on public.products (branch_id, category_id, is_active);

create index if not exists product_categories_parent_idx
  on public.product_categories (branch_id, parent_id);

comment on column public.products.price_tier_1 is 'Precio base compatible con el precio actual.';
comment on column public.products.track_inventory is 'Permite distinguir productos físicos vs servicios.';

-- =====================================================
-- 6) Proveedores / compras / líneas de compra
-- =====================================================

alter table public.suppliers add column if not exists document_type text;
alter table public.suppliers add column if not exists document_number text;
alter table public.suppliers add column if not exists secondary_phone text;
alter table public.suppliers add column if not exists city text;
alter table public.suppliers add column if not exists province text;
alter table public.suppliers add column if not exists country_code text not null default 'DO';
alter table public.suppliers add column if not exists postal_code text;
alter table public.suppliers add column if not exists payment_terms_days integer not null default 0;
alter table public.suppliers add column if not exists comments text;
alter table public.suppliers add column if not exists metadata jsonb not null default '{}'::jsonb;

create index if not exists suppliers_document_idx
  on public.suppliers (branch_id, lower(document_number))
  where document_number is not null;

alter table public.purchases add column if not exists expected_at timestamptz;
alter table public.purchases add column if not exists received_at timestamptz;
alter table public.purchases add column if not exists payment_terms_days integer not null default 0;
alter table public.purchases add column if not exists payment_status text not null default 'pending';
alter table public.purchases add column if not exists purchase_category text;
alter table public.purchases add column if not exists receipt_type public.receipt_type;
alter table public.purchases add column if not exists supplier_document_type text;
alter table public.purchases add column if not exists supplier_document_number text;
alter table public.purchases add column if not exists tax_included boolean not null default false;
alter table public.purchases add column if not exists received_by uuid references auth.users(id);
alter table public.purchases add column if not exists external_reference text;
alter table public.purchases add column if not exists metadata jsonb not null default '{}'::jsonb;

create index if not exists purchases_status_date_idx
  on public.purchases (branch_id, status, purchase_date desc);

alter table public.purchase_items add column if not exists category_id uuid;
alter table public.purchase_items add column if not exists barcode_snapshot text;
alter table public.purchase_items add column if not exists sku_snapshot text;
alter table public.purchase_items add column if not exists product_name_snapshot text;
alter table public.purchase_items add column if not exists unit_name text;
alter table public.purchase_items add column if not exists received_quantity numeric(14,3) not null default 0;
alter table public.purchase_items add column if not exists notes text;
alter table public.purchase_items add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.purchase_items
  drop constraint if exists purchase_items_category_fk;

alter table public.purchase_items
  add constraint purchase_items_category_fk
  foreign key (category_id)
  references public.product_categories(id)
  on delete set null;

create index if not exists purchase_items_category_idx
  on public.purchase_items (purchase_id, category_id);

-- =====================================================
-- 7) Ventas / líneas / soporte fiscal y snapshots
-- =====================================================

alter table public.sales add column if not exists cash_session_id uuid;
alter table public.sales add column if not exists legacy_ncf_sequence_id uuid;
alter table public.sales add column if not exists seller_id uuid references auth.users(id);
alter table public.sales add column if not exists client_name_snapshot text;
alter table public.sales add column if not exists client_document_type_snapshot text;
alter table public.sales add column if not exists client_document_number_snapshot text;
alter table public.sales add column if not exists client_address_snapshot text;
alter table public.sales add column if not exists branch_name_snapshot text;
alter table public.sales add column if not exists branch_tax_id_snapshot text;
alter table public.sales add column if not exists taxable_amount numeric(14,2) not null default 0;
alter table public.sales add column if not exists exempt_amount numeric(14,2) not null default 0;
alter table public.sales add column if not exists service_charge_rate numeric(5,2) not null default 0;
alter table public.sales add column if not exists service_charge_amount numeric(14,2) not null default 0;
alter table public.sales add column if not exists exported_at timestamptz;
alter table public.sales add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.sales
  drop constraint if exists sales_cash_session_fk;

alter table public.sales
  add constraint sales_cash_session_fk
  foreign key (cash_session_id, branch_id)
  references public.cash_sessions(id, branch_id)
  on delete restrict;

alter table public.sales
  drop constraint if exists sales_legacy_ncf_sequence_fk;

alter table public.sales
  add constraint sales_legacy_ncf_sequence_fk
  foreign key (legacy_ncf_sequence_id)
  references public.ncf_sequences(id)
  on delete set null;

create index if not exists sales_cash_session_idx
  on public.sales (cash_session_id)
  where cash_session_id is not null;

create index if not exists sales_receipt_type_status_idx
  on public.sales (branch_id, receipt_type, status, sale_date desc);

alter table public.sale_items add column if not exists barcode_snapshot text;
alter table public.sale_items add column if not exists sku_snapshot text;
alter table public.sale_items add column if not exists category_id uuid;
alter table public.sale_items add column if not exists category_name_snapshot text;
alter table public.sale_items add column if not exists unit_name text;
alter table public.sale_items add column if not exists service_charge_amount numeric(14,2) not null default 0;
alter table public.sale_items add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.sale_items
  drop constraint if exists sale_items_category_fk;

alter table public.sale_items
  add constraint sale_items_category_fk
  foreign key (category_id)
  references public.product_categories(id)
  on delete set null;

create index if not exists sale_items_category_idx
  on public.sale_items (sale_id, category_id);

-- =====================================================
-- 8) Secuencias NCF + documentos fiscales emitidos
-- =====================================================

alter table public.ncf_sequences add column if not exists series text;
alter table public.ncf_sequences add column if not exists document_code text;
alter table public.ncf_sequences add column if not exists sequence_start bigint;
alter table public.ncf_sequences add column if not exists sequence_end bigint;
alter table public.ncf_sequences add column if not exists next_number bigint;
alter table public.ncf_sequences add column if not exists warning_threshold integer not null default 25;
alter table public.ncf_sequences add column if not exists status text not null default 'active';
alter table public.ncf_sequences add column if not exists notes text;
alter table public.ncf_sequences add column if not exists metadata jsonb not null default '{}'::jsonb;

update public.ncf_sequences
set sequence_end = coalesce(sequence_end, max_number),
    sequence_start = coalesce(sequence_start, 1),
    next_number = coalesce(next_number, current_number + 1)
where sequence_end is null
   or sequence_start is null
   or next_number is null;

create index if not exists ncf_sequences_status_idx
  on public.ncf_sequences (branch_id, status, is_active);

create table if not exists public.fiscal_documents (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  sale_id uuid,
  client_id uuid,
  ncf_sequence_id uuid references public.ncf_sequences(id) on delete set null,
  receipt_type public.receipt_type not null,
  ncf text not null,
  sequence_number bigint,
  fiscal_status public.dgii_status not null default 'pending',
  issued_at timestamptz not null default timezone('utc', now()),
  expires_on date,
  voided_at timestamptz,
  void_reason text,
  customer_name text,
  customer_document_type text,
  customer_document_number text,
  customer_address text,
  issuer_name text,
  issuer_tax_id text,
  issuer_address text,
  subtotal numeric(14,2) not null default 0,
  discount_amount numeric(14,2) not null default 0,
  taxable_amount numeric(14,2) not null default 0,
  exempt_amount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  service_charge_amount numeric(14,2) not null default 0,
  total_amount numeric(14,2) not null default 0,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint fiscal_documents_sale_fk
    foreign key (sale_id, branch_id)
    references public.sales(id, branch_id)
    on delete set null,
  constraint fiscal_documents_client_fk
    foreign key (client_id, branch_id)
    references public.clients(id, branch_id)
    on delete set null,
  unique (branch_id, ncf)
);

comment on table public.fiscal_documents is 'Documento fiscal emitido/registrado con snapshots suficientes para reportes e impresión.';

create index if not exists fiscal_documents_sale_idx
  on public.fiscal_documents (sale_id)
  where sale_id is not null;

create index if not exists fiscal_documents_issued_at_idx
  on public.fiscal_documents (branch_id, issued_at desc);

create index if not exists fiscal_documents_status_idx
  on public.fiscal_documents (branch_id, fiscal_status, receipt_type);

-- =====================================================
-- 9) Reportes / exportación / presets
-- =====================================================

create table if not exists public.report_presets (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  report_key text not null,
  name text not null,
  description text,
  filters_json jsonb not null default '{}'::jsonb,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id)
);

create table if not exists public.report_exports (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  report_key text not null,
  export_format public.report_export_format not null,
  status public.report_export_status not null default 'pending',
  filters_json jsonb not null default '{}'::jsonb,
  requested_by uuid references auth.users(id) on delete set null,
  requested_at timestamptz not null default timezone('utc', now()),
  generated_at timestamptz,
  expires_at timestamptz,
  storage_path text,
  download_url text,
  file_name text,
  file_size_bytes bigint,
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id)
);

create index if not exists report_presets_branch_key_idx
  on public.report_presets (branch_id, report_key, is_active);

create index if not exists report_exports_branch_status_idx
  on public.report_exports (branch_id, status, requested_at desc);

comment on table public.report_exports is 'Historial/cola de exportaciones PDF, Excel o CSV.';

-- =====================================================
-- 10) Funciones helper de permisos
-- =====================================================

create or replace function public.current_user_role_key(target_branch_id uuid default null)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select lower(
    coalesce(
      (
        select coalesce(ub.role_override::text, p.role::text)
        from public.users_branches ub
        join public.profiles p on p.id = ub.user_id
        where ub.user_id = auth.uid()
          and ub.is_active
          and (target_branch_id is null or ub.branch_id = target_branch_id)
        order by ub.is_default desc, ub.created_at asc
        limit 1
      ),
      (
        select p.role::text
        from public.profiles p
        where p.id = auth.uid()
          and p.is_active
        limit 1
      ),
      'cashier'
    )
  );
$$;

create or replace function public.has_permission(permission_code text, target_branch_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with requested_branch as (
    select coalesce(target_branch_id, public.current_branch_id()) as branch_id
  ),
  user_override as (
    select up.allowed
    from public.user_permissions up
    join public.permissions p on p.id = up.permission_id
    join requested_branch rb on true
    where up.user_id = auth.uid()
      and up.is_active
      and p.code = permission_code
      and (
        up.branch_id is null
        or up.branch_id = rb.branch_id
      )
    order by case when up.branch_id = rb.branch_id then 0 else 1 end, up.created_at desc
    limit 1
  ),
  role_grant as (
    select rp.allowed
    from public.role_permissions rp
    join public.permissions p on p.id = rp.permission_id
    join requested_branch rb on true
    where rp.is_active
      and p.code = permission_code
      and rp.role_key = public.current_user_role_key(rb.branch_id)
    order by rp.created_at desc
    limit 1
  )
  select case
    when public.is_admin() then true
    when exists (select 1 from user_override) then (select granted from user_override)
    when exists (select 1 from role_grant) then (select allowed from role_grant)
    else false
  end;
$$;

grant execute on function public.current_user_role_key(uuid) to authenticated;
grant execute on function public.has_permission(text, uuid) to authenticated;

-- =====================================================
-- 11) Seed base de permisos canónicos
-- =====================================================

insert into public.permissions (code, name, module, action_type, description, sort_order)
values
  ('dashboard.view', 'Ver Dashboard', 'dashboard', 'view', 'Ver dashboard general', 10),
  ('sales.view', 'Ver Ventas', 'sales', 'view', 'Ver ventas', 20),
  ('sales.create', 'Crear Ventas', 'sales', 'create', 'Crear ventas', 21),
  ('sales.edit', 'Editar Ventas', 'sales', 'edit', 'Editar ventas', 22),
  ('sales.void', 'Anular Ventas', 'sales', 'void', 'Anular ventas', 23),
  ('sales.export', 'Exportar Ventas', 'sales', 'export', 'Exportar ventas', 24),
  ('clients.view', 'Ver Clientes', 'clients', 'view', 'Ver clientes', 30),
  ('clients.create', 'Crear Clientes', 'clients', 'create', 'Crear clientes', 31),
  ('clients.edit', 'Editar Clientes', 'clients', 'edit', 'Editar clientes', 32),
  ('clients.credit', 'Gestionar Crédito', 'clients', 'credit', 'Gestionar crédito de clientes', 33),
  ('inventory.view', 'Ver Inventario', 'inventory', 'view', 'Ver inventario', 40),
  ('inventory.create', 'Crear Productos', 'inventory', 'create', 'Crear productos', 41),
  ('inventory.edit', 'Editar Productos', 'inventory', 'edit', 'Editar productos', 42),
  ('inventory.adjust', 'Ajustar Inventario', 'inventory', 'adjust', 'Ajustar inventario', 43),
  ('inventory.export', 'Exportar Inventario', 'inventory', 'export', 'Exportar inventario', 44),
  ('purchases.view', 'Ver Compras', 'purchases', 'view', 'Ver compras', 50),
  ('purchases.create', 'Crear Compras', 'purchases', 'create', 'Crear compras', 51),
  ('purchases.edit', 'Editar Compras', 'purchases', 'edit', 'Editar compras', 52),
  ('purchases.receive', 'Recibir Compras', 'purchases', 'receive', 'Recibir compras', 53),
  ('cash.open', 'Abrir Caja', 'cash', 'open', 'Abrir caja', 60),
  ('cash.close', 'Cerrar Caja', 'cash', 'close', 'Cerrar caja', 61),
  ('cash.manage', 'Gestionar Caja', 'cash', 'manage', 'Gestionar caja', 62),
  ('reports.view', 'Ver Reportes', 'reports', 'view', 'Ver reportes', 70),
  ('reports.export', 'Exportar Reportes', 'reports', 'export', 'Exportar reportes', 71),
  ('employees.view', 'Ver Empleados', 'employees', 'view', 'Ver empleados', 80),
  ('employees.manage', 'Administrar Personal', 'employees', 'manage', 'Administrar empleados y permisos', 81),
  ('settings.view', 'Ver Configuración', 'settings', 'view', 'Ver configuración', 90),
  ('settings.manage', 'Editar Configuración', 'settings', 'manage', 'Editar configuración', 91),
  ('ncf.view', 'Ver NCF', 'ncf', 'view', 'Ver secuencias fiscales', 100),
  ('ncf.manage', 'Administrar NCF', 'ncf', 'manage', 'Administrar comprobantes fiscales', 101),
  ('ncf.issue', 'Emitir NCF', 'ncf', 'issue', 'Emitir comprobantes fiscales', 102)
on conflict (code) do update set
  name = excluded.name,
  module = excluded.module,
  action_type = excluded.action_type,
  description = excluded.description,
  sort_order = excluded.sort_order,
  updated_at = timezone('utc', now());

insert into public.role_permissions (role_key, permission_id, allowed)
select role_key, p.id, true
from public.permissions p
join (
  values
    ('admin', '%'),
    ('supervisor', 'dashboard.view'),
    ('supervisor', 'sales.view'),
    ('supervisor', 'sales.create'),
    ('supervisor', 'sales.edit'),
    ('supervisor', 'sales.export'),
    ('supervisor', 'clients.view'),
    ('supervisor', 'clients.create'),
    ('supervisor', 'clients.edit'),
    ('supervisor', 'clients.credit'),
    ('supervisor', 'inventory.view'),
    ('supervisor', 'inventory.create'),
    ('supervisor', 'inventory.edit'),
    ('supervisor', 'inventory.adjust'),
    ('supervisor', 'purchases.view'),
    ('supervisor', 'purchases.create'),
    ('supervisor', 'purchases.edit'),
    ('supervisor', 'purchases.receive'),
    ('supervisor', 'cash.open'),
    ('supervisor', 'cash.close'),
    ('supervisor', 'cash.manage'),
    ('supervisor', 'reports.view'),
    ('supervisor', 'reports.export'),
    ('supervisor', 'employees.view'),
    ('supervisor', 'settings.view'),
    ('supervisor', 'ncf.view'),
    ('supervisor', 'ncf.issue'),
    ('cashier', 'dashboard.view'),
    ('cashier', 'sales.view'),
    ('cashier', 'sales.create'),
    ('cashier', 'clients.view'),
    ('cashier', 'clients.create'),
    ('cashier', 'clients.edit'),
    ('cashier', 'cash.open'),
    ('cashier', 'cash.close'),
    ('cashier', 'reports.view'),
    ('accountant', 'dashboard.view'),
    ('accountant', 'reports.view'),
    ('accountant', 'reports.export'),
    ('accountant', 'purchases.view'),
    ('accountant', 'purchases.create'),
    ('accountant', 'purchases.edit'),
    ('accountant', 'clients.view'),
    ('accountant', 'clients.credit'),
    ('accountant', 'settings.view'),
    ('accountant', 'ncf.view')
) as grant_map(role_key, permission_code)
  on grant_map.permission_code = '%' or p.code = grant_map.permission_code
on conflict (role_key, permission_id) do nothing;

-- =====================================================
-- 12) Triggers de updated_at / audit para tablas nuevas
-- =====================================================

drop trigger if exists trg_branch_fiscal_settings_updated_at on public.branch_fiscal_settings;
create trigger trg_branch_fiscal_settings_updated_at
before update on public.branch_fiscal_settings
for each row execute function public.set_updated_at();

drop trigger if exists trg_permissions_updated_at on public.permissions;
create trigger trg_permissions_updated_at
before update on public.permissions
for each row execute function public.set_updated_at();

drop trigger if exists trg_role_permissions_updated_at on public.role_permissions;
create trigger trg_role_permissions_updated_at
before update on public.role_permissions
for each row execute function public.set_updated_at();

drop trigger if exists trg_user_permissions_updated_at on public.user_permissions;
create trigger trg_user_permissions_updated_at
before update on public.user_permissions
for each row execute function public.set_updated_at();

drop trigger if exists trg_fiscal_documents_updated_at on public.fiscal_documents;
create trigger trg_fiscal_documents_updated_at
before update on public.fiscal_documents
for each row execute function public.set_updated_at();

drop trigger if exists trg_report_presets_updated_at on public.report_presets;
create trigger trg_report_presets_updated_at
before update on public.report_presets
for each row execute function public.set_updated_at();

drop trigger if exists trg_report_exports_updated_at on public.report_exports;
create trigger trg_report_exports_updated_at
before update on public.report_exports
for each row execute function public.set_updated_at();

drop trigger if exists trg_branch_fiscal_settings_audit_fields on public.branch_fiscal_settings;
create trigger trg_branch_fiscal_settings_audit_fields
before insert or update on public.branch_fiscal_settings
for each row execute function public.set_audit_fields();

drop trigger if exists trg_permissions_audit_fields on public.permissions;
create trigger trg_permissions_audit_fields
before insert or update on public.permissions
for each row execute function public.set_audit_fields();

drop trigger if exists trg_role_permissions_audit_fields on public.role_permissions;
create trigger trg_role_permissions_audit_fields
before insert or update on public.role_permissions
for each row execute function public.set_audit_fields();

drop trigger if exists trg_user_permissions_audit_fields on public.user_permissions;
create trigger trg_user_permissions_audit_fields
before insert or update on public.user_permissions
for each row execute function public.set_audit_fields();

drop trigger if exists trg_fiscal_documents_audit_fields on public.fiscal_documents;
create trigger trg_fiscal_documents_audit_fields
before insert or update on public.fiscal_documents
for each row execute function public.set_audit_fields();

drop trigger if exists trg_report_presets_audit_fields on public.report_presets;
create trigger trg_report_presets_audit_fields
before insert or update on public.report_presets
for each row execute function public.set_audit_fields();

drop trigger if exists trg_report_exports_audit_fields on public.report_exports;
create trigger trg_report_exports_audit_fields
before insert or update on public.report_exports
for each row execute function public.set_audit_fields();

-- =====================================================
-- 13) RLS para tablas nuevas
-- =====================================================

alter table public.branch_fiscal_settings enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_permissions enable row level security;
alter table public.fiscal_documents enable row level security;
alter table public.report_presets enable row level security;
alter table public.report_exports enable row level security;

drop policy if exists branch_fiscal_settings_select on public.branch_fiscal_settings;
create policy branch_fiscal_settings_select
on public.branch_fiscal_settings
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists branch_fiscal_settings_write on public.branch_fiscal_settings;
create policy branch_fiscal_settings_write
on public.branch_fiscal_settings
for all
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists permissions_select on public.permissions;
create policy permissions_select
on public.permissions
for select
to authenticated
using (true);

drop policy if exists permissions_write on public.permissions;
create policy permissions_write
on public.permissions
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists role_permissions_select on public.role_permissions;
create policy role_permissions_select
on public.role_permissions
for select
to authenticated
using (true);

drop policy if exists role_permissions_write on public.role_permissions;
create policy role_permissions_write
on public.role_permissions
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists user_permissions_select on public.user_permissions;
create policy user_permissions_select
on public.user_permissions
for select
to authenticated
using (
  public.is_admin()
  or user_id = auth.uid()
  or (branch_id is not null and public.has_branch_access(branch_id))
);

drop policy if exists user_permissions_write on public.user_permissions;
create policy user_permissions_write
on public.user_permissions
for all
to authenticated
using (
  public.is_admin()
  or (branch_id is not null and public.has_branch_access(branch_id) and public.can_manage_branch_data())
)
with check (
  public.is_admin()
  or (branch_id is not null and public.has_branch_access(branch_id) and public.can_manage_branch_data())
);

drop policy if exists fiscal_documents_select on public.fiscal_documents;
create policy fiscal_documents_select
on public.fiscal_documents
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists fiscal_documents_write on public.fiscal_documents;
create policy fiscal_documents_write
on public.fiscal_documents
for all
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists report_presets_select on public.report_presets;
create policy report_presets_select
on public.report_presets
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists report_presets_write on public.report_presets;
create policy report_presets_write
on public.report_presets
for all
to authenticated
using (public.has_branch_access(branch_id) and public.has_permission('reports.export', branch_id))
with check (public.has_branch_access(branch_id) and public.has_permission('reports.export', branch_id));

drop policy if exists report_exports_select on public.report_exports;
create policy report_exports_select
on public.report_exports
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists report_exports_write on public.report_exports;
create policy report_exports_write
on public.report_exports
for all
to authenticated
using (public.has_branch_access(branch_id) and public.has_permission('reports.export', branch_id))
with check (public.has_branch_access(branch_id) and public.has_permission('reports.export', branch_id));

-- =====================================================
-- 14) Vistas útiles para dashboard/reportes/backoffice
-- =====================================================

create or replace view public.branch_business_profile_view
with (security_invoker = true)
as
select
  b.id as branch_id,
  b.code as branch_code,
  b.name as branch_name,
  coalesce(b.trade_name, bfs.commercial_name, b.name) as display_name,
  coalesce(b.legal_name, bfs.taxpayer_name, b.name) as legal_name,
  coalesce(b.tax_id, bfs.taxpayer_rnc) as tax_id,
  coalesce(b.email, bfs.email) as email,
  coalesce(b.phone, bfs.phone) as phone,
  coalesce(b.website, bfs.website) as website,
  coalesce(b.logo_url, bfs.logo_url) as logo_url,
  coalesce(b.address, bfs.fiscal_address) as address,
  coalesce(b.city, bfs.invoice_city) as city,
  coalesce(b.province, bfs.invoice_province) as province,
  b.country_code,
  b.currency_code,
  coalesce(b.default_tax_rate, bfs.default_tax_rate) as default_tax_rate,
  coalesce(b.default_service_charge_rate, bfs.service_charge_rate) as default_service_charge_rate,
  coalesce(b.invoice_footer, bfs.invoice_footer) as invoice_footer,
  bfs.default_receipt_type,
  bfs.service_charge_enabled,
  bfs.tax_enabled
from public.branches b
left join public.branch_fiscal_settings bfs on bfs.branch_id = b.id
where public.has_branch_access(b.id);

create or replace view public.customer_balances_view
with (security_invoker = true)
as
select
  c.id,
  c.branch_id,
  c.full_name,
  c.company_name,
  c.phone,
  c.email,
  c.credit_limit,
  c.balance_due,
  c.price_tier,
  c.tax_exempt,
  c.charge_itbis,
  count(s.id) filter (where s.status <> 'voided'::public.sale_status)::bigint as sales_count,
  coalesce(sum(s.total_amount) filter (where s.status <> 'voided'::public.sale_status), 0)::numeric(14,2) as total_sales_amount,
  max(s.sale_date) as last_sale_at
from public.clients c
left join public.sales s on s.client_id = c.id and s.branch_id = c.branch_id
where public.has_branch_access(c.branch_id)
group by c.id, c.branch_id, c.full_name, c.company_name, c.phone, c.email, c.credit_limit, c.balance_due, c.price_tier, c.tax_exempt, c.charge_itbis;

create or replace view public.sales_tax_breakdown_view
with (security_invoker = true)
as
select
  s.id as sale_id,
  s.branch_id,
  s.sale_number,
  s.sale_date,
  s.receipt_type,
  s.status,
  s.taxable_amount,
  s.exempt_amount,
  s.tax_amount,
  s.service_charge_amount,
  s.total_amount,
  coalesce(s.client_name_snapshot, c.full_name, 'Cliente General') as client_name
from public.sales s
left join public.clients c on c.id = s.client_id and c.branch_id = s.branch_id
where public.has_branch_access(s.branch_id)
  and s.status <> 'voided'::public.sale_status;

create or replace view public.purchase_operational_view
with (security_invoker = true)
as
select
  p.id,
  p.branch_id,
  p.purchase_number,
  p.invoice_number,
  p.status,
  p.payment_status,
  p.purchase_category,
  p.purchase_date,
  p.expected_at,
  p.received_at,
  p.total_amount,
  s.legal_name as supplier_name,
  count(pi.id)::bigint as lines_count,
  coalesce(sum(pi.quantity), 0)::numeric(14,3) as items_quantity,
  coalesce(sum(pi.received_quantity), 0)::numeric(14,3) as received_quantity
from public.purchases p
join public.suppliers s on s.id = p.supplier_id and s.branch_id = p.branch_id
left join public.purchase_items pi on pi.purchase_id = p.id and pi.branch_id = p.branch_id
where public.has_branch_access(p.branch_id)
group by p.id, p.branch_id, p.purchase_number, p.invoice_number, p.status, p.payment_status, p.purchase_category, p.purchase_date, p.expected_at, p.received_at, p.total_amount, s.legal_name;

create or replace view public.employee_effective_permissions_view
with (security_invoker = true)
as
with branch_scope as (
  select ub.user_id, ub.branch_id, coalesce(ub.role_override::text, p.role::text) as role_key
  from public.users_branches ub
  join public.profiles p on p.id = ub.user_id
  where ub.is_active
    and p.is_active
    and public.has_branch_access(ub.branch_id)
),
role_grants as (
  select bs.user_id, bs.branch_id, p.code as permission_code, rp.allowed
  from branch_scope bs
  join public.role_permissions rp on lower(rp.role_key) = lower(bs.role_key) and rp.is_active
  join public.permissions p on p.id = rp.permission_id and p.is_active
),
user_overrides as (
  select up.user_id, up.branch_id, p.code as permission_code, up.granted
  from public.user_permissions up
  join public.permissions p on p.id = up.permission_id and p.is_active
  where up.is_active
)
select
  bs.user_id,
  bs.branch_id,
  p.code as permission_code,
  p.name as permission_name,
  p.module,
  p.action_type,
  coalesce(
    (select rg.allowed from role_grants rg where rg.user_id = bs.user_id and rg.branch_id = bs.branch_id and rg.permission_code = p.code limit 1),
    false
  ) as role_grant,
  (
    select uo.granted
    from user_overrides uo
    where uo.user_id = bs.user_id
      and (uo.branch_id = bs.branch_id or uo.branch_id is null)
      and uo.permission_code = p.code
    order by case when uo.branch_id = bs.branch_id then 0 else 1 end
    limit 1
  ) as user_override,
  coalesce(
    (
      select uo.granted
      from user_overrides uo
      where uo.user_id = bs.user_id
        and (uo.branch_id = bs.branch_id or uo.branch_id is null)
        and uo.permission_code = p.code
      order by case when uo.branch_id = bs.branch_id then 0 else 1 end
      limit 1
    ),
    (
      select rg.allowed
      from role_grants rg
      where rg.user_id = bs.user_id
        and rg.branch_id = bs.branch_id
        and rg.permission_code = p.code
      limit 1
    ),
    false
  ) as effective_grant
from branch_scope bs
cross join public.permissions p
where p.is_active;

commit;
