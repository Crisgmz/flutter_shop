-- ============================================================================
-- Migración 105 — Certificación e-CF ante la DGII desde la app
-- ============================================================================
-- El admin de la empresa hace él mismo la certificación de emisor electrónico
-- desde Configuración → Facturación electrónica (5 pasos, igual que el panel de
-- MangoPOS): firma la postulación, carga el set de pruebas de la DGII, lo firma
-- y lo manda, las aprobaciones comerciales, la simulación y la declaración.
--
-- Esto REVIERTE la decisión del 28 oct 2026 (certificación manual, sin guardar
-- nada): para firmar los sets durante varios días hace falta conservar el
-- certificado .p12 con su contraseña. Se guardan CIFRADOS por la Edge Function
-- `ecf-onboarding` (AES-256-GCM, llave `ECF_CREDENTIALS_KEY` del entorno de
-- las funciones, nunca en la BD; el company_id va como dato autenticado). Los
-- checks impiden guardar texto plano por error. Lo mismo la clave de la OFV y
-- el token de la DGII.
--
-- Portado de mangospos, migraciones 20260917_0003, 20261008_0001 (solo la
-- clave OFV; lo demás ya está en la 102), 20261008_0003, 20261009_0002,
-- 20261009_0003, 20261009_0006 y 20261027_0001. Diferencias:
--   * El dueño es `company_id` (como en la 90), no `business_id`.
--   * Sin `set_test_id` / `set_test_created_at` (set de Alanube que mangospos
--     dejó sin uso).
--   * `ecf_onboarding_audit` nueva: aquí no hay `noc_audit_log`. Usar el
--     certificado guardado o ver la clave de la OFV sin dejar rastro no se
--     permite (la función aborta si no puede auditar).
--
-- Todas las tablas: RLS encendido y SIN policies. Solo service_role (la Edge
-- Function, que valida que quien llama sea admin de la empresa).
--
-- Depende de las migraciones 90 y 102. Aplicar ANTES de publicar la versión de
-- ecf-onboarding que la usa. Idempotente.
-- ============================================================================

begin;

-- ── 1. ecf_onboarding: avance de la certificación y secretos cifrados ───────

alter table public.ecf_onboarding
  add column if not exists postulation_signed_at       timestamptz,
  add column if not exists declaration_signed_at       timestamptz,
  add column if not exists roles_signed_at             timestamptz,
  add column if not exists dgii_authorized_at          timestamptz,
  add column if not exists ofv_password_enc            text,
  add column if not exists ofv_password_updated_at     timestamptz,
  add column if not exists certificate_filename        text,
  add column if not exists certificate_updated_at      timestamptz,
  add column if not exists certificate_enc             text,
  add column if not exists test_set_filename           text,
  add column if not exists test_set_loaded_at          timestamptz,
  add column if not exists approval_set_filename       text,
  add column if not exists approval_set_loaded_at      timestamptz,
  add column if not exists simulation_set_generated_at timestamptz,
  add column if not exists simulation_sequences        jsonb not null default '{}'::jsonb,
  add column if not exists dgii_test_token_enc         text,
  add column if not exists dgii_test_token_expires_at  timestamptz;

alter table public.ecf_onboarding
  drop constraint if exists ecf_onboarding_ofv_password_sealed,
  add constraint ecf_onboarding_ofv_password_sealed
    check (ofv_password_enc is null or ofv_password_enc like 'v1:%'),
  drop constraint if exists ecf_onboarding_certificate_sealed,
  add constraint ecf_onboarding_certificate_sealed
    check (certificate_enc is null or certificate_enc like 'v1:%'),
  drop constraint if exists ecf_onboarding_dgii_test_token_sealed,
  add constraint ecf_onboarding_dgii_test_token_sealed
    check (dgii_test_token_enc is null or dgii_test_token_enc like 'v1:%'),
  drop constraint if exists ecf_onboarding_simulation_sequences_is_object,
  add constraint ecf_onboarding_simulation_sequences_is_object
    check (jsonb_typeof(simulation_sequences) = 'object');

comment on table public.ecf_onboarding is
  'Solicitud de facturación electrónica de una empresa y su certificación ante '
  'la DGII. Solo la escribe la Edge Function ecf-onboarding (service_role). El '
  'certificado con su contraseña, la clave OFV y el token de la DGII se guardan '
  'cifrados (ECF_CREDENTIALS_KEY) y nunca vuelven al navegador.';
comment on column public.ecf_onboarding.postulation_signed_at is
  'Última firma del XML de postulación. Firmar no es subirlo: la verdad está en la OFV.';
comment on column public.ecf_onboarding.declaration_signed_at is
  'Última firma de la declaración jurada.';
comment on column public.ecf_onboarding.roles_signed_at is
  'Última firma del XML de asignación de roles (opcional).';
comment on column public.ecf_onboarding.dgii_authorized_at is
  'Lo marca el admin: la DGII lo autorizó como emisor electrónico. Solo mueve '
  'la etapa de la tarjeta; no habilita la emisión (eso es company_ecf_settings.mode).';
comment on column public.ecf_onboarding.ofv_password_enc is
  'Clave de la OFV cifrada (AES-256-GCM, ECF_CREDENTIALS_KEY, AAD company_id). '
  'Formato v1:base64. Solo la descifra reveal_ofv_password, que queda auditada.';
comment on column public.ecf_onboarding.certificate_enc is
  'Certificado .p12 y su contraseña cifrados (AES-256-GCM, ECF_CREDENTIALS_KEY, '
  'AAD company_id:ecf-certificate). Se abre solo para firmar en el servidor.';
comment on column public.ecf_onboarding.certificate_filename is
  'Nombre del certificado guardado para firmar.';
comment on column public.ecf_onboarding.test_set_filename is
  'Archivo del set de pruebas de datos e-CF de la DGII que está cargado.';
comment on column public.ecf_onboarding.approval_set_filename is
  'Archivo de aprobaciones comerciales de la DGII que está cargado.';
comment on column public.ecf_onboarding.simulation_sequences is
  'Último e-NCF usado por tipo en la simulación ({"31": 16, ...}). No baja '
  'nunca: la DGII no deja reusar números.';
comment on column public.ecf_onboarding.dgii_test_token_enc is
  'Token de CerteCF cifrado (dura ~1 h): consultar los envíos sin volver a firmar la semilla.';

-- ── 2. Casos del set de pruebas de la DGII ──────────────────────────────────

create table if not exists public.ecf_test_set_cases (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references public.companies(id) on delete cascade,
  kind           text not null default 'ecf'
                   check (kind in ('ecf', 'acecf', 'sim')),
  position       integer not null,
  case_id        text not null,
  ecf_type       text not null,
  encf           text not null,
  total          numeric(18, 2),
  via            text not null check (via in ('ecf', 'rfce', 'acecf')),
  modifies       text,
  issuer_rnc     text,
  fields         jsonb not null check (jsonb_typeof(fields) = 'array'),
  summary_fields jsonb check (summary_fields is null or jsonb_typeof(summary_fields) = 'array'),
  status         text not null default 'pending'
                   check (status in ('pending', 'sent', 'accepted', 'conditional', 'rejected', 'error')),
  track_id       text,
  security_code  text,
  signed_xml     text,
  messages       jsonb,
  sent_at        timestamptz,
  checked_at     timestamptz,
  created_at     timestamptz not null default now()
);

create index if not exists ecf_test_set_cases_company_idx
  on public.ecf_test_set_cases (company_id, kind, position);

-- e-CF y simulación: un e-NCF por set. Aprobaciones: emisor + e-NCF (el mismo
-- e-NCF puede venir de emisores distintos).
create unique index if not exists ecf_test_set_cases_encf_unique
  on public.ecf_test_set_cases (company_id, kind, encf)
  where kind <> 'acecf';
create unique index if not exists ecf_test_set_cases_acecf_unique
  on public.ecf_test_set_cases (company_id, kind, coalesce(issuer_rnc, ''), encf)
  where kind = 'acecf';

alter table public.ecf_test_set_cases enable row level security;

comment on table public.ecf_test_set_cases is
  'Set de pruebas de la DGII (certificación e-CF): un caso por fila del Excel, '
  'o por e-CF de la simulación. Solo lo escribe ecf-onboarding (service_role).';
comment on column public.ecf_test_set_cases.kind is
  'ecf = pruebas de datos e-CF (+ RFCE); acecf = aprobación comercial; sim = simulación.';
comment on column public.ecf_test_set_cases.via is
  'ecf = Recepción + trackId; rfce = E32 < 250 mil, se manda su resumen; acecf = aprobación comercial.';
comment on column public.ecf_test_set_cases.fields is
  'Pares [columna, valor] de la hoja ECF tal cual el archivo (sin celdas vacías ni #e).';
comment on column public.ecf_test_set_cases.summary_fields is
  'E32 menor de RD$250 mil: pares de la hoja RFCE (o derivados del E32 si se subió un CSV).';
comment on column public.ecf_test_set_cases.issuer_rnc is
  'Aprobaciones comerciales: RNC del emisor del e-CF aprobado, solo dígitos.';
comment on column public.ecf_test_set_cases.signed_xml is
  'XML firmado que se mandó (los E32 < 250 mil se suben a mano en el portal).';

-- ── 3. Reemplazo atómico de un set ──────────────────────────────────────────
-- Borrar y guardar en una transacción: si el set nuevo no entra, el anterior
-- queda como estaba.

create or replace function public.fn_ecf_replace_test_set_cases(
  p_company_id uuid,
  p_kind text,
  p_cases jsonb
)
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_count integer;
begin
  if p_company_id is null or p_kind is null then
    raise exception 'COMPANY_AND_KIND_REQUIRED';
  end if;
  if jsonb_typeof(p_cases) is distinct from 'array' then
    raise exception 'CASES_MUST_BE_ARRAY';
  end if;

  delete from public.ecf_test_set_cases
  where company_id = p_company_id
    and kind = p_kind;

  insert into public.ecf_test_set_cases (
    company_id, kind, position, case_id, ecf_type, encf, total, via,
    modifies, fields, summary_fields, issuer_rnc
  )
  select p_company_id, p_kind, c.position, c.case_id, c.ecf_type, c.encf,
         c.total, c.via, c.modifies, c.fields, c.summary_fields, c.issuer_rnc
  from jsonb_to_recordset(p_cases) as c(
    position integer, case_id text, ecf_type text, encf text, total numeric,
    via text, modifies text, fields jsonb, summary_fields jsonb, issuer_rnc text
  );
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

-- Simulación: dos «Generar» a la vez reservarían los MISMOS e-NCF. Se bloquea
-- la fila, se comprueba que las secuencias siguen siendo las que leyó quien
-- generó y solo entonces se reservan y se reemplazan los casos.
create or replace function public.fn_ecf_replace_simulation_set(
  p_company_id uuid,
  p_user_id uuid,
  p_expected_sequences jsonb,
  p_sequences jsonb,
  p_cases jsonb
)
returns timestamptz
language plpgsql
set search_path = public
as $$
declare
  v_current jsonb;
  v_now timestamptz := now();
begin
  select simulation_sequences into v_current
  from public.ecf_onboarding
  where company_id = p_company_id
  for update;

  if not found then
    raise exception 'ONBOARDING_NOT_FOUND';
  end if;
  if v_current is distinct from coalesce(p_expected_sequences, '{}'::jsonb) then
    raise exception 'SIMULATION_CONFLICT'
      using detail = 'Otra simulación reservó números mientras se armaba esta.';
  end if;

  update public.ecf_onboarding
  set simulation_sequences = p_sequences,
      simulation_set_generated_at = v_now,
      updated_by = p_user_id
  where company_id = p_company_id;

  perform public.fn_ecf_replace_test_set_cases(p_company_id, 'sim', p_cases);

  return v_now;
end;
$$;

revoke all on function public.fn_ecf_replace_test_set_cases(uuid, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.fn_ecf_replace_simulation_set(uuid, uuid, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.fn_ecf_replace_test_set_cases(uuid, text, jsonb) to service_role;
grant execute on function public.fn_ecf_replace_simulation_set(uuid, uuid, jsonb, jsonb, jsonb) to service_role;

-- ── 4. Bitácora de la certificación ─────────────────────────────────────────
-- Quién usó el certificado guardado, quién vio la clave de la OFV, qué se
-- mandó a la DGII. Sin secretos en `payload`.

create table if not exists public.ecf_onboarding_audit (
  id          bigint generated always as identity primary key,
  company_id  uuid not null references public.companies(id) on delete cascade,
  user_id     uuid references auth.users(id),
  action      text not null,
  payload     jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists ecf_onboarding_audit_company_idx
  on public.ecf_onboarding_audit (company_id, created_at desc);

alter table public.ecf_onboarding_audit enable row level security;

comment on table public.ecf_onboarding_audit is
  'Bitácora de ecf-onboarding (ecf.onboarding.<acción>). Solo service_role.';

commit;

notify pgrst, 'reload schema';
