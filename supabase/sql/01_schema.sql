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
