-- ============================================================
-- Shop+ RD — Bundle SQL completo (self-hosted)
-- Generado: 2026-05-24 10:17:05
--
-- Aplicar en orden, en una BD Postgres limpia (Supabase self-hosted).
-- Cada archivo está delimitado por un banner para que sea fácil
-- ubicar problemas si algo falla.
--
-- Si querés datos demo, edita build_full_sql.sh y descomenta
-- la línea de 02_seed.sql.
-- ============================================================


-- ============================================================
-- BEGIN: sql/01_schema.sql
-- ============================================================
-- Shop+ RD
-- Supabase schema MVP (PRD React -> Flutter)
-- Execute first in Supabase SQL Editor.

begin;

create extension if not exists pgcrypto;
create extension if not exists citext;

-- =========================
-- Enum types
-- =========================
do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_role') then
    create type public.app_role as enum (
      'admin',
      'supervisor',
      'cashier',
      'accountant'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'receipt_type') then
    create type public.receipt_type as enum (
      'consumer_final',
      'fiscal_credit',
      'governmental',
      'special',
      'export'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'dgii_status') then
    create type public.dgii_status as enum (
      'pending',
      'sent',
      'approved',
      'rejected'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'sale_status') then
    create type public.sale_status as enum (
      'draft',
      'completed',
      'credit',
      'pending',
      'voided'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'purchase_status') then
    create type public.purchase_status as enum (
      'draft',
      'posted',
      'cancelled'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'cash_session_status') then
    create type public.cash_session_status as enum (
      'open',
      'closed'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'payment_method') then
    create type public.payment_method as enum (
      'cash',
      'card',
      'transfer',
      'mobile',
      'mixed',
      'credit'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'entity_type') then
    create type public.entity_type as enum (
      'person',
      'company',
      'government'
    );
  end if;
end $$;

-- =========================
-- Shared functions
-- =========================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create or replace function public.set_audit_fields()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.created_by is null then
      new.created_by = auth.uid();
    end if;
    if new.updated_by is null then
      new.updated_by = auth.uid();
    end if;
  else
    new.updated_by = coalesce(auth.uid(), new.updated_by);
  end if;
  return new;
end;
$$;

-- =========================
-- Core tables
-- =========================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email citext unique,
  full_name text not null default '',
  role public.app_role not null default 'cashier',
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  address text,
  phone text,
  is_main boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id)
);

create table if not exists public.users_branches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  role_override public.app_role,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (user_id, branch_id)
);

create unique index if not exists users_branches_default_active_unique
  on public.users_branches (user_id)
  where is_default and is_active;

create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id)
);

create unique index if not exists product_categories_name_unique
  on public.product_categories (branch_id, lower(name));

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  category_id uuid,
  sku text,
  barcode text,
  name text not null,
  description text,
  unit text not null default 'unidad',
  cost numeric(14,2) not null default 0 check (cost >= 0),
  price numeric(14,2) not null check (price >= 0),
  tax_rate numeric(5,2) not null default 18.00 check (tax_rate >= 0 and tax_rate <= 100),
  stock numeric(14,3) not null default 0,
  min_stock numeric(14,3) not null default 0 check (min_stock >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id),
  constraint products_category_branch_fk
    foreign key (category_id, branch_id)
    references public.product_categories(id, branch_id)
    on delete restrict
);

create unique index if not exists products_sku_unique
  on public.products (branch_id, sku)
  where sku is not null;

create unique index if not exists products_barcode_unique
  on public.products (branch_id, barcode)
  where barcode is not null;

create index if not exists products_name_idx
  on public.products (branch_id, lower(name));

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  entity_type public.entity_type not null default 'person',
  full_name text not null,
  legal_name text,
  email citext,
  phone text,
  address text,
  document_type text,
  document_number text,
  credit_limit numeric(14,2) not null default 0 check (credit_limit >= 0),
  balance_due numeric(14,2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id)
);

create unique index if not exists clients_document_unique
  on public.clients (branch_id, coalesce(lower(document_type), ''), coalesce(lower(document_number), ''))
  where document_number is not null;

create index if not exists clients_name_idx
  on public.clients (branch_id, lower(full_name));

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  legal_name text not null,
  trade_name text,
  email citext,
  phone text,
  address text,
  rnc text,
  contact_name text,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id)
);

create unique index if not exists suppliers_rnc_unique
  on public.suppliers (branch_id, lower(rnc))
  where rnc is not null;

create table if not exists public.purchases (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  supplier_id uuid not null,
  purchase_number text,
  invoice_number text,
  status public.purchase_status not null default 'posted',
  purchase_date date not null default current_date,
  notes text,
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id),
  constraint purchases_supplier_branch_fk
    foreign key (supplier_id, branch_id)
    references public.suppliers(id, branch_id)
    on delete restrict
);

create unique index if not exists purchases_number_unique
  on public.purchases (branch_id, purchase_number)
  where purchase_number is not null;

create table if not exists public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null,
  branch_id uuid not null,
  product_id uuid not null,
  description text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_rate numeric(5,2) not null default 18.00 check (tax_rate >= 0 and tax_rate <= 100),
  line_subtotal numeric(14,2) not null check (line_subtotal >= 0),
  line_tax numeric(14,2) not null default 0 check (line_tax >= 0),
  line_total numeric(14,2) not null check (line_total >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint purchase_items_purchase_fk
    foreign key (purchase_id, branch_id)
    references public.purchases(id, branch_id)
    on delete cascade,
  constraint purchase_items_product_fk
    foreign key (product_id, branch_id)
    references public.products(id, branch_id)
    on delete restrict
);

create index if not exists purchase_items_purchase_idx
  on public.purchase_items (purchase_id);

create table if not exists public.ncf_sequences (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  receipt_type public.receipt_type not null,
  prefix text not null,
  current_number bigint not null default 0,
  max_number bigint,
  expires_on date,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (branch_id, receipt_type, prefix)
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  sale_number text,
  client_id uuid,
  cashier_id uuid references auth.users(id),
  receipt_type public.receipt_type not null default 'consumer_final',
  ncf text,
  dgii_status public.dgii_status not null default 'pending',
  status public.sale_status not null default 'completed',
  sale_date timestamptz not null default timezone('utc', now()),
  due_date date,
  notes text,
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  paid_amount numeric(14,2) not null default 0 check (paid_amount >= 0),
  balance_due numeric(14,2) not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id),
  constraint sales_client_branch_fk
    foreign key (client_id, branch_id)
    references public.clients(id, branch_id)
    on delete restrict
);

create unique index if not exists sales_number_unique
  on public.sales (branch_id, sale_number)
  where sale_number is not null;

create unique index if not exists sales_ncf_unique
  on public.sales (branch_id, ncf)
  where ncf is not null;

create index if not exists sales_date_idx
  on public.sales (branch_id, sale_date desc);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null,
  branch_id uuid not null,
  product_id uuid not null,
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
  constraint sale_items_sale_fk
    foreign key (sale_id, branch_id)
    references public.sales(id, branch_id)
    on delete cascade,
  constraint sale_items_product_fk
    foreign key (product_id, branch_id)
    references public.products(id, branch_id)
    on delete restrict
);

create index if not exists sale_items_sale_idx
  on public.sale_items (sale_id);

create table if not exists public.cash_sessions (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  opened_by uuid not null references auth.users(id),
  closed_by uuid references auth.users(id),
  status public.cash_session_status not null default 'open',
  opened_at timestamptz not null default timezone('utc', now()),
  closed_at timestamptz,
  opening_amount numeric(14,2) not null default 0,
  expected_amount numeric(14,2) not null default 0,
  closing_amount numeric(14,2),
  difference_amount numeric(14,2),
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id)
);

create unique index if not exists cash_sessions_open_unique
  on public.cash_sessions (branch_id)
  where status = 'open';

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  sale_id uuid,
  client_id uuid,
  cash_session_id uuid,
  payment_method public.payment_method not null,
  amount numeric(14,2) not null check (amount > 0),
  paid_at timestamptz not null default timezone('utc', now()),
  reference text,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint payments_sale_fk
    foreign key (sale_id, branch_id)
    references public.sales(id, branch_id)
    on delete restrict,
  constraint payments_client_fk
    foreign key (client_id, branch_id)
    references public.clients(id, branch_id)
    on delete restrict,
  constraint payments_cash_session_fk
    foreign key (cash_session_id, branch_id)
    references public.cash_sessions(id, branch_id)
    on delete restrict,
  constraint payments_requires_target
    check (sale_id is not null or client_id is not null)
);

create index if not exists payments_sale_idx
  on public.payments (sale_id);

create index if not exists payments_client_idx
  on public.payments (client_id);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  cash_session_id uuid,
  supplier_id uuid,
  category text not null,
  description text,
  payment_method public.payment_method not null default 'cash',
  amount numeric(14,2) not null check (amount > 0),
  expense_date date not null default current_date,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint expenses_cash_session_fk
    foreign key (cash_session_id, branch_id)
    references public.cash_sessions(id, branch_id)
    on delete restrict,
  constraint expenses_supplier_fk
    foreign key (supplier_id, branch_id)
    references public.suppliers(id, branch_id)
    on delete restrict
);

create index if not exists expenses_date_idx
  on public.expenses (branch_id, expense_date desc);

-- =========================
-- Stock movement triggers
-- =========================
create or replace function public.apply_purchase_item_stock()
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

  if tg_op = 'UPDATE' then
    if old.product_id = new.product_id and old.branch_id = new.branch_id then
      update public.products
        set stock = stock + (new.quantity - old.quantity)
      where id = new.product_id
        and branch_id = new.branch_id;
    else
      update public.products
        set stock = stock - old.quantity
      where id = old.product_id
        and branch_id = old.branch_id;

      update public.products
        set stock = stock + new.quantity
      where id = new.product_id
        and branch_id = new.branch_id;
    end if;
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

create or replace function public.apply_sale_item_stock()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    update public.products
      set stock = stock - new.quantity
    where id = new.product_id
      and branch_id = new.branch_id;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.product_id = new.product_id and old.branch_id = new.branch_id then
      update public.products
        set stock = stock - (new.quantity - old.quantity)
      where id = new.product_id
        and branch_id = new.branch_id;
    else
      update public.products
        set stock = stock + old.quantity
      where id = old.product_id
        and branch_id = old.branch_id;

      update public.products
        set stock = stock - new.quantity
      where id = new.product_id
        and branch_id = new.branch_id;
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    update public.products
      set stock = stock + old.quantity
    where id = old.product_id
      and branch_id = old.branch_id;
    return old;
  end if;

  return null;
end;
$$;

-- =========================
-- Auth sync trigger
-- =========================
create or replace function public.handle_auth_user_upsert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role_text text;
  v_role public.app_role;
  v_full_name text;
begin
  v_role_text := coalesce(new.raw_user_meta_data ->> 'role', 'cashier');
  if v_role_text in ('admin', 'supervisor', 'cashier', 'accountant') then
    v_role := v_role_text::public.app_role;
  else
    v_role := 'cashier';
  end if;

  v_full_name := coalesce(new.raw_user_meta_data ->> 'full_name', split_part(coalesce(new.email, ''), '@', 1));

  insert into public.profiles (id, email, full_name, role, is_active)
  values (new.id, new.email, coalesce(v_full_name, ''), v_role, true)
  on conflict (id)
  do update set
    email = excluded.email,
    updated_at = timezone('utc', now());

  return new;
end;
$$;

-- =========================
-- Updated at + audit triggers
-- =========================
drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists trg_branches_updated_at on public.branches;
create trigger trg_branches_updated_at
before update on public.branches
for each row execute function public.set_updated_at();

drop trigger if exists trg_users_branches_updated_at on public.users_branches;
create trigger trg_users_branches_updated_at
before update on public.users_branches
for each row execute function public.set_updated_at();

drop trigger if exists trg_product_categories_updated_at on public.product_categories;
create trigger trg_product_categories_updated_at
before update on public.product_categories
for each row execute function public.set_updated_at();

drop trigger if exists trg_products_updated_at on public.products;
create trigger trg_products_updated_at
before update on public.products
for each row execute function public.set_updated_at();

drop trigger if exists trg_clients_updated_at on public.clients;
create trigger trg_clients_updated_at
before update on public.clients
for each row execute function public.set_updated_at();

drop trigger if exists trg_suppliers_updated_at on public.suppliers;
create trigger trg_suppliers_updated_at
before update on public.suppliers
for each row execute function public.set_updated_at();

drop trigger if exists trg_purchases_updated_at on public.purchases;
create trigger trg_purchases_updated_at
before update on public.purchases
for each row execute function public.set_updated_at();

drop trigger if exists trg_purchase_items_updated_at on public.purchase_items;
create trigger trg_purchase_items_updated_at
before update on public.purchase_items
for each row execute function public.set_updated_at();

drop trigger if exists trg_ncf_sequences_updated_at on public.ncf_sequences;
create trigger trg_ncf_sequences_updated_at
before update on public.ncf_sequences
for each row execute function public.set_updated_at();

drop trigger if exists trg_sales_updated_at on public.sales;
create trigger trg_sales_updated_at
before update on public.sales
for each row execute function public.set_updated_at();

drop trigger if exists trg_sale_items_updated_at on public.sale_items;
create trigger trg_sale_items_updated_at
before update on public.sale_items
for each row execute function public.set_updated_at();

drop trigger if exists trg_cash_sessions_updated_at on public.cash_sessions;
create trigger trg_cash_sessions_updated_at
before update on public.cash_sessions
for each row execute function public.set_updated_at();

drop trigger if exists trg_payments_updated_at on public.payments;
create trigger trg_payments_updated_at
before update on public.payments
for each row execute function public.set_updated_at();

drop trigger if exists trg_expenses_updated_at on public.expenses;
create trigger trg_expenses_updated_at
before update on public.expenses
for each row execute function public.set_updated_at();

drop trigger if exists trg_branches_audit_fields on public.branches;
create trigger trg_branches_audit_fields
before insert or update on public.branches
for each row execute function public.set_audit_fields();

drop trigger if exists trg_users_branches_audit_fields on public.users_branches;
create trigger trg_users_branches_audit_fields
before insert or update on public.users_branches
for each row execute function public.set_audit_fields();

drop trigger if exists trg_product_categories_audit_fields on public.product_categories;
create trigger trg_product_categories_audit_fields
before insert or update on public.product_categories
for each row execute function public.set_audit_fields();

drop trigger if exists trg_products_audit_fields on public.products;
create trigger trg_products_audit_fields
before insert or update on public.products
for each row execute function public.set_audit_fields();

drop trigger if exists trg_clients_audit_fields on public.clients;
create trigger trg_clients_audit_fields
before insert or update on public.clients
for each row execute function public.set_audit_fields();

drop trigger if exists trg_suppliers_audit_fields on public.suppliers;
create trigger trg_suppliers_audit_fields
before insert or update on public.suppliers
for each row execute function public.set_audit_fields();

drop trigger if exists trg_purchases_audit_fields on public.purchases;
create trigger trg_purchases_audit_fields
before insert or update on public.purchases
for each row execute function public.set_audit_fields();

drop trigger if exists trg_purchase_items_audit_fields on public.purchase_items;
create trigger trg_purchase_items_audit_fields
before insert or update on public.purchase_items
for each row execute function public.set_audit_fields();

drop trigger if exists trg_ncf_sequences_audit_fields on public.ncf_sequences;
create trigger trg_ncf_sequences_audit_fields
before insert or update on public.ncf_sequences
for each row execute function public.set_audit_fields();

drop trigger if exists trg_sales_audit_fields on public.sales;
create trigger trg_sales_audit_fields
before insert or update on public.sales
for each row execute function public.set_audit_fields();

drop trigger if exists trg_sale_items_audit_fields on public.sale_items;
create trigger trg_sale_items_audit_fields
before insert or update on public.sale_items
for each row execute function public.set_audit_fields();

drop trigger if exists trg_cash_sessions_audit_fields on public.cash_sessions;
create trigger trg_cash_sessions_audit_fields
before insert or update on public.cash_sessions
for each row execute function public.set_audit_fields();

drop trigger if exists trg_payments_audit_fields on public.payments;
create trigger trg_payments_audit_fields
before insert or update on public.payments
for each row execute function public.set_audit_fields();

drop trigger if exists trg_expenses_audit_fields on public.expenses;
create trigger trg_expenses_audit_fields
before insert or update on public.expenses
for each row execute function public.set_audit_fields();

drop trigger if exists trg_purchase_items_stock on public.purchase_items;
create trigger trg_purchase_items_stock
after insert or update or delete on public.purchase_items
for each row execute function public.apply_purchase_item_stock();

drop trigger if exists trg_sale_items_stock on public.sale_items;
create trigger trg_sale_items_stock
after insert or update or delete on public.sale_items
for each row execute function public.apply_sale_item_stock();

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_auth_user_upsert();

-- Backfill profiles for users that already exist.
insert into public.profiles (id, email, full_name, role, is_active)
select
  u.id,
  u.email,
  coalesce(u.raw_user_meta_data ->> 'full_name', split_part(coalesce(u.email, ''), '@', 1)),
  'cashier'::public.app_role,
  true
from auth.users u
where not exists (
  select 1 from public.profiles p where p.id = u.id
);

-- =========================
-- RLS helper functions
-- =========================
create or replace function public.current_user_role()
returns public.app_role
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select p.role
      from public.profiles p
      where p.id = auth.uid()
        and p.is_active
      limit 1
    ),
    'cashier'::public.app_role
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_user_role() = 'admin'::public.app_role;
$$;

create or replace function public.can_manage_branch_data()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_user_role() in ('admin'::public.app_role, 'supervisor'::public.app_role);
$$;

create or replace function public.can_operate_pos()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_user_role() in (
    'admin'::public.app_role,
    'supervisor'::public.app_role,
    'cashier'::public.app_role
  );
$$;

create or replace function public.has_branch_access(target_branch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users_branches ub
    join public.profiles p on p.id = ub.user_id
    where ub.user_id = auth.uid()
      and ub.branch_id = target_branch_id
      and ub.is_active
      and p.is_active
  );
$$;

grant execute on function public.current_user_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_manage_branch_data() to authenticated;
grant execute on function public.can_operate_pos() to authenticated;
grant execute on function public.has_branch_access(uuid) to authenticated;

-- =========================
-- RLS policies
-- =========================
alter table public.profiles enable row level security;
alter table public.branches enable row level security;
alter table public.users_branches enable row level security;
alter table public.product_categories enable row level security;
alter table public.products enable row level security;
alter table public.clients enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.ncf_sequences enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.cash_sessions enable row level security;
alter table public.payments enable row level security;
alter table public.expenses enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select
on public.profiles
for select
using (auth.uid() = id or public.is_admin());

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert
on public.profiles
for insert
to authenticated
with check (auth.uid() = id or public.is_admin());

drop policy if exists profiles_update on public.profiles;
create policy profiles_update
on public.profiles
for update
to authenticated
using (auth.uid() = id or public.is_admin())
with check (auth.uid() = id or public.is_admin());

drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete
on public.profiles
for delete
to authenticated
using (public.is_admin());

drop policy if exists branches_select on public.branches;
create policy branches_select
on public.branches
for select
to authenticated
using (public.is_admin() or public.has_branch_access(id));

drop policy if exists branches_write on public.branches;
create policy branches_write
on public.branches
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists users_branches_select on public.users_branches;
create policy users_branches_select
on public.users_branches
for select
to authenticated
using (public.is_admin() or user_id = auth.uid());

drop policy if exists users_branches_write on public.users_branches;
create policy users_branches_write
on public.users_branches
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists product_categories_select on public.product_categories;
create policy product_categories_select
on public.product_categories
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists product_categories_insert on public.product_categories;
create policy product_categories_insert
on public.product_categories
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists product_categories_update on public.product_categories;
create policy product_categories_update
on public.product_categories
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists product_categories_delete on public.product_categories;
create policy product_categories_delete
on public.product_categories
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists products_select on public.products;
create policy products_select
on public.products
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists products_insert on public.products;
create policy products_insert
on public.products
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists products_update on public.products;
create policy products_update
on public.products
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists products_delete on public.products;
create policy products_delete
on public.products
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists clients_select on public.clients;
create policy clients_select
on public.clients
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists clients_insert on public.clients;
create policy clients_insert
on public.clients
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists clients_update on public.clients;
create policy clients_update
on public.clients
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists clients_delete on public.clients;
create policy clients_delete
on public.clients
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists suppliers_select on public.suppliers;
create policy suppliers_select
on public.suppliers
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists suppliers_insert on public.suppliers;
create policy suppliers_insert
on public.suppliers
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists suppliers_update on public.suppliers;
create policy suppliers_update
on public.suppliers
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists suppliers_delete on public.suppliers;
create policy suppliers_delete
on public.suppliers
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists purchases_select on public.purchases;
create policy purchases_select
on public.purchases
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists purchases_insert on public.purchases;
create policy purchases_insert
on public.purchases
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists purchases_update on public.purchases;
create policy purchases_update
on public.purchases
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists purchases_delete on public.purchases;
create policy purchases_delete
on public.purchases
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists purchase_items_select on public.purchase_items;
create policy purchase_items_select
on public.purchase_items
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists purchase_items_insert on public.purchase_items;
create policy purchase_items_insert
on public.purchase_items
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists purchase_items_update on public.purchase_items;
create policy purchase_items_update
on public.purchase_items
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists purchase_items_delete on public.purchase_items;
create policy purchase_items_delete
on public.purchase_items
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists ncf_sequences_select on public.ncf_sequences;
create policy ncf_sequences_select
on public.ncf_sequences
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists ncf_sequences_write on public.ncf_sequences;
create policy ncf_sequences_write
on public.ncf_sequences
for all
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists sales_select on public.sales;
create policy sales_select
on public.sales
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists sales_insert on public.sales;
create policy sales_insert
on public.sales
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists sales_update on public.sales;
create policy sales_update
on public.sales
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists sales_delete on public.sales;
create policy sales_delete
on public.sales
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists sale_items_select on public.sale_items;
create policy sale_items_select
on public.sale_items
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists sale_items_insert on public.sale_items;
create policy sale_items_insert
on public.sale_items
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists sale_items_update on public.sale_items;
create policy sale_items_update
on public.sale_items
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists sale_items_delete on public.sale_items;
create policy sale_items_delete
on public.sale_items
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists cash_sessions_select on public.cash_sessions;
create policy cash_sessions_select
on public.cash_sessions
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists cash_sessions_insert on public.cash_sessions;
create policy cash_sessions_insert
on public.cash_sessions
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists cash_sessions_update on public.cash_sessions;
create policy cash_sessions_update
on public.cash_sessions
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists cash_sessions_delete on public.cash_sessions;
create policy cash_sessions_delete
on public.cash_sessions
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists payments_select on public.payments;
create policy payments_select
on public.payments
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists payments_insert on public.payments;
create policy payments_insert
on public.payments
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists payments_update on public.payments;
create policy payments_update
on public.payments
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists payments_delete on public.payments;
create policy payments_delete
on public.payments
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists expenses_select on public.expenses;
create policy expenses_select
on public.expenses
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists expenses_insert on public.expenses;
create policy expenses_insert
on public.expenses
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists expenses_update on public.expenses;
create policy expenses_update
on public.expenses
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists expenses_delete on public.expenses;
create policy expenses_delete
on public.expenses
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

-- =========================
-- Grants
-- =========================
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

commit;

-- ============================================================
-- END:   sql/01_schema.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql/03_reports_views.sql
-- ============================================================
-- Shop+ RD
-- Vistas de reportes para dashboard / panel
-- Ejecutar despues de 01_schema.sql y 02_seed.sql

begin;

-- =========================
-- Helpers
-- =========================
create or replace function public.current_branch_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select ub.branch_id
  from public.users_branches ub
  where ub.user_id = auth.uid()
    and ub.is_active
  order by ub.is_default desc, ub.created_at asc
  limit 1;
$$;

grant execute on function public.current_branch_id() to authenticated;

-- =========================
-- Dashboard KPIs
-- =========================
create or replace view public.dashboard_kpis_by_branch
with (security_invoker = true)
as
with sales_scope as (
  select s.*
  from public.sales s
  where s.status <> 'voided'::public.sale_status
),
month_bounds as (
  select
    date_trunc('month', timezone('utc', now())) as month_start,
    date_trunc('month', timezone('utc', now())) + interval '1 month' as next_month_start
),
active_products as (
  select p.branch_id, count(*)::bigint as products_active
  from public.products p
  where p.is_active
  group by p.branch_id
),
active_clients as (
  select c.branch_id, count(*)::bigint as clients_active
  from public.clients c
  where c.is_active
  group by c.branch_id
),
ncf_usage as (
  select
    ns.branch_id,
    coalesce(sum(ns.current_number), 0)::bigint as ncf_consumed,
    coalesce(sum(greatest(coalesce(ns.max_number, ns.current_number), ns.current_number) - ns.current_number), 0)::bigint as ncf_available
  from public.ncf_sequences ns
  where ns.is_active
  group by ns.branch_id
)
select
  b.id as branch_id,
  b.code as branch_code,
  b.name as branch_name,
  coalesce(sum(case when s.sale_date::date = timezone('utc', now())::date then s.total_amount else 0 end), 0)::numeric(14,2) as sales_today_amount,
  coalesce(sum(case when s.sale_date::date = timezone('utc', now())::date then 1 else 0 end), 0)::bigint as sales_today_count,
  coalesce(sum(case when s.sale_date >= mb.month_start and s.sale_date < mb.next_month_start then s.total_amount else 0 end), 0)::numeric(14,2) as sales_month_amount,
  coalesce(sum(case when s.sale_date >= mb.month_start and s.sale_date < mb.next_month_start then 1 else 0 end), 0)::bigint as sales_month_count,
  coalesce(ap.products_active, 0)::bigint as products_active,
  coalesce(ac.clients_active, 0)::bigint as clients_active,
  coalesce(sum(case when s.ncf is not null and s.sale_date >= mb.month_start and s.sale_date < mb.next_month_start then 1 else 0 end), 0)::bigint as ecf_issued_month,
  coalesce(nu.ncf_consumed, 0)::bigint as ncf_consumed,
  coalesce(nu.ncf_available, 0)::bigint as ncf_available
from public.branches b
cross join month_bounds mb
left join sales_scope s on s.branch_id = b.id
left join active_products ap on ap.branch_id = b.id
left join active_clients ac on ac.branch_id = b.id
left join ncf_usage nu on nu.branch_id = b.id
where public.has_branch_access(b.id)
group by b.id, b.code, b.name, ap.products_active, ac.clients_active, nu.ncf_consumed, nu.ncf_available;

-- =========================
-- Ventas por mes (ultimos 12 meses)
-- =========================
create or replace view public.sales_monthly_summary
with (security_invoker = true)
as
with months as (
  select generate_series(
    date_trunc('month', timezone('utc', now())) - interval '11 months',
    date_trunc('month', timezone('utc', now())),
    interval '1 month'
  ) as month_start
),
branches_scope as (
  select b.id, b.code, b.name
  from public.branches b
  where public.has_branch_access(b.id)
)
select
  bs.id as branch_id,
  bs.code as branch_code,
  bs.name as branch_name,
  m.month_start::date as period_start,
  to_char(m.month_start, 'YYYY-MM') as period_key,
  to_char(m.month_start, 'Mon YYYY') as period_label,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as total_amount,
  coalesce(count(s.id), 0)::bigint as transaction_count
from branches_scope bs
cross join months m
left join public.sales s
  on s.branch_id = bs.id
 and s.status <> 'voided'::public.sale_status
 and s.sale_date >= m.month_start
 and s.sale_date < m.month_start + interval '1 month'
group by bs.id, bs.code, bs.name, m.month_start
order by bs.name, m.month_start;

-- =========================
-- Ventas por semana (ultimas 12 semanas)
-- =========================
create or replace view public.sales_weekly_summary
with (security_invoker = true)
as
with weeks as (
  select generate_series(
    date_trunc('week', timezone('utc', now())) - interval '11 weeks',
    date_trunc('week', timezone('utc', now())),
    interval '1 week'
  ) as week_start
),
branches_scope as (
  select b.id, b.code, b.name
  from public.branches b
  where public.has_branch_access(b.id)
)
select
  bs.id as branch_id,
  bs.code as branch_code,
  bs.name as branch_name,
  w.week_start::date as period_start,
  to_char(w.week_start, 'IYYY-"W"IW') as period_key,
  to_char(w.week_start, 'DD Mon') || ' - ' || to_char(w.week_start + interval '6 days', 'DD Mon') as period_label,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as total_amount,
  coalesce(count(s.id), 0)::bigint as transaction_count
from branches_scope bs
cross join weeks w
left join public.sales s
  on s.branch_id = bs.id
 and s.status <> 'voided'::public.sale_status
 and s.sale_date >= w.week_start
 and s.sale_date < w.week_start + interval '1 week'
group by bs.id, bs.code, bs.name, w.week_start
order by bs.name, w.week_start;

-- =========================
-- Ultimas ventas
-- =========================
create or replace view public.latest_sales_view
with (security_invoker = true)
as
select
  s.id,
  s.branch_id,
  b.code as branch_code,
  b.name as branch_name,
  s.sale_number,
  s.sale_date,
  s.receipt_type,
  s.ncf,
  s.dgii_status,
  s.status,
  s.total_amount,
  s.paid_amount,
  s.balance_due,
  coalesce(c.full_name, 'Cliente General') as client_name,
  p.full_name as cashier_name
from public.sales s
join public.branches b on b.id = s.branch_id
left join public.clients c on c.id = s.client_id and c.branch_id = s.branch_id
left join public.profiles p on p.id = s.cashier_id
where public.has_branch_access(s.branch_id)
  and s.status <> 'voided'::public.sale_status
order by s.sale_date desc;

-- =========================
-- Cuentas por cobrar (resumen)
-- =========================
create or replace view public.accounts_receivable_summary
with (security_invoker = true)
as
select
  s.branch_id,
  b.code as branch_code,
  b.name as branch_name,
  count(*) filter (where s.balance_due > 0)::bigint as invoices_open,
  coalesce(sum(s.balance_due) filter (where s.balance_due > 0), 0)::numeric(14,2) as total_balance_due,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as total_invoiced,
  coalesce(sum(p.amount), 0)::numeric(14,2) as total_collected
from public.sales s
join public.branches b on b.id = s.branch_id
left join public.payments p on p.sale_id = s.id and p.branch_id = s.branch_id
where public.has_branch_access(s.branch_id)
  and s.status in ('completed'::public.sale_status, 'credit'::public.sale_status, 'pending'::public.sale_status)
group by s.branch_id, b.code, b.name;

-- =========================
-- Inventario bajo stock
-- =========================
create or replace view public.inventory_low_stock_view
with (security_invoker = true)
as
select
  p.id,
  p.branch_id,
  b.code as branch_code,
  b.name as branch_name,
  p.sku,
  p.barcode,
  p.name,
  p.stock,
  p.min_stock,
  p.price,
  p.is_active,
  (p.stock <= p.min_stock) as is_low_stock
from public.products p
join public.branches b on b.id = p.branch_id
where public.has_branch_access(p.branch_id)
  and p.is_active
  and p.stock <= p.min_stock
order by p.stock asc, p.name asc;

-- =========================
-- NCF consumidos/disponibles
-- =========================
create or replace view public.ncf_usage_summary
with (security_invoker = true)
as
select
  ns.id,
  ns.branch_id,
  b.code as branch_code,
  b.name as branch_name,
  ns.receipt_type,
  ns.prefix,
  ns.current_number,
  ns.max_number,
  greatest(coalesce(ns.max_number, ns.current_number), ns.current_number) - ns.current_number as available,
  ns.expires_on,
  ns.is_active
from public.ncf_sequences ns
join public.branches b on b.id = ns.branch_id
where public.has_branch_access(ns.branch_id)
order by b.name, ns.receipt_type, ns.prefix;

-- =========================
-- Grants
-- =========================
grant select on public.dashboard_kpis_by_branch to authenticated;
grant select on public.sales_monthly_summary to authenticated;
grant select on public.sales_weekly_summary to authenticated;
grant select on public.latest_sales_view to authenticated;
grant select on public.accounts_receivable_summary to authenticated;
grant select on public.inventory_low_stock_view to authenticated;
grant select on public.ncf_usage_summary to authenticated;

commit;

-- ============================================================
-- END:   sql/03_reports_views.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql/04_branch_context.sql
-- ============================================================
-- Shop+ RD
-- Helper para cambiar sucursal actual por usuario autenticado.
-- Ejecutar despues de 01_schema.sql y 03_reports_views.sql.

begin;

create or replace function public.set_current_branch(target_branch_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'No hay sesión activa.';
  end if;

  if not exists (
    select 1
    from public.users_branches ub
    where ub.user_id = v_user_id
      and ub.branch_id = target_branch_id
      and ub.is_active
  ) then
    raise exception 'La sucursal no está asignada al usuario.';
  end if;

  update public.users_branches
  set is_default = false
  where user_id = v_user_id
    and is_active
    and is_default;

  update public.users_branches
  set is_default = true
  where user_id = v_user_id
    and branch_id = target_branch_id
    and is_active;

  return target_branch_id;
end;
$$;

grant execute on function public.set_current_branch(uuid) to authenticated;

commit;

-- ============================================================
-- END:   sql/04_branch_context.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/05_cash_foundation_core.sql
-- ============================================================
-- =============================================================================
-- Shop+ RD - Cash foundation core (phase-safe, additive)
-- Fecha: 2026-04-10
--
-- Purpose:
--   Introduce cash_locations, cash_transfers, cash_movements, and extend
--   cash_sessions with location-aware fields without breaking current runtime.
--
-- Compatibility rules:
--   - Keep existing public.cash_sessions_open_unique on (branch_id) untouched.
--   - Do not require location_id on cash_sessions yet.
--   - Do not change current payments/expenses/sales write paths yet.
-- =============================================================================

begin;

-- =============================================================================
-- 1) ENUMS
-- =============================================================================
do $$
begin
  if not exists (select 1 from pg_type where typname = 'cash_location_type') then
    create type public.cash_location_type as enum (
      'register_drawer',
      'safe',
      'petty_cash',
      'bank_account',
      'mobile_wallet',
      'in_transit',
      'virtual'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'cash_location_status') then
    create type public.cash_location_status as enum (
      'active',
      'inactive',
      'archived'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'cash_entry_direction') then
    create type public.cash_entry_direction as enum (
      'in',
      'out'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'cash_movement_type') then
    create type public.cash_movement_type as enum (
      'opening_float',
      'sale_cash_in',
      'customer_payment',
      'expense_cash_out',
      'supplier_payment',
      'deposit',
      'withdrawal',
      'adjustment',
      'transfer_out',
      'transfer_in',
      'close_reconciliation',
      'refund',
      'change_given'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'cash_transfer_status') then
    create type public.cash_transfer_status as enum (
      'draft',
      'pending_approval',
      'approved',
      'in_transit',
      'received',
      'cancelled'
    );
  end if;
end
$$;

-- =============================================================================
-- 2) CASH LOCATIONS
-- =============================================================================
create table if not exists public.cash_locations (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  parent_location_id uuid,
  code text not null,
  name text not null,
  location_type public.cash_location_type not null,
  status public.cash_location_status not null default 'active',
  description text,
  allows_sessions boolean not null default false,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id),
  unique (branch_id, code),
  constraint cash_locations_parent_fk
    foreign key (parent_location_id, branch_id)
    references public.cash_locations(id, branch_id)
    on delete restrict,
  constraint cash_locations_code_not_blank
    check (btrim(code) <> ''),
  constraint cash_locations_name_not_blank
    check (btrim(name) <> '')
);

comment on table public.cash_locations is
  'Physical or logical places where operational balances are held: drawer, safe, petty cash, bank, wallet, in transit.';

comment on column public.cash_locations.allows_sessions is
  'Whether an operational cash session may be opened against this location in future app flows.';

create index if not exists cash_locations_branch_status_idx
  on public.cash_locations (branch_id, status, sort_order, name);

create index if not exists cash_locations_parent_idx
  on public.cash_locations (parent_location_id)
  where parent_location_id is not null;

-- =============================================================================
-- 3) CASH TRANSFERS
-- =============================================================================
create table if not exists public.cash_transfers (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  from_location_id uuid not null,
  to_location_id uuid not null,
  status public.cash_transfer_status not null default 'draft',
  amount numeric(14,2) not null,
  requested_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  received_by uuid references auth.users(id),
  requested_at timestamptz not null default timezone('utc', now()),
  approved_at timestamptz,
  sent_at timestamptz,
  received_at timestamptz,
  cancelled_at timestamptz,
  reference_number text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id),
  constraint cash_transfers_from_location_fk
    foreign key (from_location_id, branch_id)
    references public.cash_locations(id, branch_id)
    on delete restrict,
  constraint cash_transfers_to_location_fk
    foreign key (to_location_id, branch_id)
    references public.cash_locations(id, branch_id)
    on delete restrict,
  constraint cash_transfers_amount_positive
    check (amount > 0),
  constraint cash_transfers_distinct_locations
    check (from_location_id <> to_location_id)
);

comment on table public.cash_transfers is
  'Operational transfer document between two cash locations inside the same branch.';

create index if not exists cash_transfers_branch_status_idx
  on public.cash_transfers (branch_id, status, requested_at desc);

create index if not exists cash_transfers_from_idx
  on public.cash_transfers (from_location_id, requested_at desc);

create index if not exists cash_transfers_to_idx
  on public.cash_transfers (to_location_id, requested_at desc);

-- =============================================================================
-- 4) CASH MOVEMENTS
-- =============================================================================
create table if not exists public.cash_movements (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  location_id uuid not null,
  cash_session_id uuid,
  transfer_id uuid,
  sale_id uuid,
  payment_id uuid,
  expense_id uuid,
  entry_direction public.cash_entry_direction not null,
  movement_type public.cash_movement_type not null,
  amount numeric(14,2) not null,
  effective_at timestamptz not null default timezone('utc', now()),
  reference_number text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id),
  constraint cash_movements_location_fk
    foreign key (location_id, branch_id)
    references public.cash_locations(id, branch_id)
    on delete restrict,
  constraint cash_movements_session_fk
    foreign key (cash_session_id, branch_id)
    references public.cash_sessions(id, branch_id)
    on delete restrict,
  constraint cash_movements_transfer_fk
    foreign key (transfer_id, branch_id)
    references public.cash_transfers(id, branch_id)
    on delete restrict,
  constraint cash_movements_sale_fk
    foreign key (sale_id, branch_id)
    references public.sales(id, branch_id)
    on delete restrict,
  constraint cash_movements_payment_fk
    foreign key (payment_id)
    references public.payments(id)
    on delete restrict,
  constraint cash_movements_expense_fk
    foreign key (expense_id)
    references public.expenses(id)
    on delete restrict,
  constraint cash_movements_amount_positive
    check (amount > 0),
  constraint cash_movements_transfer_pairing_check
    check (
      (movement_type in ('transfer_out', 'transfer_in') and transfer_id is not null)
      or (movement_type not in ('transfer_out', 'transfer_in'))
    )
);

comment on table public.cash_movements is
  'Operational cash ledger. One row impacts one location with an in/out direction.';

comment on column public.cash_movements.entry_direction is
  'in increases available balance for the location; out decreases it.';

create index if not exists cash_movements_location_effective_idx
  on public.cash_movements (location_id, effective_at desc, created_at desc);

create index if not exists cash_movements_branch_effective_idx
  on public.cash_movements (branch_id, effective_at desc, created_at desc);

create index if not exists cash_movements_session_idx
  on public.cash_movements (cash_session_id)
  where cash_session_id is not null;

create index if not exists cash_movements_transfer_idx
  on public.cash_movements (transfer_id)
  where transfer_id is not null;

create index if not exists cash_movements_payment_idx
  on public.cash_movements (payment_id)
  where payment_id is not null;

create index if not exists cash_movements_expense_idx
  on public.cash_movements (expense_id)
  where expense_id is not null;

-- =============================================================================
-- 5) EVOLVE CASH SESSIONS INTO LOCATION-AWARE SESSIONS
-- =============================================================================
alter table public.cash_sessions
  add column if not exists location_id uuid,
  add column if not exists device_id text,
  add column if not exists device_name text,
  add column if not exists session_label text;

alter table public.cash_sessions
  drop constraint if exists cash_sessions_location_fk;

alter table public.cash_sessions
  add constraint cash_sessions_location_fk
    foreign key (location_id, branch_id)
    references public.cash_locations(id, branch_id)
    on delete restrict;

comment on column public.cash_sessions.location_id is
  'Nullable compatibility-phase location pointer. Future flows should open sessions against a cash location.';

comment on column public.cash_sessions.device_id is
  'Optional client/device identifier reserved for future session uniqueness rules.';

comment on column public.cash_sessions.device_name is
  'Optional human-readable terminal/device name.';

comment on column public.cash_sessions.session_label is
  'Optional human-readable session label.';

create index if not exists cash_sessions_location_idx
  on public.cash_sessions (location_id)
  where location_id is not null;

create unique index if not exists cash_sessions_open_location_unique
  on public.cash_sessions (location_id)
  where status = 'open' and location_id is not null;

-- Existing branch-wide open-session uniqueness remains in place by design.

-- =============================================================================
-- 6) TRIGGERS
-- =============================================================================
drop trigger if exists trg_cash_locations_updated_at on public.cash_locations;
create trigger trg_cash_locations_updated_at
before update on public.cash_locations
for each row execute function public.set_updated_at();

drop trigger if exists trg_cash_transfers_updated_at on public.cash_transfers;
create trigger trg_cash_transfers_updated_at
before update on public.cash_transfers
for each row execute function public.set_updated_at();

drop trigger if exists trg_cash_movements_updated_at on public.cash_movements;
create trigger trg_cash_movements_updated_at
before update on public.cash_movements
for each row execute function public.set_updated_at();

drop trigger if exists trg_cash_locations_audit_fields on public.cash_locations;
create trigger trg_cash_locations_audit_fields
before insert or update on public.cash_locations
for each row execute function public.set_audit_fields();

drop trigger if exists trg_cash_transfers_audit_fields on public.cash_transfers;
create trigger trg_cash_transfers_audit_fields
before insert or update on public.cash_transfers
for each row execute function public.set_audit_fields();

drop trigger if exists trg_cash_movements_audit_fields on public.cash_movements;
create trigger trg_cash_movements_audit_fields
before insert or update on public.cash_movements
for each row execute function public.set_audit_fields();

-- =============================================================================
-- 7) RLS + POLICIES
-- =============================================================================
alter table public.cash_locations enable row level security;
alter table public.cash_transfers enable row level security;
alter table public.cash_movements enable row level security;

drop policy if exists cash_locations_select on public.cash_locations;
create policy cash_locations_select
on public.cash_locations
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists cash_locations_insert on public.cash_locations;
create policy cash_locations_insert
on public.cash_locations
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists cash_locations_update on public.cash_locations;
create policy cash_locations_update
on public.cash_locations
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists cash_locations_delete on public.cash_locations;
create policy cash_locations_delete
on public.cash_locations
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists cash_transfers_select on public.cash_transfers;
create policy cash_transfers_select
on public.cash_transfers
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists cash_transfers_insert on public.cash_transfers;
create policy cash_transfers_insert
on public.cash_transfers
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists cash_transfers_update on public.cash_transfers;
create policy cash_transfers_update
on public.cash_transfers
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists cash_transfers_delete on public.cash_transfers;
create policy cash_transfers_delete
on public.cash_transfers
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists cash_movements_select on public.cash_movements;
create policy cash_movements_select
on public.cash_movements
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists cash_movements_insert on public.cash_movements;
create policy cash_movements_insert
on public.cash_movements
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists cash_movements_update on public.cash_movements;
create policy cash_movements_update
on public.cash_movements
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists cash_movements_delete on public.cash_movements;
create policy cash_movements_delete
on public.cash_movements
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data());

-- =============================================================================
-- 8) GRANTS
-- =============================================================================
grant select, insert, update, delete on public.cash_locations to authenticated;
grant select, insert, update, delete on public.cash_transfers to authenticated;
grant select, insert, update, delete on public.cash_movements to authenticated;

commit;

-- ============================================================
-- END:   sql-next/05_cash_foundation_core.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/06_cash_foundation_backfill.sql
-- ============================================================
-- =============================================================================
-- Shop+ RD - Cash foundation backfill (safe + idempotent)
-- Fecha: 2026-04-10
--
-- Purpose:
--   Seed one default session-capable location per branch and attach historical
--   cash_sessions to it. This keeps current runtime intact while preparing
--   location-aware migration.
-- =============================================================================

begin;

insert into public.cash_locations (
  branch_id,
  code,
  name,
  location_type,
  status,
  description,
  allows_sessions,
  sort_order,
  metadata
)
select
  b.id,
  'MAIN_DRAWER',
  'Caja principal',
  'register_drawer',
  'active',
  'Ubicación por defecto para compatibilidad inicial de sesiones de caja.',
  true,
  0,
  jsonb_build_object(
    'seeded_by', '06_cash_foundation_backfill.sql',
    'compatibility_default', true
  )
from public.branches b
where not exists (
  select 1
  from public.cash_locations l
  where l.branch_id = b.id
    and l.code = 'MAIN_DRAWER'
);

update public.cash_sessions s
set location_id = l.id
from public.cash_locations l
where l.branch_id = s.branch_id
  and l.code = 'MAIN_DRAWER'
  and s.location_id is null;

commit;

-- ============================================================
-- END:   sql-next/06_cash_foundation_backfill.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/07_cash_foundation_views.sql
-- ============================================================
-- =============================================================================
-- Shop+ RD - Cash foundation derived views
-- Fecha: 2026-04-10
-- =============================================================================

begin;

create or replace view public.cash_location_balances
with (security_invoker = true)
as
select
  l.id as location_id,
  l.branch_id,
  l.code,
  l.name,
  l.location_type,
  l.status,
  l.allows_sessions,
  l.parent_location_id,
  coalesce(sum(
    case m.entry_direction
      when 'in' then m.amount
      when 'out' then -m.amount
      else 0
    end
  ), 0)::numeric(14,2) as current_balance,
  max(m.effective_at) as last_movement_at
from public.cash_locations l
left join public.cash_movements m
  on m.location_id = l.id
 and m.branch_id = l.branch_id
group by
  l.id,
  l.branch_id,
  l.code,
  l.name,
  l.location_type,
  l.status,
  l.allows_sessions,
  l.parent_location_id;

comment on view public.cash_location_balances is
  'Current derived operational balance per cash location based on cash_movements.';

grant select on public.cash_location_balances to authenticated;

commit;

-- ============================================================
-- END:   sql-next/07_cash_foundation_views.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260410_pos_transactional_core.sql
-- ============================================================
-- Sprint 1 - POS transactional core hardening
-- Additive migration: introduce canonical receipt_type normalization and
-- a single transactional sale checkout RPC for POS operations.

create or replace function public.normalize_receipt_type(p_value text)
returns public.receipt_type
language plpgsql
stable
set search_path = public
as $$
declare
  v_normalized text;
begin
  v_normalized := lower(coalesce(trim(p_value), ''));
  v_normalized := replace(v_normalized, 'á', 'a');
  v_normalized := replace(v_normalized, 'é', 'e');
  v_normalized := replace(v_normalized, 'í', 'i');
  v_normalized := replace(v_normalized, 'ó', 'o');
  v_normalized := replace(v_normalized, 'ú', 'u');
  v_normalized := regexp_replace(v_normalized, '[^a-z0-9]+', '_', 'g');
  v_normalized := regexp_replace(v_normalized, '_+', '_', 'g');
  v_normalized := regexp_replace(v_normalized, '^_|_$', '', 'g');

  case v_normalized
    when '', 'consumer_final', 'consumidor_final' then
      return 'consumer_final'::public.receipt_type;
    when 'fiscal_credit', 'credito_fiscal' then
      return 'fiscal_credit'::public.receipt_type;
    when 'governmental', 'gubernamental' then
      return 'governmental'::public.receipt_type;
    when 'special', 'regimen_especial' then
      return 'special'::public.receipt_type;
    when 'export', 'exportacion' then
      return 'export'::public.receipt_type;
    else
      raise exception 'Tipo de comprobante no soportado: %', p_value
        using errcode = '22023';
  end case;
end;
$$;

grant execute on function public.normalize_receipt_type(text) to authenticated;

create or replace function public.checkout_sale_transactional(
  p_items jsonb,
  p_receipt_type text default 'consumer_final',
  p_as_credit boolean default false,
  p_payment_method text default null,
  p_client_id uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid := public.current_branch_id();
  v_receipt_type public.receipt_type;
  v_sale_status public.sale_status;
  v_payment_method public.payment_method;
  v_sale_id uuid;
  v_sale_number text;
  v_subtotal numeric(14,2) := 0;
  v_tax_amount numeric(14,2) := 0;
  v_total_amount numeric(14,2) := 0;
  v_paid_amount numeric(14,2) := 0;
  v_balance_due numeric(14,2) := 0;
  v_open_cash_session_id uuid;
  v_client record;
  v_item record;
  v_product record;
  v_item_count integer := 0;
  v_note text;
  v_now timestamptz := timezone('utc', now());
begin
  if v_user_id is null then
    raise exception 'Sesión inválida. Inicia sesión de nuevo.'
      using errcode = '28000';
  end if;

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada para este usuario.'
      using errcode = '22023';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'No tienes acceso a la sucursal actual.'
      using errcode = '42501';
  end if;

  if not public.can_operate_pos() then
    raise exception 'Tu rol no puede operar el POS.'
      using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No hay productos en el carrito.'
      using errcode = '22023';
  end if;

  v_receipt_type := public.normalize_receipt_type(p_receipt_type);
  v_sale_status := case when p_as_credit then 'credit'::public.sale_status else 'completed'::public.sale_status end;
  v_note := nullif(trim(coalesce(p_notes, '')), '');

  if not p_as_credit then
    begin
      v_payment_method := coalesce(nullif(trim(p_payment_method), ''), 'cash')::public.payment_method;
    exception
      when invalid_text_representation then
        raise exception 'Método de pago no soportado: %', p_payment_method
          using errcode = '22023';
    end;
  end if;

  if p_client_id is not null then
    select
      c.id,
      c.full_name,
      c.legal_name,
      c.document_number,
      c.is_active
    into v_client
    from public.clients c
    where c.id = p_client_id
      and c.branch_id = v_branch_id
    limit 1;

    if not found then
      raise exception 'El cliente seleccionado no existe en la sucursal actual.'
        using errcode = '23503';
    end if;

    if coalesce(v_client.is_active, false) is false then
      raise exception 'El cliente seleccionado está inactivo.'
        using errcode = '22023';
    end if;
  end if;

  if p_as_credit and p_client_id is null then
    raise exception 'Para ventas a crédito debe seleccionar un cliente.'
      using errcode = '22023';
  end if;

  if v_receipt_type <> 'consumer_final'::public.receipt_type then
    if p_client_id is null then
      raise exception 'Debe seleccionar un cliente para este tipo de comprobante.'
        using errcode = '22023';
    end if;

    if nullif(trim(coalesce(v_client.document_number, '')), '') is null then
      raise exception 'El cliente debe tener documento fiscal para este comprobante.'
        using errcode = '22023';
    end if;

    if nullif(trim(coalesce(v_client.legal_name, v_client.full_name, '')), '') is null then
      raise exception 'El cliente debe tener nombre válido para este comprobante.'
        using errcode = '22023';
    end if;
  end if;

  create temporary table if not exists tmp_checkout_items (
    product_id uuid primary key,
    description text,
    quantity numeric(14,3) not null,
    unit_price numeric(14,2) not null,
    tax_rate numeric(5,2) not null,
    line_subtotal numeric(14,2),
    line_tax numeric(14,2),
    line_total numeric(14,2)
  ) on commit drop;

  truncate table tmp_checkout_items;

  for v_item in
    select *
    from jsonb_to_recordset(p_items) as x(
      product_id uuid,
      description text,
      quantity numeric,
      unit_price numeric,
      tax_rate numeric
    )
  loop
    v_item_count := v_item_count + 1;

    if v_item.product_id is null then
      raise exception 'Hay una línea sin producto válido.'
        using errcode = '22023';
    end if;

    if coalesce(v_item.quantity, 0) <= 0 then
      raise exception 'La cantidad del producto % debe ser mayor que cero.', v_item.product_id
        using errcode = '22023';
    end if;

    if coalesce(v_item.unit_price, 0) < 0 then
      raise exception 'El precio del producto % no es válido.', v_item.product_id
        using errcode = '22023';
    end if;

    if coalesce(v_item.tax_rate, 0) < 0 or coalesce(v_item.tax_rate, 0) > 100 then
      raise exception 'La tasa de impuesto del producto % no es válida.', v_item.product_id
        using errcode = '22023';
    end if;

    insert into tmp_checkout_items (
      product_id,
      description,
      quantity,
      unit_price,
      tax_rate
    ) values (
      v_item.product_id,
      nullif(trim(coalesce(v_item.description, '')), ''),
      round(v_item.quantity::numeric, 3),
      round(v_item.unit_price::numeric, 2),
      round(v_item.tax_rate::numeric, 2)
    )
    on conflict (product_id)
    do update set
      description = coalesce(excluded.description, tmp_checkout_items.description),
      quantity = round(tmp_checkout_items.quantity + excluded.quantity, 3),
      unit_price = excluded.unit_price,
      tax_rate = excluded.tax_rate;
  end loop;

  if v_item_count = 0 then
    raise exception 'No hay productos en el carrito.'
      using errcode = '22023';
  end if;

  for v_item in
    select * from tmp_checkout_items order by product_id
  loop
    select
      p.id,
      p.name,
      p.stock,
      p.is_active
    into v_product
    from public.products p
    where p.id = v_item.product_id
      and p.branch_id = v_branch_id
    for update;

    if not found then
      raise exception 'Producto no encontrado en la sucursal actual: %', v_item.product_id
        using errcode = '23503';
    end if;

    if coalesce(v_product.is_active, false) is false then
      raise exception 'El producto % está inactivo.', coalesce(v_product.name, v_item.product_id::text)
        using errcode = '22023';
    end if;

    if coalesce(v_product.stock, 0) < v_item.quantity then
      raise exception 'Stock insuficiente para %: disponible %, solicitado %.',
        coalesce(v_product.name, v_item.product_id::text),
        round(coalesce(v_product.stock, 0)::numeric, 3),
        round(v_item.quantity::numeric, 3)
        using errcode = '22023';
    end if;

    update tmp_checkout_items
    set
      description = coalesce(v_item.description, v_product.name),
      line_subtotal = round((v_item.quantity * v_item.unit_price)::numeric, 2),
      line_tax = round((v_item.quantity * v_item.unit_price * (v_item.tax_rate / 100))::numeric, 2),
      line_total = round(((v_item.quantity * v_item.unit_price) + (v_item.quantity * v_item.unit_price * (v_item.tax_rate / 100)))::numeric, 2)
    where product_id = v_item.product_id;
  end loop;

  select
    round(coalesce(sum(line_subtotal), 0)::numeric, 2),
    round(coalesce(sum(line_tax), 0)::numeric, 2),
    round(coalesce(sum(line_total), 0)::numeric, 2)
  into v_subtotal, v_tax_amount, v_total_amount
  from tmp_checkout_items;

  v_paid_amount := case when p_as_credit then 0 else v_total_amount end;
  v_balance_due := case when p_as_credit then v_total_amount else 0 end;

  if not p_as_credit then
    select cs.id
    into v_open_cash_session_id
    from public.cash_sessions cs
    where cs.branch_id = v_branch_id
      and cs.status = 'open'
    order by cs.opened_at desc
    limit 1
    for update;

    if v_open_cash_session_id is null then
      raise exception 'Debe abrir una sesión de caja antes de cobrar una venta.'
        using errcode = '22023';
    end if;
  end if;

  v_sale_number := 'VTA-' || to_char(v_now at time zone 'UTC', 'YYYYMMDD-HH24MISSMS') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));

  insert into public.sales (
    branch_id,
    sale_number,
    client_id,
    cashier_id,
    receipt_type,
    status,
    sale_date,
    subtotal,
    discount_amount,
    tax_amount,
    total_amount,
    paid_amount,
    balance_due,
    notes
  ) values (
    v_branch_id,
    v_sale_number,
    p_client_id,
    v_user_id,
    v_receipt_type,
    v_sale_status,
    v_now,
    v_subtotal,
    0,
    v_tax_amount,
    v_total_amount,
    v_paid_amount,
    v_balance_due,
    v_note
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
    v_branch_id,
    product_id,
    description,
    quantity,
    unit_price,
    0,
    tax_rate,
    line_subtotal,
    line_tax,
    line_total
  from tmp_checkout_items
  order by product_id;

  if not p_as_credit then
    insert into public.payments (
      branch_id,
      sale_id,
      client_id,
      cash_session_id,
      payment_method,
      amount,
      paid_at,
      reference,
      notes
    ) values (
      v_branch_id,
      v_sale_id,
      p_client_id,
      v_open_cash_session_id,
      v_payment_method,
      v_total_amount,
      v_now,
      v_sale_number,
      v_note
    );
  elsif p_client_id is not null then
    update public.clients
    set balance_due = round((coalesce(balance_due, 0) + v_total_amount)::numeric, 2)
    where id = p_client_id
      and branch_id = v_branch_id;
  end if;

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'sale_number', v_sale_number,
    'branch_id', v_branch_id,
    'cash_session_id', v_open_cash_session_id,
    'receipt_type', v_receipt_type,
    'status', v_sale_status,
    'subtotal', v_subtotal,
    'tax_amount', v_tax_amount,
    'total_amount', v_total_amount,
    'paid_amount', v_paid_amount,
    'balance_due', v_balance_due,
    'items_count', (select count(*) from tmp_checkout_items)
  );
end;
$$;

grant execute on function public.checkout_sale_transactional(jsonb, text, boolean, text, uuid, text) to authenticated;

-- ============================================================
-- END:   sql-next/20260410_pos_transactional_core.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260410_quotations_schema.sql
-- ============================================================
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


-- ============================================================
-- END:   sql-next/20260410_quotations_schema.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260421_structural_backoffice_foundation.sql
-- ============================================================
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
    select up.granted
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

-- ============================================================
-- END:   sql-next/20260421_structural_backoffice_foundation.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260422_fix_permissions_final.sql
-- ============================================================
-- supabase/sql-next/20260422_fix_permissions_final.sql
-- Script de reparación para el sistema de permisos de Shop+ RD

BEGIN;

-- 1. Eliminar la vista para permitir el cambio de nombres de columnas
DROP VIEW IF EXISTS public.employee_effective_permissions_view;

-- 2. Corregir tabla de permisos (Renombrar y añadir columnas faltantes)
DO $$ 
BEGIN
  -- Renombrar module_key a module si existe
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='permissions' AND column_name='module_key') THEN
    ALTER TABLE public.permissions RENAME COLUMN module_key TO module;
  END IF;

  -- Renombrar action_key a action_type si existe
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='permissions' AND column_name='action_key') THEN
    ALTER TABLE public.permissions RENAME COLUMN action_key TO action_type;
  END IF;

  -- Añadir columna name si no existe
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='permissions' AND column_name='name') THEN
    ALTER TABLE public.permissions ADD COLUMN name text;
  END IF;
END $$;

-- Actualizar nombres iniciales (usando descripción o código como fallback)
UPDATE public.permissions 
SET name = COALESCE(description, code) 
WHERE name IS NULL;

-- 3. Corregir tabla de user_permissions (Renombrar allowed a granted)
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='user_permissions' AND column_name='allowed') THEN
    ALTER TABLE public.user_permissions RENAME COLUMN allowed TO granted;
  END IF;
END $$;

-- 4. Actualizar la función has_permission para usar la columna 'granted'
CREATE OR REPLACE FUNCTION public.has_permission(permission_code text, target_branch_id uuid DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH requested_branch AS (
    SELECT COALESCE(target_branch_id, public.current_branch_id()) AS branch_id
  ),
  user_override AS (
    SELECT up.granted
    FROM public.user_permissions up
    JOIN public.permissions p ON p.id = up.permission_id
    JOIN requested_branch rb ON true
    WHERE up.user_id = auth.uid()
      AND up.is_active
      AND p.code = permission_code
      AND (up.branch_id IS NULL OR up.branch_id = rb.branch_id)
    ORDER BY CASE WHEN up.branch_id = rb.branch_id THEN 0 ELSE 1 END, up.created_at DESC
    LIMIT 1
  ),
  role_grant AS (
    SELECT rp.allowed
    FROM public.role_permissions rp
    JOIN public.permissions p ON p.id = rp.permission_id
    JOIN requested_branch rb ON true
    WHERE rp.is_active
      AND p.code = permission_code
      AND rp.role_key = public.current_user_role_key(rb.branch_id)
    ORDER BY rp.created_at DESC
    LIMIT 1
  )
  SELECT CASE
    WHEN public.is_admin() THEN true
    WHEN EXISTS (SELECT 1 FROM user_override) THEN (SELECT granted FROM user_override)
    WHEN EXISTS (SELECT 1 FROM role_grant) THEN (SELECT allowed FROM role_grant)
    ELSE false
  END;
$$;

-- 5. Recrear la vista con el formato esperado por Flutter (incluyendo permission_name)
CREATE OR REPLACE VIEW public.employee_effective_permissions_view
WITH (security_invoker = true)
AS
WITH branch_scope AS (
  SELECT ub.user_id, ub.branch_id, COALESCE(ub.role_override::text, p.role::text) AS role_key
  FROM public.users_branches ub
  JOIN public.profiles p ON p.id = ub.user_id
  WHERE ub.is_active AND p.is_active AND public.has_branch_access(ub.branch_id)
),
role_grants AS (
  SELECT bs.user_id, bs.branch_id, p.code AS permission_code, rp.allowed
  FROM branch_scope bs
  JOIN public.role_permissions rp ON LOWER(rp.role_key) = LOWER(bs.role_key) AND rp.is_active
  JOIN public.permissions p ON p.id = rp.permission_id AND p.is_active
),
user_overrides AS (
  SELECT up.user_id, up.branch_id, p.code AS permission_code, up.granted
  FROM public.user_permissions up
  JOIN public.permissions p ON p.id = up.permission_id AND p.is_active
  WHERE up.is_active
)
SELECT
  bs.user_id,
  bs.branch_id,
  p.code AS permission_code,
  p.name AS permission_name,
  p.module,
  p.action_type,
  COALESCE(
    (SELECT rg.allowed FROM role_grants rg WHERE rg.user_id = bs.user_id AND rg.branch_id = bs.branch_id AND rg.permission_code = p.code LIMIT 1),
    false
  ) AS role_grant,
  (
    SELECT uo.granted
    FROM user_overrides uo
    WHERE uo.user_id = bs.user_id
      AND (uo.branch_id = bs.branch_id OR uo.branch_id IS NULL)
      AND uo.permission_code = p.code
    ORDER BY CASE WHEN uo.branch_id = bs.branch_id THEN 0 ELSE 1 END
    LIMIT 1
  ) AS user_override,
  COALESCE(
    (
      SELECT uo.granted
      FROM user_overrides uo
      WHERE uo.user_id = bs.user_id
        AND (uo.branch_id = bs.branch_id OR uo.branch_id IS NULL)
        AND uo.permission_code = p.code
      ORDER BY CASE WHEN uo.branch_id = bs.branch_id THEN 0 ELSE 1 END
      LIMIT 1
    ),
    (
      SELECT rg.allowed
      FROM role_grants rg
      WHERE rg.user_id = bs.user_id
        AND rg.branch_id = bs.branch_id
        AND rg.permission_code = p.code
      LIMIT 1
    ),
    false
  ) AS effective_grant
FROM branch_scope bs
CROSS JOIN public.permissions p
WHERE p.is_active;

-- 6. Actualizar las inserciones iniciales con nombres descriptivos
INSERT INTO public.permissions (code, name, module, action_type, description, sort_order)
VALUES
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
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  module = EXCLUDED.module,
  action_type = EXCLUDED.action_type,
  updated_at = NOW();

COMMIT;

-- ============================================================
-- END:   sql-next/20260422_fix_permissions_final.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260509_08_app_settings.sql
-- ============================================================
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

-- ============================================================
-- END:   sql-next/20260509_08_app_settings.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260509_09_reports_schema.sql
-- ============================================================
-- 20260509_09_reports_schema.sql
-- Shop+ RD - PRD 07: Módulo de Reportes Unificado (esqueleto compatible)
--
-- Ejecutar después de:
--   supabase/sql/01_schema.sql
--   supabase/sql/03_reports_views.sql
--   supabase/sql/04_branch_context.sql
--   supabase/sql-next/20260421_structural_backoffice_foundation.sql
--   supabase/sql-next/20260509_08_app_settings.sql
--
-- Diseño:
--   - Aditivo: ninguna tabla existente se modifica destructivamente.
--   - inventory_movements: movimientos manuales NO cubiertos por
--     triggers actuales (waste/breakage/expired/kitchen_return/ajustes/traslados).
--   - fiscal_z_closures: cierres Z inmutables (UPDATE bloqueado por trigger).
--   - fiscal_dgii_reports: archivos 606/607/IT-1 generados, con conteo
--     de inconsistencias.
--   - custom_reports: definición persistida del query builder visual.
--   - report_generation_log: bitácora ligera de uso (complementa report_exports).
--   - 6 materialized views base; refresh por función RPC + concurrente.

begin;

create extension if not exists pgcrypto;

-- =====================================================
-- 1) Enums auxiliares
-- =====================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'inventory_movement_type') then
    create type public.inventory_movement_type as enum (
      'waste',
      'breakage',
      'expired',
      'kitchen_return',
      'adjustment_in',
      'adjustment_out',
      'transfer_in',
      'transfer_out',
      'opening',
      'recount'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'fiscal_dgii_report_type') then
    create type public.fiscal_dgii_report_type as enum ('606', '607', 'IT1');
  end if;

  if not exists (select 1 from pg_type where typname = 'report_generation_mode') then
    create type public.report_generation_mode as enum ('graphic', 'summary', 'export');
  end if;
end $$;

-- =====================================================
-- 2) inventory_movements: mermas, ajustes, traslados
-- =====================================================

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  product_id uuid not null,
  movement_type public.inventory_movement_type not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  reason text,
  reference_type text,
  reference_id uuid,
  occurred_at timestamptz not null default timezone('utc', now()),
  recorded_by uuid references auth.users(id),
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint inventory_movements_product_branch_fk
    foreign key (product_id, branch_id)
    references public.products(id, branch_id)
    on delete restrict
);

comment on table public.inventory_movements is
  'Movimientos manuales de inventario (mermas, ajustes, traslados). NO duplica los triggers automáticos de purchase_items/sale_items.';

create index if not exists inventory_movements_branch_date_idx
  on public.inventory_movements (branch_id, occurred_at desc);

create index if not exists inventory_movements_product_idx
  on public.inventory_movements (branch_id, product_id, occurred_at desc);

create index if not exists inventory_movements_type_idx
  on public.inventory_movements (branch_id, movement_type, occurred_at desc);

-- Trigger que actualiza products.stock según el tipo
create or replace function public.apply_inventory_movement_stock()
returns trigger
language plpgsql
as $$
declare
  v_signed_qty numeric(14,3);
begin
  if tg_op = 'INSERT' then
    v_signed_qty := case new.movement_type
      when 'adjustment_in'  then  new.quantity
      when 'transfer_in'    then  new.quantity
      when 'opening'        then  new.quantity
      when 'recount'        then  new.quantity
      when 'waste'          then -new.quantity
      when 'breakage'       then -new.quantity
      when 'expired'        then -new.quantity
      when 'kitchen_return' then -new.quantity
      when 'adjustment_out' then -new.quantity
      when 'transfer_out'   then -new.quantity
    end;

    update public.products
      set stock = stock + v_signed_qty
    where id = new.product_id
      and branch_id = new.branch_id;

    return new;
  end if;

  if tg_op = 'DELETE' then
    -- Revertir efecto al borrar
    v_signed_qty := case old.movement_type
      when 'adjustment_in'  then -old.quantity
      when 'transfer_in'    then -old.quantity
      when 'opening'        then -old.quantity
      when 'recount'        then -old.quantity
      when 'waste'          then  old.quantity
      when 'breakage'       then  old.quantity
      when 'expired'        then  old.quantity
      when 'kitchen_return' then  old.quantity
      when 'adjustment_out' then  old.quantity
      when 'transfer_out'   then  old.quantity
    end;

    update public.products
      set stock = stock + v_signed_qty
    where id = old.product_id
      and branch_id = old.branch_id;

    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_inventory_movements_stock on public.inventory_movements;
create trigger trg_inventory_movements_stock
after insert or delete on public.inventory_movements
for each row execute function public.apply_inventory_movement_stock();

drop trigger if exists trg_inventory_movements_updated_at on public.inventory_movements;
create trigger trg_inventory_movements_updated_at
before update on public.inventory_movements
for each row execute function public.set_updated_at();

drop trigger if exists trg_inventory_movements_audit on public.inventory_movements;
create trigger trg_inventory_movements_audit
before insert or update on public.inventory_movements
for each row execute function public.set_audit_fields();

-- =====================================================
-- 3) fiscal_z_closures: cierres Z fiscales inmutables
-- =====================================================

create table if not exists public.fiscal_z_closures (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  cash_session_id uuid not null,
  closure_number integer not null,
  emitted_at timestamptz not null default timezone('utc', now()),
  emitted_by uuid references auth.users(id),
  payload jsonb not null,
  pdf_url text,
  is_complementary boolean not null default false,
  parent_closure_id uuid references public.fiscal_z_closures(id),
  created_at timestamptz not null default timezone('utc', now()),
  unique (branch_id, closure_number),
  constraint fiscal_z_closures_session_fk
    foreign key (cash_session_id, branch_id)
    references public.cash_sessions(id, branch_id)
    on delete restrict
);

comment on table public.fiscal_z_closures is
  'Cierres Z fiscales sellados; inmutables post-emisión. Para corregir se emite un complementario.';

create index if not exists fiscal_z_closures_session_idx
  on public.fiscal_z_closures (cash_session_id);

create index if not exists fiscal_z_closures_branch_emitted_idx
  on public.fiscal_z_closures (branch_id, emitted_at desc);

-- Bloquear UPDATE: cierres Z son inmutables.
create or replace function public.block_fiscal_z_closure_update()
returns trigger
language plpgsql
as $$
begin
  raise exception 'fiscal_z_closures es inmutable. Para corregir, emita un cierre complementario.'
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists trg_fiscal_z_closures_block_update on public.fiscal_z_closures;
create trigger trg_fiscal_z_closures_block_update
before update on public.fiscal_z_closures
for each row execute function public.block_fiscal_z_closure_update();

-- =====================================================
-- 4) fiscal_dgii_reports: archivos 606/607/IT-1 generados
-- =====================================================

create table if not exists public.fiscal_dgii_reports (
  id uuid primary key default gen_random_uuid(),
  report_type public.fiscal_dgii_report_type not null,
  period_year integer not null check (period_year between 2020 and 2100),
  period_month integer not null check (period_month between 1 and 12),
  generated_at timestamptz not null default timezone('utc', now()),
  generated_by uuid references auth.users(id),
  records_count integer not null default 0,
  inconsistencies_count integer not null default 0,
  inconsistencies jsonb not null default '[]'::jsonb,
  txt_file_url text,
  pdf_file_url text,
  storage_path text,
  status text not null default 'generated',
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (report_type, period_year, period_month)
);

comment on table public.fiscal_dgii_reports is
  'Reportes mensuales DGII (606/607/IT-1) ya generados, con inconsistencias detectadas.';

create index if not exists fiscal_dgii_reports_period_idx
  on public.fiscal_dgii_reports (report_type, period_year desc, period_month desc);

-- =====================================================
-- 5) custom_reports: definiciones del query builder
-- =====================================================

create table if not exists public.custom_reports (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  config jsonb not null,
  is_shared boolean not null default false,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  updated_by uuid references auth.users(id),
  unique (created_by, name)
);

comment on table public.custom_reports is
  'Reportes personalizados creados por el usuario vía query builder. config: definición JSON validada server-side contra whitelist de tablas/columnas.';

create index if not exists custom_reports_owner_idx
  on public.custom_reports (created_by, is_active);

create index if not exists custom_reports_shared_idx
  on public.custom_reports (is_shared)
  where is_shared = true and is_active = true;

drop trigger if exists trg_custom_reports_updated_at on public.custom_reports;
create trigger trg_custom_reports_updated_at
before update on public.custom_reports
for each row execute function public.set_updated_at();

-- =====================================================
-- 6) report_generation_log: bitácora ligera de uso
-- =====================================================

create table if not exists public.report_generation_log (
  id bigserial primary key,
  branch_id uuid references public.branches(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  report_category text not null,
  report_mode public.report_generation_mode not null,
  filters jsonb not null default '{}'::jsonb,
  duration_ms integer,
  rows_returned integer,
  generated_at timestamptz not null default timezone('utc', now())
);

comment on table public.report_generation_log is
  'Bitácora de generación de reportes (telemetría). Complementa report_exports que es la cola operativa.';

create index if not exists report_generation_log_branch_date_idx
  on public.report_generation_log (branch_id, generated_at desc);

create index if not exists report_generation_log_category_idx
  on public.report_generation_log (report_category, generated_at desc);

-- =====================================================
-- 7) RLS para tablas nuevas
-- =====================================================

alter table public.inventory_movements enable row level security;
alter table public.fiscal_z_closures enable row level security;
alter table public.fiscal_dgii_reports enable row level security;
alter table public.custom_reports enable row level security;
alter table public.report_generation_log enable row level security;

-- inventory_movements: lee con acceso a sucursal; escribe con can_manage_branch_data
drop policy if exists inventory_movements_select on public.inventory_movements;
create policy inventory_movements_select
on public.inventory_movements
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists inventory_movements_insert on public.inventory_movements;
create policy inventory_movements_insert
on public.inventory_movements
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists inventory_movements_update on public.inventory_movements;
create policy inventory_movements_update
on public.inventory_movements
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists inventory_movements_delete on public.inventory_movements;
create policy inventory_movements_delete
on public.inventory_movements
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.is_admin());

-- fiscal_z_closures: lee con acceso a sucursal; INSERT solo vía función seal_fiscal_z_closure
drop policy if exists fiscal_z_closures_select on public.fiscal_z_closures;
create policy fiscal_z_closures_select
on public.fiscal_z_closures
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists fiscal_z_closures_insert on public.fiscal_z_closures;
create policy fiscal_z_closures_insert
on public.fiscal_z_closures
for insert
to authenticated
with check (
  public.has_branch_access(branch_id)
  and (public.is_admin() or public.current_user_role() in ('supervisor'::public.app_role, 'cashier'::public.app_role, 'accountant'::public.app_role))
);

-- DELETE prohibido: cierres Z son inmutables incluso para admin.
drop policy if exists fiscal_z_closures_delete on public.fiscal_z_closures;
create policy fiscal_z_closures_delete
on public.fiscal_z_closures
for delete
to authenticated
using (false);

-- fiscal_dgii_reports: solo admin / accountant ven y generan
drop policy if exists fiscal_dgii_reports_select on public.fiscal_dgii_reports;
create policy fiscal_dgii_reports_select
on public.fiscal_dgii_reports
for select
to authenticated
using (
  public.is_admin()
  or public.current_user_role() = 'accountant'::public.app_role
);

drop policy if exists fiscal_dgii_reports_insert on public.fiscal_dgii_reports;
create policy fiscal_dgii_reports_insert
on public.fiscal_dgii_reports
for insert
to authenticated
with check (
  public.is_admin()
  or public.current_user_role() = 'accountant'::public.app_role
);

drop policy if exists fiscal_dgii_reports_update on public.fiscal_dgii_reports;
create policy fiscal_dgii_reports_update
on public.fiscal_dgii_reports
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists fiscal_dgii_reports_delete on public.fiscal_dgii_reports;
create policy fiscal_dgii_reports_delete
on public.fiscal_dgii_reports
for delete
to authenticated
using (public.is_admin());

-- custom_reports: dueño ve sus propios + los compartidos; solo dueño edita
drop policy if exists custom_reports_select on public.custom_reports;
create policy custom_reports_select
on public.custom_reports
for select
to authenticated
using (
  created_by = auth.uid()
  or is_shared = true
  or public.is_admin()
);

drop policy if exists custom_reports_insert on public.custom_reports;
create policy custom_reports_insert
on public.custom_reports
for insert
to authenticated
with check (created_by = auth.uid());

drop policy if exists custom_reports_update on public.custom_reports;
create policy custom_reports_update
on public.custom_reports
for update
to authenticated
using (created_by = auth.uid() or public.is_admin())
with check (created_by = auth.uid() or public.is_admin());

drop policy if exists custom_reports_delete on public.custom_reports;
create policy custom_reports_delete
on public.custom_reports
for delete
to authenticated
using (created_by = auth.uid() or public.is_admin());

-- report_generation_log: cada usuario inserta el suyo; admin lee todos, otros solo los suyos
drop policy if exists report_generation_log_select on public.report_generation_log;
create policy report_generation_log_select
on public.report_generation_log
for select
to authenticated
using (public.is_admin() or user_id = auth.uid());

drop policy if exists report_generation_log_insert on public.report_generation_log;
create policy report_generation_log_insert
on public.report_generation_log
for insert
to authenticated
with check (user_id is null or user_id = auth.uid());

-- =====================================================
-- 8) Materialized views base
-- =====================================================

-- 8.1) Ventas diarias por sucursal / cajero / receipt_type
drop materialized view if exists public.mv_sales_daily;
create materialized view public.mv_sales_daily as
select
  s.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  coalesce(s.seller_id, s.cashier_id) as seller_user_id,
  s.receipt_type,
  count(*)::bigint as sales_count,
  coalesce(sum(s.subtotal), 0)::numeric(14,2) as gross_total,
  coalesce(sum(s.tax_amount), 0)::numeric(14,2) as itbis_total,
  coalesce(sum(s.service_charge_amount), 0)::numeric(14,2) as service_charge_total,
  coalesce(sum(s.discount_amount), 0)::numeric(14,2) as discount_total,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as net_total
from public.sales s
where s.status = 'completed'::public.sale_status
group by 1, 2, 3, 4;

create unique index if not exists mv_sales_daily_pk
  on public.mv_sales_daily (branch_id, sale_day, seller_user_id, receipt_type);

create index if not exists mv_sales_daily_branch_day_idx
  on public.mv_sales_daily (branch_id, sale_day desc);

-- 8.2) Ventas por artículo
drop materialized view if exists public.mv_sales_by_item;
create materialized view public.mv_sales_by_item as
select
  si.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  si.product_id,
  coalesce(p.name, si.description) as product_name,
  coalesce(sum(si.quantity), 0)::numeric(14,3) as units_sold,
  coalesce(sum(si.line_subtotal), 0)::numeric(14,2) as gross_total,
  coalesce(sum(si.line_tax), 0)::numeric(14,2) as itbis_total,
  coalesce(sum(si.line_total), 0)::numeric(14,2) as net_total,
  count(distinct si.sale_id)::bigint as sales_count
from public.sale_items si
join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
left join public.products p on p.id = si.product_id and p.branch_id = si.branch_id
where s.status = 'completed'::public.sale_status
group by 1, 2, 3, 4;

create unique index if not exists mv_sales_by_item_pk
  on public.mv_sales_by_item (branch_id, sale_day, product_id);

create index if not exists mv_sales_by_item_product_idx
  on public.mv_sales_by_item (branch_id, product_id, sale_day desc);

-- 8.3) Ventas por categoría
drop materialized view if exists public.mv_sales_by_category;
create materialized view public.mv_sales_by_category as
select
  si.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  coalesce(si.category_id, p.category_id) as category_id,
  coalesce(si.category_name_snapshot, pc.name, 'Sin categoría') as category_name,
  coalesce(sum(si.quantity), 0)::numeric(14,3) as units_sold,
  coalesce(sum(si.line_subtotal), 0)::numeric(14,2) as gross_total,
  coalesce(sum(si.line_tax), 0)::numeric(14,2) as itbis_total,
  coalesce(sum(si.line_total), 0)::numeric(14,2) as net_total
from public.sale_items si
join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
left join public.products p on p.id = si.product_id and p.branch_id = si.branch_id
left join public.product_categories pc
  on pc.id = coalesce(si.category_id, p.category_id)
  and pc.branch_id = si.branch_id
where s.status = 'completed'::public.sale_status
group by 1, 2, 3, 4;

create unique index if not exists mv_sales_by_category_pk
  on public.mv_sales_by_category (branch_id, sale_day, coalesce(category_id, '00000000-0000-0000-0000-000000000000'::uuid));

create index if not exists mv_sales_by_category_branch_day_idx
  on public.mv_sales_by_category (branch_id, sale_day desc);

-- 8.4) Compras diarias
drop materialized view if exists public.mv_purchases_daily;
create materialized view public.mv_purchases_daily as
select
  p.branch_id,
  p.purchase_date,
  p.supplier_id,
  count(*)::bigint as purchases_count,
  coalesce(sum(p.subtotal), 0)::numeric(14,2) as subtotal_total,
  coalesce(sum(p.discount_amount), 0)::numeric(14,2) as discount_total,
  coalesce(sum(p.tax_amount), 0)::numeric(14,2) as tax_total,
  coalesce(sum(p.total_amount), 0)::numeric(14,2) as grand_total
from public.purchases p
where p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
group by 1, 2, 3;

create unique index if not exists mv_purchases_daily_pk
  on public.mv_purchases_daily (branch_id, purchase_date, supplier_id);

create index if not exists mv_purchases_daily_branch_date_idx
  on public.mv_purchases_daily (branch_id, purchase_date desc);

-- 8.5) Movimientos de inventario diarios
drop materialized view if exists public.mv_inventory_movements_daily;
create materialized view public.mv_inventory_movements_daily as
select
  im.branch_id,
  date(im.occurred_at at time zone 'America/Santo_Domingo') as movement_day,
  im.movement_type,
  im.product_id,
  coalesce(sum(im.quantity), 0)::numeric(14,3) as total_quantity,
  coalesce(sum(im.quantity * im.unit_cost), 0)::numeric(14,2) as total_cost,
  count(*)::bigint as movements_count
from public.inventory_movements im
group by 1, 2, 3, 4;

create unique index if not exists mv_inventory_movements_daily_pk
  on public.mv_inventory_movements_daily (branch_id, movement_day, movement_type, product_id);

-- 8.6) Resumen por sesión de caja
drop materialized view if exists public.mv_cash_session_summary;
create materialized view public.mv_cash_session_summary as
select
  cs.id as cash_session_id,
  cs.branch_id,
  cs.opened_by,
  cs.closed_by,
  cs.status,
  cs.opened_at,
  cs.closed_at,
  cs.opening_amount,
  cs.expected_amount,
  cs.closing_amount,
  cs.difference_amount,
  count(distinct s.id) filter (where s.status = 'completed'::public.sale_status)::bigint as sales_completed,
  count(distinct s.id) filter (where s.status = 'voided'::public.sale_status)::bigint as sales_voided,
  coalesce(sum(s.total_amount) filter (where s.status = 'completed'::public.sale_status), 0)::numeric(14,2) as sales_total,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'cash'::public.payment_method), 0)::numeric(14,2) as cash_collected,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'card'::public.payment_method), 0)::numeric(14,2) as card_collected,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'transfer'::public.payment_method), 0)::numeric(14,2) as transfer_collected,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'mobile'::public.payment_method), 0)::numeric(14,2) as mobile_collected,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'credit'::public.payment_method), 0)::numeric(14,2) as credit_collected
from public.cash_sessions cs
left join public.sales s
  on s.cash_session_id = cs.id
  and s.branch_id = cs.branch_id
left join public.payments pay
  on pay.cash_session_id = cs.id
  and pay.branch_id = cs.branch_id
group by cs.id, cs.branch_id, cs.opened_by, cs.closed_by, cs.status,
         cs.opened_at, cs.closed_at, cs.opening_amount, cs.expected_amount,
         cs.closing_amount, cs.difference_amount;

create unique index if not exists mv_cash_session_summary_pk
  on public.mv_cash_session_summary (cash_session_id);

create index if not exists mv_cash_session_summary_branch_idx
  on public.mv_cash_session_summary (branch_id, opened_at desc);

-- =====================================================
-- 9) Vistas wrapper con RLS por sucursal sobre las MVs
-- =====================================================
-- Las materialized views no soportan RLS directamente; envolvemos
-- en vistas security_invoker que aplican has_branch_access().

create or replace view public.sales_daily_view
with (security_invoker = true)
as
select * from public.mv_sales_daily
where public.has_branch_access(branch_id);

create or replace view public.sales_by_item_view
with (security_invoker = true)
as
select * from public.mv_sales_by_item
where public.has_branch_access(branch_id);

create or replace view public.sales_by_category_view
with (security_invoker = true)
as
select * from public.mv_sales_by_category
where public.has_branch_access(branch_id);

create or replace view public.purchases_daily_view
with (security_invoker = true)
as
select * from public.mv_purchases_daily
where public.has_branch_access(branch_id);

create or replace view public.inventory_movements_daily_view
with (security_invoker = true)
as
select * from public.mv_inventory_movements_daily
where public.has_branch_access(branch_id);

create or replace view public.cash_session_summary_view
with (security_invoker = true)
as
select * from public.mv_cash_session_summary
where public.has_branch_access(branch_id);

-- =====================================================
-- 10) Función RPC: refrescar reportes
-- =====================================================

create or replace function public.refresh_business_reports()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view public.mv_sales_daily;
  refresh materialized view public.mv_sales_by_item;
  refresh materialized view public.mv_sales_by_category;
  refresh materialized view public.mv_purchases_daily;
  refresh materialized view public.mv_inventory_movements_daily;
  refresh materialized view public.mv_cash_session_summary;
end;
$$;

grant execute on function public.refresh_business_reports() to authenticated;

-- Versión concurrente para uso programado (requiere índice unique en cada MV).
create or replace function public.refresh_business_reports_concurrently()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view concurrently public.mv_sales_daily;
  refresh materialized view concurrently public.mv_sales_by_item;
  refresh materialized view concurrently public.mv_sales_by_category;
  refresh materialized view concurrently public.mv_purchases_daily;
  refresh materialized view concurrently public.mv_inventory_movements_daily;
  refresh materialized view concurrently public.mv_cash_session_summary;
end;
$$;

grant execute on function public.refresh_business_reports_concurrently() to authenticated;

-- =====================================================
-- 11) Función: build_z_closure_payload (snapshot interno)
-- =====================================================

create or replace function public.build_z_closure_payload(
  p_branch_id uuid,
  p_cash_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session record;
  v_sales jsonb;
  v_payments jsonb;
  v_taxes jsonb;
  v_voids jsonb;
begin
  select cs.* into v_session
  from public.cash_sessions cs
  where cs.id = p_cash_session_id
    and cs.branch_id = p_branch_id;

  if not found then
    raise exception 'Cash session not found for branch';
  end if;

  -- Ventas por receipt_type
  select coalesce(jsonb_agg(jsonb_build_object(
    'receipt_type', t.receipt_type,
    'count', t.cnt,
    'subtotal', t.subtotal,
    'tax', t.tax,
    'service_charge', t.service_charge,
    'total', t.total
  )), '[]'::jsonb)
  into v_sales
  from (
    select
      s.receipt_type,
      count(*) as cnt,
      coalesce(sum(s.subtotal), 0)::numeric(14,2) as subtotal,
      coalesce(sum(s.tax_amount), 0)::numeric(14,2) as tax,
      coalesce(sum(s.service_charge_amount), 0)::numeric(14,2) as service_charge,
      coalesce(sum(s.total_amount), 0)::numeric(14,2) as total
    from public.sales s
    where s.cash_session_id = p_cash_session_id
      and s.branch_id = p_branch_id
      and s.status = 'completed'::public.sale_status
    group by s.receipt_type
  ) t;

  -- Pagos por método
  select coalesce(jsonb_object_agg(payment_method::text, total), '{}'::jsonb)
  into v_payments
  from (
    select
      p.payment_method,
      coalesce(sum(p.amount), 0)::numeric(14,2) as total
    from public.payments p
    where p.cash_session_id = p_cash_session_id
      and p.branch_id = p_branch_id
    group by p.payment_method
  ) t;

  -- Desglose ITBIS
  select jsonb_build_object(
    'taxable_amount', coalesce(sum(s.taxable_amount), 0)::numeric(14,2),
    'exempt_amount',  coalesce(sum(s.exempt_amount), 0)::numeric(14,2),
    'tax_amount',     coalesce(sum(s.tax_amount), 0)::numeric(14,2),
    'service_charge', coalesce(sum(s.service_charge_amount), 0)::numeric(14,2)
  )
  into v_taxes
  from public.sales s
  where s.cash_session_id = p_cash_session_id
    and s.branch_id = p_branch_id
    and s.status = 'completed'::public.sale_status;

  -- Anulaciones
  select jsonb_build_object(
    'count', count(*)::bigint,
    'amount', coalesce(sum(s.total_amount), 0)::numeric(14,2)
  )
  into v_voids
  from public.sales s
  where s.cash_session_id = p_cash_session_id
    and s.branch_id = p_branch_id
    and s.status = 'voided'::public.sale_status;

  return jsonb_build_object(
    'session', jsonb_build_object(
      'id', v_session.id,
      'opened_at', v_session.opened_at,
      'closed_at', v_session.closed_at,
      'opened_by', v_session.opened_by,
      'closed_by', v_session.closed_by,
      'opening_amount', v_session.opening_amount,
      'expected_amount', v_session.expected_amount,
      'closing_amount', v_session.closing_amount,
      'difference_amount', v_session.difference_amount
    ),
    'sales_by_receipt_type', v_sales,
    'payments_by_method', v_payments,
    'tax_breakdown', v_taxes,
    'voids', v_voids,
    'generated_at', timezone('utc', now())
  );
end;
$$;

grant execute on function public.build_z_closure_payload(uuid, uuid) to authenticated;

-- =====================================================
-- 12) Función: seal_fiscal_z_closure
-- =====================================================

create or replace function public.seal_fiscal_z_closure(
  p_branch_id uuid,
  p_cash_session_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_closure_id uuid;
  v_payload jsonb;
  v_next_number integer;
begin
  -- Verificar acceso a la sucursal
  if not public.has_branch_access(p_branch_id) and not public.is_admin() then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  -- La sesión debe existir y estar cerrada
  if not exists (
    select 1 from public.cash_sessions
    where id = p_cash_session_id
      and branch_id = p_branch_id
      and closed_at is not null
  ) then
    raise exception 'La sesión de caja no existe o aún no está cerrada';
  end if;

  -- No permitir doble cierre Z primario para la misma sesión
  if exists (
    select 1 from public.fiscal_z_closures
    where cash_session_id = p_cash_session_id
      and is_complementary = false
  ) then
    raise exception 'Ya existe un cierre Z para esta sesión. Para corregir, emita un complementario.';
  end if;

  -- Calcular siguiente número correlativo por sucursal
  select coalesce(max(closure_number), 0) + 1
    into v_next_number
    from public.fiscal_z_closures
   where branch_id = p_branch_id;

  -- Construir snapshot
  v_payload := public.build_z_closure_payload(p_branch_id, p_cash_session_id);

  insert into public.fiscal_z_closures (
    branch_id, cash_session_id, closure_number, emitted_by, payload
  )
  values (
    p_branch_id, p_cash_session_id, v_next_number, auth.uid(), v_payload
  )
  returning id into v_closure_id;

  return v_closure_id;
end;
$$;

grant execute on function public.seal_fiscal_z_closure(uuid, uuid) to authenticated;

-- =====================================================
-- 13) Permisos canónicos adicionales (para PRD 7)
-- =====================================================

insert into public.permissions (code, name, module, action_type, description, sort_order)
values
  ('reports.fiscal', 'Generar Reportes Fiscales DGII', 'reports', 'fiscal', 'Generar 606, 607, IT-1, Cierre Z fiscal', 72),
  ('reports.custom', 'Crear Reportes Personalizados', 'reports', 'custom', 'Crear reportes vía query builder', 73),
  ('inventory.waste', 'Registrar Mermas', 'inventory', 'waste', 'Registrar movimientos de merma/quiebre/vencido', 45),
  ('inventory.transfer', 'Trasladar Inventario', 'inventory', 'transfer', 'Registrar traslados entre sucursales', 46)
on conflict (code) do update set
  name = excluded.name,
  module = excluded.module,
  action_type = excluded.action_type,
  description = excluded.description,
  sort_order = excluded.sort_order,
  updated_at = timezone('utc', now());

-- Asignaciones por rol
insert into public.role_permissions (role_key, permission_id, allowed)
select role_key, p.id, true
from public.permissions p
join (
  values
    ('admin', 'reports.fiscal'),
    ('admin', 'reports.custom'),
    ('admin', 'inventory.waste'),
    ('admin', 'inventory.transfer'),
    ('accountant', 'reports.fiscal'),
    ('accountant', 'reports.custom'),
    ('supervisor', 'reports.custom'),
    ('supervisor', 'inventory.waste'),
    ('supervisor', 'inventory.transfer')
) as grant_map(role_key, permission_code)
  on p.code = grant_map.permission_code
on conflict (role_key, permission_id) do nothing;

-- =====================================================
-- 14) Refresh inicial de las MVs
-- =====================================================

select public.refresh_business_reports();

-- =====================================================
-- 15) Grants finales
-- =====================================================

grant select, insert, update, delete on public.inventory_movements to authenticated;
grant select, insert on public.fiscal_z_closures to authenticated;
grant select, insert, update, delete on public.fiscal_dgii_reports to authenticated;
grant select, insert, update, delete on public.custom_reports to authenticated;
grant select, insert on public.report_generation_log to authenticated;

grant select on public.mv_sales_daily to authenticated;
grant select on public.mv_sales_by_item to authenticated;
grant select on public.mv_sales_by_category to authenticated;
grant select on public.mv_purchases_daily to authenticated;
grant select on public.mv_inventory_movements_daily to authenticated;
grant select on public.mv_cash_session_summary to authenticated;

grant select on public.sales_daily_view to authenticated;
grant select on public.sales_by_item_view to authenticated;
grant select on public.sales_by_category_view to authenticated;
grant select on public.purchases_daily_view to authenticated;
grant select on public.inventory_movements_daily_view to authenticated;
grant select on public.cash_session_summary_view to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260509_09_reports_schema.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260509_10_dashboard_v2.sql
-- ============================================================
-- 20260509_10_dashboard_v2.sql
-- Shop+ RD - PRD Dashboard 06 (sub-fase 2): backend para nuevo Panel.
--
-- Ejecutar después de:
--   supabase/sql/01_schema.sql
--   supabase/sql/03_reports_views.sql
--   supabase/sql/04_branch_context.sql
--   supabase/sql-next/20260421_structural_backoffice_foundation.sql
--   supabase/sql-next/20260509_09_reports_schema.sql
--
-- Aporta 3 RPCs SECURITY DEFINER, todas branch-scoped:
--   - dashboard_v2_kpis(branch_id)         → 4 contadores (F1)
--   - dashboard_v2_sales_chart(branch_id, range) → serie temporal (F3)
--   - dashboard_v2_closeout(branch_id, date)     → 6 bloques (F4)
--
-- Fuentes:
--   sales, sale_items, purchases, purchase_items, expenses, payments,
--   products, clients, cash_sessions, fiscal_documents (PRD 6).
--
-- Notas:
--   - "Total Kits" hoy = 0: no existe modelo de kits en este esquema; el
--     PRD §12.1 lo deja como TBD. Cuando aparezca, esta RPC devuelve count.
--   - "Devoluciones" hoy se aproxima con sales.status = 'voided' porque la
--     tabla `returns` (PRD F5) aún no existe; cuando llegue, ajustar.

begin;

-- =====================================================
-- 1) RPC: KPIs F1
-- =====================================================

create or replace function public.dashboard_v2_kpis(
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_total_ventas bigint;
  v_total_inventario bigint;
  v_total_clientes bigint;
  v_total_kits bigint;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  if v_branch_id is null then
    return jsonb_build_object(
      'partial', true,
      'total_ventas', 0,
      'total_inventario', 0,
      'total_clientes', 0,
      'total_kits', 0
    );
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  select count(*)
    into v_total_ventas
    from public.sales s
   where s.branch_id = v_branch_id
     and s.status <> 'voided'::public.sale_status;

  select count(*)
    into v_total_inventario
    from public.products p
   where p.branch_id = v_branch_id
     and p.is_active = true
     and p.stock > 0;

  select count(*)
    into v_total_clientes
    from public.clients c
   where c.branch_id = v_branch_id
     and c.is_active = true
     and lower(coalesce(c.full_name, '')) <> 'consumidor final';

  -- Kits: TBD (PRD §12.1). No hay modelo de kits aún.
  v_total_kits := 0;

  return jsonb_build_object(
    'branch_id', v_branch_id,
    'total_ventas', coalesce(v_total_ventas, 0),
    'total_inventario', coalesce(v_total_inventario, 0),
    'total_clientes', coalesce(v_total_clientes, 0),
    'total_kits', v_total_kits,
    'partial', false
  );
end;
$$;

grant execute on function public.dashboard_v2_kpis(uuid) to authenticated;

-- =====================================================
-- 2) RPC: serie temporal F3 (mes / semana)
-- =====================================================

create or replace function public.dashboard_v2_sales_chart(
  p_branch_id uuid default null,
  p_range text default 'month'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_start date;
  v_end date;
  v_today date;
  v_result jsonb;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  if v_branch_id is null then
    return '[]'::jsonb;
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  v_today := (timezone('America/Santo_Domingo', now()))::date;

  if lower(coalesce(p_range, 'month')) = 'week' then
    v_start := v_today - interval '6 days';
    v_end := v_today;
  else
    v_start := date_trunc('month', v_today)::date;
    v_end := v_today;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'date', d::date,
           'transactions', coalesce(s.cnt, 0),
           'total', coalesce(s.total, 0)
         ) order by d), '[]'::jsonb)
    into v_result
    from generate_series(v_start, v_end, interval '1 day') as d
    left join (
      select date(sale_date at time zone 'America/Santo_Domingo') as day,
             count(*) as cnt,
             coalesce(sum(total_amount), 0)::numeric(14,2) as total
        from public.sales
       where branch_id = v_branch_id
         and status = 'completed'::public.sale_status
         and sale_date >= (v_start::timestamp at time zone 'America/Santo_Domingo')
         and sale_date <  ((v_end + 1)::timestamp at time zone 'America/Santo_Domingo')
       group by 1
    ) s on s.day = d::date;

  return v_result;
end;
$$;

grant execute on function public.dashboard_v2_sales_chart(uuid, text) to authenticated;

-- =====================================================
-- 3) RPC: cierre del día F4 (6 bloques)
-- =====================================================

create or replace function public.dashboard_v2_closeout(
  p_branch_id uuid default null,
  p_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_date date;
  v_start timestamptz;
  v_end timestamptz;

  v_sales_block jsonb;
  v_credit_block jsonb;
  v_returns_block jsonb;
  v_purchases_block jsonb;
  v_expenses_block jsonb;
  v_cash_block jsonb;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  v_date := coalesce(p_date, (timezone('America/Santo_Domingo', now()))::date);

  if v_branch_id is null then
    return jsonb_build_object('partial', true);
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  v_start := (v_date::timestamp at time zone 'America/Santo_Domingo');
  v_end   := ((v_date + 1)::timestamp at time zone 'America/Santo_Domingo');

  -- 4.1 VENTAS
  with day_sales as (
    select s.*
      from public.sales s
     where s.branch_id = v_branch_id
       and s.status = 'completed'::public.sale_status
       and s.sale_date >= v_start
       and s.sale_date <  v_end
  ),
  day_items as (
    select si.*
      from public.sale_items si
      join day_sales s on s.id = si.sale_id and s.branch_id = si.branch_id
  ),
  cash_payments as (
    select coalesce(sum(p.amount), 0)::numeric(14,2) as cash_total
      from public.payments p
      join day_sales s on s.id = p.sale_id and s.branch_id = p.branch_id
     where p.payment_method = 'cash'::public.payment_method
  ),
  by_category as (
    select coalesce(pc.name, 'Sin categoría') as category_name,
           coalesce(sum(di.line_total), 0)::numeric(14,2) as total
      from day_items di
      left join public.products p
        on p.id = di.product_id
       and p.branch_id = di.branch_id
      left join public.product_categories pc
        on pc.id = coalesce(di.category_id, p.category_id)
       and pc.branch_id = di.branch_id
     group by 1
  ),
  inv_totals as (
    select coalesce(sum(p.stock), 0)::numeric(14,3) as qty_on_hand,
           coalesce(sum(p.stock * p.cost), 0)::numeric(14,2) as inv_value
      from public.products p
     where p.branch_id = v_branch_id
       and p.is_active = true
  )
  select jsonb_build_object(
    'sales_total_no_tax', coalesce(sum(s.taxable_amount + s.exempt_amount), 0)::numeric(14,2),
    'sales_total_with_tax', coalesce(sum(s.total_amount), 0)::numeric(14,2),
    'profit', coalesce(sum(s.total_amount), 0)::numeric(14,2)
              - coalesce(sum((select sum(si.quantity * coalesce(p.cost, 0))
                              from public.sale_items si
                              left join public.products p
                                on p.id = si.product_id and p.branch_id = si.branch_id
                              where si.sale_id = s.id and si.branch_id = s.branch_id)), 0)::numeric(14,2),
    'inventory_qty_on_hand', (select qty_on_hand from inv_totals),
    'inventory_value', (select inv_value from inv_totals),
    'breakdown_by_category', (select coalesce(jsonb_agg(jsonb_build_object(
                                       'name', category_name,
                                       'amount', total
                                     ) order by total desc), '[]'::jsonb)
                              from by_category),
    'transactions_count', count(*),
    'avg_ticket', case when count(*) > 0
                       then coalesce(sum(s.total_amount), 0) / count(*)
                       else 0 end,
    'items_sold', coalesce((select sum(quantity) from day_items), 0)::numeric(14,3),
    'tax_amount', coalesce(sum(s.tax_amount), 0)::numeric(14,2),
    'no_tax_amount', coalesce(sum(s.taxable_amount + s.exempt_amount), 0)::numeric(14,2),
    'cash_amount', coalesce((select cash_total from cash_payments), 0)
  ) into v_sales_block
  from day_sales s;

  -- 4.2 CRÉDITO
  with day_payments as (
    select p.*
      from public.payments p
     where p.branch_id = v_branch_id
       and p.paid_at >= v_start
       and p.paid_at <  v_end
  )
  select jsonb_build_object(
    'debits',  coalesce((select sum(amount) from day_payments where payment_method = 'credit'::public.payment_method), 0)::numeric(14,2),
    'credits', coalesce((select sum(amount) from day_payments where payment_method <> 'credit'::public.payment_method
                                                              and client_id is not null), 0)::numeric(14,2),
    'store_account_balance_total', coalesce((select sum(c.balance_due) from public.clients c
                                              where c.branch_id = v_branch_id and c.is_active = true), 0)::numeric(14,2)
  ) into v_credit_block;

  -- 4.3 DEVOLUCIONES (proxy: sales voided del día)
  -- Cuando exista la tabla `returns` (PRD F5) ajustar este bloque.
  with voided_sales as (
    select s.*
      from public.sales s
     where s.branch_id = v_branch_id
       and s.status = 'voided'::public.sale_status
       and s.updated_at >= v_start
       and s.updated_at <  v_end
  ),
  voided_items as (
    select si.product_id, si.description, si.quantity, si.line_total
      from public.sale_items si
      join voided_sales s on s.id = si.sale_id and s.branch_id = si.branch_id
  )
  select jsonb_build_object(
    'returns_total', coalesce(sum(s.total_amount), 0)::numeric(14,2),
    'breakdown_by_item', (select coalesce(jsonb_agg(jsonb_build_object(
                                   'description', description,
                                   'quantity', quantity,
                                   'amount', line_total
                                 )), '[]'::jsonb)
                          from voided_items),
    'transactions_count', count(*),
    'items_returned', coalesce((select sum(quantity) from voided_items), 0)::numeric(14,3),
    'tax_amount', coalesce(sum(s.tax_amount), 0)::numeric(14,2),
    'returns_table_available', false
  ) into v_returns_block
  from voided_sales s;

  -- 4.4 COMPRAS (recepciones)
  with day_purchases as (
    select p.*
      from public.purchases p
     where p.branch_id = v_branch_id
       and p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
       and p.purchase_date = v_date
  ),
  day_purchase_items as (
    select pi.*
      from public.purchase_items pi
      join day_purchases p on p.id = pi.purchase_id and p.branch_id = pi.branch_id
  )
  select jsonb_build_object(
    'receivings_total_no_tax', coalesce(sum(p.subtotal), 0)::numeric(14,2),
    'receivings_total_with_tax', coalesce(sum(p.total_amount), 0)::numeric(14,2),
    'transactions_count', count(*),
    'avg_ticket', case when count(*) > 0
                       then coalesce(sum(p.total_amount), 0) / count(*)
                       else 0 end,
    'items_received', coalesce((select sum(quantity) from day_purchase_items), 0)::numeric(14,3),
    'tax_amount', coalesce(sum(p.tax_amount), 0)::numeric(14,2),
    'no_tax_amount', coalesce(sum(p.subtotal), 0)::numeric(14,2)
  ) into v_purchases_block
  from day_purchases p;

  -- 4.5 GASTOS
  select jsonb_build_object(
    'expenses_total', coalesce(sum(amount), 0)::numeric(14,2),
    'transactions_count', count(*)
  ) into v_expenses_block
  from public.expenses
  where branch_id = v_branch_id
    and expense_date = v_date;

  -- 4.6 CASH MONITORING (sesión de caja del día)
  select jsonb_build_object(
    'enabled', cs.id is not null,
    'session_id', cs.id,
    'opened_at', cs.opened_at,
    'closed_at', cs.closed_at,
    'opening_amount', coalesce(cs.opening_amount, 0)::numeric(14,2),
    'expected_amount', coalesce(cs.expected_amount, 0)::numeric(14,2),
    'closing_amount', cs.closing_amount,
    'difference_amount', cs.difference_amount,
    'status', cs.status
  ) into v_cash_block
  from public.cash_sessions cs
  where cs.branch_id = v_branch_id
    and cs.opened_at >= v_start - interval '1 day'
    and cs.opened_at <  v_end
  order by cs.opened_at desc
  limit 1;

  if v_cash_block is null then
    v_cash_block := jsonb_build_object('enabled', false);
  end if;

  return jsonb_build_object(
    'branch_id', v_branch_id,
    'date', v_date,
    'sales', v_sales_block,
    'credit', v_credit_block,
    'returns', v_returns_block,
    'purchases', v_purchases_block,
    'expenses', v_expenses_block,
    'cash_monitoring', v_cash_block,
    'partial', false
  );
end;
$$;

grant execute on function public.dashboard_v2_closeout(uuid, date) to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260509_10_dashboard_v2.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260509_11_returns.sql
-- ============================================================
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

-- ============================================================
-- END:   sql-next/20260509_11_returns.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260509_12_closeout_returns_fix.sql
-- ============================================================
-- 20260509_12_closeout_returns_fix.sql
-- Shop+ RD - PRD Dashboard 06 (cierre F4 fix):
--   el bloque "Devoluciones" del RPC `dashboard_v2_closeout` leía
--   `sales WHERE status='voided'` como proxy porque la tabla `returns`
--   aún no existía. Tras 20260509_11_returns.sql, la tabla está
--   poblada por el flujo Venta/Devolución del POS — apuntamos el RPC a
--   esa tabla y marcamos `returns_table_available: true`.
--
-- Ejecutar después de:
--   supabase/sql-next/20260509_11_returns.sql

begin;

create or replace function public.dashboard_v2_closeout(
  p_branch_id uuid default null,
  p_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_date date;
  v_start timestamptz;
  v_end timestamptz;

  v_sales_block jsonb;
  v_credit_block jsonb;
  v_returns_block jsonb;
  v_purchases_block jsonb;
  v_expenses_block jsonb;
  v_cash_block jsonb;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  v_date := coalesce(p_date, (timezone('America/Santo_Domingo', now()))::date);

  if v_branch_id is null then
    return jsonb_build_object('partial', true);
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  v_start := (v_date::timestamp at time zone 'America/Santo_Domingo');
  v_end   := ((v_date + 1)::timestamp at time zone 'America/Santo_Domingo');

  -- 4.1 VENTAS (idéntico a v1)
  with day_sales as (
    select s.*
      from public.sales s
     where s.branch_id = v_branch_id
       and s.status = 'completed'::public.sale_status
       and s.sale_date >= v_start
       and s.sale_date <  v_end
  ),
  day_items as (
    select si.*
      from public.sale_items si
      join day_sales s on s.id = si.sale_id and s.branch_id = si.branch_id
  ),
  cash_payments as (
    select coalesce(sum(p.amount), 0)::numeric(14,2) as cash_total
      from public.payments p
      join day_sales s on s.id = p.sale_id and s.branch_id = p.branch_id
     where p.payment_method = 'cash'::public.payment_method
  ),
  by_category as (
    select coalesce(pc.name, 'Sin categoría') as category_name,
           coalesce(sum(di.line_total), 0)::numeric(14,2) as total
      from day_items di
      left join public.products p
        on p.id = di.product_id
       and p.branch_id = di.branch_id
      left join public.product_categories pc
        on pc.id = coalesce(di.category_id, p.category_id)
       and pc.branch_id = di.branch_id
     group by 1
  ),
  inv_totals as (
    select coalesce(sum(p.stock), 0)::numeric(14,3) as qty_on_hand,
           coalesce(sum(p.stock * p.cost), 0)::numeric(14,2) as inv_value
      from public.products p
     where p.branch_id = v_branch_id
       and p.is_active = true
  )
  select jsonb_build_object(
    'sales_total_no_tax', coalesce(sum(s.taxable_amount + s.exempt_amount), 0)::numeric(14,2),
    'sales_total_with_tax', coalesce(sum(s.total_amount), 0)::numeric(14,2),
    'profit', coalesce(sum(s.total_amount), 0)::numeric(14,2)
              - coalesce(sum((select sum(si.quantity * coalesce(p.cost, 0))
                              from public.sale_items si
                              left join public.products p
                                on p.id = si.product_id and p.branch_id = si.branch_id
                              where si.sale_id = s.id and si.branch_id = s.branch_id)), 0)::numeric(14,2),
    'inventory_qty_on_hand', (select qty_on_hand from inv_totals),
    'inventory_value', (select inv_value from inv_totals),
    'breakdown_by_category', (select coalesce(jsonb_agg(jsonb_build_object(
                                       'name', category_name,
                                       'amount', total
                                     ) order by total desc), '[]'::jsonb)
                              from by_category),
    'transactions_count', count(*),
    'avg_ticket', case when count(*) > 0
                       then coalesce(sum(s.total_amount), 0) / count(*)
                       else 0 end,
    'items_sold', coalesce((select sum(quantity) from day_items), 0)::numeric(14,3),
    'tax_amount', coalesce(sum(s.tax_amount), 0)::numeric(14,2),
    'no_tax_amount', coalesce(sum(s.taxable_amount + s.exempt_amount), 0)::numeric(14,2),
    'cash_amount', coalesce((select cash_total from cash_payments), 0)
  ) into v_sales_block
  from day_sales s;

  -- 4.2 CRÉDITO (idéntico a v1)
  with day_payments as (
    select p.*
      from public.payments p
     where p.branch_id = v_branch_id
       and p.paid_at >= v_start
       and p.paid_at <  v_end
  )
  select jsonb_build_object(
    'debits',  coalesce((select sum(amount) from day_payments where payment_method = 'credit'::public.payment_method), 0)::numeric(14,2),
    'credits', coalesce((select sum(amount) from day_payments where payment_method <> 'credit'::public.payment_method
                                                              and client_id is not null), 0)::numeric(14,2),
    'store_account_balance_total', coalesce((select sum(c.balance_due) from public.clients c
                                              where c.branch_id = v_branch_id and c.is_active = true), 0)::numeric(14,2)
  ) into v_credit_block;

  -- 4.3 DEVOLUCIONES — ahora lee de `returns` (FIX vs proxy original).
  with day_returns as (
    select r.*
      from public.returns r
     where r.branch_id = v_branch_id
       and r.return_date >= v_start
       and r.return_date <  v_end
  ),
  day_return_items as (
    select ri.product_id, ri.description, ri.quantity, ri.line_total
      from public.return_items ri
      join day_returns r on r.id = ri.return_id and r.branch_id = ri.branch_id
  )
  select jsonb_build_object(
    'returns_total', coalesce(sum(r.total_amount), 0)::numeric(14,2),
    'breakdown_by_item', (select coalesce(jsonb_agg(jsonb_build_object(
                                   'description', description,
                                   'quantity', quantity,
                                   'amount', line_total
                                 )), '[]'::jsonb)
                          from day_return_items),
    'transactions_count', count(*),
    'items_returned', coalesce((select sum(quantity) from day_return_items), 0)::numeric(14,3),
    'tax_amount', coalesce(sum(r.tax_amount), 0)::numeric(14,2),
    'returns_table_available', true
  ) into v_returns_block
  from day_returns r;

  -- 4.4 COMPRAS (idéntico a v1)
  with day_purchases as (
    select p.*
      from public.purchases p
     where p.branch_id = v_branch_id
       and p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
       and p.purchase_date = v_date
  ),
  day_purchase_items as (
    select pi.*
      from public.purchase_items pi
      join day_purchases p on p.id = pi.purchase_id and p.branch_id = pi.branch_id
  )
  select jsonb_build_object(
    'receivings_total_no_tax', coalesce(sum(p.subtotal), 0)::numeric(14,2),
    'receivings_total_with_tax', coalesce(sum(p.total_amount), 0)::numeric(14,2),
    'transactions_count', count(*),
    'avg_ticket', case when count(*) > 0
                       then coalesce(sum(p.total_amount), 0) / count(*)
                       else 0 end,
    'items_received', coalesce((select sum(quantity) from day_purchase_items), 0)::numeric(14,3),
    'tax_amount', coalesce(sum(p.tax_amount), 0)::numeric(14,2),
    'no_tax_amount', coalesce(sum(p.subtotal), 0)::numeric(14,2)
  ) into v_purchases_block
  from day_purchases p;

  -- 4.5 GASTOS (idéntico a v1)
  select jsonb_build_object(
    'expenses_total', coalesce(sum(amount), 0)::numeric(14,2),
    'transactions_count', count(*)
  ) into v_expenses_block
  from public.expenses
  where branch_id = v_branch_id
    and expense_date = v_date;

  -- 4.6 CASH MONITORING (idéntico a v1)
  select jsonb_build_object(
    'enabled', cs.id is not null,
    'session_id', cs.id,
    'opened_at', cs.opened_at,
    'closed_at', cs.closed_at,
    'opening_amount', coalesce(cs.opening_amount, 0)::numeric(14,2),
    'expected_amount', coalesce(cs.expected_amount, 0)::numeric(14,2),
    'closing_amount', cs.closing_amount,
    'difference_amount', cs.difference_amount,
    'status', cs.status
  ) into v_cash_block
  from public.cash_sessions cs
  where cs.branch_id = v_branch_id
    and cs.opened_at >= v_start - interval '1 day'
    and cs.opened_at <  v_end
  order by cs.opened_at desc
  limit 1;

  if v_cash_block is null then
    v_cash_block := jsonb_build_object('enabled', false);
  end if;

  return jsonb_build_object(
    'branch_id', v_branch_id,
    'date', v_date,
    'sales', v_sales_block,
    'credit', v_credit_block,
    'returns', v_returns_block,
    'purchases', v_purchases_block,
    'expenses', v_expenses_block,
    'cash_monitoring', v_cash_block,
    'partial', false
  );
end;
$$;

grant execute on function public.dashboard_v2_closeout(uuid, date) to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260509_12_closeout_returns_fix.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260509_13_reports_round2_views.sql
-- ============================================================
-- 20260509_13_reports_round2_views.sql
-- Shop+ RD - PRD 07 Round 2: views + RPCs para los 12 reportes operativos
-- de empleados, productos, financieros y clientes.
--
-- Ejecutar después de:
--   supabase/sql-next/20260509_09_reports_schema.sql  (MVs base ya creadas)
--   supabase/sql-next/20260509_11_returns.sql         (tabla returns)
--   supabase/sql-next/20260509_12_closeout_returns_fix.sql
--
-- Diseño:
--   - Todas las vistas usan `security_invoker = true` para que RLS por
--     sucursal se aplique según el usuario que consulta.
--   - Vista o RPC según el caso. Vistas para agregaciones simples,
--     RPCs para casos con parámetros (rango de fecha, settings).
--   - Cobertura:
--       Empleados, Comisión, Inventario, Precios, Mermas (ya cubierto en m9),
--       P&L, Crédito, Gastos, Compras, Proveedores, Clientes, Descuentos.

begin;

-- =====================================================
-- 1) Empleados — productividad por usuario / mesero
-- =====================================================

create or replace view public.report_employees_view
with (security_invoker = true)
as
select
  s.branch_id,
  coalesce(s.seller_id, s.cashier_id) as employee_id,
  coalesce(p.full_name, 'Sin asignar')::text as employee_name,
  count(*)::bigint as sales_count,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as sales_total,
  case when count(*) > 0
       then (coalesce(sum(s.total_amount), 0) / count(*))::numeric(14,2)
       else 0 end as avg_ticket,
  coalesce(sum((
    select sum(si.quantity)
      from public.sale_items si
     where si.sale_id = s.id and si.branch_id = s.branch_id
  )), 0)::numeric(14,3) as items_sold,
  max(s.sale_date) as last_sale_at,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day
from public.sales s
left join public.profiles p
  on p.id = coalesce(s.seller_id, s.cashier_id)
where s.status = 'completed'::public.sale_status
  and public.has_branch_access(s.branch_id)
group by s.branch_id, coalesce(s.seller_id, s.cashier_id), p.full_name,
         date(s.sale_date at time zone 'America/Santo_Domingo');

grant select on public.report_employees_view to authenticated;

-- =====================================================
-- 2) Comisión — RPC que respeta app_settings.emp_commission_*
-- =====================================================

create or replace function public.report_commission(
  p_from date default null,
  p_to date default null,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_from date;
  v_to date;
  v_rate numeric(5,2);
  v_method text;
  v_rows jsonb;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  v_from := coalesce(p_from, date_trunc('month', current_date)::date);
  v_to := coalesce(p_to, current_date);

  if v_branch_id is null then
    return jsonb_build_object('partial', true, 'rows', '[]'::jsonb);
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  -- Lee tasa y método desde app_settings (singleton id=1).
  select coalesce(emp_commission_rate, 0)::numeric(5,2),
         coalesce(emp_commission_method, 'sale_price')::text
    into v_rate, v_method
    from public.app_settings where id = 1;

  v_rate := coalesce(v_rate, 0);
  v_method := coalesce(v_method, 'sale_price');

  with day_sales as (
    select s.*
      from public.sales s
     where s.branch_id = v_branch_id
       and s.status = 'completed'::public.sale_status
       and s.sale_date >= (v_from::timestamp at time zone 'America/Santo_Domingo')
       and s.sale_date <  ((v_to + 1)::timestamp at time zone 'America/Santo_Domingo')
  ),
  base as (
    select
      coalesce(s.seller_id, s.cashier_id) as employee_id,
      coalesce(p.full_name, 'Sin asignar') as employee_name,
      count(*) as sales_count,
      sum(s.total_amount) as sales_total,
      sum(s.subtotal) as base_price,
      sum(
        s.subtotal - coalesce((
          select sum(si.quantity * coalesce(prod.cost, 0))
            from public.sale_items si
            left join public.products prod
              on prod.id = si.product_id and prod.branch_id = si.branch_id
           where si.sale_id = s.id and si.branch_id = s.branch_id
        ), 0)
      ) as profit_base
    from day_sales s
    left join public.profiles p
      on p.id = coalesce(s.seller_id, s.cashier_id)
    group by 1, 2
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'employee_id', employee_id,
    'employee_name', employee_name,
    'sales_count', sales_count,
    'sales_total', sales_total,
    'base_amount', case v_method
                     when 'sale_price' then base_price
                     when 'profit_margin' then profit_base
                     when 'total_sales' then sales_total
                     else base_price end,
    'commission_rate', v_rate,
    'commission_amount', round(
      (case v_method
         when 'sale_price' then base_price
         when 'profit_margin' then profit_base
         when 'total_sales' then sales_total
         else base_price end) * v_rate / 100.0, 2)
  ) order by sales_total desc), '[]'::jsonb)
  into v_rows
  from base;

  return jsonb_build_object(
    'from', v_from,
    'to', v_to,
    'rate', v_rate,
    'method', v_method,
    'rows', v_rows
  );
end;
$$;

grant execute on function public.report_commission(date, date, uuid) to authenticated;

-- =====================================================
-- 3) Inventario — snapshot actual con valor y low-stock flag
-- =====================================================

create or replace view public.report_inventory_status_view
with (security_invoker = true)
as
select
  p.branch_id,
  p.id as product_id,
  p.name,
  p.sku,
  p.barcode,
  p.category_id,
  pc.name as category_name,
  p.stock,
  p.min_stock,
  p.cost,
  p.price,
  (p.stock * p.cost)::numeric(14,2) as inventory_value,
  case when p.stock <= p.min_stock and p.min_stock > 0 then true else false end
    as is_low_stock,
  case when p.stock <= 0 then true else false end as is_out_of_stock,
  p.is_active,
  p.updated_at
from public.products p
left join public.product_categories pc
  on pc.id = p.category_id and pc.branch_id = p.branch_id
where p.is_active = true
  and public.has_branch_access(p.branch_id);

grant select on public.report_inventory_status_view to authenticated;

-- =====================================================
-- 4) Precios — precio actual + margen (no hay historial todavía)
-- =====================================================

create or replace view public.report_current_prices_view
with (security_invoker = true)
as
select
  p.branch_id,
  p.id as product_id,
  p.name,
  p.sku,
  p.barcode,
  pc.name as category_name,
  p.cost,
  p.price,
  case when p.cost > 0
       then round(((p.price - p.cost) / p.cost) * 100, 2)
       else null end as margin_pct,
  p.price_tier_1,
  p.price_tier_2,
  p.price_tier_3,
  p.updated_at
from public.products p
left join public.product_categories pc
  on pc.id = p.category_id and pc.branch_id = p.branch_id
where p.is_active = true
  and public.has_branch_access(p.branch_id);

grant select on public.report_current_prices_view to authenticated;

-- =====================================================
-- 5) Pérdidas y Ganancias — RPC con rango
-- =====================================================

create or replace function public.report_pl(
  p_from date default null,
  p_to date default null,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_from date;
  v_to date;
  v_start timestamptz;
  v_end timestamptz;
  v_revenue numeric(14,2);
  v_cogs numeric(14,2);
  v_returns numeric(14,2);
  v_expenses numeric(14,2);
  v_tax_received numeric(14,2);
  v_tax_paid numeric(14,2);
  v_purchases numeric(14,2);
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());
  v_from := coalesce(p_from, date_trunc('month', current_date)::date);
  v_to := coalesce(p_to, current_date);

  if v_branch_id is null then
    return jsonb_build_object('partial', true);
  end if;

  if not (public.has_branch_access(v_branch_id) or public.is_admin()) then
    raise exception 'Sin acceso a la sucursal indicada';
  end if;

  v_start := (v_from::timestamp at time zone 'America/Santo_Domingo');
  v_end := ((v_to + 1)::timestamp at time zone 'America/Santo_Domingo');

  -- Revenue: ventas completadas en el rango
  select coalesce(sum(total_amount), 0),
         coalesce(sum(tax_amount), 0)
    into v_revenue, v_tax_received
    from public.sales
   where branch_id = v_branch_id
     and status = 'completed'::public.sale_status
     and sale_date >= v_start
     and sale_date <  v_end;

  -- COGS: sum(quantity * cost) en sale_items de ventas en el rango
  select coalesce(sum(si.quantity * coalesce(p.cost, 0)), 0)
    into v_cogs
    from public.sale_items si
    join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
    left join public.products p
      on p.id = si.product_id and p.branch_id = si.branch_id
   where s.branch_id = v_branch_id
     and s.status = 'completed'::public.sale_status
     and s.sale_date >= v_start
     and s.sale_date <  v_end;

  -- Devoluciones
  select coalesce(sum(total_amount), 0)
    into v_returns
    from public.returns
   where branch_id = v_branch_id
     and return_date >= v_start
     and return_date <  v_end;

  -- Gastos
  select coalesce(sum(amount), 0)
    into v_expenses
    from public.expenses
   where branch_id = v_branch_id
     and expense_date >= v_from
     and expense_date <= v_to;

  -- Compras + ITBIS pagado
  select coalesce(sum(total_amount), 0),
         coalesce(sum(tax_amount), 0)
    into v_purchases, v_tax_paid
    from public.purchases
   where branch_id = v_branch_id
     and status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
     and purchase_date >= v_from
     and purchase_date <= v_to;

  return jsonb_build_object(
    'from', v_from,
    'to', v_to,
    'revenue', v_revenue,
    'cogs', v_cogs,
    'returns', v_returns,
    'gross_profit', v_revenue - v_cogs - v_returns,
    'expenses', v_expenses,
    'net_profit', (v_revenue - v_cogs - v_returns) - v_expenses,
    'tax_received', v_tax_received,
    'tax_paid', v_tax_paid,
    'tax_balance', v_tax_received - v_tax_paid,
    'purchases_total', v_purchases
  );
end;
$$;

grant execute on function public.report_pl(date, date, uuid) to authenticated;

-- =====================================================
-- 6) Crédito — antigüedad de saldos por cliente
-- =====================================================

create or replace view public.report_credit_aging_view
with (security_invoker = true)
as
with oldest_unpaid as (
  select
    s.branch_id,
    s.client_id,
    min(s.sale_date) as oldest_at
  from public.sales s
  where s.balance_due > 0
    and s.status in ('credit'::public.sale_status, 'completed'::public.sale_status)
    and s.client_id is not null
  group by s.branch_id, s.client_id
)
select
  c.branch_id,
  c.id as client_id,
  c.full_name as client_name,
  c.balance_due,
  c.credit_limit,
  ou.oldest_at,
  case
    when ou.oldest_at is null then null
    else greatest(0, (current_date - ou.oldest_at::date))::integer
  end as days_overdue,
  case
    when ou.oldest_at is null then '—'
    when (current_date - ou.oldest_at::date) <= 30 then '0-30'
    when (current_date - ou.oldest_at::date) <= 60 then '31-60'
    when (current_date - ou.oldest_at::date) <= 90 then '61-90'
    else '+90'
  end as aging_bucket
from public.clients c
left join oldest_unpaid ou
  on ou.client_id = c.id and ou.branch_id = c.branch_id
where c.balance_due > 0
  and c.is_active = true
  and public.has_branch_access(c.branch_id);

grant select on public.report_credit_aging_view to authenticated;

-- =====================================================
-- 7) Gastos — agrupados por categoría (vista para reporte)
-- =====================================================

create or replace view public.report_expenses_view
with (security_invoker = true)
as
select
  e.branch_id,
  e.expense_date,
  coalesce(e.category, 'Sin categoría') as category,
  count(*)::bigint as count,
  sum(e.amount)::numeric(14,2) as total
from public.expenses e
where public.has_branch_access(e.branch_id)
group by e.branch_id, e.expense_date, e.category;

grant select on public.report_expenses_view to authenticated;

-- =====================================================
-- 8) Compras — agregadas por día y proveedor
-- =====================================================

create or replace view public.report_purchases_view
with (security_invoker = true)
as
select
  p.branch_id,
  p.purchase_date,
  p.supplier_id,
  s.legal_name as supplier_name,
  count(*)::bigint as purchases_count,
  sum(p.subtotal)::numeric(14,2) as subtotal_total,
  sum(p.tax_amount)::numeric(14,2) as tax_total,
  sum(p.total_amount)::numeric(14,2) as grand_total
from public.purchases p
join public.suppliers s on s.id = p.supplier_id and s.branch_id = p.branch_id
where p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
  and public.has_branch_access(p.branch_id)
group by p.branch_id, p.purchase_date, p.supplier_id, s.legal_name;

grant select on public.report_purchases_view to authenticated;

-- =====================================================
-- 9) Proveedores — top proveedores y deuda actual
-- =====================================================

create or replace view public.report_suppliers_view
with (security_invoker = true)
as
with totals as (
  select
    p.branch_id,
    p.supplier_id,
    count(*)::bigint as purchases_count,
    sum(p.total_amount)::numeric(14,2) as purchases_total,
    max(p.purchase_date) as last_purchase_at,
    sum(
      case when coalesce(p.payment_status, 'pending') <> 'paid'
           then p.total_amount else 0 end
    )::numeric(14,2) as outstanding_amount
  from public.purchases p
  where p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
  group by p.branch_id, p.supplier_id
)
select
  s.branch_id,
  s.id as supplier_id,
  s.legal_name as supplier_name,
  s.trade_name,
  s.rnc,
  coalesce(t.purchases_count, 0) as purchases_count,
  coalesce(t.purchases_total, 0)::numeric(14,2) as purchases_total,
  coalesce(t.outstanding_amount, 0)::numeric(14,2) as outstanding_amount,
  t.last_purchase_at
from public.suppliers s
left join totals t on t.supplier_id = s.id and t.branch_id = s.branch_id
where s.is_active = true
  and public.has_branch_access(s.branch_id);

grant select on public.report_suppliers_view to authenticated;

-- =====================================================
-- 10) Clientes — top clientes, frecuencia, ticket promedio
-- =====================================================

create or replace view public.report_clients_view
with (security_invoker = true)
as
with sale_agg as (
  select
    s.branch_id,
    s.client_id,
    count(*) filter (where s.status = 'completed'::public.sale_status)::bigint
      as sales_count,
    coalesce(sum(s.total_amount) filter (where s.status = 'completed'::public.sale_status), 0)::numeric(14,2)
      as sales_total,
    max(s.sale_date) filter (where s.status = 'completed'::public.sale_status)
      as last_sale_at
  from public.sales s
  where s.client_id is not null
  group by s.branch_id, s.client_id
)
select
  c.branch_id,
  c.id as client_id,
  c.full_name as client_name,
  c.phone,
  c.email,
  c.credit_limit,
  c.balance_due,
  coalesce(sa.sales_count, 0) as sales_count,
  coalesce(sa.sales_total, 0)::numeric(14,2) as sales_total,
  case when coalesce(sa.sales_count, 0) > 0
       then (coalesce(sa.sales_total, 0) / sa.sales_count)::numeric(14,2)
       else 0 end as avg_ticket,
  sa.last_sale_at
from public.clients c
left join sale_agg sa
  on sa.client_id = c.id and sa.branch_id = c.branch_id
where c.is_active = true
  and public.has_branch_access(c.branch_id);

grant select on public.report_clients_view to authenticated;

-- =====================================================
-- 11) Descuentos — ventas con descuento aplicado
-- =====================================================

create or replace view public.report_discounts_view
with (security_invoker = true)
as
select
  s.branch_id,
  s.id as sale_id,
  s.sale_number,
  s.sale_date,
  s.client_id,
  c.full_name as client_name,
  s.cashier_id,
  p.full_name as cashier_name,
  s.discount_amount,
  s.subtotal,
  s.total_amount,
  case when s.subtotal > 0
       then round((s.discount_amount / s.subtotal) * 100, 2)
       else 0 end as discount_pct
from public.sales s
left join public.clients c
  on c.id = s.client_id and c.branch_id = s.branch_id
left join public.profiles p on p.id = s.cashier_id
where s.discount_amount > 0
  and s.status = 'completed'::public.sale_status
  and public.has_branch_access(s.branch_id);

grant select on public.report_discounts_view to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260509_13_reports_round2_views.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260509_14_dgii_reports.sql
-- ============================================================
-- 20260509_14_dgii_reports.sql
-- Shop+ RD - PRD 07 Round 3: Reportes Fiscales DGII.
--
-- Ejecutar después de:
--   supabase/sql-next/20260509_09_reports_schema.sql (fiscal_dgii_reports
--     y fiscal_z_closures tablas ya creadas)
--   supabase/sql-next/20260509_13_reports_round2_views.sql
--
-- Diseño:
--   - 3 RPCs SECURITY DEFINER que devuelven la data lista para serializar
--     a TXT en el cliente Flutter:
--       * `dgii_606_data(p_year, p_month)` — compras del mes con NCF
--         (formato 606).
--       * `dgii_607_data(p_year, p_month)` — ventas del mes con NCF
--         (formato 607).
--       * `dgii_it1_summary(p_year, p_month)` — resumen IT-1.
--   - 1 view + 1 RPC para "Impuestos" (desglose ITBIS por período).
--   - Cada RPC reporta inconsistencias (NCF inválido, RNC faltante en
--     crédito fiscal, etc.) para que el cliente decida.
--   - RLS: sólo admin/accountant ejecutan (policy en
--     `fiscal_dgii_reports` lo refuerza también).

begin;

-- =====================================================
-- 1) Helper: detectar NCF válido (formato fiscal RD)
-- =====================================================

create or replace function public.is_valid_ncf(p_ncf text)
returns boolean
language sql
immutable
as $$
  -- Formato moderno B01-NNNNNNNN o legacy A0100000001 (12 chars)
  select p_ncf ~ '^[BAE][0-9]{2}-?[0-9]{8,10}$';
$$;

-- =====================================================
-- 2) RPC: dgii_606_data — Compras del mes con NCF
-- =====================================================

create or replace function public.dgii_606_data(
  p_year integer,
  p_month integer,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_period text;
  v_rnc text;
  v_rows jsonb;
  v_inconsistencies jsonb;
  v_total_count integer;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada';
  end if;

  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant pueden generar reportes fiscales';
  end if;

  if p_month < 1 or p_month > 12 then
    raise exception 'Mes inválido (1-12)';
  end if;

  v_period := lpad(p_year::text, 4, '0') || lpad(p_month::text, 2, '0');

  -- RNC del negocio desde app_settings
  select coalesce(company_tax_id, '')::text into v_rnc
    from public.app_settings where id = 1;

  with month_purchases as (
    select
      p.id,
      p.branch_id,
      p.purchase_date,
      p.invoice_number,
      p.subtotal,
      p.tax_amount,
      p.total_amount,
      p.supplier_document_type,
      p.supplier_document_number,
      p.receipt_type,
      s.rnc as supplier_rnc,
      s.legal_name as supplier_name
    from public.purchases p
    join public.suppliers s on s.id = p.supplier_id and s.branch_id = p.branch_id
    where p.branch_id = v_branch_id
      and p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
      and extract(year from p.purchase_date) = p_year
      and extract(month from p.purchase_date) = p_month
  ),
  valid_rows as (
    select * from month_purchases
    where invoice_number is not null
      and public.is_valid_ncf(invoice_number)
      and supplier_rnc is not null
      and supplier_rnc <> ''
  ),
  invalid_rows as (
    select *,
      case
        when invoice_number is null then 'NCF faltante'
        when not public.is_valid_ncf(invoice_number) then 'NCF inválido'
        when supplier_rnc is null or supplier_rnc = '' then 'RNC de proveedor faltante'
        else 'Otra inconsistencia'
      end as reason
    from month_purchases
    where invoice_number is null
       or not public.is_valid_ncf(invoice_number)
       or supplier_rnc is null
       or supplier_rnc = ''
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'rnc_proveedor', supplier_rnc,
      'tipo_id', case when length(coalesce(supplier_rnc, '')) >= 11 then '2' else '1' end,
      'tipo_bien_servicio', '09',
      'ncf', invoice_number,
      'ncf_modificado', null,
      'fecha_comprobante', to_char(purchase_date, 'YYYYMMDD'),
      'fecha_pago', to_char(purchase_date, 'YYYYMMDD'),
      'monto_facturado', subtotal,
      'itbis_facturado', tax_amount,
      'monto_total', total_amount,
      'supplier_name', supplier_name
    ) order by purchase_date), '[]'::jsonb)
    into v_rows
    from valid_rows;

  select coalesce(jsonb_agg(jsonb_build_object(
    'purchase_id', id,
    'purchase_date', purchase_date,
    'supplier_name', supplier_name,
    'invoice_number', invoice_number,
    'reason', reason
  )), '[]'::jsonb)
  into v_inconsistencies
  from invalid_rows;

  select count(*) into v_total_count from valid_rows;

  return jsonb_build_object(
    'report_type', '606',
    'period', v_period,
    'rnc_negocio', v_rnc,
    'records_count', v_total_count,
    'rows', v_rows,
    'inconsistencies', v_inconsistencies,
    'inconsistencies_count', jsonb_array_length(v_inconsistencies)
  );
end;
$$;

grant execute on function public.dgii_606_data(integer, integer, uuid) to authenticated;

-- =====================================================
-- 3) RPC: dgii_607_data — Ventas del mes con NCF
-- =====================================================

create or replace function public.dgii_607_data(
  p_year integer,
  p_month integer,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_period text;
  v_rnc text;
  v_rows jsonb;
  v_inconsistencies jsonb;
  v_total_count integer;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada';
  end if;

  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant pueden generar reportes fiscales';
  end if;

  if p_month < 1 or p_month > 12 then
    raise exception 'Mes inválido (1-12)';
  end if;

  v_period := lpad(p_year::text, 4, '0') || lpad(p_month::text, 2, '0');

  select coalesce(company_tax_id, '')::text into v_rnc
    from public.app_settings where id = 1;

  with month_sales as (
    select
      s.id,
      s.branch_id,
      s.sale_date,
      s.sale_number,
      s.ncf,
      s.receipt_type,
      s.client_id,
      s.subtotal,
      s.tax_amount,
      s.total_amount,
      s.paid_amount,
      s.balance_due,
      s.status,
      c.document_number as client_doc,
      c.document_type as client_doc_type,
      c.full_name as client_name,
      -- Tipo de ingreso DGII (regla simplificada por receipt_type)
      case s.receipt_type
        when 'consumer_final' then '02'   -- Operaciones a consumidores finales
        when 'fiscal_credit'  then '01'   -- Ventas a contribuyentes
        when 'governmental'   then '06'   -- Operaciones gubernamentales
        when 'special'        then '03'   -- Régimen especial
        when 'export'         then '04'   -- Exportaciones
        else '02'
      end as tipo_ingreso
    from public.sales s
    left join public.clients c on c.id = s.client_id and c.branch_id = s.branch_id
    where s.branch_id = v_branch_id
      and s.status in ('completed'::public.sale_status, 'credit'::public.sale_status)
      and extract(year from s.sale_date) = p_year
      and extract(month from s.sale_date) = p_month
  ),
  valid_rows as (
    select * from month_sales
    where ncf is not null
      and public.is_valid_ncf(ncf)
      -- Crédito fiscal exige cliente con documento
      and (receipt_type <> 'fiscal_credit'::public.receipt_type
           or (client_doc is not null and client_doc <> ''))
  ),
  invalid_rows as (
    select *,
      case
        when ncf is null then 'NCF faltante'
        when not public.is_valid_ncf(coalesce(ncf, '')) then 'NCF inválido'
        when receipt_type = 'fiscal_credit'::public.receipt_type
             and (client_doc is null or client_doc = '')
          then 'Crédito fiscal sin documento de cliente'
        else 'Otra inconsistencia'
      end as reason
    from month_sales
    where ncf is null
       or not public.is_valid_ncf(coalesce(ncf, ''))
       or (receipt_type = 'fiscal_credit'::public.receipt_type
           and (client_doc is null or client_doc = ''))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'rnc_cliente', client_doc,
    'tipo_id', case when length(coalesce(client_doc, '')) >= 11 then '2'
                    when length(coalesce(client_doc, '')) >= 9 then '1'
                    else '3' end,
    'ncf', ncf,
    'ncf_modificado', null,
    'tipo_ingreso', tipo_ingreso,
    'fecha_comprobante', to_char(sale_date, 'YYYYMMDD'),
    'monto_facturado', subtotal,
    'itbis_facturado', tax_amount,
    'monto_total', total_amount,
    'efectivo', case when status = 'completed' then paid_amount else 0 end,
    'credito', case when status = 'credit' then total_amount else balance_due end,
    'client_name', client_name
  ) order by sale_date), '[]'::jsonb)
  into v_rows
  from valid_rows;

  select coalesce(jsonb_agg(jsonb_build_object(
    'sale_id', id,
    'sale_date', sale_date,
    'sale_number', sale_number,
    'client_name', client_name,
    'ncf', ncf,
    'reason', reason
  )), '[]'::jsonb)
  into v_inconsistencies
  from invalid_rows;

  select count(*) into v_total_count from valid_rows;

  return jsonb_build_object(
    'report_type', '607',
    'period', v_period,
    'rnc_negocio', v_rnc,
    'records_count', v_total_count,
    'rows', v_rows,
    'inconsistencies', v_inconsistencies,
    'inconsistencies_count', jsonb_array_length(v_inconsistencies)
  );
end;
$$;

grant execute on function public.dgii_607_data(integer, integer, uuid) to authenticated;

-- =====================================================
-- 4) RPC: dgii_it1_summary — Resumen IT-1 (ITBIS mensual)
-- =====================================================

create or replace function public.dgii_it1_summary(
  p_year integer,
  p_month integer,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_period text;
  v_rnc text;
  v_sales_total numeric(14,2) := 0;
  v_sales_taxable numeric(14,2) := 0;
  v_sales_exempt numeric(14,2) := 0;
  v_itbis_received numeric(14,2) := 0;
  v_purchases_total numeric(14,2) := 0;
  v_itbis_paid numeric(14,2) := 0;
  v_returns_total numeric(14,2) := 0;
  v_returns_itbis numeric(14,2) := 0;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada';
  end if;

  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant pueden generar reportes fiscales';
  end if;

  v_period := lpad(p_year::text, 4, '0') || lpad(p_month::text, 2, '0');

  select coalesce(company_tax_id, '')::text into v_rnc
    from public.app_settings where id = 1;

  -- Ventas + ITBIS recibido
  select
    coalesce(sum(total_amount), 0),
    coalesce(sum(taxable_amount), 0),
    coalesce(sum(exempt_amount), 0),
    coalesce(sum(tax_amount), 0)
  into v_sales_total, v_sales_taxable, v_sales_exempt, v_itbis_received
  from public.sales
  where branch_id = v_branch_id
    and status in ('completed'::public.sale_status, 'credit'::public.sale_status)
    and extract(year from sale_date) = p_year
    and extract(month from sale_date) = p_month;

  -- Compras + ITBIS pagado
  select
    coalesce(sum(total_amount), 0),
    coalesce(sum(tax_amount), 0)
  into v_purchases_total, v_itbis_paid
  from public.purchases
  where branch_id = v_branch_id
    and status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
    and extract(year from purchase_date) = p_year
    and extract(month from purchase_date) = p_month;

  -- Devoluciones del período
  select
    coalesce(sum(total_amount), 0),
    coalesce(sum(tax_amount), 0)
  into v_returns_total, v_returns_itbis
  from public.returns
  where branch_id = v_branch_id
    and extract(year from return_date) = p_year
    and extract(month from return_date) = p_month;

  return jsonb_build_object(
    'report_type', 'IT1',
    'period', v_period,
    'rnc_negocio', v_rnc,
    'sales_total', v_sales_total,
    'sales_taxable', v_sales_taxable,
    'sales_exempt', v_sales_exempt,
    'itbis_received', v_itbis_received,
    'purchases_total', v_purchases_total,
    'itbis_paid', v_itbis_paid,
    'returns_total', v_returns_total,
    'returns_itbis', v_returns_itbis,
    'itbis_balance', v_itbis_received - v_itbis_paid - v_returns_itbis,
    'balance_direction',
      case
        when (v_itbis_received - v_itbis_paid - v_returns_itbis) > 0 then 'pagar'
        when (v_itbis_received - v_itbis_paid - v_returns_itbis) < 0 then 'favor'
        else 'cero' end
  );
end;
$$;

grant execute on function public.dgii_it1_summary(integer, integer, uuid) to authenticated;

-- =====================================================
-- 5) Impuestos — vista de desglose por tasa
-- =====================================================

create or replace view public.report_tax_breakdown_view
with (security_invoker = true)
as
select
  si.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  si.tax_rate,
  count(distinct si.sale_id)::bigint as sales_count,
  sum(si.quantity)::numeric(14,3) as items_count,
  sum(si.line_subtotal)::numeric(14,2) as taxable_base,
  sum(si.line_tax)::numeric(14,2) as tax_amount,
  sum(si.line_total)::numeric(14,2) as total_with_tax
from public.sale_items si
join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
where s.status = 'completed'::public.sale_status
  and public.has_branch_access(si.branch_id)
group by si.branch_id, date(s.sale_date at time zone 'America/Santo_Domingo'), si.tax_rate;

grant select on public.report_tax_breakdown_view to authenticated;

-- =====================================================
-- 6) Helper: registrar un reporte DGII generado (audit)
-- =====================================================

create or replace function public.record_dgii_report(
  p_report_type text,
  p_year integer,
  p_month integer,
  p_records_count integer,
  p_inconsistencies_count integer,
  p_storage_path text default null,
  p_txt_url text default null,
  p_pdf_url text default null,
  p_inconsistencies jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant';
  end if;

  insert into public.fiscal_dgii_reports (
    report_type, period_year, period_month, generated_by,
    records_count, inconsistencies_count, inconsistencies,
    txt_file_url, pdf_file_url, storage_path, status
  ) values (
    p_report_type::public.fiscal_dgii_report_type,
    p_year, p_month, auth.uid(),
    p_records_count, p_inconsistencies_count, p_inconsistencies,
    p_txt_url, p_pdf_url, p_storage_path, 'generated'
  )
  on conflict (report_type, period_year, period_month) do update set
    generated_at = timezone('utc', now()),
    generated_by = auth.uid(),
    records_count = excluded.records_count,
    inconsistencies_count = excluded.inconsistencies_count,
    inconsistencies = excluded.inconsistencies,
    txt_file_url = coalesce(excluded.txt_file_url, public.fiscal_dgii_reports.txt_file_url),
    pdf_file_url = coalesce(excluded.pdf_file_url, public.fiscal_dgii_reports.pdf_file_url),
    storage_path = coalesce(excluded.storage_path, public.fiscal_dgii_reports.storage_path)
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.record_dgii_report(text, integer, integer, integer, integer, text, text, text, jsonb) to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260509_14_dgii_reports.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260509_15_realtime_report_views.sql
-- ============================================================
-- 20260509_15_realtime_report_views.sql
-- Shop+ RD - PRD 07 fix crítico: las vistas operativas envolvían
-- materialized views que sólo se refrescan via `refresh_business_reports()`.
-- Eso causaba que ventas/compras del día no aparecieran en /reportes
-- hasta que alguien refrescara las MVs manualmente.
--
-- Esta migración reescribe las vistas para que lean directamente de las
-- tablas transaccionales (real-time). Las MVs en sí se mantienen para uso
-- futuro en analítica de gran escala, pero las vistas operativas no las
-- consumen.
--
-- Ejecutar después de:
--   supabase/sql-next/20260509_14_dgii_reports.sql

begin;

-- =====================================================
-- 1) sales_daily_view → real-time desde `sales`
-- =====================================================

create or replace view public.sales_daily_view
with (security_invoker = true)
as
select
  s.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  coalesce(s.seller_id, s.cashier_id) as seller_user_id,
  s.receipt_type,
  count(*)::bigint as sales_count,
  coalesce(sum(s.subtotal), 0)::numeric(14,2) as gross_total,
  coalesce(sum(s.tax_amount), 0)::numeric(14,2) as itbis_total,
  coalesce(sum(s.service_charge_amount), 0)::numeric(14,2) as service_charge_total,
  coalesce(sum(s.discount_amount), 0)::numeric(14,2) as discount_total,
  coalesce(sum(s.total_amount), 0)::numeric(14,2) as net_total
from public.sales s
where s.status = 'completed'::public.sale_status
  and public.has_branch_access(s.branch_id)
group by 1, 2, 3, 4;

-- =====================================================
-- 2) sales_by_item_view → real-time
-- =====================================================

create or replace view public.sales_by_item_view
with (security_invoker = true)
as
select
  si.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  si.product_id,
  coalesce(p.name, si.description) as product_name,
  coalesce(sum(si.quantity), 0)::numeric(14,3) as units_sold,
  coalesce(sum(si.line_subtotal), 0)::numeric(14,2) as gross_total,
  coalesce(sum(si.line_tax), 0)::numeric(14,2) as itbis_total,
  coalesce(sum(si.line_total), 0)::numeric(14,2) as net_total,
  count(distinct si.sale_id)::bigint as sales_count
from public.sale_items si
join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
left join public.products p
  on p.id = si.product_id and p.branch_id = si.branch_id
where s.status = 'completed'::public.sale_status
  and public.has_branch_access(si.branch_id)
group by 1, 2, 3, 4;

-- =====================================================
-- 3) sales_by_category_view → real-time
-- =====================================================

create or replace view public.sales_by_category_view
with (security_invoker = true)
as
select
  si.branch_id,
  date(s.sale_date at time zone 'America/Santo_Domingo') as sale_day,
  coalesce(si.category_id, p.category_id) as category_id,
  coalesce(si.category_name_snapshot, pc.name, 'Sin categoría') as category_name,
  coalesce(sum(si.quantity), 0)::numeric(14,3) as units_sold,
  coalesce(sum(si.line_subtotal), 0)::numeric(14,2) as gross_total,
  coalesce(sum(si.line_tax), 0)::numeric(14,2) as itbis_total,
  coalesce(sum(si.line_total), 0)::numeric(14,2) as net_total
from public.sale_items si
join public.sales s on s.id = si.sale_id and s.branch_id = si.branch_id
left join public.products p on p.id = si.product_id and p.branch_id = si.branch_id
left join public.product_categories pc
  on pc.id = coalesce(si.category_id, p.category_id)
  and pc.branch_id = si.branch_id
where s.status = 'completed'::public.sale_status
  and public.has_branch_access(si.branch_id)
group by 1, 2, 3, 4;

-- =====================================================
-- 4) purchases_daily_view → real-time
-- =====================================================

create or replace view public.purchases_daily_view
with (security_invoker = true)
as
select
  p.branch_id,
  p.purchase_date,
  p.supplier_id,
  count(*)::bigint as purchases_count,
  coalesce(sum(p.subtotal), 0)::numeric(14,2) as subtotal_total,
  coalesce(sum(p.discount_amount), 0)::numeric(14,2) as discount_total,
  coalesce(sum(p.tax_amount), 0)::numeric(14,2) as tax_total,
  coalesce(sum(p.total_amount), 0)::numeric(14,2) as grand_total
from public.purchases p
where p.status in ('posted'::public.purchase_status, 'received'::public.purchase_status)
  and public.has_branch_access(p.branch_id)
group by 1, 2, 3;

-- =====================================================
-- 5) inventory_movements_daily_view → real-time
-- =====================================================

create or replace view public.inventory_movements_daily_view
with (security_invoker = true)
as
select
  im.branch_id,
  date(im.occurred_at at time zone 'America/Santo_Domingo') as movement_day,
  im.movement_type,
  im.product_id,
  coalesce(sum(im.quantity), 0)::numeric(14,3) as total_quantity,
  coalesce(sum(im.quantity * im.unit_cost), 0)::numeric(14,2) as total_cost,
  count(*)::bigint as movements_count
from public.inventory_movements im
where public.has_branch_access(im.branch_id)
group by 1, 2, 3, 4;

-- =====================================================
-- 6) cash_session_summary_view → real-time
-- =====================================================

create or replace view public.cash_session_summary_view
with (security_invoker = true)
as
select
  cs.id as cash_session_id,
  cs.branch_id,
  cs.opened_by,
  cs.closed_by,
  cs.status,
  cs.opened_at,
  cs.closed_at,
  cs.opening_amount,
  cs.expected_amount,
  cs.closing_amount,
  cs.difference_amount,
  count(distinct s.id) filter (where s.status = 'completed'::public.sale_status)::bigint as sales_completed,
  count(distinct s.id) filter (where s.status = 'voided'::public.sale_status)::bigint as sales_voided,
  coalesce(sum(s.total_amount) filter (where s.status = 'completed'::public.sale_status), 0)::numeric(14,2) as sales_total,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'cash'::public.payment_method), 0)::numeric(14,2) as cash_collected,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'card'::public.payment_method), 0)::numeric(14,2) as card_collected,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'transfer'::public.payment_method), 0)::numeric(14,2) as transfer_collected,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'mobile'::public.payment_method), 0)::numeric(14,2) as mobile_collected,
  coalesce(sum(pay.amount) filter (where pay.payment_method = 'credit'::public.payment_method), 0)::numeric(14,2) as credit_collected
from public.cash_sessions cs
left join public.sales s
  on s.cash_session_id = cs.id and s.branch_id = cs.branch_id
left join public.payments pay
  on pay.cash_session_id = cs.id and pay.branch_id = cs.branch_id
where public.has_branch_access(cs.branch_id)
group by cs.id, cs.branch_id, cs.opened_by, cs.closed_by, cs.status,
         cs.opened_at, cs.closed_at, cs.opening_amount, cs.expected_amount,
         cs.closing_amount, cs.difference_amount;

commit;

-- ============================================================
-- END:   sql-next/20260509_15_realtime_report_views.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260509_16_operational_extensions.sql
-- ============================================================
-- 20260509_16_operational_extensions.sql
-- Shop+ RD - Sprint Facturación 2026-05.
--
-- Esta migración prepara backend para:
--   F3 — Adición de efectivo a la caja activa (cash_register_movements).
--   F8 — Módulo de caja chica (petty_cash_*).
--   F9 — Precio por cliente (helper de tier — todas las columnas ya
--        existen en migración 20260421).
--
-- Ejecutar después de:
--   supabase/sql-next/20260509_15_realtime_report_views.sql

begin;

-- =====================================================
-- 1) Enums
-- =====================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'cash_movement_type') then
    create type public.cash_movement_type as enum (
      'deposit',      -- inyección de efectivo a la caja
      'withdrawal',   -- sangría / retiro
      'adjustment',   -- ajuste manual (sobrante/faltante)
      'opening_top_up' -- agregar al monto de apertura
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'petty_cash_session_status') then
    create type public.petty_cash_session_status as enum ('open', 'closed');
  end if;

  if not exists (select 1 from pg_type where typname = 'petty_cash_movement_type') then
    create type public.petty_cash_movement_type as enum (
      'income',          -- ingreso (reposición o caja recibida)
      'expense',         -- gasto
      'replenishment',   -- reposición desde caja principal
      'adjustment'       -- ajuste de arqueo
    );
  end if;
end $$;

-- =====================================================
-- 2) F3 — Cash register movements (inyección/retiro a la sesión activa)
-- =====================================================

create table if not exists public.cash_register_movements (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  cash_session_id uuid not null,
  movement_type public.cash_movement_type not null,
  amount numeric(14,2) not null check (amount > 0),
  reason text,
  reference_type text,
  reference_id uuid,
  performed_by uuid references auth.users(id),
  occurred_at timestamptz not null default timezone('utc', now()),
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint cash_register_movements_session_fk
    foreign key (cash_session_id, branch_id)
    references public.cash_sessions(id, branch_id)
    on delete cascade
);

create index if not exists cash_register_movements_session_idx
  on public.cash_register_movements (cash_session_id, occurred_at desc);
create index if not exists cash_register_movements_branch_idx
  on public.cash_register_movements (branch_id, occurred_at desc);

comment on table public.cash_register_movements is
  'Movimientos manuales de efectivo dentro de una sesión de caja '
  '(inyecciones, sangrías, ajustes). Cada inserción ajusta '
  'cash_sessions.expected_amount.';

-- Trigger: ajustar expected_amount al insertar/borrar el movimiento
create or replace function public.apply_cash_register_movement()
returns trigger
language plpgsql
as $$
declare
  v_delta numeric(14,2);
begin
  if tg_op = 'INSERT' then
    v_delta := case new.movement_type
      when 'deposit'        then  new.amount
      when 'opening_top_up' then  new.amount
      when 'adjustment'     then  new.amount  -- signed positive = sobrante
      when 'withdrawal'     then -new.amount
      else 0
    end;
    update public.cash_sessions
       set expected_amount = coalesce(expected_amount, 0) + v_delta
     where id = new.cash_session_id
       and branch_id = new.branch_id;
    return new;
  end if;
  if tg_op = 'DELETE' then
    v_delta := case old.movement_type
      when 'deposit'        then  old.amount
      when 'opening_top_up' then  old.amount
      when 'adjustment'     then  old.amount
      when 'withdrawal'     then -old.amount
      else 0
    end;
    update public.cash_sessions
       set expected_amount = coalesce(expected_amount, 0) - v_delta
     where id = old.cash_session_id
       and branch_id = old.branch_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_cash_register_movements_apply on public.cash_register_movements;
create trigger trg_cash_register_movements_apply
after insert or delete on public.cash_register_movements
for each row execute function public.apply_cash_register_movement();

drop trigger if exists trg_cash_register_movements_updated_at on public.cash_register_movements;
create trigger trg_cash_register_movements_updated_at
before update on public.cash_register_movements
for each row execute function public.set_updated_at();

drop trigger if exists trg_cash_register_movements_audit on public.cash_register_movements;
create trigger trg_cash_register_movements_audit
before insert or update on public.cash_register_movements
for each row execute function public.set_audit_fields();

alter table public.cash_register_movements enable row level security;

drop policy if exists cash_register_movements_select on public.cash_register_movements;
create policy cash_register_movements_select
on public.cash_register_movements
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists cash_register_movements_insert on public.cash_register_movements;
create policy cash_register_movements_insert
on public.cash_register_movements
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists cash_register_movements_update on public.cash_register_movements;
create policy cash_register_movements_update
on public.cash_register_movements
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists cash_register_movements_delete on public.cash_register_movements;
create policy cash_register_movements_delete
on public.cash_register_movements
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.is_admin());

-- =====================================================
-- 3) F8 — Caja chica
-- =====================================================

create table if not exists public.petty_cash_categories (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  name text not null,
  description text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id)
);

-- UNIQUE en expresión `lower(name)` requiere índice (no se puede inline).
create unique index if not exists petty_cash_categories_branch_name_unique
  on public.petty_cash_categories (branch_id, lower(name));

create table if not exists public.petty_cash_sessions (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  opened_by uuid not null references auth.users(id),
  closed_by uuid references auth.users(id),
  status public.petty_cash_session_status not null default 'open',
  opened_at timestamptz not null default timezone('utc', now()),
  closed_at timestamptz,
  opening_amount numeric(14,2) not null default 0 check (opening_amount >= 0),
  expected_amount numeric(14,2) not null default 0,
  closing_amount numeric(14,2),
  difference_amount numeric(14,2),
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  unique (id, branch_id)
);

-- Solo una sesión abierta de caja chica por sucursal a la vez
create unique index if not exists petty_cash_sessions_open_unique
  on public.petty_cash_sessions (branch_id)
  where status = 'open';

create table if not exists public.petty_cash_movements (
  id uuid primary key default gen_random_uuid(),
  petty_cash_session_id uuid not null,
  branch_id uuid not null,
  movement_type public.petty_cash_movement_type not null,
  category_id uuid references public.petty_cash_categories(id) on delete set null,
  amount numeric(14,2) not null check (amount > 0),
  description text,
  payee text,
  receipt_reference text,
  occurred_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  constraint petty_cash_movements_session_fk
    foreign key (petty_cash_session_id, branch_id)
    references public.petty_cash_sessions(id, branch_id)
    on delete cascade
);

create index if not exists petty_cash_movements_session_idx
  on public.petty_cash_movements (petty_cash_session_id, occurred_at desc);
create index if not exists petty_cash_movements_category_idx
  on public.petty_cash_movements (category_id);
create index if not exists petty_cash_movements_branch_idx
  on public.petty_cash_movements (branch_id, occurred_at desc);

-- Trigger: ajustar expected_amount de la sesión por cada movimiento
create or replace function public.apply_petty_cash_movement()
returns trigger
language plpgsql
as $$
declare
  v_delta numeric(14,2);
begin
  if tg_op = 'INSERT' then
    v_delta := case new.movement_type
      when 'income'        then  new.amount
      when 'replenishment' then  new.amount
      when 'adjustment'    then  new.amount  -- positivo = sobrante; usar valor negativo en `amount` no se permite por CHECK; usar 'expense' para faltante
      when 'expense'       then -new.amount
      else 0
    end;
    update public.petty_cash_sessions
       set expected_amount = coalesce(expected_amount, 0) + v_delta
     where id = new.petty_cash_session_id
       and branch_id = new.branch_id;
    return new;
  end if;
  if tg_op = 'DELETE' then
    v_delta := case old.movement_type
      when 'income'        then  old.amount
      when 'replenishment' then  old.amount
      when 'adjustment'    then  old.amount
      when 'expense'       then -old.amount
      else 0
    end;
    update public.petty_cash_sessions
       set expected_amount = coalesce(expected_amount, 0) - v_delta
     where id = old.petty_cash_session_id
       and branch_id = old.branch_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_petty_cash_movements_apply on public.petty_cash_movements;
create trigger trg_petty_cash_movements_apply
after insert or delete on public.petty_cash_movements
for each row execute function public.apply_petty_cash_movement();

drop trigger if exists trg_petty_cash_sessions_updated_at on public.petty_cash_sessions;
create trigger trg_petty_cash_sessions_updated_at
before update on public.petty_cash_sessions
for each row execute function public.set_updated_at();

drop trigger if exists trg_petty_cash_sessions_audit on public.petty_cash_sessions;
create trigger trg_petty_cash_sessions_audit
before insert or update on public.petty_cash_sessions
for each row execute function public.set_audit_fields();

drop trigger if exists trg_petty_cash_movements_updated_at on public.petty_cash_movements;
create trigger trg_petty_cash_movements_updated_at
before update on public.petty_cash_movements
for each row execute function public.set_updated_at();

drop trigger if exists trg_petty_cash_movements_audit on public.petty_cash_movements;
create trigger trg_petty_cash_movements_audit
before insert or update on public.petty_cash_movements
for each row execute function public.set_audit_fields();

drop trigger if exists trg_petty_cash_categories_updated_at on public.petty_cash_categories;
create trigger trg_petty_cash_categories_updated_at
before update on public.petty_cash_categories
for each row execute function public.set_updated_at();

drop trigger if exists trg_petty_cash_categories_audit on public.petty_cash_categories;
create trigger trg_petty_cash_categories_audit
before insert or update on public.petty_cash_categories
for each row execute function public.set_audit_fields();

-- RLS petty_cash_categories
alter table public.petty_cash_categories enable row level security;

drop policy if exists petty_cash_categories_select on public.petty_cash_categories;
create policy petty_cash_categories_select
on public.petty_cash_categories
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists petty_cash_categories_write on public.petty_cash_categories;
create policy petty_cash_categories_write
on public.petty_cash_categories
for all
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

-- RLS petty_cash_sessions
alter table public.petty_cash_sessions enable row level security;

drop policy if exists petty_cash_sessions_select on public.petty_cash_sessions;
create policy petty_cash_sessions_select
on public.petty_cash_sessions
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists petty_cash_sessions_insert on public.petty_cash_sessions;
create policy petty_cash_sessions_insert
on public.petty_cash_sessions
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists petty_cash_sessions_update on public.petty_cash_sessions;
create policy petty_cash_sessions_update
on public.petty_cash_sessions
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_operate_pos())
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists petty_cash_sessions_delete on public.petty_cash_sessions;
create policy petty_cash_sessions_delete
on public.petty_cash_sessions
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.is_admin());

-- RLS petty_cash_movements
alter table public.petty_cash_movements enable row level security;

drop policy if exists petty_cash_movements_select on public.petty_cash_movements;
create policy petty_cash_movements_select
on public.petty_cash_movements
for select
to authenticated
using (public.has_branch_access(branch_id));

drop policy if exists petty_cash_movements_insert on public.petty_cash_movements;
create policy petty_cash_movements_insert
on public.petty_cash_movements
for insert
to authenticated
with check (public.has_branch_access(branch_id) and public.can_operate_pos());

drop policy if exists petty_cash_movements_update on public.petty_cash_movements;
create policy petty_cash_movements_update
on public.petty_cash_movements
for update
to authenticated
using (public.has_branch_access(branch_id) and public.can_manage_branch_data())
with check (public.has_branch_access(branch_id) and public.can_manage_branch_data());

drop policy if exists petty_cash_movements_delete on public.petty_cash_movements;
create policy petty_cash_movements_delete
on public.petty_cash_movements
for delete
to authenticated
using (public.has_branch_access(branch_id) and public.is_admin());

-- Seed: categorías default por sucursal. Idempotente vía el índice único
-- `petty_cash_categories_branch_name_unique`.
insert into public.petty_cash_categories (branch_id, name, description, sort_order)
select b.id, x.name, x.description, x.sort_order
  from public.branches b
  cross join (values
    ('Transporte',   'Combustible, taxi, peajes',                10),
    ('Papelería',    'Material de oficina, impresiones',          20),
    ('Limpieza',     'Productos de limpieza, mantenimiento',      30),
    ('Comida',       'Almuerzos, refrigerios para el personal',   40),
    ('Servicios',    'Pagos puntuales (mensajería, plomero…)',    50),
    ('Otros',        'Gastos varios sin categoría',               99)
  ) as x(name, description, sort_order)
on conflict (branch_id, lower(name)) do nothing;

-- =====================================================
-- 4) F9 — Helper para resolver precio por cliente
-- =====================================================
--
-- products tiene: price (base), price_tier_1, price_tier_2, price_tier_3.
-- clients tiene:  price_tier ('retail' | 'tier_1' | 'tier_2' | 'tier_3').
-- Esta función devuelve el precio efectivo dado un producto y opcional
-- cliente. Útil para POS y reportes.

create or replace function public.resolve_product_price(
  p_product_id uuid,
  p_client_id uuid default null
)
returns numeric(14,2)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_tier text;
  v_price numeric(14,2);
  v_tier_1 numeric(14,2);
  v_tier_2 numeric(14,2);
  v_tier_3 numeric(14,2);
begin
  select branch_id, price, price_tier_1, price_tier_2, price_tier_3
    into v_branch_id, v_price, v_tier_1, v_tier_2, v_tier_3
    from public.products
   where id = p_product_id;

  if v_branch_id is null then
    return null;
  end if;

  if p_client_id is null then
    return v_price;
  end if;

  select coalesce(price_tier, 'retail') into v_tier
    from public.clients
   where id = p_client_id and branch_id = v_branch_id;

  return case lower(coalesce(v_tier, 'retail'))
    when 'tier_1' then coalesce(v_tier_1, v_price)
    when 'tier_2' then coalesce(v_tier_2, v_price)
    when 'tier_3' then coalesce(v_tier_3, v_price)
    else v_price
  end;
end;
$$;

grant execute on function public.resolve_product_price(uuid, uuid) to authenticated;

-- Etiquetas legibles para los tiers (consumido por la UI; se pueden
-- personalizar editando app_settings.sale_price_types).
comment on function public.resolve_product_price(uuid, uuid) is
  'Devuelve el precio efectivo para (producto, cliente) según el tier '
  'del cliente. Si el cliente no tiene tier o el producto no tiene el '
  'tier configurado, cae al precio base.';

-- =====================================================
-- 5) Grants
-- =====================================================

grant select, insert, update, delete on public.cash_register_movements to authenticated;
grant select, insert, update, delete on public.petty_cash_sessions to authenticated;
grant select, insert, update, delete on public.petty_cash_movements to authenticated;
grant select, insert, update, delete on public.petty_cash_categories to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260509_16_operational_extensions.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260509_17_quotations_fix_and_autoexpire.sql
-- ============================================================
-- 20260509_17_quotations_fix_and_autoexpire.sql
-- Sprint Facturación 2026-05 — fixes para cotizaciones:
--
-- 1) FIX: `update_quotation_document` tenía "column reference quotation_id
--    is ambiguous" porque el RETURNS TABLE expone `quotation_id` como OUT
--    column y dentro del body había WHERE `quotation_id = target_quotation_id`
--    sin calificar. Qualificamos con el nombre de la tabla.
--
-- 2) NUEVO: función `expire_overdue_quotations()` que marca como
--    `expired` cualquier cotización cuyo `valid_until` ya pasó y aún está
--    en estados activos (draft/sent/under_review/approved). Se agenda con
--    pg_cron cada 15 minutos (si pg_cron está disponible).
--
-- Ejecutar después de:
--   supabase/sql-next/20260410_quotations_schema.sql

begin;

-- =====================================================
-- 1) Fix: ambigüedad en update_quotation_document
-- =====================================================

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
           when requested_status = 'sent' and quotations.sent_at is null then timezone('utc', now())
           else quotations.sent_at
         end,
         approved_at = case
           when requested_status = 'approved' and quotations.approved_at is null then timezone('utc', now())
           when requested_status <> 'approved' then null
           else quotations.approved_at
         end,
         rejected_at = case
           when requested_status = 'rejected' and quotations.rejected_at is null then timezone('utc', now())
           when requested_status <> 'rejected' then null
           else quotations.rejected_at
         end,
         expired_at = case
           when requested_status = 'expired' then timezone('utc', now())
           else null
         end,
         updated_by = v_user_id
   where quotations.id = target_quotation_id;

  -- FIX ambigüedad: el RETURNS TABLE expone `quotation_id` como OUT column,
  -- así que aquí calificamos con el nombre de la tabla.
  delete from public.quotation_items qi
  where qi.quotation_id = target_quotation_id;

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

-- =====================================================
-- 2) Auto-expirar cotizaciones vencidas
-- =====================================================
--
-- Marca como `expired` las cotizaciones cuyo `valid_until` ya pasó y aún
-- estén en estados activos. También deja registro en quotation_events.
-- Devuelve la cantidad de cotizaciones afectadas.

create or replace function public.expire_overdue_quotations()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  v_row record;
begin
  for v_row in
    select q.id, q.branch_id
      from public.quotations q
     where q.status in ('draft'::public.quote_status,
                        'sent'::public.quote_status,
                        'under_review'::public.quote_status,
                        'approved'::public.quote_status)
       and q.valid_until < timezone('utc', now())
       and q.converted_sale_id is null
  loop
    update public.quotations
       set status = 'expired'::public.quote_status,
           expired_at = timezone('utc', now())
     where id = v_row.id;

    insert into public.quotation_events (
      quotation_id, branch_id, event_type, payload, created_by
    ) values (
      v_row.id,
      v_row.branch_id,
      'auto_expired',
      jsonb_build_object(
        'expired_at', timezone('utc', now()),
        'source', 'expire_overdue_quotations'
      ),
      null
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

grant execute on function public.expire_overdue_quotations() to authenticated;

comment on function public.expire_overdue_quotations() is
  'Marca como expired las cotizaciones vencidas (valid_until < now) que '
  'siguen en estados activos. Llamar manualmente o agendar con pg_cron.';

-- =====================================================
-- 3) Agendar el auto-expire cada 15 min si pg_cron está disponible
-- =====================================================

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Borra job previo con el mismo nombre (idempotente).
    perform cron.unschedule('shopplus_expire_quotations')
      where exists (select 1 from cron.job where jobname = 'shopplus_expire_quotations');

    perform cron.schedule(
      'shopplus_expire_quotations',
      '*/15 * * * *',
      $cron$select public.expire_overdue_quotations();$cron$
    );

    raise notice 'pg_cron job shopplus_expire_quotations agendado cada 15 min';
  else
    raise notice 'pg_cron no está habilitado en este proyecto; usa la función '
                 'expire_overdue_quotations() manualmente o desde la UI.';
  end if;
end $$;

commit;

-- ============================================================
-- END:   sql-next/20260509_17_quotations_fix_and_autoexpire.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260513_18_ncf_autoassign.sql
-- ============================================================
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

-- ============================================================
-- END:   sql-next/20260513_18_ncf_autoassign.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260513_19_product_price_history.sql
-- ============================================================
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

-- ============================================================
-- END:   sql-next/20260513_19_product_price_history.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260520_20_product_images_bucket.sql
-- ============================================================
-- Bucket público para imágenes de productos (Supabase Storage).
--
-- Diseño:
--   - Bucket 'product_images' público (lectura abierta).
--   - Subida/actualización/borrado: solo usuarios autenticados.
--   - Path convencional: <branch_id>/<product_id>-<timestamp>.<ext>
--
-- Ejecutar después de los anteriores 01-19. Idempotente.

begin;

-- 1) Crear bucket si no existe.
insert into storage.buckets (id, name, public)
values ('product_images', 'product_images', true)
on conflict (id) do update set public = excluded.public;

-- 2) Políticas RLS sobre storage.objects para este bucket.
--    Limpiamos primero por idempotencia.
drop policy if exists "product_images_read" on storage.objects;
drop policy if exists "product_images_insert" on storage.objects;
drop policy if exists "product_images_update" on storage.objects;
drop policy if exists "product_images_delete" on storage.objects;

-- Lectura pública (bucket público).
create policy "product_images_read"
  on storage.objects for select
  using (bucket_id = 'product_images');

-- Insertar: usuarios autenticados.
create policy "product_images_insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'product_images');

-- Actualizar: usuarios autenticados.
create policy "product_images_update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'product_images')
  with check (bucket_id = 'product_images');

-- Borrar: usuarios autenticados.
create policy "product_images_delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'product_images');

commit;

-- ============================================================
-- END:   sql-next/20260520_20_product_images_bucket.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260520_21_ncf_trigger_fix.sql
-- ============================================================
-- Fix: `tg_sales_register_fiscal_document` fallaba con
--   PostgrestException(message: record "v_client" is not assigned yet,
--                       code: 55000, ...)
-- al completar ventas con NCF cuando el cliente no estaba seleccionado
-- (o cuando el SELECT no encontraba fila).
--
-- Causa raíz: `v_client record` declarado sin asignar siempre. Cuando
-- `new.client_id is null` el SELECT INTO no se ejecuta, y el INSERT
-- posterior lee `v_client.field` sobre un record indeterminado.
--
-- Arreglo: reemplazar el record por variables escalares que defaultan a
-- NULL. Mismo fix para `v_settings` por defensa.

begin;

create or replace function public.tg_sales_register_fiscal_document()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq_id              uuid;
  v_seq_number          bigint;
  v_customer_name       text;
  v_customer_legal_name text;
  v_customer_doc_type   text;
  v_customer_doc_number text;
  v_customer_address    text;
  v_issuer_name         text;
  v_issuer_legal_name   text;
  v_issuer_tax_id       text;
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

  -- Snapshot del cliente (solo si hay client_id). Las variables escalares
  -- quedan en NULL si no hay match.
  if new.client_id is not null then
    select c.full_name,
           c.legal_name,
           c.document_type::text,
           c.document_number,
           c.address
      into v_customer_name,
           v_customer_legal_name,
           v_customer_doc_type,
           v_customer_doc_number,
           v_customer_address
      from public.clients c
     where c.id = new.client_id
       and c.branch_id = new.branch_id;
  end if;

  -- Snapshot del emisor
  select company_name, company_legal_name, company_tax_id
    into v_issuer_name, v_issuer_legal_name, v_issuer_tax_id
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
    coalesce(nullif(v_customer_legal_name, ''), v_customer_name),
    v_customer_doc_type,
    v_customer_doc_number,
    v_customer_address,
    coalesce(nullif(v_issuer_legal_name, ''), v_issuer_name),
    v_issuer_tax_id,
    new.subtotal, new.discount_amount, new.tax_amount, new.total_amount,
    jsonb_build_object('sale_number', new.sale_number)
  )
  on conflict (branch_id, ncf) do nothing;

  return new;
end;
$$;

commit;

-- ============================================================
-- END:   sql-next/20260520_21_ncf_trigger_fix.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260520_22_credit_due_dates.sql
-- ============================================================
-- Plazos de crédito por venta.
--
-- Diseño:
--   1. Nuevo campo `due_date` (date) en `sales` — fecha de vencimiento del
--      crédito. Se setea automáticamente al hacer una venta a crédito (RPC
--      `checkout_sale_transactional`) sumando `app_settings.credit_default_days`
--      a la fecha de venta. Permite override por venta.
--   2. Dos campos nuevos en `app_settings`:
--        - `credit_default_days` (int, default 30): plazo estándar
--        - `credit_warn_days` (int, default 7): umbral de alerta "próximo a vencer"
--   3. Backfill: ventas a crédito existentes reciben
--      `due_date = sale_date::date + credit_default_days`.
--   4. RPC `checkout_sale_transactional` extendido con `p_credit_due_days`.
--      Si la venta no es a crédito, se ignora.
--
-- Ejecutar después de los anteriores 01-21. Idempotente.

begin;

-- 1) Columna due_date en sales -------------------------------------------------

alter table public.sales
  add column if not exists due_date date;

create index if not exists idx_sales_credit_due_date
  on public.sales (branch_id, due_date)
  where status = 'credit' and balance_due > 0;

-- 2) Settings: días default + umbral de alerta --------------------------------

alter table public.app_settings
  add column if not exists credit_default_days integer not null default 30,
  add column if not exists credit_warn_days integer not null default 7;

-- Validaciones suaves: días positivos.
alter table public.app_settings
  drop constraint if exists app_settings_credit_default_days_positive;
alter table public.app_settings
  add constraint app_settings_credit_default_days_positive
  check (credit_default_days > 0 and credit_default_days <= 365);

alter table public.app_settings
  drop constraint if exists app_settings_credit_warn_days_positive;
alter table public.app_settings
  add constraint app_settings_credit_warn_days_positive
  check (credit_warn_days >= 0 and credit_warn_days <= 90);

-- 3) Backfill de due_date en ventas a crédito sin fecha -----------------------

update public.sales s
set due_date = (s.sale_date at time zone 'UTC')::date
              + (coalesce(a.credit_default_days, 30) || ' days')::interval
from public.app_settings a
where s.status = 'credit'
  and s.balance_due > 0
  and s.due_date is null
  and a.id = 1;

-- 4) RPC extendido: acepta p_credit_due_days ----------------------------------
-- Reemplaza la firma anterior para incluir el nuevo parámetro al final.
-- El cliente puede pasar null para usar el default de app_settings.

create or replace function public.checkout_sale_transactional(
  p_items jsonb,
  p_receipt_type text default 'consumer_final',
  p_as_credit boolean default false,
  p_payment_method text default null,
  p_client_id uuid default null,
  p_notes text default null,
  p_credit_due_days integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid := public.current_branch_id();
  v_receipt_type public.receipt_type;
  v_sale_status public.sale_status;
  v_payment_method public.payment_method;
  v_sale_id uuid;
  v_sale_number text;
  v_subtotal numeric(14,2) := 0;
  v_tax_amount numeric(14,2) := 0;
  v_total_amount numeric(14,2) := 0;
  v_paid_amount numeric(14,2) := 0;
  v_balance_due numeric(14,2) := 0;
  v_open_cash_session_id uuid;
  v_client record;
  v_item record;
  v_product record;
  v_item_count integer := 0;
  v_note text;
  v_now timestamptz := timezone('utc', now());
  v_default_days integer;
  v_due_days integer;
  v_due_date date;
begin
  if v_user_id is null then
    raise exception 'Sesión inválida. Inicia sesión de nuevo.'
      using errcode = '28000';
  end if;

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada para este usuario.'
      using errcode = '22023';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'No tienes acceso a la sucursal actual.'
      using errcode = '42501';
  end if;

  if not public.can_operate_pos() then
    raise exception 'Tu rol no puede operar el POS.'
      using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No hay productos en el carrito.'
      using errcode = '22023';
  end if;

  v_receipt_type := public.normalize_receipt_type(p_receipt_type);
  v_sale_status := case when p_as_credit then 'credit'::public.sale_status else 'completed'::public.sale_status end;
  v_note := nullif(trim(coalesce(p_notes, '')), '');

  if not p_as_credit then
    begin
      v_payment_method := coalesce(nullif(trim(p_payment_method), ''), 'cash')::public.payment_method;
    exception
      when invalid_text_representation then
        raise exception 'Método de pago no soportado: %', p_payment_method
          using errcode = '22023';
    end;
  end if;

  if p_client_id is not null then
    select
      c.id,
      c.full_name,
      c.balance_due,
      c.credit_limit,
      c.is_active
    into v_client
    from public.clients c
    where c.id = p_client_id and c.branch_id = v_branch_id;

    if not found then
      raise exception 'Cliente no encontrado en la sucursal actual.'
        using errcode = '23503';
    end if;

    if not v_client.is_active then
      raise exception 'Cliente "%": cuenta inactiva.', v_client.full_name
        using errcode = '22023';
    end if;
  end if;

  if p_as_credit and p_client_id is null then
    raise exception 'Las ventas a crédito requieren un cliente.'
      using errcode = '22023';
  end if;

  -- Determinar la sesión de caja abierta en la sucursal (si la hay).
  select id into v_open_cash_session_id
  from public.cash_sessions
  where branch_id = v_branch_id and status = 'open'
  order by opened_at desc
  limit 1;

  -- Tabla temporal con los items normalizados.
  -- `on commit drop` la elimina al final de la transacción, así que no es
  -- necesario limpiar al inicio (un DELETE sin WHERE además es rechazado
  -- por Supabase en algunos esquemas de seguridad).
  create temp table if not exists tmp_checkout_items (
    product_id uuid,
    description text,
    quantity numeric(14,3),
    unit_price numeric(14,2),
    tax_rate numeric(5,2),
    line_subtotal numeric(14,2),
    line_tax numeric(14,2),
    line_total numeric(14,2)
  ) on commit drop;
  truncate tmp_checkout_items;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price
    from jsonb_array_elements(p_items) as item
  loop
    if v_item.product_id is null then
      raise exception 'Producto sin id en el carrito.'
        using errcode = '22023';
    end if;

    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Cantidad inválida en producto %', v_item.product_id
        using errcode = '22023';
    end if;

    select
      p.id,
      p.name,
      p.price,
      p.tax_rate,
      p.stock,
      p.is_active,
      p.allow_negative_stock,
      p.is_service,
      p.is_tax_exempt
    into v_product
    from public.products p
    where p.id = v_item.product_id and p.branch_id = v_branch_id;

    if not found then
      raise exception 'Producto no encontrado: %', v_item.product_id
        using errcode = '23503';
    end if;

    if not v_product.is_active then
      raise exception 'Producto "%": inactivo.', v_product.name
        using errcode = '22023';
    end if;

    if (not v_product.is_service)
       and (not coalesce(v_product.allow_negative_stock, false))
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
        using errcode = '22023';
    end if;

    insert into tmp_checkout_items (
      product_id,
      description,
      quantity,
      unit_price,
      tax_rate,
      line_subtotal,
      line_tax,
      line_total
    ) values (
      v_item.product_id,
      coalesce(nullif(v_item.description, ''), v_product.name),
      v_item.quantity,
      v_item.unit_price,
      case when v_product.is_tax_exempt then 0 else v_product.tax_rate end,
      round((v_item.unit_price * v_item.quantity)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             case when v_product.is_tax_exempt then 0 else v_product.tax_rate end / 100)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             (1 + case when v_product.is_tax_exempt then 0 else v_product.tax_rate end / 100))::numeric, 2)
    );

    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No hay productos válidos en el carrito.'
      using errcode = '22023';
  end if;

  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0)
  into v_subtotal, v_tax_amount, v_total_amount
  from tmp_checkout_items;

  v_paid_amount := case when p_as_credit then 0 else v_total_amount end;
  v_balance_due := case when p_as_credit then v_total_amount else 0 end;

  -- Calcular due_date si la venta es a crédito.
  if p_as_credit then
    select credit_default_days into v_default_days
    from public.app_settings
    where id = 1;

    v_default_days := coalesce(v_default_days, 30);
    v_due_days := coalesce(p_credit_due_days, v_default_days);

    if v_due_days <= 0 or v_due_days > 365 then
      v_due_days := v_default_days;
    end if;

    v_due_date := (v_now at time zone 'UTC')::date + (v_due_days || ' days')::interval;
  end if;

  v_sale_number := 'VTA-' || to_char(v_now at time zone 'UTC', 'YYYYMMDD-HH24MISSMS') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));

  insert into public.sales (
    branch_id,
    sale_number,
    client_id,
    cashier_id,
    receipt_type,
    status,
    sale_date,
    subtotal,
    discount_amount,
    tax_amount,
    total_amount,
    paid_amount,
    balance_due,
    notes,
    due_date
  ) values (
    v_branch_id,
    v_sale_number,
    p_client_id,
    v_user_id,
    v_receipt_type,
    v_sale_status,
    v_now,
    v_subtotal,
    0,
    v_tax_amount,
    v_total_amount,
    v_paid_amount,
    v_balance_due,
    v_note,
    v_due_date
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
    v_branch_id,
    product_id,
    description,
    quantity,
    unit_price,
    0,
    tax_rate,
    line_subtotal,
    line_tax,
    line_total
  from tmp_checkout_items
  order by product_id;

  if not p_as_credit then
    insert into public.payments (
      branch_id,
      sale_id,
      client_id,
      cash_session_id,
      payment_method,
      amount,
      paid_at,
      reference,
      notes
    ) values (
      v_branch_id,
      v_sale_id,
      p_client_id,
      v_open_cash_session_id,
      v_payment_method,
      v_total_amount,
      v_now,
      v_sale_number,
      v_note
    );
  elsif p_client_id is not null then
    update public.clients
    set balance_due = round((coalesce(balance_due, 0) + v_total_amount)::numeric, 2)
    where id = p_client_id
      and branch_id = v_branch_id;
  end if;

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'sale_number', v_sale_number,
    'branch_id', v_branch_id,
    'cash_session_id', v_open_cash_session_id,
    'receipt_type', v_receipt_type,
    'status', v_sale_status,
    'subtotal', v_subtotal,
    'tax_amount', v_tax_amount,
    'total_amount', v_total_amount,
    'paid_amount', v_paid_amount,
    'balance_due', v_balance_due,
    'due_date', v_due_date,
    'items_count', (select count(*) from tmp_checkout_items)
  );
end;
$$;

grant execute on function public.checkout_sale_transactional(jsonb, text, boolean, text, uuid, text, integer) to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260520_22_credit_due_dates.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260520_23_dgii_reports_fix.sql
-- ============================================================
-- Fix: `dgii_606_data` y `dgii_607_data` lanzaban
--   "relation \"invalid_rows\" does not exist (42P01)"
-- porque el segundo SELECT (... into v_inconsistencies) intentaba usar la
-- CTE `invalid_rows` definida en la cadena WITH del primer SELECT — y las
-- CTEs solo viven dentro de la query a la que están asociadas.
--
-- Solución: cada función produce filas, inconsistencias y conteo en UNA sola
-- query usando `jsonb_agg(...) FILTER (WHERE ...)` sobre una subquery con la
-- clasificación pre-calculada. Más eficiente además (un solo scan).
--
-- Sin cambios funcionales: el JSON resultante tiene la misma forma.
--
-- Ejecutar después de 20260509_14_dgii_reports.sql. Idempotente.

begin;

-- =====================================================
-- dgii_606_data — Compras del mes con NCF (FIX)
-- =====================================================

create or replace function public.dgii_606_data(
  p_year integer,
  p_month integer,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_period text;
  v_rnc text;
  v_rows jsonb;
  v_inconsistencies jsonb;
  v_total_count integer;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada';
  end if;

  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant pueden generar reportes fiscales';
  end if;

  if p_month < 1 or p_month > 12 then
    raise exception 'Mes inválido (1-12)';
  end if;

  v_period := lpad(p_year::text, 4, '0') || lpad(p_month::text, 2, '0');

  select coalesce(company_tax_id, '')::text into v_rnc
    from public.app_settings where id = 1;

  -- Una sola query: clasifica cada compra y agrega filas válidas /
  -- inconsistencias en paralelo usando FILTER.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rnc_proveedor', supplier_rnc,
          'tipo_id', case when length(coalesce(supplier_rnc, '')) >= 11 then '2' else '1' end,
          'tipo_bien_servicio', '09',
          'ncf', invoice_number,
          'ncf_modificado', null,
          'fecha_comprobante', to_char(purchase_date, 'YYYYMMDD'),
          'fecha_pago', to_char(purchase_date, 'YYYYMMDD'),
          'monto_facturado', subtotal,
          'itbis_facturado', tax_amount,
          'monto_total', total_amount,
          'supplier_name', supplier_name
        ) order by purchase_date
      ) filter (where is_valid),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'purchase_id', id,
          'purchase_date', purchase_date,
          'supplier_name', supplier_name,
          'invoice_number', invoice_number,
          'reason', reason
        )
      ) filter (where not is_valid),
      '[]'::jsonb
    ),
    count(*) filter (where is_valid)
  into v_rows, v_inconsistencies, v_total_count
  from (
    select
      p.id,
      p.branch_id,
      p.purchase_date,
      p.invoice_number,
      p.subtotal,
      p.tax_amount,
      p.total_amount,
      p.receipt_type,
      s.rnc as supplier_rnc,
      s.legal_name as supplier_name,
      -- Clasificación inline:
      (p.invoice_number is not null
       and public.is_valid_ncf(p.invoice_number)
       and s.rnc is not null
       and s.rnc <> '') as is_valid,
      case
        when p.invoice_number is null then 'NCF faltante'
        when not public.is_valid_ncf(p.invoice_number) then 'NCF inválido'
        when s.rnc is null or s.rnc = '' then 'RNC de proveedor faltante'
        else 'Otra inconsistencia'
      end as reason
    from public.purchases p
    join public.suppliers s
      on s.id = p.supplier_id and s.branch_id = p.branch_id
    where p.branch_id = v_branch_id
      and p.status in ('posted'::public.purchase_status,
                       'received'::public.purchase_status)
      and extract(year from p.purchase_date) = p_year
      and extract(month from p.purchase_date) = p_month
  ) classified;

  return jsonb_build_object(
    'report_type', '606',
    'period', v_period,
    'rnc_negocio', v_rnc,
    'records_count', v_total_count,
    'rows', v_rows,
    'inconsistencies', v_inconsistencies,
    'inconsistencies_count', jsonb_array_length(v_inconsistencies)
  );
end;
$$;

grant execute on function public.dgii_606_data(integer, integer, uuid) to authenticated;

-- =====================================================
-- dgii_607_data — Ventas del mes con NCF (FIX)
-- =====================================================

create or replace function public.dgii_607_data(
  p_year integer,
  p_month integer,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_period text;
  v_rnc text;
  v_rows jsonb;
  v_inconsistencies jsonb;
  v_total_count integer;
begin
  v_branch_id := coalesce(p_branch_id, public.current_branch_id());

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada';
  end if;

  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant pueden generar reportes fiscales';
  end if;

  if p_month < 1 or p_month > 12 then
    raise exception 'Mes inválido (1-12)';
  end if;

  v_period := lpad(p_year::text, 4, '0') || lpad(p_month::text, 2, '0');

  select coalesce(company_tax_id, '')::text into v_rnc
    from public.app_settings where id = 1;

  -- Una sola query: clasifica cada venta y agrega filas válidas /
  -- inconsistencias en paralelo usando FILTER.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rnc_cliente', client_doc,
          'tipo_id', case
                       when length(coalesce(client_doc, '')) >= 11 then '2'
                       when length(coalesce(client_doc, '')) >= 9 then '1'
                       else '3'
                     end,
          'ncf', ncf,
          'ncf_modificado', null,
          'tipo_ingreso', tipo_ingreso,
          'fecha_comprobante', to_char(sale_date, 'YYYYMMDD'),
          'monto_facturado', subtotal,
          'itbis_facturado', tax_amount,
          'monto_total', total_amount,
          'efectivo', case when status = 'completed' then paid_amount else 0 end,
          'credito', case when status = 'credit' then total_amount else balance_due end,
          'client_name', client_name
        ) order by sale_date
      ) filter (where is_valid),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'sale_id', id,
          'sale_date', sale_date,
          'sale_number', sale_number,
          'client_name', client_name,
          'ncf', ncf,
          'reason', reason
        )
      ) filter (where not is_valid),
      '[]'::jsonb
    ),
    count(*) filter (where is_valid)
  into v_rows, v_inconsistencies, v_total_count
  from (
    select
      s.id,
      s.branch_id,
      s.sale_date,
      s.sale_number,
      s.ncf,
      s.receipt_type,
      s.client_id,
      s.subtotal,
      s.tax_amount,
      s.total_amount,
      s.paid_amount,
      s.balance_due,
      s.status,
      c.document_number as client_doc,
      c.document_type as client_doc_type,
      c.full_name as client_name,
      case s.receipt_type
        when 'consumer_final' then '02'
        when 'fiscal_credit'  then '01'
        when 'governmental'   then '06'
        when 'special'        then '03'
        when 'export'         then '04'
        else '02'
      end as tipo_ingreso,
      -- Clasificación inline:
      (s.ncf is not null
       and public.is_valid_ncf(s.ncf)
       and (s.receipt_type <> 'fiscal_credit'::public.receipt_type
            or (c.document_number is not null
                and c.document_number <> ''))) as is_valid,
      case
        when s.ncf is null then 'NCF faltante'
        when not public.is_valid_ncf(coalesce(s.ncf, '')) then 'NCF inválido'
        when s.receipt_type = 'fiscal_credit'::public.receipt_type
             and (c.document_number is null or c.document_number = '')
          then 'Crédito fiscal sin documento de cliente'
        else 'Otra inconsistencia'
      end as reason
    from public.sales s
    left join public.clients c
      on c.id = s.client_id and c.branch_id = s.branch_id
    where s.branch_id = v_branch_id
      and s.status in ('completed'::public.sale_status,
                       'credit'::public.sale_status)
      and extract(year from s.sale_date) = p_year
      and extract(month from s.sale_date) = p_month
  ) classified;

  return jsonb_build_object(
    'report_type', '607',
    'period', v_period,
    'rnc_negocio', v_rnc,
    'records_count', v_total_count,
    'rows', v_rows,
    'inconsistencies', v_inconsistencies,
    'inconsistencies_count', jsonb_array_length(v_inconsistencies)
  );
end;
$$;

grant execute on function public.dgii_607_data(integer, integer, uuid) to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260520_23_dgii_reports_fix.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260520_24_enable_realtime_inventory.sql
-- ============================================================
-- 20260520_24_enable_realtime_inventory.sql
-- Habilitar actualizaciones en tiempo real para la tabla de productos y categorías de productos de forma segura.

do $$
begin
  -- Asegurar que la publicación supabase_realtime exista
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end;
$$;

-- Intentar agregar la tabla products a la publicación
do $$
begin
  alter publication supabase_realtime add table public.products;
exception
  when duplicate_object then
    null;
end;
$$;

-- Intentar agregar la tabla product_categories a la publicación
do $$
begin
  alter publication supabase_realtime add table public.product_categories;
exception
  when duplicate_object then
    null;
end;
$$;

-- ============================================================
-- END:   sql-next/20260520_24_enable_realtime_inventory.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260520_25_edit_sale_rpc.sql
-- ============================================================
-- RPC para editar una venta completada/a crédito DESPUÉS de emitirla.
--
-- Permite cambiar:
--   - Items (agregar, quitar, modificar cantidad/precio/descuento)
--   - Notas
--   - Cliente asignado
--
-- NO cambia:
--   - sale_number, sale_date, cashier_id (auditoría)
--   - NCF (fiscalidad — si necesita corregir un NCF, usar nota de crédito)
--   - receipt_type, status, due_date
--
-- Stock: se restaura la cantidad vieja en todos los items y se aplica la
-- nueva. Todo dentro de una transacción para que no quede inconsistente.
--
-- Recálculo: subtotal, tax_amount, total_amount, balance_due se vuelven a
-- computar desde los nuevos items. paid_amount se preserva tal cual; si el
-- nuevo total < paid se considera un sobre-pago (balance_due = 0).
--
-- Si la venta es a crédito, se ajusta `clients.balance_due` por la
-- diferencia (nuevo total − viejo total).
--
-- Solo admin / supervisor pueden ejecutarla — los cajeros no.
--
-- Idempotente. Reemplaza la función si ya existe.

begin;

create or replace function public.edit_sale_transactional(
  p_sale_id uuid,
  p_items jsonb,
  p_client_id uuid default null,
  p_clear_client boolean default false,
  p_notes text default null,
  p_clear_notes boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid;
  v_sale record;
  v_old_total numeric(14,2);
  v_old_client_id uuid;
  v_item record;
  v_product record;
  v_subtotal numeric(14,2) := 0;
  v_tax_amount numeric(14,2) := 0;
  v_total_amount numeric(14,2) := 0;
  v_balance_due numeric(14,2);
  v_note text;
  v_target_client uuid;
  v_item_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Sesión inválida.' using errcode = '28000';
  end if;

  if not public.is_admin()
     and public.current_user_role() <> 'supervisor'::public.app_role then
    raise exception 'Solo admin o supervisor pueden editar ventas.'
      using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no puede quedar sin items.'
      using errcode = '22023';
  end if;

  -- Bloqueo de la fila para evitar ediciones concurrentes.
  select id, branch_id, status, total_amount, paid_amount, client_id, notes
  into v_sale
  from public.sales
  where id = p_sale_id
  for update;

  if not found then
    raise exception 'Venta % no encontrada.', p_sale_id
      using errcode = '23503';
  end if;

  if v_sale.status = 'voided'::public.sale_status then
    raise exception 'No se puede editar una venta anulada.'
      using errcode = '22023';
  end if;

  v_branch_id := v_sale.branch_id;
  v_old_total := coalesce(v_sale.total_amount, 0);
  v_old_client_id := v_sale.client_id;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'No tienes acceso a la sucursal de esta venta.'
      using errcode = '42501';
  end if;

  -- Resolver cliente final.
  if p_clear_client then
    v_target_client := null;
  elsif p_client_id is not null then
    v_target_client := p_client_id;
  else
    v_target_client := v_old_client_id;
  end if;

  -- Validar cliente nuevo si cambió.
  if v_target_client is not null and v_target_client is distinct from v_old_client_id then
    if not exists (
      select 1 from public.clients
      where id = v_target_client and branch_id = v_branch_id and is_active
    ) then
      raise exception 'Cliente nuevo no válido para esta sucursal.'
        using errcode = '23503';
    end if;
  end if;

  -- Resolver notas.
  if p_clear_notes then
    v_note := null;
  elsif p_notes is not null then
    v_note := nullif(trim(p_notes), '');
  else
    v_note := v_sale.notes;
  end if;

  -- 1) Restaurar stock de los items viejos.
  --    Solo productos físicos (track_inventory true e is_service false).
  update public.products p
  set stock = round(
    (coalesce(p.stock, 0) + si.quantity)::numeric(14, 3),
    3
  )
  from public.sale_items si
  where si.sale_id = p_sale_id
    and p.id = si.product_id
    and p.branch_id = v_branch_id
    and coalesce(p.is_service, false) = false
    and coalesce(p.track_inventory, true) = true;

  -- 2) Borrar los items viejos.
  delete from public.sale_items where sale_id = p_sale_id;

  -- 3) Tabla temporal con items normalizados.
  create temp table if not exists tmp_edit_items (
    product_id uuid,
    description text,
    quantity numeric(14,3),
    unit_price numeric(14,2),
    discount_amount numeric(14,2),
    tax_rate numeric(5,2),
    line_subtotal numeric(14,2),
    line_tax numeric(14,2),
    line_total numeric(14,2)
  ) on commit drop;
  truncate tmp_edit_items;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price,
      coalesce((item->>'discount_pct')::numeric, 0)::numeric(5,2) as discount_pct
    from jsonb_array_elements(p_items) as item
  loop
    if v_item.product_id is null then
      raise exception 'Producto sin id en la edición.'
        using errcode = '22023';
    end if;
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Cantidad inválida en producto %', v_item.product_id
        using errcode = '22023';
    end if;
    if v_item.discount_pct < 0 or v_item.discount_pct > 100 then
      raise exception 'Descuento fuera de rango (0-100).'
        using errcode = '22023';
    end if;

    select p.id, p.name, p.price, p.tax_rate, p.stock,
           p.is_active, p.allow_negative_stock, p.is_service,
           p.is_tax_exempt, p.track_inventory
    into v_product
    from public.products p
    where p.id = v_item.product_id and p.branch_id = v_branch_id;

    if not found then
      raise exception 'Producto no encontrado: %', v_item.product_id
        using errcode = '23503';
    end if;
    if not v_product.is_active then
      raise exception 'Producto "%": inactivo.', v_product.name
        using errcode = '22023';
    end if;

    -- Validación de stock (stock ya restaurado, así que comparamos contra
    -- el stock actualizado).
    if (not v_product.is_service)
       and (not coalesce(v_product.allow_negative_stock, false))
       and coalesce(v_product.track_inventory, true)
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
        using errcode = '22023';
    end if;

    declare
      v_rate numeric(5,2) := case
        when v_product.is_tax_exempt then 0
        else v_product.tax_rate
      end;
      v_gross numeric(14,2) := round(
        (v_item.unit_price * v_item.quantity)::numeric, 2
      );
      v_disc numeric(14,2) := round(
        (v_item.unit_price * v_item.quantity * v_item.discount_pct / 100)::numeric,
        2
      );
      v_sub numeric(14,2);
      v_tax numeric(14,2);
    begin
      v_sub := round((v_gross - v_disc)::numeric, 2);
      v_tax := round((v_sub * v_rate / 100)::numeric, 2);

      insert into tmp_edit_items (
        product_id,
        description,
        quantity,
        unit_price,
        discount_amount,
        tax_rate,
        line_subtotal,
        line_tax,
        line_total
      ) values (
        v_item.product_id,
        coalesce(nullif(v_item.description, ''), v_product.name),
        v_item.quantity,
        v_item.unit_price,
        v_disc,
        v_rate,
        v_sub,
        v_tax,
        round((v_sub + v_tax)::numeric, 2)
      );
    end;

    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No se procesó ningún item válido.'
      using errcode = '22023';
  end if;

  -- 4) Aplicar el nuevo stock (deducir cantidad nueva).
  update public.products p
  set stock = round(
    (coalesce(p.stock, 0) - tei.quantity)::numeric(14, 3),
    3
  )
  from tmp_edit_items tei
  where p.id = tei.product_id
    and p.branch_id = v_branch_id
    and coalesce(p.is_service, false) = false
    and coalesce(p.track_inventory, true) = true;

  -- 5) Insertar los nuevos items.
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
    p_sale_id,
    v_branch_id,
    product_id,
    description,
    quantity,
    unit_price,
    discount_amount,
    tax_rate,
    line_subtotal,
    line_tax,
    line_total
  from tmp_edit_items
  order by product_id;

  -- 6) Recalcular totales desde tmp_edit_items.
  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0)
  into v_subtotal, v_tax_amount, v_total_amount
  from tmp_edit_items;

  -- 7) balance_due = nuevo total − pagado (no negativo).
  v_balance_due := greatest(
    round((v_total_amount - coalesce(v_sale.paid_amount, 0))::numeric, 2),
    0
  );

  -- 8) Actualizar la fila sales (sin tocar sale_number, sale_date, NCF,
  --    cashier_id, receipt_type, status, due_date).
  update public.sales
  set
    subtotal = v_subtotal,
    tax_amount = v_tax_amount,
    total_amount = v_total_amount,
    balance_due = v_balance_due,
    client_id = v_target_client,
    notes = v_note,
    updated_at = timezone('utc', now())
  where id = p_sale_id;

  -- 9) Ajustar clients.balance_due por la diferencia.
  --    Caso A: cliente cambia → restar todo el viejo total al cliente
  --    anterior, sumar nuevo total al nuevo cliente (si la venta es de
  --    crédito o tiene balance pendiente).
  --    Caso B: mismo cliente → ajustar por diferencia.
  if v_sale.status = 'credit'::public.sale_status
     or v_balance_due > 0 then
    if v_old_client_id is distinct from v_target_client then
      if v_old_client_id is not null then
        update public.clients
        set balance_due = greatest(
          round((coalesce(balance_due, 0) - v_old_total)::numeric, 2),
          0
        )
        where id = v_old_client_id and branch_id = v_branch_id;
      end if;
      if v_target_client is not null then
        update public.clients
        set balance_due = round(
          (coalesce(balance_due, 0) + v_total_amount)::numeric, 2
        )
        where id = v_target_client and branch_id = v_branch_id;
      end if;
    elsif v_target_client is not null then
      update public.clients
      set balance_due = greatest(
        round(
          (coalesce(balance_due, 0) + (v_total_amount - v_old_total))::numeric,
          2
        ),
        0
      )
      where id = v_target_client and branch_id = v_branch_id;
    end if;
  end if;

  return jsonb_build_object(
    'sale_id', p_sale_id,
    'subtotal', v_subtotal,
    'tax_amount', v_tax_amount,
    'total_amount', v_total_amount,
    'paid_amount', coalesce(v_sale.paid_amount, 0),
    'balance_due', v_balance_due,
    'items_count', v_item_count,
    'client_id', v_target_client,
    'old_total', v_old_total
  );
end;
$$;

grant execute on function public.edit_sale_transactional(
  uuid, jsonb, uuid, boolean, text, boolean
) to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260520_25_edit_sale_rpc.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260520_26_multi_cashier_sessions.sql
-- ============================================================
-- Multi-caja por usuario.
--
-- Antes: solo UNA sesión de caja abierta por sucursal. Si tres cajeros
-- vendían a la vez, todo iba a la misma caja.
--
-- Ahora: cada usuario puede tener su propia sesión abierta en la sucursal.
-- El UNIQUE pasa a ser (branch_id, opened_by) where status='open'.
--
-- `checkout_sale_transactional` se actualiza para que el `cash_session_id`
-- de la venta sea la sesión del cajero actual (auth.uid()), no "cualquier"
-- sesión abierta de la sucursal.
--
-- Backward-compat: ventas viejas mantienen su `cash_session_id` original;
-- la sesión existente al momento del cambio queda igual.
--
-- Idempotente.

begin;

-- 1) Reemplazar UNIQUE INDEX.
drop index if exists public.cash_sessions_open_unique;

create unique index if not exists cash_sessions_open_by_user_unique
  on public.cash_sessions (branch_id, opened_by)
  where status = 'open';

-- 2) RPC checkout: usar la sesión abierta DEL USUARIO ACTUAL.
--    Mantiene la misma firma (con p_credit_due_days). Solo cambia cómo
--    selecciona `v_open_cash_session_id`.

create or replace function public.checkout_sale_transactional(
  p_items jsonb,
  p_receipt_type text default 'consumer_final',
  p_as_credit boolean default false,
  p_payment_method text default null,
  p_client_id uuid default null,
  p_notes text default null,
  p_credit_due_days integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid := public.current_branch_id();
  v_receipt_type public.receipt_type;
  v_sale_status public.sale_status;
  v_payment_method public.payment_method;
  v_sale_id uuid;
  v_sale_number text;
  v_subtotal numeric(14,2) := 0;
  v_tax_amount numeric(14,2) := 0;
  v_total_amount numeric(14,2) := 0;
  v_paid_amount numeric(14,2) := 0;
  v_balance_due numeric(14,2) := 0;
  v_open_cash_session_id uuid;
  v_client record;
  v_item record;
  v_product record;
  v_item_count integer := 0;
  v_note text;
  v_now timestamptz := timezone('utc', now());
  v_default_days integer;
  v_due_days integer;
  v_due_date date;
begin
  if v_user_id is null then
    raise exception 'Sesión inválida. Inicia sesión de nuevo.'
      using errcode = '28000';
  end if;

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada para este usuario.'
      using errcode = '22023';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'No tienes acceso a la sucursal actual.'
      using errcode = '42501';
  end if;

  if not public.can_operate_pos() then
    raise exception 'Tu rol no puede operar el POS.'
      using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'No hay productos en el carrito.'
      using errcode = '22023';
  end if;

  v_receipt_type := public.normalize_receipt_type(p_receipt_type);
  v_sale_status := case when p_as_credit then 'credit'::public.sale_status
                        else 'completed'::public.sale_status end;
  v_note := nullif(trim(coalesce(p_notes, '')), '');

  if not p_as_credit then
    begin
      v_payment_method := coalesce(nullif(trim(p_payment_method), ''), 'cash')
        ::public.payment_method;
    exception
      when invalid_text_representation then
        raise exception 'Método de pago no soportado: %', p_payment_method
          using errcode = '22023';
    end;
  end if;

  if p_client_id is not null then
    select c.id, c.full_name, c.balance_due, c.credit_limit, c.is_active
    into v_client
    from public.clients c
    where c.id = p_client_id and c.branch_id = v_branch_id;
    if not found then
      raise exception 'Cliente no encontrado en la sucursal actual.'
        using errcode = '23503';
    end if;
    if not v_client.is_active then
      raise exception 'Cliente "%": cuenta inactiva.', v_client.full_name
        using errcode = '22023';
    end if;
  end if;

  if p_as_credit and p_client_id is null then
    raise exception 'Las ventas a crédito requieren un cliente.'
      using errcode = '22023';
  end if;

  -- CAMBIO CLAVE: sesión abierta DEL USUARIO ACTUAL.
  select id into v_open_cash_session_id
  from public.cash_sessions
  where branch_id = v_branch_id
    and status = 'open'
    and opened_by = v_user_id
  order by opened_at desc
  limit 1;

  create temp table if not exists tmp_checkout_items (
    product_id uuid,
    description text,
    quantity numeric(14,3),
    unit_price numeric(14,2),
    tax_rate numeric(5,2),
    line_subtotal numeric(14,2),
    line_tax numeric(14,2),
    line_total numeric(14,2)
  ) on commit drop;
  truncate tmp_checkout_items;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price
    from jsonb_array_elements(p_items) as item
  loop
    if v_item.product_id is null then
      raise exception 'Producto sin id en el carrito.' using errcode = '22023';
    end if;
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Cantidad inválida en producto %', v_item.product_id
        using errcode = '22023';
    end if;

    select p.id, p.name, p.price, p.tax_rate, p.stock, p.is_active,
           p.allow_negative_stock, p.is_service, p.is_tax_exempt
    into v_product
    from public.products p
    where p.id = v_item.product_id and p.branch_id = v_branch_id;

    if not found then
      raise exception 'Producto no encontrado: %', v_item.product_id
        using errcode = '23503';
    end if;
    if not v_product.is_active then
      raise exception 'Producto "%": inactivo.', v_product.name
        using errcode = '22023';
    end if;
    if (not v_product.is_service)
       and (not coalesce(v_product.allow_negative_stock, false))
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
        using errcode = '22023';
    end if;

    insert into tmp_checkout_items
    values (
      v_item.product_id,
      coalesce(nullif(v_item.description, ''), v_product.name),
      v_item.quantity,
      v_item.unit_price,
      case when v_product.is_tax_exempt then 0 else v_product.tax_rate end,
      round((v_item.unit_price * v_item.quantity)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             case when v_product.is_tax_exempt then 0
                  else v_product.tax_rate end / 100)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             (1 + case when v_product.is_tax_exempt then 0
                       else v_product.tax_rate end / 100))::numeric, 2)
    );
    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No hay productos válidos en el carrito.'
      using errcode = '22023';
  end if;

  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0)
  into v_subtotal, v_tax_amount, v_total_amount
  from tmp_checkout_items;

  v_paid_amount := case when p_as_credit then 0 else v_total_amount end;
  v_balance_due := case when p_as_credit then v_total_amount else 0 end;

  if p_as_credit then
    select credit_default_days into v_default_days
    from public.app_settings where id = 1;
    v_default_days := coalesce(v_default_days, 30);
    v_due_days := coalesce(p_credit_due_days, v_default_days);
    if v_due_days <= 0 or v_due_days > 365 then
      v_due_days := v_default_days;
    end if;
    v_due_date := (v_now at time zone 'UTC')::date
                  + (v_due_days || ' days')::interval;
  end if;

  v_sale_number := 'VTA-'
    || to_char(v_now at time zone 'UTC', 'YYYYMMDD-HH24MISSMS')
    || '-'
    || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));

  insert into public.sales (
    branch_id, sale_number, client_id, cashier_id, receipt_type, status,
    sale_date, subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, balance_due, notes, due_date, cash_session_id
  ) values (
    v_branch_id, v_sale_number, p_client_id, v_user_id, v_receipt_type,
    v_sale_status, v_now, v_subtotal, 0, v_tax_amount, v_total_amount,
    v_paid_amount, v_balance_due, v_note, v_due_date, v_open_cash_session_id
  )
  returning id into v_sale_id;

  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total
  )
  select v_sale_id, v_branch_id, product_id, description, quantity,
         unit_price, 0, tax_rate, line_subtotal, line_tax, line_total
  from tmp_checkout_items
  order by product_id;

  if not p_as_credit then
    insert into public.payments (
      branch_id, sale_id, client_id, cash_session_id, payment_method,
      amount, paid_at, reference, notes
    ) values (
      v_branch_id, v_sale_id, p_client_id, v_open_cash_session_id,
      v_payment_method, v_total_amount, v_now, v_sale_number, v_note
    );
  elsif p_client_id is not null then
    update public.clients
    set balance_due = round(
      (coalesce(balance_due, 0) + v_total_amount)::numeric, 2
    )
    where id = p_client_id and branch_id = v_branch_id;
  end if;

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'sale_number', v_sale_number,
    'branch_id', v_branch_id,
    'cash_session_id', v_open_cash_session_id,
    'receipt_type', v_receipt_type,
    'status', v_sale_status,
    'subtotal', v_subtotal,
    'tax_amount', v_tax_amount,
    'total_amount', v_total_amount,
    'paid_amount', v_paid_amount,
    'balance_due', v_balance_due,
    'due_date', v_due_date,
    'items_count', (select count(*) from tmp_checkout_items)
  );
end;
$$;

grant execute on function public.checkout_sale_transactional(
  jsonb, text, boolean, text, uuid, text, integer
) to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260520_26_multi_cashier_sessions.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260520_27_multi_tenant_foundation.sql
-- ============================================================
-- Fase 1 — Multi-tenant foundation.
--
-- Objetivo: pasar el sistema de single-tenant (un solo negocio implícito) a
-- multi-tenant con aislamiento lógico vía RLS. ESTA fase NO cambia el
-- código Dart todavía — el negocio existente queda como "company legacy" y
-- todo lo demás sigue funcionando exactamente igual.
--
-- Pasos:
--   1) Nueva tabla `companies`.
--   2) Backfill: una "company legacy" con los datos actuales de
--      `app_settings` (nombre, RNC). UUID fijo para que sea predecible.
--   3) `branches.company_id` NOT NULL → FK a companies.
--   4) `app_settings.company_id` con UNIQUE (una fila por empresa).
--   5) Helpers `current_company_id()` y `has_company_access(uuid)`.
--   6) RLS sobre `companies` (SELECT/INSERT/UPDATE/DELETE).
--
-- Aislamiento futuro: como TODAS las tablas operativas (sales, products,
-- payments, etc.) ya filtran por sucursal vía `has_branch_access`, y cada
-- sucursal pertenece a UNA company, el aislamiento entre empresas queda
-- garantizado siempre y cuando los nuevos usuarios solo se asignen a
-- sucursales de SU empresa (cosa que la Fase 2 — onboarding — va a hacer
-- atómicamente).
--
-- Reversibilidad: hacer BACKUP antes de correr. `company_id NOT NULL` es
-- difícil de revertir limpiamente. Idempotente, pero no idempotente al
-- 100% (la marca NOT NULL solo se aplica si la columna no la tiene).

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Tabla companies
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tax_id text,
  slug text unique,
  owner_id uuid references auth.users(id) on delete set null,
  plan text not null default 'free',
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_companies_owner on public.companies(owner_id);
create index if not exists idx_companies_active
  on public.companies(is_active) where is_active;

-- Trigger updated_at — reutiliza la convención existente.
drop trigger if exists trg_companies_updated_at on public.companies;
create trigger trg_companies_updated_at
before update on public.companies
for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Legacy company (negocio que ya existe)
--    UUID fijo y predecible para que los scripts y debug sean fáciles.
-- ─────────────────────────────────────────────────────────────────────────

insert into public.companies (id, name, tax_id, slug, plan, is_active)
select
  '00000000-0000-0000-0000-000000000001'::uuid,
  coalesce(nullif(trim(s.company_name), ''), 'Mi Negocio'),
  s.company_tax_id,
  'legacy',
  'legacy',
  true
from public.app_settings s
where s.id = 1
on conflict (id) do nothing;

-- Si no había fila en app_settings (DB nueva), crear company default igual.
insert into public.companies (id, name, slug, plan)
values (
  '00000000-0000-0000-0000-000000000001'::uuid,
  'Mi Negocio',
  'legacy',
  'legacy'
)
on conflict (id) do nothing;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) branches.company_id
-- ─────────────────────────────────────────────────────────────────────────

alter table public.branches
  add column if not exists company_id uuid
  references public.companies(id) on delete restrict;

-- Backfill: todas las sucursales existentes → company legacy.
update public.branches
set company_id = '00000000-0000-0000-0000-000000000001'::uuid
where company_id is null;

-- NOT NULL (si la columna ya estaba NOT NULL, no falla porque ya cumple).
alter table public.branches
  alter column company_id set not null;

create index if not exists idx_branches_company on public.branches(company_id);

-- ─────────────────────────────────────────────────────────────────────────
-- 4) app_settings.company_id
--    PK existente es `id` (singleton id=1). Agregamos company_id con
--    UNIQUE para que cada empresa tenga UNA fila de settings.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.app_settings
  add column if not exists company_id uuid
  references public.companies(id) on delete cascade;

update public.app_settings
set company_id = '00000000-0000-0000-0000-000000000001'::uuid
where id = 1 and company_id is null;

-- UNIQUE: una fila por empresa (cuando company_id no es null).
create unique index if not exists app_settings_company_unique
  on public.app_settings(company_id)
  where company_id is not null;

-- ─────────────────────────────────────────────────────────────────────────
-- 5) Helpers RLS
-- ─────────────────────────────────────────────────────────────────────────

-- current_company_id(): empresa de la sucursal activa del usuario.
create or replace function public.current_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select b.company_id
  from public.branches b
  where b.id = public.current_branch_id()
  limit 1;
$$;

grant execute on function public.current_company_id() to authenticated;

-- has_company_access(uuid): el usuario tiene alguna sucursal activa de esa
-- empresa O es owner de la empresa.
create or replace function public.has_company_access(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users_branches ub
    join public.branches b on b.id = ub.branch_id
    join public.profiles p on p.id = ub.user_id
    where ub.user_id = auth.uid()
      and ub.is_active
      and p.is_active
      and b.company_id = p_company_id
  ) or exists (
    select 1 from public.companies c
    where c.id = p_company_id and c.owner_id = auth.uid()
  );
$$;

grant execute on function public.has_company_access(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 6) RLS sobre companies
-- ─────────────────────────────────────────────────────────────────────────

alter table public.companies enable row level security;

-- SELECT: el usuario ve la(s) empresa(s) a las que pertenece.
drop policy if exists companies_select on public.companies;
create policy companies_select on public.companies
  for select to authenticated
  using (public.has_company_access(id));

-- INSERT: cualquier usuario autenticado puede crear UNA empresa de la cual
-- es owner. Lo usa el flujo de onboarding (Fase 2).
drop policy if exists companies_insert on public.companies;
create policy companies_insert on public.companies
  for insert to authenticated
  with check (owner_id = auth.uid());

-- UPDATE: el owner puede modificar su empresa. Admins del sistema también.
drop policy if exists companies_update on public.companies;
create policy companies_update on public.companies
  for update to authenticated
  using (owner_id = auth.uid() or public.is_admin())
  with check (owner_id = auth.uid() or public.is_admin());

-- DELETE: solo owner. Cuidado: cascada elimina app_settings (intencional)
-- pero `branches` es ON DELETE RESTRICT — no se puede borrar empresa con
-- sucursales adentro. El owner debe borrar sucursales primero.
drop policy if exists companies_delete on public.companies;
create policy companies_delete on public.companies
  for delete to authenticated
  using (owner_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────
-- 7) Asignar owner_id a la company legacy
--    Toma el primer admin existente como owner. Si no hay, queda null
--    (un super-admin futuro lo seteará manualmente).
-- ─────────────────────────────────────────────────────────────────────────

update public.companies
set owner_id = (
  select p.id from public.profiles p
  where p.role = 'admin'::public.app_role
    and p.is_active
  order by p.created_at asc
  limit 1
)
where id = '00000000-0000-0000-0000-000000000001'::uuid
  and owner_id is null;

commit;

-- ============================================================
-- END:   sql-next/20260520_27_multi_tenant_foundation.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260520_28_company_bootstrap.sql
-- ============================================================
-- Fase 2 — Signup público + onboarding atómico.
--
-- Cambios:
--   1) `app_settings.id` deja de ser singleton (id=1). Se convierte en
--      auto-increment vía sequence. La fila legacy mantiene id=1.
--   2) RLS de `app_settings` se endurece: cada usuario solo ve / edita la
--      fila de SU empresa (via `has_company_access`).
--   3) Nuevo RPC `bootstrap_new_company`: crea atómicamente company +
--      sucursal + profile (rol admin) + users_branches + app_settings para
--      el usuario recién registrado. SECURITY DEFINER para saltar las RLS
--      durante el bootstrap.
--
-- Idempotente excepto por el ALTER que cambia el default de `id`.

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) app_settings.id: drop singleton constraint, usar sequence.
-- ─────────────────────────────────────────────────────────────────────────

-- Buscar el check constraint que ata id=1 y dropearlo. El nombre depende
-- del momento en que se creó la tabla — Postgres lo nombra automáticamente.
do $$
declare
  v_constraint_name text;
begin
  select conname into v_constraint_name
  from pg_constraint
  where conrelid = 'public.app_settings'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%(id = 1)%';

  if v_constraint_name is not null then
    execute format(
      'alter table public.app_settings drop constraint %I',
      v_constraint_name
    );
  end if;
end $$;

-- Sequence asociada a la columna id.
create sequence if not exists public.app_settings_id_seq
  owned by public.app_settings.id;

-- Avanzar la sequence más allá del máximo actual.
select setval(
  'public.app_settings_id_seq',
  greatest((select coalesce(max(id), 0) from public.app_settings), 1)
);

alter table public.app_settings
  alter column id set default nextval('public.app_settings_id_seq');

-- ─────────────────────────────────────────────────────────────────────────
-- 2) RLS multi-tenant sobre app_settings.
--    Cada empresa ve / edita SOLO su fila. La inserción la hace el RPC
--    bootstrap (SECURITY DEFINER), no necesita policy abierta.
-- ─────────────────────────────────────────────────────────────────────────

drop policy if exists app_settings_select on public.app_settings;
create policy app_settings_select on public.app_settings
  for select to authenticated
  using (
    company_id is null
    or public.has_company_access(company_id)
  );

drop policy if exists app_settings_update on public.app_settings;
create policy app_settings_update on public.app_settings
  for update to authenticated
  using (
    public.is_admin()
    and (company_id is null or public.has_company_access(company_id))
  )
  with check (
    public.is_admin()
    and (company_id is null or public.has_company_access(company_id))
  );

-- INSERT: lo hace SOLO el RPC bootstrap (SECURITY DEFINER, bypassa RLS) o
-- los admins legacy. Mantener la policy strict.
drop policy if exists app_settings_insert on public.app_settings;
create policy app_settings_insert on public.app_settings
  for insert to authenticated
  with check (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────
-- 3) Bootstrap RPC.
--    Lo invoca el usuario inmediatamente después de hacer signUp (cuando
--    todavía no tiene profile ni nada). Crea TODO atómicamente.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.bootstrap_new_company(
  p_company_name text,
  p_branch_name text default 'Sucursal principal',
  p_full_name text default null,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text;
  v_company_id uuid;
  v_branch_id uuid;
  v_slug text;
  v_branch_code text;
  v_app_settings_id integer;
begin
  if v_user_id is null then
    raise exception 'No autenticado.'
      using errcode = '28000';
  end if;

  -- Idempotencia: si ya tiene profile, falla con mensaje claro.
  if exists (select 1 from public.profiles where id = v_user_id) then
    raise exception 'Este usuario ya tiene un perfil. Usa /usuarios para invitar empleados.'
      using errcode = '23505';
  end if;

  if coalesce(trim(p_company_name), '') = '' then
    raise exception 'El nombre de la empresa es requerido.'
      using errcode = '22023';
  end if;

  -- Email del usuario autenticado.
  select email::text into v_email
  from auth.users
  where id = v_user_id;

  -- Slug único: nombre normalizado + sufijo aleatorio para evitar colisión.
  v_slug := lower(
    regexp_replace(trim(p_company_name), '[^a-zA-Z0-9]+', '-', 'g')
  ) || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);

  -- 1) Empresa nueva, el usuario actual es owner.
  insert into public.companies (name, slug, owner_id, plan, is_active)
  values (trim(p_company_name), v_slug, v_user_id, 'free', true)
  returning id into v_company_id;

  -- 2) Sucursal principal de la empresa. branches.code es global-unique,
  --    derivamos un código predecible del UUID de la empresa.
  v_branch_code := 'B-' || upper(
    substr(replace(v_company_id::text, '-', ''), 1, 8)
  );

  insert into public.branches (
    code, name, is_main, is_active, company_id, created_by, updated_by
  ) values (
    v_branch_code,
    coalesce(nullif(trim(p_branch_name), ''), 'Sucursal principal'),
    true,
    true,
    v_company_id,
    v_user_id,
    v_user_id
  )
  returning id into v_branch_id;

  -- 3) Profile (admin de su empresa).
  insert into public.profiles (id, email, full_name, role, phone, is_active)
  values (
    v_user_id,
    v_email,
    coalesce(nullif(trim(p_full_name), ''), v_email, ''),
    'admin'::public.app_role,
    p_phone,
    true
  );

  -- 4) Linkear usuario a su sucursal default.
  insert into public.users_branches (
    user_id, branch_id, is_default, is_active, created_by, updated_by
  ) values (
    v_user_id, v_branch_id, true, true, v_user_id, v_user_id
  );

  -- 5) app_settings de la empresa (resto de defaults de la tabla aplican).
  insert into public.app_settings (company_name, company_id)
  values (trim(p_company_name), v_company_id)
  returning id into v_app_settings_id;

  return jsonb_build_object(
    'company_id', v_company_id,
    'branch_id', v_branch_id,
    'user_id', v_user_id,
    'app_settings_id', v_app_settings_id
  );
end;
$$;

grant execute on function public.bootstrap_new_company(text, text, text, text)
  to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260520_28_company_bootstrap.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260521_29_bootstrap_upsert_profile.sql
-- ============================================================
-- Fix: bootstrap_new_company choca con el trigger on_auth_user_created.
--
-- Problema:
--   El trigger handle_auth_user_upsert() inserta un profile con role='cashier'
--   apenas se crea la fila en auth.users. Cuando el flujo de signup público
--   después llama a bootstrap_new_company, el RPC encontraba ese profile y
--   abortaba con "Este usuario ya tiene un perfil".
--
-- Solución:
--   El RPC ahora hace UPSERT del profile: si ya existe (creado por el trigger),
--   lo PROMUEVE a 'admin' y completa el resto del bootstrap (company, sucursal,
--   users_branches, app_settings). Solo aborta si el usuario ya tiene company
--   asignada en users_branches (señal real de que ya completó el bootstrap).

begin;

create or replace function public.bootstrap_new_company(
  p_company_name text,
  p_branch_name text default 'Sucursal principal',
  p_full_name text default null,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text;
  v_company_id uuid;
  v_branch_id uuid;
  v_slug text;
  v_branch_code text;
  v_app_settings_id integer;
begin
  if v_user_id is null then
    raise exception 'No autenticado.'
      using errcode = '28000';
  end if;

  if coalesce(trim(p_company_name), '') = '' then
    raise exception 'El nombre de la empresa es requerido.'
      using errcode = '22023';
  end if;

  -- Idempotencia real: si ya tiene users_branches activos, ya completó el
  -- bootstrap antes. El profile solo (creado por el trigger del signup) NO
  -- cuenta como bootstrap completado.
  if exists (
    select 1
    from public.users_branches ub
    join public.branches b on b.id = ub.branch_id
    where ub.user_id = v_user_id
      and ub.is_active
      and b.company_id is not null
  ) then
    raise exception 'Este usuario ya pertenece a una empresa. Usa /usuarios para invitar empleados.'
      using errcode = '23505';
  end if;

  -- Email del usuario autenticado.
  select email::text into v_email
  from auth.users
  where id = v_user_id;

  -- Slug único: nombre normalizado + sufijo aleatorio para evitar colisión.
  v_slug := lower(
    regexp_replace(trim(p_company_name), '[^a-zA-Z0-9]+', '-', 'g')
  ) || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);

  -- 1) Empresa nueva, el usuario actual es owner.
  insert into public.companies (name, slug, owner_id, plan, is_active)
  values (trim(p_company_name), v_slug, v_user_id, 'free', true)
  returning id into v_company_id;

  -- 2) Sucursal principal de la empresa. branches.code es global-unique,
  --    derivamos un código predecible del UUID de la empresa.
  v_branch_code := 'B-' || upper(
    substr(replace(v_company_id::text, '-', ''), 1, 8)
  );

  insert into public.branches (
    code, name, is_main, is_active, company_id, created_by, updated_by
  ) values (
    v_branch_code,
    coalesce(nullif(trim(p_branch_name), ''), 'Sucursal principal'),
    true,
    true,
    v_company_id,
    v_user_id,
    v_user_id
  )
  returning id into v_branch_id;

  -- 3) Profile: UPSERT para convivir con el trigger handle_auth_user_upsert().
  --    Si el trigger ya creó la fila con role='cashier', la promovemos a admin.
  insert into public.profiles (id, email, full_name, role, phone, is_active)
  values (
    v_user_id,
    v_email,
    coalesce(nullif(trim(p_full_name), ''), v_email, ''),
    'admin'::public.app_role,
    p_phone,
    true
  )
  on conflict (id) do update set
    email = excluded.email,
    full_name = coalesce(nullif(excluded.full_name, ''), public.profiles.full_name),
    role = 'admin'::public.app_role,
    phone = coalesce(excluded.phone, public.profiles.phone),
    is_active = true;

  -- 4) Linkear usuario a su sucursal default.
  insert into public.users_branches (
    user_id, branch_id, is_default, is_active, created_by, updated_by
  ) values (
    v_user_id, v_branch_id, true, true, v_user_id, v_user_id
  );

  -- 5) app_settings de la empresa (resto de defaults de la tabla aplican).
  insert into public.app_settings (company_name, company_id)
  values (trim(p_company_name), v_company_id)
  returning id into v_app_settings_id;

  return jsonb_build_object(
    'company_id', v_company_id,
    'branch_id', v_branch_id,
    'user_id', v_user_id,
    'app_settings_id', v_app_settings_id
  );
end;
$$;

grant execute on function public.bootstrap_new_company(text, text, text, text)
  to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260521_29_bootstrap_upsert_profile.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260521_30_void_sale_with_stock_return.sql
-- ============================================================
-- RPC: void_sale_with_stock_return
--
-- Anula una venta atómicamente:
--   1) Borra sale_items → el trigger trg_sale_items_stock devuelve el stock.
--   2) Borra payments asociados (revierte cobros).
--   3) Marca sales.status = 'voided'.
--
-- No toca NCFs (el módulo de comprobantes fiscales tiene su propio flujo de
-- anulación contra DGII). Si la venta tenía NCF, el comprobante queda
-- huérfano apuntando a una venta voided — eso es esperado.
--
-- Seguridad: SECURITY DEFINER pero valida has_branch_access(branch_id) de
-- la venta antes de hacer nada.

begin;

create or replace function public.void_sale_with_stock_return(
  p_sale_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_status public.sale_status;
begin
  if p_sale_id is null then
    raise exception 'p_sale_id es requerido.'
      using errcode = '22023';
  end if;

  select branch_id, status into v_branch_id, v_status
  from public.sales
  where id = p_sale_id;

  if v_branch_id is null then
    raise exception 'Venta no encontrada.'
      using errcode = 'P0002';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'Sin acceso a esta venta.'
      using errcode = '42501';
  end if;

  if v_status = 'voided'::public.sale_status then
    raise exception 'La venta ya está anulada.'
      using errcode = '23505';
  end if;

  -- 1) Borrar sale_items. El trigger trg_sale_items_stock corre por cada
  --    fila y devuelve el stock al producto.
  delete from public.sale_items
  where sale_id = p_sale_id;

  -- 2) Borrar pagos vinculados (no quedan apuntando a una venta anulada).
  delete from public.payments
  where sale_id = p_sale_id;

  -- 3) Marcar la venta como anulada.
  update public.sales
    set status = 'voided'::public.sale_status,
        updated_at = timezone('utc', now())
  where id = p_sale_id;
end;
$$;

grant execute on function public.void_sale_with_stock_return(uuid)
  to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260521_30_void_sale_with_stock_return.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260521_31_update_sale_payment_method.sql
-- ============================================================
-- RPC: update_sale_payment_method
--
-- Cambia el método de pago de TODAS las filas de payments asociadas a una
-- venta. Pensado para corregir errores del cajero (ej. registró efectivo
-- pero el cliente pagó por transferencia).
--
-- No cambia montos ni crea pagos nuevos — solo el `payment_method`. Si la
-- venta tiene varios pagos (split payment), todos pasan al mismo método.
-- Para split-payment con métodos distintos, usar el editor de pagos
-- avanzado (no implementado todavía).
--
-- Seguridad: SECURITY DEFINER + has_branch_access + solo admin/supervisor.

begin;

create or replace function public.update_sale_payment_method(
  p_sale_id uuid,
  p_payment_method public.payment_method
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_status public.sale_status;
  v_updated integer;
begin
  if p_sale_id is null then
    raise exception 'p_sale_id es requerido.'
      using errcode = '22023';
  end if;
  if p_payment_method is null then
    raise exception 'p_payment_method es requerido.'
      using errcode = '22023';
  end if;

  if not public.is_admin()
     and public.current_user_role() <> 'supervisor'::public.app_role then
    raise exception 'Solo admin o supervisor pueden cambiar el método de pago.'
      using errcode = '42501';
  end if;

  select branch_id, status into v_branch_id, v_status
  from public.sales
  where id = p_sale_id;

  if v_branch_id is null then
    raise exception 'Venta no encontrada.'
      using errcode = 'P0002';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'Sin acceso a esta venta.'
      using errcode = '42501';
  end if;

  if v_status = 'voided'::public.sale_status then
    raise exception 'No se puede modificar una venta anulada.'
      using errcode = '22023';
  end if;

  update public.payments
    set payment_method = p_payment_method,
        updated_at = timezone('utc', now())
  where sale_id = p_sale_id
    and branch_id = v_branch_id;

  get diagnostics v_updated = row_count;

  return v_updated;
end;
$$;

grant execute on function public.update_sale_payment_method(
  uuid, public.payment_method
) to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260521_31_update_sale_payment_method.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260521_32_extra_price_tiers.sql
-- ============================================================
-- Extiende los tiers de precio de productos de 3 a 10.
--
-- Antes había solo price_tier_1, price_tier_2, price_tier_3. Ahora se
-- agregan price_tier_4..price_tier_10 para soportar negocios con más
-- niveles (p. ej. mayorista, distribuidor, VIP, online, B2B, etc.).
--
-- Las etiquetas de los tiers viven en app_settings.sale_price_types
-- (jsonb) — esa tabla no necesita cambios porque ya es flexible.
--
-- Todos los nuevos columns son nullable: si no se asigna precio en ese
-- tier, el código cae al `price` base.
--
-- Idempotente.

begin;

alter table public.products
  add column if not exists price_tier_4  numeric(14,2),
  add column if not exists price_tier_5  numeric(14,2),
  add column if not exists price_tier_6  numeric(14,2),
  add column if not exists price_tier_7  numeric(14,2),
  add column if not exists price_tier_8  numeric(14,2),
  add column if not exists price_tier_9  numeric(14,2),
  add column if not exists price_tier_10 numeric(14,2);

commit;

-- ============================================================
-- END:   sql-next/20260521_32_extra_price_tiers.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260521_33_cash_registers.sql
-- ============================================================
-- Cajas físicas/lógicas con asignación de usuarios.
--
-- Antes: cada cajero abría su propia sesión (cash_sessions). El sistema
-- asumía que cajero = caja. No había concepto de "caja con nombre".
--
-- Ahora: la sucursal tiene N cajas configurables (cash_registers). Cada
-- caja puede tener usuarios asignados (cash_register_users). Para abrir
-- una sesión sobre una caja, el usuario tiene que estar asignado.
--
-- Backwards-compat: cash_sessions.cash_register_id es NULLABLE. Sesiones
-- viejas no tienen caja asignada (vacío). El cliente puede mostrar
-- "Caja sin asignar" para esos casos. El nuevo openSession RPC requiere
-- cash_register_id.
--
-- Idempotente: todas las creaciones usan `if not exists`; las policies
-- se dropean primero.

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Tabla cash_registers (catálogo de cajas por sucursal)
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.cash_registers (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id)
);

create unique index if not exists cash_registers_name_per_branch
  on public.cash_registers (branch_id, lower(name))
  where is_active;

-- Trigger de updated_at + audit (set_updated_at y set_audit_fields ya existen).
drop trigger if exists trg_cash_registers_updated_at on public.cash_registers;
create trigger trg_cash_registers_updated_at
before update on public.cash_registers
for each row execute function public.set_updated_at();

drop trigger if exists trg_cash_registers_audit_fields on public.cash_registers;
create trigger trg_cash_registers_audit_fields
before insert or update on public.cash_registers
for each row execute function public.set_audit_fields();

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Tabla cash_register_users (asignación de usuarios a cajas)
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.cash_register_users (
  cash_register_id uuid not null references public.cash_registers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (cash_register_id, user_id)
);

-- ─────────────────────────────────────────────────────────────────────────
-- 3) cash_sessions.cash_register_id (relación 1:N)
-- ─────────────────────────────────────────────────────────────────────────

alter table public.cash_sessions
  add column if not exists cash_register_id uuid
    references public.cash_registers(id);

-- ─────────────────────────────────────────────────────────────────────────
-- 4) RLS
-- ─────────────────────────────────────────────────────────────────────────

alter table public.cash_registers enable row level security;
alter table public.cash_register_users enable row level security;

-- cash_registers: SELECT a todos los del branch, INSERT/UPDATE/DELETE solo admin/supervisor.
drop policy if exists cash_registers_select on public.cash_registers;
create policy cash_registers_select on public.cash_registers
  for select to authenticated
  using (public.has_branch_access(branch_id));

drop policy if exists cash_registers_insert on public.cash_registers;
create policy cash_registers_insert on public.cash_registers
  for insert to authenticated
  with check (
    public.has_branch_access(branch_id)
    and (public.is_admin() or public.current_user_role() = 'supervisor'::public.app_role)
  );

drop policy if exists cash_registers_update on public.cash_registers;
create policy cash_registers_update on public.cash_registers
  for update to authenticated
  using (
    public.has_branch_access(branch_id)
    and (public.is_admin() or public.current_user_role() = 'supervisor'::public.app_role)
  )
  with check (
    public.has_branch_access(branch_id)
    and (public.is_admin() or public.current_user_role() = 'supervisor'::public.app_role)
  );

drop policy if exists cash_registers_delete on public.cash_registers;
create policy cash_registers_delete on public.cash_registers
  for delete to authenticated
  using (
    public.has_branch_access(branch_id)
    and (public.is_admin() or public.current_user_role() = 'supervisor'::public.app_role)
  );

-- cash_register_users: SELECT a los del branch, INSERT/DELETE solo admin/supervisor del branch.
drop policy if exists cash_register_users_select on public.cash_register_users;
create policy cash_register_users_select on public.cash_register_users
  for select to authenticated
  using (
    exists (
      select 1 from public.cash_registers cr
      where cr.id = cash_register_id
        and public.has_branch_access(cr.branch_id)
    )
  );

drop policy if exists cash_register_users_insert on public.cash_register_users;
create policy cash_register_users_insert on public.cash_register_users
  for insert to authenticated
  with check (
    (public.is_admin() or public.current_user_role() = 'supervisor'::public.app_role)
    and exists (
      select 1 from public.cash_registers cr
      where cr.id = cash_register_id
        and public.has_branch_access(cr.branch_id)
    )
  );

drop policy if exists cash_register_users_delete on public.cash_register_users;
create policy cash_register_users_delete on public.cash_register_users
  for delete to authenticated
  using (
    (public.is_admin() or public.current_user_role() = 'supervisor'::public.app_role)
    and exists (
      select 1 from public.cash_registers cr
      where cr.id = cash_register_id
        and public.has_branch_access(cr.branch_id)
    )
  );

-- ─────────────────────────────────────────────────────────────────────────
-- 5) RPC open_cash_session_for_register
--
--    Crea una cash_session apuntando a cash_register_id, validando que el
--    usuario actual esté asignado a esa caja. El cliente lo invoca en
--    lugar del INSERT directo cuando hay cajas configuradas.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.open_cash_session_for_register(
  p_cash_register_id uuid,
  p_opening_amount numeric,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid;
  v_session_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sesión inválida.' using errcode = '28000';
  end if;
  if p_cash_register_id is null then
    raise exception 'p_cash_register_id es requerido.' using errcode = '22023';
  end if;
  if p_opening_amount is null or p_opening_amount < 0 then
    raise exception 'Monto de apertura inválido.' using errcode = '22023';
  end if;

  -- La caja existe + el usuario tiene acceso a la sucursal.
  select branch_id into v_branch_id
  from public.cash_registers
  where id = p_cash_register_id and is_active;

  if v_branch_id is null then
    raise exception 'Caja no encontrada o inactiva.' using errcode = 'P0002';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'Sin acceso a esta sucursal.' using errcode = '42501';
  end if;

  -- El usuario está asignado a la caja.
  if not exists (
    select 1 from public.cash_register_users
    where cash_register_id = p_cash_register_id
      and user_id = v_user_id
      and is_active
  ) then
    raise exception 'No tenés acceso a esta caja.' using errcode = '42501';
  end if;

  -- No abrir otra sesión si el usuario ya tiene una abierta en esta sucursal
  -- (regla del migration 26: una sesión abierta por (branch_id, opened_by)).
  if exists (
    select 1 from public.cash_sessions
    where branch_id = v_branch_id
      and opened_by = v_user_id
      and status = 'open'
  ) then
    raise exception 'Ya tenés una sesión de caja abierta en esta sucursal.'
      using errcode = '23505';
  end if;

  insert into public.cash_sessions (
    branch_id, opened_by, status, opened_at,
    opening_amount, expected_amount, notes, cash_register_id
  ) values (
    v_branch_id, v_user_id, 'open', timezone('utc', now()),
    round(p_opening_amount::numeric, 2), round(p_opening_amount::numeric, 2),
    nullif(trim(coalesce(p_notes, '')), ''), p_cash_register_id
  )
  returning id into v_session_id;

  return v_session_id;
end;
$$;

grant execute on function public.open_cash_session_for_register(uuid, numeric, text)
  to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260521_33_cash_registers.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260522_34_app_settings_legacy_fix.sql
-- ============================================================
-- Fix: bug del signup multi-tenant.
--
-- Síntoma:
--   Al registrar un negocio nuevo, /configuración muestra los datos del
--   negocio viejo. Los cambios guardados en /configuración del negocio
--   nuevo terminan en la fila legacy y los ven todos los usuarios.
--
-- Causa raíz:
--   1) La fila legacy `app_settings` (id=1, anterior al migration multi-tenant
--      #27) quedó con `company_id IS NULL`.
--   2) El RLS de `app_settings` permite ver / editar filas con
--      `company_id IS NULL` a TODOS los usuarios autenticados:
--          using (company_id is null or has_company_access(company_id))
--      Era una puerta trasera para mantener compatibilidad legacy.
--   3) El cliente hace `select().limit(1)` sin filtro. Postgres devuelve la
--      primera fila visible — normalmente la legacy id=1.
--   4) Bootstrap crea la fila correcta con company_id, pero el cliente la
--      ignora y sigue usando la legacy.
--
-- Fix:
--   1) Asignar la fila legacy a una empresa real (la más antigua que tenga
--      sucursales). Si no hay empresas, borrar la fila.
--   2) Endurecer el RLS: ya NO se permite `company_id IS NULL`. Cada
--      empresa ve y edita SOLO su propia fila.
--   3) Garantizar que toda app_settings tiene company_id (NOT NULL).
--
-- Defensiva: si las tablas requeridas (app_settings, companies) o el helper
-- has_company_access() no existen, la migration se salta toda con un NOTICE.
-- Eso permite correrla en cualquier estado de la DB; si una migration previa
-- no se ha corrido, primero hay que correr esa.
--
-- Idempotente.

begin;

do $$
declare
  v_legacy_count integer;
  v_target_company uuid;
  v_collision_count integer;
begin
  -- ── Pre-flight: dependencias ──────────────────────────────────────────
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'app_settings'
  ) then
    raise notice
      'Salteando: app_settings no existe. Corre primero 20260509_08_app_settings.sql';
    return;
  end if;

  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'companies'
  ) then
    raise notice
      'Salteando: companies no existe. Corre primero 20260520_27_multi_tenant_foundation.sql';
    return;
  end if;

  if not exists (
    select 1 from information_schema.routines
    where routine_schema = 'public' and routine_name = 'has_company_access'
  ) then
    raise notice
      'Salteando: has_company_access() no existe. Corre primero 20260520_27_multi_tenant_foundation.sql';
    return;
  end if;

  -- ── 1) Reparar la fila legacy app_settings (company_id NULL) ──────────
  execute 'select count(*) from public.app_settings where company_id is null'
    into v_legacy_count;

  if v_legacy_count > 0 then
    -- Empresa "principal": la más antigua con al menos una sucursal activa.
    select c.id into v_target_company
    from public.companies c
    where c.is_active
      and exists (
        select 1 from public.branches b
        where b.company_id = c.id and b.is_active
      )
    order by c.created_at asc
    limit 1;

    if v_target_company is null then
      -- No hay empresas reales todavía: la fila legacy no sirve, borrarla.
      execute 'delete from public.app_settings where company_id is null';
    else
      -- ¿La empresa elegida ya tiene su propia app_settings (vía bootstrap)?
      execute 'select count(*) from public.app_settings where company_id = $1'
        into v_collision_count
        using v_target_company;

      if v_collision_count > 0 then
        -- Sí, hay colisión: borrar la legacy para no duplicar.
        execute 'delete from public.app_settings where company_id is null';
      else
        -- No, re-etiquetar la legacy con la empresa elegida.
        execute 'update public.app_settings set company_id = $1 where company_id is null'
          using v_target_company;
      end if;
    end if;

    -- Cualquier otra empresa que aún no tenga app_settings necesita su
    -- propia fila para que el RLS post-fix no la deje sin configuración.
    execute $sql$
      insert into public.app_settings (company_name, company_id)
      select c.name, c.id
        from public.companies c
       where c.is_active
         and not exists (
           select 1 from public.app_settings s where s.company_id = c.id
         )
    $sql$;
  end if;

  -- ── 2) NOT NULL en company_id para prevenir nuevas filas huérfanas ────
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'app_settings'
      and column_name = 'company_id'
      and is_nullable = 'YES'
  ) then
    execute 'alter table public.app_settings alter column company_id set not null';
  end if;

  -- ── 3) RLS endurecida: cada empresa ve y edita SOLO su fila ───────────
  execute 'drop policy if exists app_settings_select on public.app_settings';
  execute $sql$
    create policy app_settings_select on public.app_settings
      for select to authenticated
      using (public.has_company_access(company_id))
  $sql$;

  execute 'drop policy if exists app_settings_update on public.app_settings';
  execute $sql$
    create policy app_settings_update on public.app_settings
      for update to authenticated
      using (
        public.is_admin()
        and public.has_company_access(company_id)
      )
      with check (
        public.is_admin()
        and public.has_company_access(company_id)
      )
  $sql$;
end $$;

commit;

-- ============================================================
-- END:   sql-next/20260522_34_app_settings_legacy_fix.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260522_35_checkout_respects_global_stock_setting.sql
-- ============================================================
-- Fix: el RPC checkout_sale_transactional ignora app_settings.inv_disallow_no_stock.
--
-- Síntoma:
--   El switch "No permitir venta sin stock" en /configuración no tiene
--   efecto real al cobrar. El RPC solo respetaba el flag por-producto
--   `products.allow_negative_stock`, dejando dos lógicas paralelas sin
--   relación.
--
-- Decisión de producto:
--   El setting global manda. Cuando está APAGADO (`inv_disallow_no_stock =
--   false`), se permite vender CUALQUIER producto sin stock — el flag por
--   producto deja de aplicar. Cuando está PRENDIDO, se respeta el flag por
--   producto como hasta ahora.
--
--   Default si no hay app_settings o no hay fila para la company: PRENDIDO
--   (proteger por defecto; cumplir explícitamente para permitir oversell).
--
-- Cambio:
--   Solo se modifica la validación de stock dentro del loop de items. El
--   resto de la función es idéntico a 20260520_26.
--
-- Idempotente.

begin;

create or replace function public.checkout_sale_transactional(
  p_items jsonb,
  p_receipt_type text default 'consumer_final',
  p_as_credit boolean default false,
  p_payment_method text default null,
  p_client_id uuid default null,
  p_notes text default null,
  p_credit_due_days integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_branch_id uuid := public.current_branch_id();
  v_receipt_type public.receipt_type;
  v_sale_status public.sale_status;
  v_payment_method public.payment_method;
  v_sale_id uuid;
  v_sale_number text;
  v_subtotal numeric(14,2) := 0;
  v_tax_amount numeric(14,2) := 0;
  v_total_amount numeric(14,2) := 0;
  v_paid_amount numeric(14,2) := 0;
  v_balance_due numeric(14,2) := 0;
  v_open_cash_session_id uuid;
  v_client record;
  v_item record;
  v_product record;
  v_item_count integer := 0;
  v_note text;
  v_now timestamptz := timezone('utc', now());
  v_default_days integer;
  v_due_days integer;
  v_due_date date;
  v_enforce_stock boolean := true;
begin
  if v_user_id is null then
    raise exception 'Sesión inválida. Inicia sesión de nuevo.'
      using errcode = '28000';
  end if;

  if v_branch_id is null then
    raise exception 'No hay sucursal asignada para este usuario.'
      using errcode = '22023';
  end if;

  if not public.has_branch_access(v_branch_id) then
    raise exception 'No tienes acceso a la sucursal actual.'
      using errcode = '42501';
  end if;

  if not public.can_operate_pos() then
    raise exception 'Tu rol no puede operar el POS.'
      using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'No hay productos en el carrito.'
      using errcode = '22023';
  end if;

  v_receipt_type := public.normalize_receipt_type(p_receipt_type);
  v_sale_status := case when p_as_credit then 'credit'::public.sale_status
                        else 'completed'::public.sale_status end;
  v_note := nullif(trim(coalesce(p_notes, '')), '');

  if not p_as_credit then
    begin
      v_payment_method := coalesce(nullif(trim(p_payment_method), ''), 'cash')
        ::public.payment_method;
    exception
      when invalid_text_representation then
        raise exception 'Método de pago no soportado: %', p_payment_method
          using errcode = '22023';
    end;
  end if;

  if p_client_id is not null then
    select c.id, c.full_name, c.balance_due, c.credit_limit, c.is_active
    into v_client
    from public.clients c
    where c.id = p_client_id and c.branch_id = v_branch_id;
    if not found then
      raise exception 'Cliente no encontrado en la sucursal actual.'
        using errcode = '23503';
    end if;
    if not v_client.is_active then
      raise exception 'Cliente "%": cuenta inactiva.', v_client.full_name
        using errcode = '22023';
    end if;
  end if;

  if p_as_credit and p_client_id is null then
    raise exception 'Las ventas a crédito requieren un cliente.'
      using errcode = '22023';
  end if;

  -- Sesión abierta DEL USUARIO ACTUAL.
  select id into v_open_cash_session_id
  from public.cash_sessions
  where branch_id = v_branch_id
    and status = 'open'
    and opened_by = v_user_id
  order by opened_at desc
  limit 1;

  -- ── Setting global: ¿hay que validar stock? ─────────────────────────────
  -- Defensivo: si app_settings no tiene company_id (esquema viejo) o la
  -- fila no existe, dejamos v_enforce_stock = true (proteger por defecto).
  begin
    select coalesce(s.inv_disallow_no_stock, true)
      into v_enforce_stock
      from public.app_settings s
      join public.branches b on b.company_id = s.company_id
     where b.id = v_branch_id
     limit 1;
    if v_enforce_stock is null then
      v_enforce_stock := true;
    end if;
  exception
    when undefined_column or undefined_table or undefined_function then
      v_enforce_stock := true;
  end;

  create temp table if not exists tmp_checkout_items (
    product_id uuid,
    description text,
    quantity numeric(14,3),
    unit_price numeric(14,2),
    tax_rate numeric(5,2),
    line_subtotal numeric(14,2),
    line_tax numeric(14,2),
    line_total numeric(14,2)
  ) on commit drop;
  truncate tmp_checkout_items;

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      coalesce(nullif(trim(item->>'description'), ''), '')::text as description,
      coalesce((item->>'quantity')::numeric, 0)::numeric(14,3) as quantity,
      coalesce((item->>'unit_price')::numeric, 0)::numeric(14,2) as unit_price
    from jsonb_array_elements(p_items) as item
  loop
    if v_item.product_id is null then
      raise exception 'Producto sin id en el carrito.' using errcode = '22023';
    end if;
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Cantidad inválida en producto %', v_item.product_id
        using errcode = '22023';
    end if;

    select p.id, p.name, p.price, p.tax_rate, p.stock, p.is_active,
           p.allow_negative_stock, p.is_service, p.is_tax_exempt
    into v_product
    from public.products p
    where p.id = v_item.product_id and p.branch_id = v_branch_id;

    if not found then
      raise exception 'Producto no encontrado: %', v_item.product_id
        using errcode = '23503';
    end if;
    if not v_product.is_active then
      raise exception 'Producto "%": inactivo.', v_product.name
        using errcode = '22023';
    end if;

    -- Validación de stock:
    --   - Servicios: nunca se valida.
    --   - Si el setting global está APAGADO → permitir siempre.
    --   - Si está PRENDIDO → respetar el flag por producto.
    if v_enforce_stock
       and (not v_product.is_service)
       and (not coalesce(v_product.allow_negative_stock, false))
       and (v_product.stock is null or v_product.stock < v_item.quantity) then
      raise exception 'Stock insuficiente para "%": disponible % requerido %',
        v_product.name, coalesce(v_product.stock, 0), v_item.quantity
        using errcode = '22023';
    end if;

    insert into tmp_checkout_items
    values (
      v_item.product_id,
      coalesce(nullif(v_item.description, ''), v_product.name),
      v_item.quantity,
      v_item.unit_price,
      case when v_product.is_tax_exempt then 0 else v_product.tax_rate end,
      round((v_item.unit_price * v_item.quantity)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             case when v_product.is_tax_exempt then 0
                  else v_product.tax_rate end / 100)::numeric, 2),
      round((v_item.unit_price * v_item.quantity *
             (1 + case when v_product.is_tax_exempt then 0
                       else v_product.tax_rate end / 100))::numeric, 2)
    );
    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count = 0 then
    raise exception 'No hay productos válidos en el carrito.'
      using errcode = '22023';
  end if;

  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_tax), 0),
    coalesce(sum(line_total), 0)
  into v_subtotal, v_tax_amount, v_total_amount
  from tmp_checkout_items;

  v_paid_amount := case when p_as_credit then 0 else v_total_amount end;
  v_balance_due := case when p_as_credit then v_total_amount else 0 end;

  if p_as_credit then
    select credit_default_days into v_default_days
    from public.app_settings where id = 1;
    v_default_days := coalesce(v_default_days, 30);
    v_due_days := coalesce(p_credit_due_days, v_default_days);
    if v_due_days <= 0 or v_due_days > 365 then
      v_due_days := v_default_days;
    end if;
    v_due_date := (v_now at time zone 'UTC')::date
                  + (v_due_days || ' days')::interval;
  end if;

  v_sale_number := 'VTA-'
    || to_char(v_now at time zone 'UTC', 'YYYYMMDD-HH24MISSMS')
    || '-'
    || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));

  insert into public.sales (
    branch_id, sale_number, client_id, cashier_id, receipt_type, status,
    sale_date, subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, balance_due, notes, due_date, cash_session_id
  ) values (
    v_branch_id, v_sale_number, p_client_id, v_user_id, v_receipt_type,
    v_sale_status, v_now, v_subtotal, 0, v_tax_amount, v_total_amount,
    v_paid_amount, v_balance_due, v_note, v_due_date, v_open_cash_session_id
  )
  returning id into v_sale_id;

  insert into public.sale_items (
    sale_id, branch_id, product_id, description, quantity, unit_price,
    discount_amount, tax_rate, line_subtotal, line_tax, line_total
  )
  select v_sale_id, v_branch_id, product_id, description, quantity,
         unit_price, 0, tax_rate, line_subtotal, line_tax, line_total
  from tmp_checkout_items
  order by product_id;

  if not p_as_credit then
    insert into public.payments (
      branch_id, sale_id, client_id, cash_session_id, payment_method,
      amount, paid_at, reference, notes
    ) values (
      v_branch_id, v_sale_id, p_client_id, v_open_cash_session_id,
      v_payment_method, v_total_amount, v_now, v_sale_number, v_note
    );
  elsif p_client_id is not null then
    update public.clients
    set balance_due = round(
      (coalesce(balance_due, 0) + v_total_amount)::numeric, 2
    )
    where id = p_client_id and branch_id = v_branch_id;
  end if;

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'sale_number', v_sale_number,
    'branch_id', v_branch_id,
    'cash_session_id', v_open_cash_session_id,
    'receipt_type', v_receipt_type,
    'status', v_sale_status,
    'subtotal', v_subtotal,
    'tax_amount', v_tax_amount,
    'total_amount', v_total_amount,
    'paid_amount', v_paid_amount,
    'balance_due', v_balance_due,
    'due_date', v_due_date,
    'items_count', (select count(*) from tmp_checkout_items)
  );
end;
$$;

grant execute on function public.checkout_sale_transactional(
  jsonb, text, boolean, text, uuid, text, integer
) to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260522_35_checkout_respects_global_stock_setting.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260522_36_user_isolation_per_company.sql
-- ============================================================
-- Fix: leak de usuarios entre empresas (multi-tenant).
--
-- Síntoma:
--   En /usuarios, el admin de una empresa ve los usuarios (profiles +
--   users_branches) de OTRAS empresas. Los cajeros y demás roles del
--   sistema aparecen mezclados sin importar a qué company pertenecen.
--
-- Causa raíz:
--   El RLS original de `profiles` y `users_branches` permite a CUALQUIER
--   admin ver todas las filas. Era OK en single-tenant, pero rompe el
--   aislamiento en multi-tenant.
--
--   profiles_select:    using (auth.uid() = id or public.is_admin())
--   users_branches_select: using (public.is_admin() or user_id = auth.uid())
--
-- Fix:
--   Endurecer ambas policies. El admin solo ve users / memberships cuyo
--   usuario tenga al menos una sucursal activa de su company.
--
-- Idempotente.

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) profiles: el admin solo ve su propio perfil y los de usuarios de su
--    company (vía users_branches → branches → company_id).
-- ─────────────────────────────────────────────────────────────────────────

drop policy if exists profiles_select on public.profiles;
create policy profiles_select
on public.profiles
for select
using (
  auth.uid() = id
  or (
    public.is_admin()
    and exists (
      select 1
      from public.users_branches ub
      join public.branches b on b.id = ub.branch_id
      where ub.user_id = public.profiles.id
        and ub.is_active
        and b.company_id = public.current_company_id()
    )
  )
);

-- INSERT / UPDATE / DELETE quedan como están — el admin se valida igual,
-- pero solo puede modificar profiles que ya pasan el SELECT (RLS aplica).
-- Si querés bloquear UPDATE/DELETE explícitamente, descomentar abajo.

drop policy if exists profiles_update on public.profiles;
create policy profiles_update
on public.profiles
for update
to authenticated
using (
  auth.uid() = id
  or (
    public.is_admin()
    and exists (
      select 1
      from public.users_branches ub
      join public.branches b on b.id = ub.branch_id
      where ub.user_id = public.profiles.id
        and ub.is_active
        and b.company_id = public.current_company_id()
    )
  )
)
with check (
  auth.uid() = id
  or (
    public.is_admin()
    and exists (
      select 1
      from public.users_branches ub
      join public.branches b on b.id = ub.branch_id
      where ub.user_id = public.profiles.id
        and ub.is_active
        and b.company_id = public.current_company_id()
    )
  )
);

drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete
on public.profiles
for delete
to authenticated
using (
  public.is_admin()
  and exists (
    select 1
    from public.users_branches ub
    join public.branches b on b.id = ub.branch_id
    where ub.user_id = public.profiles.id
      and ub.is_active
      and b.company_id = public.current_company_id()
  )
);

-- ─────────────────────────────────────────────────────────────────────────
-- 2) users_branches: el admin solo ve memberships en branches de su
--    company. El usuario sigue viendo los suyos.
-- ─────────────────────────────────────────────────────────────────────────

drop policy if exists users_branches_select on public.users_branches;
create policy users_branches_select
on public.users_branches
for select
to authenticated
using (
  user_id = auth.uid()
  or (
    public.is_admin()
    and exists (
      select 1
      from public.branches b
      where b.id = public.users_branches.branch_id
        and b.company_id = public.current_company_id()
    )
  )
);

drop policy if exists users_branches_write on public.users_branches;
create policy users_branches_write
on public.users_branches
for all
to authenticated
using (
  public.is_admin()
  and exists (
    select 1
    from public.branches b
    where b.id = public.users_branches.branch_id
      and b.company_id = public.current_company_id()
  )
)
with check (
  public.is_admin()
  and exists (
    select 1
    from public.branches b
    where b.id = public.users_branches.branch_id
      and b.company_id = public.current_company_id()
  )
);

commit;

-- ============================================================
-- END:   sql-next/20260522_36_user_isolation_per_company.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260522_37_branch_isolation_per_company.sql
-- ============================================================
-- Fix: leak de sucursales entre empresas (multi-tenant).
--
-- Síntoma:
--   El admin de una empresa ve sucursales (branches) de otras empresas en
--   /sucursales y en los selectores de "Asignar sucursal" al editar
--   usuarios. Mismo tipo de bug que tuvimos con profiles y users_branches
--   (migration 36), pero esta vez en la tabla branches.
--
-- Causa raíz:
--   El RLS original de `branches_select` permite al admin ver TODAS las
--   filas:
--     using (public.is_admin() or public.has_branch_access(id))
--
--   En multi-tenant, eso filtra sucursales entre empresas porque
--   `is_admin()` no chequea company.
--
-- Fix:
--   Endurecer las policies SELECT y WRITE para que el admin solo
--   alcance branches cuya company_id coincida con su current_company_id().
--   El usuario regular sigue viendo solo las branches a las que está
--   asignado (has_branch_access).
--
-- Idempotente.

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) branches: el admin solo ve / edita branches de su company.
-- ─────────────────────────────────────────────────────────────────────────

drop policy if exists branches_select on public.branches;
create policy branches_select
on public.branches
for select
to authenticated
using (
  public.has_branch_access(id)
  or (
    public.is_admin()
    and company_id = public.current_company_id()
  )
);

drop policy if exists branches_write on public.branches;
create policy branches_write
on public.branches
for all
to authenticated
using (
  public.is_admin()
  and company_id = public.current_company_id()
)
with check (
  public.is_admin()
  and company_id = public.current_company_id()
);

commit;

-- ============================================================
-- END:   sql-next/20260522_37_branch_isolation_per_company.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260522_38_multitenant_isolation_audit.sql
-- ============================================================
-- Audit consolidado de aislamiento multi-tenant.
--
-- Después de las migrations 34, 36 y 37 (app_settings, profiles+users_branches,
-- branches), quedaban 4 leaks pendientes detectados en review. Esta migration
-- los cierra todos.
--
-- Severidad de cada bug y fix aplicado:
--
-- 1. fiscal_dgii_reports (CRÍTICO)
--    - No tenía company_id. El UNIQUE(report_type, year, month) era global
--      → solo UNA empresa podía generar el 606 de un mes; las demás bloqueadas.
--    - RLS permitía a cualquier admin/accountant ver TODOS los reportes.
--    - Fix: agregar company_id NOT NULL (backfill desde generated_by → branch
--      → company), cambiar UNIQUE a (company_id, type, year, month), RLS por
--      has_company_access.
--
-- 2. custom_reports (ALTO)
--    - No tenía company_id. `is_shared=true` los hacía visibles entre TODAS
--      las empresas.
--    - Fix: agregar company_id, RLS para que is_shared aplique solo dentro
--      de la company.
--
-- 3. user_permissions (ALTO)
--    - RLS permitía a cualquier admin ver permisos de usuarios de otras
--      empresas (mismo patrón que profiles antes de migration 36).
--    - Fix: condicionar `is_admin()` a que el user tenga sucursales activas
--      en la company del admin.
--
-- 4. app_settings_audit (MEDIO)
--    - RLS abierto a cualquier admin. La tabla no tiene company_id, pero
--      cada fila refiere a un campo de app_settings (que sí tiene company).
--    - Fix: limitar el SELECT a admins cuya company sea la dueña del
--      app_settings auditado, vía la columna changed_by.
--
-- Adicional: vista `vw_isolation_audit_anomalies` para detectar manualmente
-- usuarios con users_branches en múltiples companies (anomalía que
-- saltearía has_branch_access).
--
-- Defensiva: cada bloque se salta si la tabla / columna requerida no existe
-- (idempotente y compatible con DBs en distinto estado).
--
-- Aplicar después de 34, 36 y 37.

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) fiscal_dgii_reports
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'fiscal_dgii_reports'
  ) then
    raise notice 'Salteando fiscal_dgii_reports: tabla no existe.';
    return;
  end if;

  -- 1.1: agregar company_id si falta.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fiscal_dgii_reports'
      and column_name = 'company_id'
  ) then
    execute $sql$
      alter table public.fiscal_dgii_reports
        add column company_id uuid references public.companies(id) on delete cascade
    $sql$;
  end if;

  -- 1.2: backfill desde generated_by → users_branches → branches.company_id.
  execute $sql$
    update public.fiscal_dgii_reports r
       set company_id = (
         select b.company_id
           from public.users_branches ub
           join public.branches b on b.id = ub.branch_id
          where ub.user_id = r.generated_by
            and ub.is_active
            and b.is_active
          order by ub.is_default desc, ub.created_at asc
          limit 1
       )
     where company_id is null
       and generated_by is not null
  $sql$;

  -- 1.3: filas sin generated_by o user huérfano → asignar a la company más
  --      antigua con sucursales activas, o borrar si no hay companies.
  execute $sql$
    update public.fiscal_dgii_reports
       set company_id = (
         select c.id
           from public.companies c
          where c.is_active
            and exists (select 1 from public.branches b
                        where b.company_id = c.id and b.is_active)
          order by c.created_at asc
          limit 1
       )
     where company_id is null
  $sql$;

  execute 'delete from public.fiscal_dgii_reports where company_id is null';

  -- 1.4: NOT NULL.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fiscal_dgii_reports'
      and column_name = 'company_id'
      and is_nullable = 'YES'
  ) then
    execute 'alter table public.fiscal_dgii_reports alter column company_id set not null';
  end if;

  -- 1.5: reemplazar UNIQUE global por una que incluya company_id.
  execute 'alter table public.fiscal_dgii_reports drop constraint if exists fiscal_dgii_reports_report_type_period_year_period_month_key';
  execute 'alter table public.fiscal_dgii_reports drop constraint if exists fiscal_dgii_reports_report_type_year_month_key';
  -- Constraint nueva (idempotente vía drop+add)
  begin
    execute $sql$
      alter table public.fiscal_dgii_reports
        add constraint fiscal_dgii_reports_company_period_unique
        unique (company_id, report_type, period_year, period_month)
    $sql$;
  exception when duplicate_object then null;
  end;

  -- 1.6: RLS basada en has_company_access.
  execute 'drop policy if exists fiscal_dgii_reports_select on public.fiscal_dgii_reports';
  execute $sql$
    create policy fiscal_dgii_reports_select on public.fiscal_dgii_reports
      for select to authenticated
      using (
        public.has_company_access(company_id)
        and (
          public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role
        )
      )
  $sql$;

  execute 'drop policy if exists fiscal_dgii_reports_insert on public.fiscal_dgii_reports';
  execute $sql$
    create policy fiscal_dgii_reports_insert on public.fiscal_dgii_reports
      for insert to authenticated
      with check (
        public.has_company_access(company_id)
        and (
          public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role
        )
      )
  $sql$;

  execute 'drop policy if exists fiscal_dgii_reports_update on public.fiscal_dgii_reports';
  execute $sql$
    create policy fiscal_dgii_reports_update on public.fiscal_dgii_reports
      for update to authenticated
      using (
        public.is_admin()
        and public.has_company_access(company_id)
      )
      with check (
        public.is_admin()
        and public.has_company_access(company_id)
      )
  $sql$;

  execute 'drop policy if exists fiscal_dgii_reports_delete on public.fiscal_dgii_reports';
  execute $sql$
    create policy fiscal_dgii_reports_delete on public.fiscal_dgii_reports
      for delete to authenticated
      using (
        public.is_admin()
        and public.has_company_access(company_id)
      )
  $sql$;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) custom_reports
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'custom_reports'
  ) then
    raise notice 'Salteando custom_reports: tabla no existe.';
    return;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'custom_reports'
      and column_name = 'company_id'
  ) then
    execute $sql$
      alter table public.custom_reports
        add column company_id uuid references public.companies(id) on delete cascade
    $sql$;
  end if;

  -- Backfill desde created_by.
  execute $sql$
    update public.custom_reports r
       set company_id = (
         select b.company_id
           from public.users_branches ub
           join public.branches b on b.id = ub.branch_id
          where ub.user_id = r.created_by
            and ub.is_active
            and b.is_active
          order by ub.is_default desc, ub.created_at asc
          limit 1
       )
     where company_id is null
  $sql$;

  -- Fallback: primera company activa.
  execute $sql$
    update public.custom_reports
       set company_id = (
         select c.id from public.companies c
          where c.is_active
          order by c.created_at asc
          limit 1
       )
     where company_id is null
  $sql$;

  execute 'delete from public.custom_reports where company_id is null';

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'custom_reports'
      and column_name = 'company_id'
      and is_nullable = 'YES'
  ) then
    execute 'alter table public.custom_reports alter column company_id set not null';
  end if;

  -- RLS: dueño siempre ve el suyo; is_shared aplica SOLO dentro de la company.
  execute 'drop policy if exists custom_reports_select on public.custom_reports';
  execute $sql$
    create policy custom_reports_select on public.custom_reports
      for select to authenticated
      using (
        created_by = auth.uid()
        or (is_shared = true and public.has_company_access(company_id))
        or (public.is_admin() and public.has_company_access(company_id))
      )
  $sql$;

  execute 'drop policy if exists custom_reports_insert on public.custom_reports';
  execute $sql$
    create policy custom_reports_insert on public.custom_reports
      for insert to authenticated
      with check (
        created_by = auth.uid()
        and public.has_company_access(company_id)
      )
  $sql$;

  execute 'drop policy if exists custom_reports_update on public.custom_reports';
  execute $sql$
    create policy custom_reports_update on public.custom_reports
      for update to authenticated
      using (
        (created_by = auth.uid() or public.is_admin())
        and public.has_company_access(company_id)
      )
      with check (
        (created_by = auth.uid() or public.is_admin())
        and public.has_company_access(company_id)
      )
  $sql$;

  execute 'drop policy if exists custom_reports_delete on public.custom_reports';
  execute $sql$
    create policy custom_reports_delete on public.custom_reports
      for delete to authenticated
      using (
        (created_by = auth.uid() or public.is_admin())
        and public.has_company_access(company_id)
      )
  $sql$;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) user_permissions
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'user_permissions'
  ) then
    raise notice 'Salteando user_permissions: tabla no existe.';
    return;
  end if;

  execute 'drop policy if exists user_permissions_select on public.user_permissions';
  execute $sql$
    create policy user_permissions_select on public.user_permissions
      for select to authenticated
      using (
        user_id = auth.uid()
        or (
          public.is_admin()
          and exists (
            select 1
              from public.users_branches ub
              join public.branches b on b.id = ub.branch_id
             where ub.user_id = public.user_permissions.user_id
               and ub.is_active
               and b.company_id = public.current_company_id()
          )
        )
      )
  $sql$;

  execute 'drop policy if exists user_permissions_write on public.user_permissions';
  execute $sql$
    create policy user_permissions_write on public.user_permissions
      for all to authenticated
      using (
        public.is_admin()
        and exists (
          select 1
            from public.users_branches ub
            join public.branches b on b.id = ub.branch_id
           where ub.user_id = public.user_permissions.user_id
             and ub.is_active
             and b.company_id = public.current_company_id()
        )
      )
      with check (
        public.is_admin()
        and exists (
          select 1
            from public.users_branches ub
            join public.branches b on b.id = ub.branch_id
           where ub.user_id = public.user_permissions.user_id
             and ub.is_active
             and b.company_id = public.current_company_id()
        )
      )
  $sql$;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) app_settings_audit
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'app_settings_audit'
  ) then
    raise notice 'Salteando app_settings_audit: tabla no existe.';
    return;
  end if;

  -- La tabla no tiene company_id directo, pero changed_by sí relaciona a un
  -- user → company vía users_branches. Eso filtra correctamente.
  execute 'drop policy if exists app_settings_audit_select on public.app_settings_audit';
  execute $sql$
    create policy app_settings_audit_select on public.app_settings_audit
      for select to authenticated
      using (
        public.is_admin()
        and (
          -- Cambios hechos por usuarios de mi company.
          exists (
            select 1
              from public.users_branches ub
              join public.branches b on b.id = ub.branch_id
             where ub.user_id = public.app_settings_audit.changed_by
               and ub.is_active
               and b.company_id = public.current_company_id()
          )
          -- O cambios hechos por el admin actual.
          or changed_by = auth.uid()
        )
      )
  $sql$;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5) Vista de diagnóstico: detectar anomalías cross-company.
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Un usuario "limpio" tiene users_branches en branches de UNA sola company.
-- Si por bug histórico quedó con membership en branches de varias companies,
-- esta vista lo lista para que el admin lo limpie a mano.
--
-- Si la vista devuelve 0 filas, el sistema está limpio.

create or replace view public.vw_isolation_audit_anomalies
with (security_invoker = true)
as
select
  ub.user_id,
  p.email,
  p.full_name,
  count(distinct b.company_id) as companies_count,
  array_agg(distinct b.company_id) as company_ids
from public.users_branches ub
join public.branches b on b.id = ub.branch_id
left join public.profiles p on p.id = ub.user_id
where ub.is_active
  and b.is_active
  and b.company_id is not null
group by ub.user_id, p.email, p.full_name
having count(distinct b.company_id) > 1;

comment on view public.vw_isolation_audit_anomalies is
  'Usuarios con membresía activa en sucursales de múltiples empresas. '
  'Cero filas = aislamiento OK.';

grant select on public.vw_isolation_audit_anomalies to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260522_38_multitenant_isolation_audit.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260522_39_users_branches_profile_fk.sql
-- ============================================================
-- Fix: PostgREST no detecta relación users_branches → profiles.
--
-- Síntoma:
--   En /sucursales, al cargar la lista de miembros de una sucursal, la
--   app falla con:
--     PostgrestException(
--       message: "Could not find a relationship between 'users_branches'
--       and 'profiles' in the schema cache",
--       code: PGRST200,
--       hint: "Perhaps you meant 'branches' instead of 'profiles'."
--     )
--
-- Causa raíz:
--   El query usa embedded select de PostgREST:
--     .from('users_branches').select('..., profiles(full_name, email, ...)')
--   PostgREST necesita una FK directa entre users_branches.user_id y
--   profiles.id para hacer el join. Pero el schema original solo tiene:
--     users_branches.user_id → auth.users(id)
--     profiles.id            → auth.users(id)
--   Ambas apuntan al mismo destino, pero NO una a la otra. PostgREST no
--   puede inferir la relación.
--
-- Fix:
--   Agregar una FK explícita users_branches.user_id → profiles.id. Es
--   lógicamente correcta: por el trigger handle_auth_user_upsert(), cada
--   user_id en users_branches tiene siempre un profile con ese id.
--
--   Después de aplicar esta migration y reiniciar PostgREST (notify pgrst),
--   los queries con embedded select funcionan.
--
-- Idempotente.

begin;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'users_branches_user_profile_fk'
      and conrelid = 'public.users_branches'::regclass
  ) then
    alter table public.users_branches
      add constraint users_branches_user_profile_fk
      foreign key (user_id)
      references public.profiles(id)
      on delete cascade;
  end if;
end $$;

-- Forzar reload del schema cache de PostgREST para que detecte la FK
-- recién agregada.
notify pgrst, 'reload schema';

commit;

-- ============================================================
-- END:   sql-next/20260522_39_users_branches_profile_fk.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/20260522_40_record_dgii_report_company.sql
-- ============================================================
-- Fix: record_dgii_report no pasaba company_id (rompía post-migration 38).
--
-- Después de la migration 38, fiscal_dgii_reports tiene:
--   - company_id NOT NULL
--   - UNIQUE (company_id, report_type, period_year, period_month)
--     (antes era UNIQUE solo por (report_type, year, month))
--
-- El RPC record_dgii_report quedó desactualizado:
--   1. Insertaba sin company_id → NOT NULL violation.
--   2. on conflict (report_type, year, month) ya no matchea el UNIQUE
--      nuevo → la UPSERT falla.
--
-- Fix: pasar company_id = current_company_id() y actualizar el on conflict.
-- Idempotente.

begin;

create or replace function public.record_dgii_report(
  p_report_type text,
  p_year integer,
  p_month integer,
  p_records_count integer,
  p_inconsistencies_count integer,
  p_storage_path text default null,
  p_txt_url text default null,
  p_pdf_url text default null,
  p_inconsistencies jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_company_id uuid;
begin
  if not (public.is_admin()
          or public.current_user_role() = 'accountant'::public.app_role) then
    raise exception 'Solo admin o accountant'
      using errcode = '42501';
  end if;

  v_company_id := public.current_company_id();
  if v_company_id is null then
    raise exception 'No hay empresa asignada al usuario actual.'
      using errcode = '22023';
  end if;

  insert into public.fiscal_dgii_reports (
    company_id, report_type, period_year, period_month, generated_by,
    records_count, inconsistencies_count, inconsistencies,
    txt_file_url, pdf_file_url, storage_path, status
  ) values (
    v_company_id,
    p_report_type::public.fiscal_dgii_report_type,
    p_year, p_month, auth.uid(),
    p_records_count, p_inconsistencies_count, p_inconsistencies,
    p_txt_url, p_pdf_url, p_storage_path, 'generated'
  )
  on conflict (company_id, report_type, period_year, period_month) do update set
    generated_at = timezone('utc', now()),
    generated_by = auth.uid(),
    records_count = excluded.records_count,
    inconsistencies_count = excluded.inconsistencies_count,
    inconsistencies = excluded.inconsistencies,
    txt_file_url = coalesce(excluded.txt_file_url, public.fiscal_dgii_reports.txt_file_url),
    pdf_file_url = coalesce(excluded.pdf_file_url, public.fiscal_dgii_reports.pdf_file_url),
    storage_path = coalesce(excluded.storage_path, public.fiscal_dgii_reports.storage_path)
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.record_dgii_report(
  text, integer, integer, integer, integer, text, text, text, jsonb
) to authenticated;

commit;

-- ============================================================
-- END:   sql-next/20260522_40_record_dgii_report_company.sql
-- ============================================================


-- ============================================================
-- BEGIN: sql-next/create_employee_rpc.sql
-- ============================================================
-- RPC para crear empleados directamente en auth.users sin Edge Function.
-- Requiere pgcrypto (ya instalado en Supabase).
-- Ejecutar en Supabase SQL Editor.

create or replace function public.create_employee_user(
  p_email         text,
  p_password      text,
  p_full_name     text,
  p_role          text,
  p_phone         text default null,
  p_employee_code text default null,
  p_job_title     text default null,
  p_notes         text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_caller_id   uuid := auth.uid();
  v_caller_role text;
  v_branch_id   uuid;
  v_user_id     uuid := gen_random_uuid();
  v_email       text := lower(trim(p_email));
begin
  -- Verificar permisos del llamador
  select role::text into v_caller_role
    from public.profiles
   where id = v_caller_id;

  if v_caller_role not in ('admin', 'supervisor') then
    raise exception 'Sin permisos para crear usuarios.'
      using errcode = '42501';
  end if;

  -- Obtener sucursal activa del llamador
  select branch_id into v_branch_id
    from public.users_branches
   where user_id   = v_caller_id
     and is_default = true
     and is_active  = true
   limit 1;

  if v_branch_id is null then
    raise exception 'No hay sucursal activa asignada al administrador.'
      using errcode = '22023';
  end if;

  -- Validaciones básicas
  if v_email is null or v_email = '' then
    raise exception 'El email es requerido.' using errcode = '22023';
  end if;
  if p_password is null or length(p_password) < 6 then
    raise exception 'La contraseña debe tener al menos 6 caracteres.' using errcode = '22023';
  end if;
  if p_full_name is null or trim(p_full_name) = '' then
    raise exception 'El nombre completo es requerido.' using errcode = '22023';
  end if;
  if p_role not in ('admin', 'supervisor', 'cashier', 'accountant') then
    raise exception 'Rol no válido: %', p_role using errcode = '22023';
  end if;

  -- Verificar email único
  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'Ya existe un usuario con ese email.' using errcode = '23505';
  end if;

  -- Insertar en auth.users (login inmediato, sin verificación de email)
  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_user_meta_data,
    raw_app_meta_data,
    is_super_admin,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    is_sso_user
  ) values (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    v_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    jsonb_build_object('full_name', trim(p_full_name), 'role', p_role),
    '{"provider":"email","providers":["email"]}'::jsonb,
    false,
    now(),
    now(),
    '', '', '', '',
    false
  );

  -- El trigger on_auth_user_created crea el perfil automáticamente.
  -- Actualizamos los campos extra que el trigger no cubre.
  update public.profiles set
    full_name     = trim(p_full_name),
    role          = p_role::public.app_role,
    phone         = nullif(trim(coalesce(p_phone, '')), ''),
    employee_code = nullif(trim(coalesce(p_employee_code, '')), ''),
    job_title     = nullif(trim(coalesce(p_job_title, '')), ''),
    is_active     = true
  where id = v_user_id;

  -- Asignar a la sucursal del administrador
  insert into public.users_branches (
    user_id, branch_id, role_override,
    is_default, is_active, created_by, updated_by
  ) values (
    v_user_id, v_branch_id, p_role::public.app_role,
    true, true, v_caller_id, v_caller_id
  )
  on conflict (user_id, branch_id) do update set
    role_override = excluded.role_override,
    is_default    = true,
    is_active     = true,
    updated_by    = v_caller_id;

  return v_user_id;
end;
$$;

grant execute on function public.create_employee_user(text, text, text, text, text, text, text, text) to authenticated;

notify pgrst, 'reload schema';

-- ============================================================
-- END:   sql-next/create_employee_rpc.sql
-- ============================================================

