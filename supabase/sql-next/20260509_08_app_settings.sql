-- 20260509_08_app_settings.sql
-- Shop+ RD - PRD 06: Módulo de Configuración Unificado (singleton global)
--
-- Ejecutar después de:
--   supabase/sql/01_schema.sql
--   supabase/sql/03_reports_views.sql
--   supabase/sql/04_branch_context.sql
--   supabase/sql-next/20260421_structural_backoffice_foundation.sql
--
-- Diseño:
--   - Una sola fila para todo el negocio (singleton enforced via partial unique index).
--   - admin escribe; resto de roles autenticados leen (lo necesitan en runtime).
--   - Audit log automático por columna modificada (app_settings_audit).
--   - Aditivo: no modifica tablas existentes; se complementa con branches /
--     branch_fiscal_settings que ya existen.
--   - Las ~120 opciones del PRD están todas presentes y tipadas.

begin;

-- =====================================================
-- 1) Enums auxiliares (solo para opciones cerradas del PRD)
-- =====================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_settings_barcode_id_source') then
    create type public.app_settings_barcode_id_source as enum ('item_id', 'barcode', 'sku');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_default_seller') then
    create type public.app_settings_default_seller as enum ('logged_in_user', 'last_used', 'manual');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_commission_method') then
    create type public.app_settings_commission_method as enum ('sale_price', 'profit_margin', 'total_sales');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_receipt_text_size') then
    create type public.app_settings_receipt_text_size as enum ('small', 'normal', 'large');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_sale_ui_column') then
    create type public.app_settings_sale_ui_column as enum ('barcode', 'sku', 'category', 'none');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_avg_method') then
    create type public.app_settings_avg_method as enum ('current_received_price', 'weighted_avg', 'last_purchase');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_giftcard_benefit_when') then
    create type public.app_settings_giftcard_benefit_when as enum ('do_nothing', 'on_sale', 'on_redemption');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_grid_default') then
    create type public.app_settings_grid_default as enum ('categories', 'tags', 'favorites');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_credit_block_when') then
    create type public.app_settings_credit_block_when as enum ('exceeds_balance_limit', 'has_overdue_invoices', 'never');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_invoice_default_format') then
    create type public.app_settings_invoice_default_format as enum ('pos_invoice', 'letter_invoice');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_invoice_b2x_format') then
    create type public.app_settings_invoice_b2x_format as enum ('b2c', 'b2b', 'b2g');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_app_language') then
    create type public.app_settings_app_language as enum ('es', 'en');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_app_time_format') then
    create type public.app_settings_app_time_format as enum ('12h', '24h');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_app_search_sort_order') then
    create type public.app_settings_app_search_sort_order as enum ('newest_first', 'oldest_first', 'alphabetical');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_app_spreadsheet_format') then
    create type public.app_settings_app_spreadsheet_format as enum ('xlsx', 'csv');
  end if;

  if not exists (select 1 from pg_type where typname = 'app_settings_app_logout_behavior') then
    create type public.app_settings_app_logout_behavior as enum ('close_browser', 'redirect_login', 'lock_screen');
  end if;
end $$;

-- =====================================================
-- 2) Tabla principal: app_settings (singleton)
-- =====================================================

create table if not exists public.app_settings (
  id smallint primary key default 1 check (id = 1),

  -- Sección 1: Información de la Compañía
  company_name text not null default '',
  company_legal_name text,
  company_tax_id text,
  company_website text,
  company_logo_url text,
  company_stamp_url text,
  company_signature_url text,
  default_ncf_sequence_id uuid references public.ncf_sequences(id) on delete set null,

  -- Sección 2: Inventario
  inv_default_is_service boolean not null default false,
  inv_barcode_id_source public.app_settings_barcode_id_source not null default 'item_id',
  inv_disallow_below_cost boolean not null default false,
  inv_disallow_no_stock boolean not null default false,
  inv_highlight_min_stock boolean not null default true,
  inv_disable_margin_calculator boolean not null default true,

  -- Sección 3: Ajustes del Empleado
  emp_pick_seller_during_sale boolean not null default false,
  emp_seller_required boolean not null default false,
  emp_default_seller public.app_settings_default_seller not null default 'logged_in_user',
  emp_commission_rate numeric(5,2) not null default 0.00 check (emp_commission_rate between 0 and 100),
  emp_commission_method public.app_settings_commission_method not null default 'sale_price',
  emp_require_login_each_sale boolean not null default false,
  emp_keep_position_after_switch boolean not null default true,
  emp_time_clock_enabled boolean not null default false,

  -- Sección 4: Impuestos y Moneda
  tax_default_price_includes_tax boolean not null default false,
  tax_charge_on_receivings boolean not null default false,
  tax_include_in_barcodes boolean not null default true,
  currency_symbol text not null default 'RD$' check (length(currency_symbol) between 1 and 5),
  currency_decimals smallint not null default 2 check (currency_decimals between 0 and 4),
  currency_thousands_sep char(1) not null default ',',
  currency_decimal_point char(1) not null default '.',
  currency_denominations jsonb not null default
    '[{"label":"RD$2000","value":2000},{"label":"RD$1000","value":1000},{"label":"RD$500","value":500},{"label":"RD$200","value":200},{"label":"RD$100","value":100},{"label":"RD$50","value":50},{"label":"RD$25","value":25},{"label":"RD$10","value":10},{"label":"RD$5","value":5},{"label":"RD$1","value":1}]'::jsonb,

  -- Sección 5.1: Recibo (presentación)
  receipt_ignore_title text,
  receipt_hide_signature boolean not null default true,
  receipt_text_size public.app_settings_receipt_text_size not null default 'small',
  receipt_show_item_id boolean not null default false,
  receipt_hide_barcode boolean not null default false,
  receipt_hide_credit_balance boolean not null default true,

  -- Sección 5.2: Recibo (comportamiento)
  receipt_print_after_sale boolean not null default true,
  receipt_print_after_purchase boolean not null default true,
  receipt_auto_duplicate_on_credit_card boolean not null default true,
  receipt_show_after_suspend boolean not null default true,
  receipt_email_customer_auto boolean not null default true,
  receipt_show_observations_auto boolean not null default false,
  receipt_redirect_after_print boolean not null default false,

  -- Sección 5.3: Interfaz de venta
  sale_ui_column public.app_settings_sale_ui_column not null default 'barcode',
  sale_focus_item_field boolean not null default false,
  sale_recent_per_customer integer not null default 10 check (sale_recent_per_customer >= 0),
  sale_strip_customer_contact boolean not null default false,
  sale_hide_recent_for_customer boolean not null default false,
  sale_disable_complete_confirmation boolean not null default true,
  sale_disable_quick_sale boolean not null default false,
  sale_change_date_on_new boolean not null default false,
  sale_no_group_identical_items boolean not null default false,
  sale_edit_zero_price_on_add boolean not null default true,

  -- Sección 5.4: Costo y precios
  sale_calc_avg_purchase_cost boolean not null default true,
  sale_avg_method public.app_settings_avg_method not null default 'current_received_price',
  sale_always_use_global_avg_cost boolean not null default false,
  sale_price_types_round_2_decimals boolean not null default true,
  sale_price_types jsonb not null default '["mayorista","pago efectivo"]'::jsonb,

  -- Sección 5.5: Tarjetas de regalo y recepciones suspendidas
  giftcard_hide_suspended_receivings boolean not null default false,
  giftcard_disable_detection boolean not null default false,
  giftcard_benefit_when public.app_settings_giftcard_benefit_when not null default 'do_nothing',

  -- Sección 5.6: Cuadrícula y layout
  grid_show_during_sale boolean not null default false,
  grid_hide_no_stock boolean not null default false,
  grid_default public.app_settings_grid_default not null default 'categories',

  -- Sección 5.7: Cliente y crédito
  customer_required_for_sale boolean not null default false,
  customer_required_for_suspended boolean not null default false,
  credit_allow_sales boolean not null default true,
  credit_allow_purchases boolean not null default true,
  credit_disable_account_on_overlimit boolean not null default false,
  credit_account_message text,
  credit_ask_ccv_on_card boolean not null default false,
  credit_block_when public.app_settings_credit_block_when not null default 'exceeds_balance_limit',
  fiscal_allow_for_exempt_products boolean not null default true,
  sale_disable_notifications boolean not null default false,
  sale_group_all_taxes_on_receipt boolean not null default false,
  sale_invoice_print_control boolean not null default false,

  -- Sección 5.8: Prefijos de documentos (todos uppercase + dígitos, máx 10 chars)
  prefix_sale text not null default 'FA' check (prefix_sale ~ '^[A-Z0-9]{1,10}$'),
  prefix_credit_note text not null default 'NC' check (prefix_credit_note ~ '^[A-Z0-9]{1,10}$'),
  prefix_debit_note text not null default 'ND' check (prefix_debit_note ~ '^[A-Z0-9]{1,10}$'),
  prefix_delivery text not null default 'CON' check (prefix_delivery ~ '^[A-Z0-9]{1,10}$'),
  prefix_quote text not null default 'CO' check (prefix_quote ~ '^[A-Z0-9]{1,10}$'),
  prefix_credit_payment text not null default 'PAC' check (prefix_credit_payment ~ '^[A-Z0-9]{1,10}$'),
  prefix_installment_payment text not null default 'PA' check (prefix_installment_payment ~ '^[A-Z0-9]{1,10}$'),
  prefix_purchase text not null default 'COM' check (prefix_purchase ~ '^[A-Z0-9]{1,10}$'),
  prefix_purchase_order text not null default 'OC' check (prefix_purchase_order ~ '^[A-Z0-9]{1,10}$'),
  prefix_receipt text not null default 'REC' check (prefix_receipt ~ '^[A-Z0-9]{1,10}$'),

  -- Sección 5.9: Métodos de pago (valores deben coincidir con enum payment_method)
  payment_methods_enabled jsonb not null default '["cash","card","transfer","mobile"]'::jsonb,
  payment_method_default text not null default 'cash',
  payment_channels jsonb not null default '[]'::jsonb,
  payment_show_channels_in_sale boolean not null default false,

  -- Sección 5.10: Formato y políticas
  invoice_default_format public.app_settings_invoice_default_format not null default 'pos_invoice',
  invoice_b2x_format public.app_settings_invoice_b2x_format not null default 'b2c',
  return_policy text not null default '0',
  announcements text,

  -- Sección 6: Cuentas abiertas / Suspendidas
  suspended_hide_payables_in_reports boolean not null default false,
  suspended_hide_account_payments_in_totals boolean not null default false,
  suspended_change_date_on_suspend boolean not null default true,
  suspended_change_date_on_complete boolean not null default true,
  suspended_show_receipt_after boolean not null default true,

  -- Sección 7: Configuración de la aplicación
  app_2fa_enabled boolean not null default false,
  app_test_mode boolean not null default false,
  app_quick_user_switch boolean not null default false,
  app_enable_delivery_notes boolean not null default false,
  app_language public.app_settings_app_language not null default 'es',
  app_date_format text not null default 'dd-MM-yyyy',
  app_time_format public.app_settings_app_time_format not null default '12h',
  app_hide_price_in_barcodes boolean not null default false,
  app_loyalty_enabled boolean not null default false,
  app_status_sounds boolean not null default true,
  app_search_rows_per_page integer not null default 20 check (app_search_rows_per_page between 5 and 100),
  app_grid_items_per_page integer not null default 15 check (app_grid_items_per_page between 5 and 100),
  app_search_sort_order public.app_settings_app_search_sort_order not null default 'newest_first',
  app_hide_panel_stats boolean not null default false,
  app_show_language_switcher boolean not null default false,
  app_show_header_clock boolean not null default false,
  app_fast_search_queries boolean not null default true,
  app_spreadsheet_format public.app_settings_app_spreadsheet_format not null default 'xlsx',
  app_logout_behavior public.app_settings_app_logout_behavior not null default 'redirect_login',

  -- Auditoría
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  updated_by uuid references auth.users(id)
);

comment on table public.app_settings is
  'Configuración global del negocio (PRD 06). Singleton: una sola fila con id=1.';

-- =====================================================
-- 3) Tabla de auditoría: app_settings_audit
-- =====================================================

create table if not exists public.app_settings_audit (
  id bigserial primary key,
  field_name text not null,
  old_value jsonb,
  new_value jsonb,
  changed_at timestamptz not null default timezone('utc', now()),
  changed_by uuid references auth.users(id)
);

create index if not exists app_settings_audit_changed_at_idx
  on public.app_settings_audit (changed_at desc);

create index if not exists app_settings_audit_field_idx
  on public.app_settings_audit (field_name, changed_at desc);

comment on table public.app_settings_audit is
  'Histórico de cambios columna a columna sobre app_settings.';

-- =====================================================
-- 4) Trigger de auditoría: una fila por columna modificada
-- =====================================================

create or replace function public.app_settings_audit_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_key text;
  v_user uuid;
begin
  v_old := to_jsonb(old) - 'updated_at' - 'updated_by';
  v_new := to_jsonb(new) - 'updated_at' - 'updated_by';
  v_user := coalesce(auth.uid(), new.updated_by);

  for v_key in select jsonb_object_keys(v_new)
  loop
    if (v_old -> v_key) is distinct from (v_new -> v_key) then
      insert into public.app_settings_audit (field_name, old_value, new_value, changed_by)
      values (v_key, v_old -> v_key, v_new -> v_key, v_user);
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_app_settings_audit on public.app_settings;
create trigger trg_app_settings_audit
after update on public.app_settings
for each row execute function public.app_settings_audit_changes();

-- updated_at maintenance reuses existing helper
drop trigger if exists trg_app_settings_updated_at on public.app_settings;
create trigger trg_app_settings_updated_at
before update on public.app_settings
for each row execute function public.set_updated_at();

-- =====================================================
-- 5) Función de inicialización (singleton seed)
-- =====================================================

create or replace function public.initialize_app_settings()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.app_settings (id, company_name)
  values (1, '')
  on conflict (id) do nothing;
end;
$$;

grant execute on function public.initialize_app_settings() to authenticated;

-- Seed la fila única en este deploy.
select public.initialize_app_settings();

-- Si hay sucursal principal con datos, copiar nombre / RNC / logo a app_settings
-- (solo si app_settings.company_name está vacío, para no pisar configuración existente).
update public.app_settings s
set
  company_name = coalesce(nullif(b.name, ''), s.company_name),
  company_legal_name = coalesce(b.legal_name, s.company_legal_name),
  company_tax_id = coalesce(b.tax_id, s.company_tax_id),
  company_website = coalesce(b.website, s.company_website),
  company_logo_url = coalesce(b.logo_url, s.company_logo_url)
from public.branches b
where s.id = 1
  and s.company_name = ''
  and b.is_main = true
  and b.is_active = true;

-- =====================================================
-- 6) RLS: lectura para autenticados, escritura solo admin
-- =====================================================

alter table public.app_settings enable row level security;
alter table public.app_settings_audit enable row level security;

drop policy if exists app_settings_select on public.app_settings;
create policy app_settings_select
on public.app_settings
for select
to authenticated
using (true);

drop policy if exists app_settings_update on public.app_settings;
create policy app_settings_update
on public.app_settings
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- INSERT bloqueado fuera de la función init: solo admin puede insertar
-- (la función init es SECURITY DEFINER y no respeta RLS).
drop policy if exists app_settings_insert on public.app_settings;
create policy app_settings_insert
on public.app_settings
for insert
to authenticated
with check (public.is_admin());

-- DELETE bloqueado a nivel de policy (singleton; nunca se elimina).
drop policy if exists app_settings_delete on public.app_settings;
create policy app_settings_delete
on public.app_settings
for delete
to authenticated
using (false);

drop policy if exists app_settings_audit_select on public.app_settings_audit;
create policy app_settings_audit_select
on public.app_settings_audit
for select
to authenticated
using (public.is_admin());

drop policy if exists app_settings_audit_block on public.app_settings_audit;
create policy app_settings_audit_block
on public.app_settings_audit
for all
to authenticated
using (false)
with check (false);

-- =====================================================
-- 7) Grants
-- =====================================================

grant select, update on public.app_settings to authenticated;
grant select on public.app_settings_audit to authenticated;

commit;
