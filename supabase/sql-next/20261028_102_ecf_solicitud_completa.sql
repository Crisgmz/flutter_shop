-- ============================================================================
-- Migración 102 — Solicitud de facturación electrónica: requisitos completos
-- ============================================================================
-- El formulario de Configuración ahora pide lo que el operador necesita para
-- hacer la certificación ante la DGII (igual que mangospos 20261008_0001):
--   - teléfono de la empresa y nombre del representante legal,
--   - sucursales con su dirección,
--   - tipos de comprobante electrónico que va a usar,
--   - usuario de la Oficina Virtual (OFV) de la DGII.
--
-- A diferencia de mangospos, la certificación aquí es MANUAL (decisión del
-- 28 oct 2026): NO se guarda la clave de la OFV ni el certificado. El operador
-- se los pide al cliente por otra vía. Por eso no hay columnas cifradas.
--
-- Depende de la migración 90 (ecf_onboarding). RLS sigue sin políticas: solo
-- la Edge Function ecf-onboarding (service_role).
--
-- Idempotente.
-- ============================================================================

begin;

alter table public.ecf_onboarding
  add column if not exists phone          text,
  add column if not exists legal_rep_name text,
  add column if not exists branches       jsonb,
  add column if not exists ecf_types      text[],
  add column if not exists ofv_user       text;

alter table public.ecf_onboarding
  drop constraint if exists ecf_onboarding_branches_is_array,
  add constraint ecf_onboarding_branches_is_array
    check (branches is null or jsonb_typeof(branches) = 'array');

comment on column public.ecf_onboarding.phone is
  'Teléfono de la empresa (el de quien coordina el trámite es contact_phone).';
comment on column public.ecf_onboarding.legal_rep_name is
  'Nombre completo del representante legal ante la DGII.';
comment on column public.ecf_onboarding.branches is
  'Sucursales que declaró el cliente: [{ "name": text|null, "address": text }].';
comment on column public.ecf_onboarding.ecf_types is
  'Tipos de e-CF que va a usar la empresa (E31, E32...).';
comment on column public.ecf_onboarding.ofv_user is
  'Usuario de la Oficina Virtual de la DGII. La clave NO se guarda.';

commit;

notify pgrst, 'reload schema';
