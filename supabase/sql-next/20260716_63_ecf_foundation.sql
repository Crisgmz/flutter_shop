-- ============================================================================
-- Migración 63 — Facturación electrónica (e-CF) — fundación
-- ============================================================================
-- Porta el concepto de mangospos/mangopos-backend (integración Alanube):
--   * La app Flutter NUNCA llama a Alanube directo; todo pasa por Edge
--     Functions (emit-document, register-company, alanube-webhook).
--   * La emisión está DESACOPLADA de la venta: el cobro nunca falla por e-CF.
--     Un trigger encola el documento en `ecf_emit_outbox`; el POS dispara la
--     Edge Function en modo sync (para tener el QR antes de imprimir) y un
--     cron cada 60s drena la cola como respaldo.
--   * Estados e-CF: pending → sent (Alanube aceptó, DGII en proceso)
--     → accepted | rejected. El webhook de Alanube trae el veredicto DGII.
--
-- Adaptaciones a flutter_shop+:
--   * Config por EMPRESA (companies), no por sucursal: el RNC emisor y el
--     mapping Alanube (`alanube_company_id`) son de la empresa.
--   * `receipt_type` sigue siendo semántico (consumer_final, fiscal_credit…);
--     la serie del NCF decide si es físico (B…) o electrónico (E…).
--     e-NCF DGII = 'E' + tipo (2 díg.) + secuencia (10 díg.) = 13 caracteres.
--   * `company_ecf_settings.mode` controla qué serie consume assign_next_ncf:
--       physical   → solo secuencias B (comportamiento actual, default)
--       electronic → solo secuencias E
--       hybrid     → prefiere E, cae a B si no hay
--
-- Idempotente. Ejecutar en el SQL Editor de Supabase DESPUÉS de la 62.
-- ============================================================================

begin;

-- =====================================================
-- 1) company_ecf_settings — config e-CF por empresa
-- =====================================================
-- Espejo de business_alanube_settings de mangospos. El certificado digital lo
-- custodia el proveedor (Alanube BaaS): aquí solo guardamos referencias.

create table if not exists public.company_ecf_settings (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null references public.companies(id) on delete cascade,
  provider             text not null default 'alanube',
  alanube_company_id   text,          -- ULID que devuelve POST /companies
  environment          text not null default 'sandbox'
                       check (environment in ('sandbox', 'production')),
  certification_status text not null default 'pending'
                       check (certification_status in ('pending', 'in_progress', 'certified', 'rejected')),
  mode                 text not null default 'physical'
                       check (mode in ('physical', 'electronic', 'hybrid')),
  webhook_secret       text,
  webhooks_configured  boolean not null default false,
  notify_by_email      boolean not null default false,
  created_at           timestamptz not null default timezone('utc', now()),
  updated_at           timestamptz not null default timezone('utc', now()),
  created_by           uuid references auth.users(id),
  updated_by           uuid references auth.users(id),
  unique (company_id)
);

create unique index if not exists company_ecf_settings_alanube_id_key
  on public.company_ecf_settings (alanube_company_id)
  where alanube_company_id is not null;

comment on table public.company_ecf_settings is
  'Configuración de facturación electrónica (e-CF) por empresa: mapping Alanube, ambiente, modalidad.';

alter table public.company_ecf_settings enable row level security;

drop policy if exists company_ecf_settings_select on public.company_ecf_settings;
create policy company_ecf_settings_select on public.company_ecf_settings
  for select using (public.has_company_access(company_id));

drop policy if exists company_ecf_settings_insert on public.company_ecf_settings;
create policy company_ecf_settings_insert on public.company_ecf_settings
  for insert with check (public.has_company_access(company_id) and public.is_admin());

drop policy if exists company_ecf_settings_update on public.company_ecf_settings;
create policy company_ecf_settings_update on public.company_ecf_settings
  for update using (public.has_company_access(company_id) and public.is_admin());

drop trigger if exists trg_company_ecf_settings_audit on public.company_ecf_settings;
create trigger trg_company_ecf_settings_audit
  before insert or update on public.company_ecf_settings
  for each row execute function public.set_audit_fields();

-- =====================================================
-- 2) fiscal_documents — columnas e-CF
-- =====================================================
-- Mismos nombres que mangospos para portar los Edge Functions casi verbatim.

alter table public.fiscal_documents
  add column if not exists is_electronic        boolean generated always as (left(ncf, 1) = 'E') stored,
  add column if not exists ecf_status           text
    check (ecf_status is null or ecf_status in ('pending', 'sent', 'accepted', 'rejected')),
  add column if not exists alanube_document_id  text,
  add column if not exists ecf_tracking_number  text,   -- trackId DGII
  add column if not exists ecf_security_code    text,   -- para el QR (Norma 01-2020)
  add column if not exists ecf_signed_at        timestamptz,
  add column if not exists public_url           text,   -- URL de consulta/timbre DGII
  add column if not exists xml_url              text,
  add column if not exists pdf_url              text,
  add column if not exists submitted_at         timestamptz,
  add column if not exists accepted_at          timestamptz,
  add column if not exists last_error           text,
  add column if not exists retry_count          integer not null default 0,
  add column if not exists idempotency_key      text;

create unique index if not exists fiscal_documents_alanube_id_key
  on public.fiscal_documents (alanube_document_id)
  where alanube_document_id is not null;

create unique index if not exists fiscal_documents_idempotency_key
  on public.fiscal_documents (branch_id, idempotency_key)
  where idempotency_key is not null;

-- Documentos electrónicos en tránsito (para cron/monitoreo)
create index if not exists fiscal_documents_ecf_pending_idx
  on public.fiscal_documents (branch_id, ecf_status)
  where ecf_status in ('pending', 'sent');

-- =====================================================
-- 3) ecf_emit_outbox — cola de emisión
-- =====================================================
-- Un fiscal_document = un job (idempotencia natural por unique FK).

create table if not exists public.ecf_emit_outbox (
  id                  uuid primary key default gen_random_uuid(),
  fiscal_document_id  uuid not null references public.fiscal_documents(id) on delete cascade,
  branch_id           uuid not null references public.branches(id) on delete cascade,
  company_id          uuid not null references public.companies(id) on delete cascade,
  status              text not null default 'pending'
                      check (status in ('pending', 'processing', 'done', 'failed')),
  attempts            integer not null default 0,
  last_attempt_at     timestamptz,
  -- Null cuando el job terminó (done); si no, cuándo toca el próximo intento.
  next_attempt_at     timestamptz default timezone('utc', now()),
  error               text,
  created_at          timestamptz not null default timezone('utc', now()),
  updated_at          timestamptz not null default timezone('utc', now()),
  unique (fiscal_document_id)
);

create index if not exists ecf_emit_outbox_pending_idx
  on public.ecf_emit_outbox (status, next_attempt_at)
  where status in ('pending', 'processing');

comment on table public.ecf_emit_outbox is
  'Cola de emisión e-CF. La procesa la Edge Function emit-document (sync desde el POS o batch por cron).';

alter table public.ecf_emit_outbox enable row level security;

-- Lectura para usuarios de la sucursal (mostrar estado/diagnóstico).
-- Escritura solo service_role (Edge Functions) y triggers security definer.
drop policy if exists ecf_emit_outbox_select on public.ecf_emit_outbox;
create policy ecf_emit_outbox_select on public.ecf_emit_outbox
  for select using (public.has_branch_access(branch_id));

drop trigger if exists trg_ecf_emit_outbox_updated_at on public.ecf_emit_outbox;
create trigger trg_ecf_emit_outbox_updated_at
  before update on public.ecf_emit_outbox
  for each row execute function public.set_updated_at();

-- =====================================================
-- 4) fiscal_document_status_events — auditoría append-only
-- =====================================================

create table if not exists public.fiscal_document_status_events (
  id                  uuid primary key default gen_random_uuid(),
  fiscal_document_id  uuid not null references public.fiscal_documents(id) on delete cascade,
  branch_id           uuid not null references public.branches(id) on delete cascade,
  previous_status     text,
  new_status          text not null,
  source              text not null default 'api_response'
                      check (source in ('enqueue', 'api_response', 'webhook', 'manual', 'retry_job', 'reconciliation')),
  note                text,
  created_at          timestamptz not null default timezone('utc', now())
);

create index if not exists fiscal_document_status_events_doc_idx
  on public.fiscal_document_status_events (fiscal_document_id, created_at desc);

comment on table public.fiscal_document_status_events is
  'Historial de cambios de estado e-CF por documento (append-only).';

alter table public.fiscal_document_status_events enable row level security;

drop policy if exists fiscal_document_status_events_select on public.fiscal_document_status_events;
create policy fiscal_document_status_events_select on public.fiscal_document_status_events
  for select using (public.has_branch_access(branch_id));

-- =====================================================
-- 5) ecf_webhook_inbox — bandeja de webhooks Alanube
-- =====================================================
-- Solo service_role: RLS habilitado sin policies = deny para authenticated.

create table if not exists public.ecf_webhook_inbox (
  id               uuid primary key default gen_random_uuid(),
  event_type       text,
  payload          jsonb not null default '{}'::jsonb,
  headers          jsonb not null default '{}'::jsonb,
  signature_valid  boolean,
  processed        boolean not null default false,
  processed_at     timestamptz,
  error            text,
  received_at      timestamptz not null default timezone('utc', now())
);

comment on table public.ecf_webhook_inbox is
  'Webhooks crudos recibidos de Alanube (auditoría/replay). Acceso solo service_role.';

alter table public.ecf_webhook_inbox enable row level security;

-- =====================================================
-- 6) assign_next_ncf — soporte serie E + modalidad
-- =====================================================
-- Cambios sobre la versión de la migración 56:
--   * La modalidad de la empresa (company_ecf_settings.mode) decide qué serie
--     se consume: physical→B, electronic→E, hybrid→E con fallback a B.
--     Sin fila de settings ⇒ physical (comportamiento actual intacto).
--   * Padding por serie: E = 10 dígitos (e-NCF de 13 chars), B = 8 dígitos.

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
  v_mode      text;
  v_seq_id    uuid;
  v_prefix    text;
  v_next_num  bigint;
  v_seq_end   bigint;
  v_ncf       text;
begin
  if p_branch_id is null then
    raise exception 'branch_id requerido' using errcode = '22023';
  end if;

  if not public.has_branch_access(p_branch_id) and not public.is_admin() then
    raise exception 'Sin acceso a la sucursal indicada' using errcode = '42501';
  end if;

  select coalesce(ces.mode, 'physical')
    into v_mode
    from public.branches b
    left join public.company_ecf_settings ces on ces.company_id = b.company_id
   where b.id = p_branch_id;
  v_mode := coalesce(v_mode, 'physical');

  -- Buscar la secuencia activa con capacidad. El "siguiente número efectivo" se
  -- deriva de next_number, o si está sin inicializar de
  -- greatest(inicio_rango, current_number + 1) — igual que vw_ncf_stock.
  -- En hybrid se prefiere la serie E; a igual serie, el número más bajo.
  select id, prefix,
         coalesce(
           next_number,
           greatest(coalesce(sequence_start, 1), coalesce(current_number, 0) + 1)
         ),
         sequence_end
    into v_seq_id, v_prefix, v_next_num, v_seq_end
    from public.ncf_sequences
   where branch_id = p_branch_id
     and receipt_type = p_receipt_type
     and is_active = true
     and coalesce(status, 'active') = 'active'
     and (expires_on is null or expires_on >= current_date)
     and (
       sequence_end is null
       or coalesce(
            next_number,
            greatest(coalesce(sequence_start, 1), coalesce(current_number, 0) + 1)
          ) <= sequence_end
     )
     and (
       case v_mode
         when 'electronic' then prefix like 'E%'
         when 'physical'   then prefix not like 'E%'
         else true
       end
     )
   order by (prefix like 'E%') desc,
            coalesce(
              next_number,
              greatest(coalesce(sequence_start, 1), coalesce(current_number, 0) + 1)
            ) asc
   limit 1
   for update;

  if v_seq_id is null then
    raise exception 'No hay secuencia NCF disponible para % en esta sucursal (modalidad %). Configúrala en Configuración › Mi cuenta/NCF.', p_receipt_type, v_mode
      using errcode = 'P0001';
  end if;

  if v_seq_end is not null and v_next_num > v_seq_end then
    raise exception 'Secuencia NCF agotada para % (último: %). Crea una nueva o extiéndela.', p_receipt_type, v_seq_end
      using errcode = 'P0001';
  end if;

  update public.ncf_sequences
     set current_number = v_next_num,
         next_number    = v_next_num + 1,
         updated_at     = timezone('utc', now())
   where id = v_seq_id;

  -- e-NCF DGII: 'E' + tipo (2) + secuencia (10). Físico: prefijo + 8 dígitos.
  v_ncf := v_prefix || lpad(v_next_num::text, case when v_prefix like 'E%' then 10 else 8 end, '0');
  return v_ncf;
end;
$$;

grant execute on function public.assign_next_ncf(uuid, public.receipt_type) to authenticated;

comment on function public.assign_next_ncf(uuid, public.receipt_type) is
  'Lockea y avanza la secuencia NCF activa para (branch, tipo). Serie según modalidad e-CF de la empresa (physical/electronic/hybrid). E = 10 dígitos, B = 8.';

-- =====================================================
-- 7) Encolado de emisión — triggers en fiscal_documents
-- =====================================================
-- BEFORE INSERT: marca ecf_status='pending' en documentos serie E.
-- AFTER INSERT: encola en ecf_emit_outbox + evento + pg_notify.
-- Ambos con manejo de errores: el e-CF JAMÁS rompe el cobro.

create or replace function public.tg_fiscal_documents_ecf_status()
returns trigger
language plpgsql
as $$
begin
  if left(new.ncf, 1) = 'E' and new.ecf_status is null then
    new.ecf_status := 'pending';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_fiscal_documents_ecf_status on public.fiscal_documents;
create trigger trg_fiscal_documents_ecf_status
  before insert on public.fiscal_documents
  for each row
  execute function public.tg_fiscal_documents_ecf_status();

create or replace function public.tg_fiscal_documents_enqueue_ecf()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_mode       text;
begin
  if left(new.ncf, 1) <> 'E' then
    return new;
  end if;

  begin
    select b.company_id, coalesce(ces.mode, 'physical')
      into v_company_id, v_mode
      from public.branches b
      left join public.company_ecf_settings ces on ces.company_id = b.company_id
     where b.id = new.branch_id;

    if v_company_id is null or v_mode = 'physical' then
      return new;
    end if;

    insert into public.ecf_emit_outbox (fiscal_document_id, branch_id, company_id)
    values (new.id, new.branch_id, v_company_id)
    on conflict (fiscal_document_id) do nothing;

    insert into public.fiscal_document_status_events
      (fiscal_document_id, branch_id, previous_status, new_status, source, note)
    values
      (new.id, new.branch_id, null, 'pending', 'enqueue', 'Documento electrónico encolado para emisión');

    perform pg_notify('ecf_emit', new.id::text);
  exception when others then
    -- Nunca romper la venta por fallas del encolado e-CF.
    raise notice 'No se pudo encolar e-CF para documento % (%): %', new.id, new.ncf, SQLERRM;
  end;

  return new;
end;
$$;

drop trigger if exists trg_fiscal_documents_enqueue_ecf on public.fiscal_documents;
create trigger trg_fiscal_documents_enqueue_ecf
  after insert on public.fiscal_documents
  for each row
  execute function public.tg_fiscal_documents_enqueue_ecf();

commit;

notify pgrst, 'reload schema';
