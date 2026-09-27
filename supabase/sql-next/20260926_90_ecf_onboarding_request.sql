-- ============================================================================
-- Migración 90 — Solicitud de facturación electrónica (e-CF) desde la app
-- ============================================================================
-- El dueño pide la facturación electrónica desde Configuración: manda sus
-- datos tal como están en la DGII, un contacto y su certificado de firma
-- (.p12). La empresa se registra en Alanube en esa misma petición y el
-- certificado NO se guarda — viaja a Alanube y se descarta.
--
-- Portado de mangospos (`ecf_onboarding`, migraciones 20260917_0002 y 0006),
-- que es donde este flujo ya está probado. Diferencias con el original:
--
--   * La llave es `company_id` y no `business_id`: en flutter_shop+ la empresa
--     es el inquilino (`companies`), y la facturación es de la empresa, no de
--     la sucursal. Es la misma llave que usa `company_ecf_settings`.
--   * El avance (empresa registrada, certificación, secuencias, activación) NO
--     se guarda acá: se deriva de `company_ecf_settings` y `ncf_sequences`,
--     igual que en mangospos. Un estado paralelo se desincroniza.
--
-- Solo la toca la Edge Function `ecf-onboarding` con service_role. La app
-- nunca lee esta tabla directo: pide `request_status` a la función, que es
-- quien sabe derivar la etapa.
--
-- Idempotente: se puede correr varias veces sin efectos secundarios.
-- ============================================================================

begin;

create table if not exists public.ecf_onboarding (
  company_id           uuid primary key
                         references public.companies(id) on delete cascade,

  -- ── Datos del contribuyente, como están en la DGII ──────────────────────
  rnc                  text,
  legal_name           text,
  trade_name           text,
  fiscal_address       text,
  province             text,
  municipality         text,
  email                text,

  -- ── Empresa en el proveedor (Alanube) ───────────────────────────────────
  alanube_company_id   text unique,
  company_linked_via   text
                         check (company_linked_via in ('registered', 'existing')),
  company_linked_at    timestamptz,

  -- ── La solicitud del cliente ────────────────────────────────────────────
  requested_at         timestamptz,
  requested_by         uuid references auth.users(id),
  contact_name         text,
  contact_phone        text,
  already_authorized   boolean,

  -- ── Seguimiento ─────────────────────────────────────────────────────────
  -- Se marca cuando el aviso al panel de soporte salió bien. Null = nadie
  -- afuera se enteró todavía; el reintento lo hace la propia función.
  notified_at          timestamptz,

  created_by           uuid references auth.users(id),
  updated_by           uuid references auth.users(id),
  created_at           timestamptz not null default timezone('utc', now()),
  updated_at           timestamptz not null default timezone('utc', now())
);

comment on table public.ecf_onboarding is
  'Solicitud de facturación electrónica de una empresa y su avance. Solo la '
  'escribe la Edge Function ecf-onboarding (service_role). NO guarda el '
  'certificado digital ni su contraseña: viajan a Alanube y se descartan.';
comment on column public.ecf_onboarding.fiscal_address is
  'Domicilio fiscal registrado en la DGII. Puede diferir de la dirección del '
  'local que sale en la factura (app_settings.company_address).';
comment on column public.ecf_onboarding.company_linked_via is
  'registered: la empresa se creó en Alanube desde acá (POST /company). '
  'existing: ya existía con ese RNC y solo se vinculó el ULID.';
comment on column public.ecf_onboarding.already_authorized is
  'Lo que declaró el cliente al pedirlo: si ya es emisor electrónico '
  'autorizado por la DGII. Informativo; lo confirma quien da soporte.';

create index if not exists ecf_onboarding_requested_at_idx
  on public.ecf_onboarding (requested_at)
  where requested_at is not null;

-- Pendientes de avisar al panel: el reintento barre por acá.
create index if not exists ecf_onboarding_pending_notify_idx
  on public.ecf_onboarding (requested_at)
  where requested_at is not null and notified_at is null;

-- ── RLS: nadie desde el cliente ─────────────────────────────────────────────
-- Sin políticas, con RLS activo, `authenticated` no ve ni escribe nada. La
-- única vía es la Edge Function con service_role, que valida que quien pide
-- sea admin de la empresa. Los datos fiscales y el contacto no tienen por qué
-- ser legibles desde el navegador.
alter table public.ecf_onboarding enable row level security;

drop trigger if exists trg_ecf_onboarding_updated_at on public.ecf_onboarding;
create trigger trg_ecf_onboarding_updated_at
before update on public.ecf_onboarding
for each row execute function public.set_updated_at();

commit;

notify pgrst, 'reload schema';
