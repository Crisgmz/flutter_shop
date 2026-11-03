// ecf-onboarding: la empresa pide y hace su facturación electrónica desde
// Configuración → Facturación electrónica.
//
// POST /functions/v1/ecf-onboarding
//   { action, company_id, ...params }
//
// Solicitud y activación:
//   request_status    → en qué va la facturación electrónica (la tarjeta)
//   submit_request    { data, details, certificate, contact_name, contact_phone,
//                       already_authorized, accept_terms, accept_certificate_storage? }
//                     → guarda la solicitud y registra la empresa en Alanube.
//                     `details.ofv_password` es opcional; si viene, se guarda
//                     cifrada. Con accept_certificate_storage se conserva el
//                     .p12 cifrado para firmar la certificación.
//   save_sequence     { branch_id, sequence } — la autorización e-NCF de la DGII
//   set_ecf_enabled   { enabled } — enciende/apaga la modalidad e-CF
//
// Certificación ante la DGII (la pantalla de 5 pasos, igual que el panel de
// MangoPOS; aquí la hace el admin de la empresa):
//   status            → todo lo que pinta la pantalla
//   save_data         { data } — datos del contribuyente
//   save_certificate  { certificate, accept_certificate_storage: true } — guarda
//                     o reemplaza el .p12 cifrado (se prueba antes de guardarlo)
//   save_ofv_credentials { ofv_user, ofv_password } — Oficina Virtual
//   reveal_ofv_password → usuario y clave de la OFV (queda auditado)
//   postulation_info  → datos del proveedor + URLs de la empresa
//   sign_document     { kind: postulation|declaration|roles, xml: { filename, content_base64 } }
//   import_test_set   { file: { filename, content_base64 }, set_kind? } — Excel
//                     de la DGII: pruebas de datos e-CF (`ecf`) o aprobaciones
//                     comerciales (`acecf`). Reemplaza los casos de ese tipo.
//   send_test_set     { set_kind?, certificate? } — firma y manda a CerteCF en
//                     lotes de ~30 s; si responde `more: true`, la app vuelve a
//                     llamar. Sin certificado explícito usa el guardado.
//   check_test_set    { set_kind?, certificate? } — consulta los trackId
//   test_case_xml     { case_id } → XML firmado de un caso y su representación impresa
//   generate_simulation_set { counts } — paso 4: e-CF de simulación con los
//                     datos reales del emisor y e-NCF nuevos
//   set_dgii_authorized { authorized } — la DGII ya lo autorizó
//
// PORTADO DE mangospos (`supabase/functions/ecf-onboarding`), donde este flujo
// ya está probado contra la DGII. Las dos apps comparten la cuenta de Alanube
// y las MISMAS reglas. Toda la lógica pura vive en `_shared/`, en copias
// VERBATIM de mangospos (si cambian allá, cambian aquí; `diff` directo):
//   ecf-onboarding.ts (salvo su línea de imports), secret-box.ts,
//   ecf-certificate.ts, dgii-signer.ts, dgii-certification.ts, ecf-test-set.ts,
//   ecf-simulation.ts, ecf-simulation-templates.ts, ecf-print.ts, dgii-catalogs.ts
// Aquí solo está el I/O, que cambia porque las tablas son distintas:
//
//   mangospos                      flutter_shop+
//   ──────────────────────────     ────────────────────────────────
//   businesses / business_id       companies / company_id
//   business_alanube_settings      company_ecf_settings
//   fiscal_settings                app_settings (por empresa)
//   ncf_sequences(ncf_type,        ncf_sequences(prefix, receipt_type,
//     range_end, expiration_date)    max_number, expires_on) POR SUCURSAL
//   ecf_onboarding(business_id)    ecf_onboarding(company_id)
//   noc_audit_log                  ecf_onboarding_audit
//
// Lo que el panel tiene y aquí NO: buscar/vincular una empresa que ya existe
// en Alanube (un cliente no puede tomar el ULID de otro contribuyente: firmaría
// con un certificado ajeno), sincronizar fiscal_settings y usar el set de otra
// empresa con el mismo RNC como modelo de la simulación (datos de otro
// inquilino). De las otras empresas con el mismo RNC solo se miran los e-NCF
// usados, para no repetir números ante la DGII.
//
// Secretos: el certificado con su contraseña, la clave de la OFV y el token de
// la DGII se guardan cifrados con AES-256-GCM y `ECF_CREDENTIALS_KEY` del
// entorno (la BD sola no los revela; el company_id va como dato autenticado).
// El .p12 se descifra solo para firmar aquí y nunca vuelve al navegador.
//
// Auth: JWT del usuario. La empresa se valida con la RLS del propio caller
// sobre `companies` (misma vía que `register-company`), y además se exige rol
// admin: la facturación electrónica compromete a la empresa ante la DGII.

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { createAlanubeClient, AlanubeClient, AlanubeError } from '../_shared/alanube-client.ts'
import {
  AssociatedCompany,
  buildCompanyPayload,
  buildWebhooks,
  CertificateInput,
  companiesMatchingRnc,
  EnablingXmlInput,
  ExistingSequence,
  hasUsableEcfSequence,
  missingForClientRequest,
  ONBOARDING_SEQUENCE_TYPES,
  parseAssociatedPage,
  parseProviderInfo,
  planSequenceWrite,
  Branch,
  RequestDetailsInput,
  RequestStage,
  requestStage,
  SIGNED_AT_COLUMN,
  suggestEcfTypes,
  summarizeCompany,
  TaxpayerData,
  TaxpayerInput,
  ValidCertificate,
  validateCertificate,
  validateEnablingXml,
  validateRequestContact,
  validateRequestDetails,
  validateTaxpayer,
} from '../_shared/ecf-onboarding.ts'
import { EMITTABLE_ECF_TYPES, environmentFromBaseUrl, normalizeRnc } from '../_shared/ecf-onboarding-deps.ts'
import { importSecretKey, openSecret, sealSecret } from '../_shared/secret-box.ts'
import {
  CertificateAccessError,
  certificateFilename,
  resolveCertificate,
  sealCertificate,
} from '../_shared/ecf-certificate.ts'
import { DgiiCertificationClient, DgiiError, DgiiResult } from '../_shared/dgii-certification.ts'
import {
  canonicalSeed,
  DgiiSigner,
  loadSigner,
  securityCode,
  SignerError,
  signXml,
} from '../_shared/dgii-signer.ts'
import {
  buildSimulationCases,
  encfNumber,
  selectSimulationTemplates,
  SimulationTemplate,
} from '../_shared/ecf-simulation.ts'
import { buildPrintModel } from '../_shared/ecf-print.ts'
import { DGII_SIMULATION_TEMPLATES } from '../_shared/ecf-simulation-templates.ts'
import {
  buildAcecfXml,
  buildEcfXml,
  buildRfceXml,
  DgiiMessage,
  dgiiTimestamp,
  isAdjustmentNote,
  isFinalStatus,
  parseApprovalSet,
  parseTestSet,
  readTestSetFile,
  sendOrder,
  TestCaseStatus,
  TestSetCase,
  TestSetField,
  TestSetKind,
} from '../_shared/ecf-test-set.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
const WEBHOOK_PATH = '/functions/v1/alanube-webhook'
const WEBHOOK_URL = Deno.env.get('ALANUBE_WEBHOOK_URL') ?? `${SUPABASE_URL}${WEBHOOK_PATH}`
const WEBHOOK_SECRET = Deno.env.get('ALANUBE_WEBHOOK_SECRET') ?? ''

// Aviso al panel de soporte cuando entra una solicitud. Opcional: sin estas
// variables la solicitud igual se guarda y se registra en Alanube, solo que
// nadie afuera se entera automáticamente.
const PANEL_NOTIFY_URL = Deno.env.get('ECF_PANEL_NOTIFY_URL') ?? ''
const PANEL_NOTIFY_SECRET = Deno.env.get('ECF_PANEL_NOTIFY_SECRET') ?? ''

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const MIGRATION_105 = 'Falta correr la migración 105 (20261102_105_ecf_certificacion_dgii.sql).'

/**
 * Tiempo de trabajo de cada `send_test_set` (y de cada `check_test_set`). El
 * runtime corta a los 60 s: la app vuelve a llamar mientras la respuesta
 * traiga `more: true`. Se revisa antes de cada llamada a la DGII, que puede
 * tardar hasta 20 s más.
 */
const TEST_SET_SEND_BUDGET_MS = 30_000
/** Espera entre consultas a la DGII después de mandar. */
const TEST_SET_POLL_INTERVAL_MS = 4_000

/** El XML firmado que devuelve Alanube pesa pocos KB. */
const MAX_SIGNED_XML_BYTES = 2 * 1024 * 1024

/** Acciones del admin de la empresa. */
const CLIENT_ACTIONS = new Set([
  'request_status',
  'submit_request',
  'save_sequence',
  'set_ecf_enabled',
  'status',
  'save_data',
  'save_certificate',
  'save_ofv_credentials',
  'reveal_ofv_password',
  'postulation_info',
  'sign_document',
  'import_test_set',
  'send_test_set',
  'check_test_set',
  'test_case_xml',
  'generate_simulation_set',
  'set_dgii_authorized',
])

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly detail?: unknown,
  ) {
    super(message)
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function fail(status: number, code: string, message: string, detail?: unknown): Response {
  return json({ error: code, message, detail }, status)
}

interface RequestBody {
  action?: string
  company_id?: string
  branch_id?: string
  data?: TaxpayerInput
  details?: RequestDetailsInput
  sequence?: Record<string, unknown>
  certificate?: CertificateInput
  contact_name?: string
  contact_phone?: string
  already_authorized?: boolean
  accept_terms?: boolean
  accept_certificate_storage?: boolean
  enabled?: boolean
  ofv_user?: string
  ofv_password?: string
  kind?: string
  xml?: Omit<EnablingXmlInput, 'kind'>
  file?: { filename?: string; content_base64?: string }
  set_kind?: string
  /** Simulación: cuántos e-CF de cada tipo pide el portal ({"31": 1, "32rfce": 1...}). */
  counts?: Record<string, unknown>
  case_id?: string
  authorized?: boolean
}

interface Ctx {
  service: SupabaseClient
  userId: string
  companyId: string
  body: RequestBody
}

// ── Fila de ecf_onboarding ──────────────────────────────────────────────────

// Los secretos (`ofv_password_enc`, `certificate_enc`, `dgii_test_token_enc`)
// NO van aquí: esta lista es la que vuelve al navegador en `status`. Solo se
// leen con su propia consulta para descifrarlos en el servidor.
const ONBOARDING_COLUMNS =
  'company_id, rnc, legal_name, trade_name, fiscal_address, province, municipality, email, ' +
  'alanube_company_id, company_linked_via, company_linked_at, ' +
  'postulation_signed_at, declaration_signed_at, roles_signed_at, dgii_authorized_at, ' +
  'requested_at, requested_by, contact_name, contact_phone, already_authorized, notified_at, ' +
  'phone, legal_rep_name, branches, ecf_types, ofv_user, ofv_password_updated_at, ' +
  'certificate_filename, certificate_updated_at, ' +
  'test_set_filename, test_set_loaded_at, approval_set_filename, approval_set_loaded_at, ' +
  'simulation_set_generated_at, simulation_sequences, ' +
  'dgii_test_token_expires_at, created_at, updated_at'

interface OnboardingRow extends TaxpayerData {
  company_id: string
  alanube_company_id: string | null
  company_linked_via: string | null
  company_linked_at: string | null
  postulation_signed_at: string | null
  declaration_signed_at: string | null
  roles_signed_at: string | null
  dgii_authorized_at: string | null
  requested_at: string | null
  requested_by: string | null
  contact_name: string | null
  contact_phone: string | null
  already_authorized: boolean | null
  notified_at: string | null
  phone: string | null
  legal_rep_name: string | null
  branches: Branch[] | null
  ecf_types: string[] | null
  ofv_user: string | null
  ofv_password_updated_at: string | null
  certificate_filename: string | null
  certificate_updated_at: string | null
  test_set_filename: string | null
  test_set_loaded_at: string | null
  approval_set_filename: string | null
  approval_set_loaded_at: string | null
  simulation_set_generated_at: string | null
  simulation_sequences: Record<string, number> | null
  dgii_test_token_expires_at: string | null
}

/** Los secretos escritos no forman parte del estado que se lee de vuelta. */
type OnboardingWrite = Partial<OnboardingRow> & {
  ofv_password_enc?: string
  certificate_enc?: string
  dgii_test_token_enc?: string | null
}

/** 42703/PGRST204: una columna que no existe (migración sin correr). */
function onboardingDbError(error: { code?: string; message: string }, what: string): HttpError {
  if (error.code === '42703' || error.code === 'PGRST204') {
    return new HttpError(500, 'migration_missing', MIGRATION_105, error.message)
  }
  return new HttpError(500, 'db_error', what, error.message)
}

async function loadOnboarding(
  service: SupabaseClient,
  companyId: string,
): Promise<OnboardingRow | null> {
  const { data, error } = await service
    .from('ecf_onboarding')
    .select(ONBOARDING_COLUMNS)
    .eq('company_id', companyId)
    .maybeSingle()
  if (error) throw onboardingDbError(error, 'No se pudo leer la solicitud')
  return (data as unknown as OnboardingRow) ?? null
}

async function upsertOnboarding(
  service: SupabaseClient,
  companyId: string,
  userId: string,
  current: OnboardingRow | null,
  patch: OnboardingWrite,
): Promise<OnboardingRow> {
  const row = {
    company_id: companyId,
    ...(current ? {} : { created_by: userId }),
    ...patch,
    updated_by: userId,
  }
  const { data, error } = await service
    .from('ecf_onboarding')
    .upsert(row, { onConflict: 'company_id' })
    .select(ONBOARDING_COLUMNS)
    .single()
  if (error) throw onboardingDbError(error, 'No se pudo guardar la solicitud')
  return data as unknown as OnboardingRow
}

interface SettingsRow {
  alanube_company_id: string | null
  environment: string
  certification_status: string
  mode: string
}

async function loadSettings(service: SupabaseClient, companyId: string): Promise<SettingsRow | null> {
  const { data, error } = await service
    .from('company_ecf_settings')
    .select('alanube_company_id, environment, certification_status, mode')
    .eq('company_id', companyId)
    .maybeSingle()
  if (error) throw new HttpError(500, 'db_error', 'No se pudo leer la configuración e-CF', error.message)
  return (data as SettingsRow | null) ?? null
}

/**
 * En qué va la empresa. Mismo `requestStage` que mangospos, con una
 * diferencia en lo que cuenta como "aprovisionado": allá es la activación
 * (business_alanube_settings con modalidad); aquí el ULID se guarda en
 * company_ecf_settings al registrar, así que tomarlo como aprovisionado
 * saltaba "En trámite DGII" y la tarjeta decía "Ya estás autorizado" a quien
 * la DGII todavía no había aprobado.
 */
function stageOf(
  current: OnboardingRow | null,
  settings: SettingsRow | null,
  usableSequences: boolean,
): RequestStage {
  const ecfEnabled = (settings?.mode ?? 'physical') !== 'physical'
  return requestStage({
    requested: Boolean(current?.requested_at),
    hasCompany: Boolean(current?.alanube_company_id ?? settings?.alanube_company_id),
    dgiiAuthorized: Boolean(current?.dgii_authorized_at) ||
      current?.already_authorized === true ||
      settings?.certification_status === 'certified',
    usableSequences,
    provisioned: Boolean(settings?.alanube_company_id) && ecfEnabled,
    ecfEnabled,
  })
}

function todayInSantoDomingo(): string {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'America/Santo_Domingo' })
}

// ── Secuencias: e-CF ↔ el modelo por sucursal de flutter_shop+ ───────────────
//
// En mangospos una secuencia es (business_id, ncf_type). Aquí es
// (branch_id, receipt_type, prefix): el tipo vive en `prefix` ('E31') y
// `receipt_type` es la clasificación semántica que ya usa el POS.
//
// La DGII autoriza el rango al RNC, o sea a la EMPRESA, pero este POS consume
// las secuencias por sucursal. Por eso `save_sequence` exige la sucursal: dos
// sucursales compartiendo el mismo rango emitirían el mismo e-NCF dos veces.
// Si el negocio tiene varias, reparte el rango entre ellas.

// Sin E34: con la nota de crédito guardada como `fiscal_credit`,
// `assign_next_ncf` la elegía para facturas de crédito fiscal (empata con la
// E31 en el número 1). Y como `credit_note` tampoco sirve todavía: la
// devolución de shop-plus la tomaría en vez de la B04 y nadie la emite.
const RECEIPT_TYPE_BY_ECF: Record<string, string> = {
  E31: 'fiscal_credit',
  E32: 'consumer_final',
  E44: 'special',
  E45: 'governmental',
}

interface ShopSequenceRow {
  id: string
  prefix: string
  current_number: number
  max_number: number | null
  expires_on: string | null
  is_active: boolean
}

/** Las secuencias e-CF de la empresa, en los términos del módulo compartido. */
async function loadEcfSequences(service: SupabaseClient, companyId: string) {
  const { data: branches, error: branchErr } = await service
    .from('branches')
    .select('id, name, address, is_active')
    .eq('company_id', companyId)
  if (branchErr) {
    throw new HttpError(500, 'db_error', 'No se pudieron leer las sucursales', branchErr.message)
  }
  const branchIds = (branches ?? []).map((b) => (b as { id: string }).id)
  if (branchIds.length === 0) return { branches: branches ?? [], rows: [] as Array<ShopSequenceRow & { branch_id: string }> }

  const { data, error } = await service
    .from('ncf_sequences')
    .select('id, branch_id, prefix, current_number, max_number, expires_on, is_active')
    .in('branch_id', branchIds)
    .in('prefix', ONBOARDING_SEQUENCE_TYPES)
  if (error) {
    throw new HttpError(500, 'db_error', 'No se pudieron leer las secuencias', error.message)
  }
  return {
    branches: branches ?? [],
    rows: (data ?? []) as Array<ShopSequenceRow & { branch_id: string }>,
  }
}

/** Forma que espera `hasUsableEcfSequence`. */
function toUsabilityRows(rows: Array<ShopSequenceRow>) {
  return rows.map((s) => ({
    ncf_type: s.prefix,
    is_active: s.is_active,
    current_number: Number(s.current_number),
    // Sin tope declarado no hay forma de saber si queda número: se trata como
    // agotada en vez de dar por buena una secuencia que puede no existir.
    range_end: Number(s.max_number ?? 0),
    expiration_date: s.expires_on,
  }))
}

/** Sucursales y secuencias como las pinta la app (tarjeta y pantalla). */
function sequencesPayload(
  branches: unknown[],
  rows: Array<ShopSequenceRow & { branch_id: string }>,
) {
  return {
    branches: branches.map((b) => {
      const branch = b as { id: string; name: string }
      return { id: branch.id, name: branch.name }
    }),
    sequences: rows.map((s) => ({
      id: s.id,
      branch_id: s.branch_id,
      ncf_type: s.prefix,
      current_number: Number(s.current_number),
      range_end: Number(s.max_number ?? 0),
      expiration_date: s.expires_on,
      is_active: s.is_active,
    })),
  }
}

// ── Alanube ─────────────────────────────────────────────────────────────────

function alanubeOrThrow(): AlanubeClient {
  try {
    return createAlanubeClient()
  } catch (e) {
    throw new HttpError(
      500,
      'config_error',
      'El servidor no tiene configurado el proveedor de facturación electrónica.',
      e instanceof Error ? e.message : String(e),
    )
  }
}

/**
 * Empresas ya asociadas a la cuenta de Alanube. Mismo recorrido por cursor
 * que en mangospos: la respuesta trae `next` y se pide desde ahí.
 */
const ASSOCIATED_PAGE_SIZE = 100
const ASSOCIATED_MAX_PAGES = 20

async function listAssociated(alanube: AlanubeClient): Promise<AssociatedCompany[]> {
  const all: AssociatedCompany[] = []
  let from: string | null = null
  for (let page = 0; page < ASSOCIATED_MAX_PAGES; page++) {
    const query = `limit=${ASSOCIATED_PAGE_SIZE}` +
      (from ? `&from=${encodeURIComponent(from)}` : '')
    let res: unknown
    try {
      res = await alanube.request<unknown>({
        method: 'GET',
        path: `/companies/associated?${query}`,
      })
    } catch (e) {
      throw new HttpError(
        502,
        'alanube_error',
        'No se pudo consultar las empresas del proveedor.',
        e instanceof AlanubeError ? e.body : String(e),
      )
    }
    const { companies, next } = parseAssociatedPage(res)
    all.push(...companies)
    if (!next) return all
    from = next
  }
  return all
}

function unwrapCompany(res: unknown): AssociatedCompany & Record<string, unknown> {
  const body = res as Record<string, unknown>
  const inner = (body?.data ?? body?.company ?? body) as Record<string, unknown>
  return inner as AssociatedCompany & Record<string, unknown>
}

async function getCompany(alanube: AlanubeClient, id: string) {
  // OJO: /companies/{id}. `GET /companies` a secas devuelve siempre la
  // empresa principal de la cuenta.
  return unwrapCompany(await alanube.request<unknown>({
    method: 'GET',
    path: `/companies/${encodeURIComponent(id)}`,
  }))
}

function describeAlanubeError(e: unknown, what: string): string {
  if (e instanceof HttpError) return e.message
  if (!(e instanceof AlanubeError)) return `No se pudo ${what}: ${errorText(e)}`
  if (e.status === 0) return `No se pudo ${what}: el proveedor no respondió (${e.message}).`
  const b = e.body as { message?: unknown; errors?: unknown; code?: unknown } | null
  const detail = b?.message ?? b?.errors
  const text = Array.isArray(detail) ? detail.join('; ') : typeof detail === 'string' ? detail : ''
  const code = typeof b?.code === 'string' ? ` ${b.code}` : ''
  return `El proveedor respondió ${e.status}${code} al ${what}${text ? `: ${text}` : '.'}`
}

/** ULID de la empresa (solicitud o configuración), o 409. */
async function requireCompanyId(ctx: Ctx): Promise<string> {
  const current = await loadOnboarding(ctx.service, ctx.companyId)
  if (current?.alanube_company_id) return current.alanube_company_id
  const settings = await loadSettings(ctx.service, ctx.companyId)
  if (settings?.alanube_company_id) return settings.alanube_company_id
  throw new HttpError(
    409,
    'no_company',
    'Primero tu empresa tiene que quedar registrada con el proveedor (paso 2).',
  )
}

/**
 * Da de alta la empresa en Alanube y guarda el ULID.
 *
 * Registrar dos veces el mismo RNC deja dos empresas en la cuenta y el riesgo
 * de vincular la que NO tiene el certificado bueno: por eso se busca primero.
 */
async function registerCompany(ctx: Ctx, current: OnboardingRow): Promise<OnboardingRow> {
  const { service, companyId, userId, body } = ctx

  const data = validateTaxpayer(current, { forRegistration: true })
  if (!data.ok) throw new HttpError(409, 'incomplete_data', data.errors.join(' '), data.errors)

  if (current.alanube_company_id) {
    throw new HttpError(409, 'already_linked', 'Esta empresa ya está registrada con el proveedor.')
  }
  const settings = await loadSettings(service, companyId)
  if (settings?.alanube_company_id) {
    throw new HttpError(409, 'already_linked', 'Esta empresa ya está activada con el proveedor.')
  }

  const cert = validateCertificate(body.certificate ?? {})
  if (!cert.ok) throw new HttpError(422, 'invalid_certificate', cert.errors.join(' '), cert.errors)

  if (!WEBHOOK_SECRET) {
    throw new HttpError(500, 'config_error', 'El servidor no tiene ALANUBE_WEBHOOK_SECRET.')
  }

  const alanube = alanubeOrThrow()

  const existing = companiesMatchingRnc(await listAssociated(alanube), data.value.rnc)
  if (existing.length > 0) {
    throw new HttpError(
      409,
      'company_exists',
      'Ya hay una empresa con ese RNC en el proveedor. Hay que vincularla en vez de crear otra.',
      { matches: existing.map(summarizeCompany) },
    )
  }

  let created: AssociatedCompany & Record<string, unknown>
  try {
    const res = await alanube.request<Record<string, unknown>>({
      method: 'POST',
      path: '/company',
      body: buildCompanyPayload(data.value, cert.value, buildWebhooks(WEBHOOK_URL, WEBHOOK_SECRET)),
      // Alanube prueba el webhook durante el alta: tarda más que una llamada
      // normal.
      timeoutMs: 60_000,
    })
    created = unwrapCompany(res)
  } catch (e) {
    if (e instanceof AlanubeError) {
      throw new HttpError(
        502,
        'alanube_rejected',
        `El proveedor rechazó el alta: ${e.message}`,
        e.body,
      )
    }
    throw e
  }

  const alanubeId = (created.id ?? created.companyId ?? '').toString()
  if (!alanubeId) {
    throw new HttpError(502, 'alanube_rejected', 'El proveedor no devolvió el id de la empresa.', created)
  }

  const now = new Date().toISOString()
  const saved = await upsertOnboarding(service, companyId, userId, current, {
    alanube_company_id: alanubeId,
    company_linked_via: 'registered',
    company_linked_at: now,
  })
  await audit(service, userId, companyId, 'register_company', {
    alanube_company_id: alanubeId,
    certificate_file: certificateFilename(cert.value),
  })

  // El ULID también va a company_ecf_settings, que es de donde lo lee
  // `emit-document` al emitir.
  const { error: setErr } = await service
    .from('company_ecf_settings')
    .upsert(
      {
        company_id: companyId,
        alanube_company_id: alanubeId,
        webhooks_configured: true,
        // El ambiente lo decide la cuenta de Alanube del servidor, no el
        // default 'sandbox' de la tabla: con él, el QR armado a mano apuntaba
        // a la consulta de prueba de la DGII en facturas de producción.
        environment: environmentFromBaseUrl(Deno.env.get('ALANUBE_BASE_URL') ?? ''),
        updated_by: userId,
      },
      { onConflict: 'company_id' },
    )
  if (setErr) {
    // La empresa YA quedó creada en Alanube: fallar aquí dejaría el ULID
    // huérfano y el próximo intento chocaría con "company_exists". Queda en
    // ecf_onboarding y se reconcilia.
    console.error('ecf-onboarding: no se pudo guardar el ULID en company_ecf_settings', setErr.message)
  }

  return saved
}

// ── Secretos ────────────────────────────────────────────────────────────────

let credentialsKey: Promise<CryptoKey> | null = null

function credentialsKeyOrThrow(): Promise<CryptoKey> {
  const raw = Deno.env.get('ECF_CREDENTIALS_KEY')
  if (!raw) {
    throw new HttpError(
      500,
      'config_error',
      'El servidor no tiene ECF_CREDENTIALS_KEY para guardar el certificado y las credenciales.',
    )
  }
  credentialsKey ??= importSecretKey(raw).catch((e) => {
    credentialsKey = null
    throw new HttpError(500, 'config_error', `ECF_CREDENTIALS_KEY inválida: ${errorText(e)}`)
  })
  return credentialsKey
}

async function signerOrThrow(cert: { content: string; password: string }): Promise<DgiiSigner> {
  let signer: DgiiSigner
  try {
    signer = await loadSigner(Uint8Array.from(atob(cert.content), (ch) => ch.charCodeAt(0)), cert.password)
  } catch (e) {
    throw new HttpError(422, 'invalid_certificate', e instanceof SignerError ? e.message : errorText(e))
  }
  if (signer.notAfter.getTime() < Date.now()) {
    throw new HttpError(
      422,
      'certificate_expired',
      `El certificado venció el ${signer.notAfter.toISOString().slice(0, 10)}. La DGII no acepta firmas con el vencido.`,
    )
  }
  return signer
}

/** El explícito de la petición o el guardado. Usar el guardado queda auditado. */
async function certificateFor(ctx: Ctx): Promise<ValidCertificate> {
  const { service, companyId, userId, body } = ctx
  try {
    const resolved = await resolveCertificate(
      body.certificate,
      async () => {
        const { data, error } = await service
          .from('ecf_onboarding')
          .select('certificate_enc')
          .eq('company_id', companyId)
          .maybeSingle()
        if (error) throw onboardingDbError(error, 'No se pudo leer el certificado guardado.')
        return (data as { certificate_enc: string | null } | null)?.certificate_enc ?? null
      },
      credentialsKeyOrThrow,
      companyId,
    )
    if (resolved.stored && !(await audit(service, userId, companyId, 'use_saved_certificate', {
      for_action: body.action,
      certificate_file: certificateFilename(resolved.certificate),
    }))) {
      throw new HttpError(500, 'audit_failed', 'No se pudo registrar el uso del certificado guardado.')
    }
    return resolved.certificate
  } catch (e) {
    if (!(e instanceof CertificateAccessError)) throw e
    const status = e.code === 'certificate_not_found' ? 404 : e.code === 'invalid_certificate' ? 422 : 500
    throw new HttpError(status, e.code, e.message)
  }
}

async function certificateWrite(key: CryptoKey, cert: ValidCertificate, companyId: string): Promise<OnboardingWrite> {
  return {
    certificate_filename: certificateFilename(cert),
    certificate_updated_at: new Date().toISOString(),
    certificate_enc: await sealCertificate(key, cert, companyId),
    // Una renovación debe autenticarse con el certificado nuevo.
    dgii_test_token_enc: null,
    dgii_test_token_expires_at: null,
  }
}

// ── Aviso al panel de soporte ───────────────────────────────────────────────
//
// Servidor a servidor, con secreto compartido. Nunca bloquea la solicitud: si
// el panel no contesta, la solicitud igual quedó guardada y registrada, y
// `notified_at` en null marca que falta avisar. `retryPanelNotice` la vuelve a
// mandar la próxima vez que el admin abre la tarjeta.

async function notifyPanel(service: SupabaseClient, row: OnboardingRow): Promise<void> {
  if (!PANEL_NOTIFY_URL || !PANEL_NOTIFY_SECRET) return
  try {
    const { data: companyRow } = await service
      .from('companies')
      .select('name')
      .eq('id', row.company_id)
      .maybeSingle()
    const companyName = (companyRow as { name: string } | null)?.name ?? ''
    const res = await fetch(PANEL_NOTIFY_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Ecf-Panel-Secret': PANEL_NOTIFY_SECRET,
      },
      body: JSON.stringify({
        source: 'flutter_shop+',
        company_id: row.company_id,
        company_name: companyName,
        rnc: row.rnc,
        legal_name: row.legal_name,
        trade_name: row.trade_name,
        email: row.email,
        contact_name: row.contact_name,
        contact_phone: row.contact_phone,
        already_authorized: row.already_authorized,
        phone: row.phone,
        legal_rep_name: row.legal_rep_name,
        branches: row.branches,
        ecf_types: row.ecf_types,
        ofv_user: row.ofv_user,
        alanube_company_id: row.alanube_company_id,
        // Con ULID = el alta con el proveedor salió; sin él, la hace soporte.
        company_registered: Boolean(row.alanube_company_id),
        requested_at: row.requested_at,
      }),
      signal: AbortSignal.timeout(10_000),
    })
    if (!res.ok) {
      console.error(`ecf-onboarding: el panel respondió ${res.status}`)
      return
    }
    await service
      .from('ecf_onboarding')
      .update({ notified_at: new Date().toISOString() })
      .eq('company_id', row.company_id)
  } catch (e) {
    console.error('ecf-onboarding: no se pudo avisar al panel', e instanceof Error ? e.message : e)
  }
}

/**
 * Una solicitud que quedó sin avisar (faltaban ECF_PANEL_NOTIFY_* cuando
 * entró, o el panel no contestó) no tiene otra vía para llegar: reenviarla ya
 * no avisa, porque con la empresa registrada da `already_in_progress`. El
 * panel es idempotente por (source, company_id).
 */
async function retryPanelNotice(service: SupabaseClient, row: OnboardingRow | null): Promise<void> {
  if (!row?.requested_at || row.notified_at) return
  await notifyPanel(service, row)
}

// ── Solicitud y activación ──────────────────────────────────────────────────

/** Datos del emisor que ya tiene la app, para precargar el formulario. */
async function prefillFromSettings(
  service: SupabaseClient,
  companyId: string,
): Promise<Partial<TaxpayerData>> {
  const { data } = await service
    .from('app_settings')
    .select('company_name, company_legal_name, company_tax_id, company_address, company_email')
    .eq('company_id', companyId)
    .maybeSingle()
  if (!data) return {}
  const s = data as Record<string, string | null>
  return {
    rnc: s.company_tax_id ?? null,
    legal_name: s.company_legal_name ?? s.company_name ?? null,
    trade_name: s.company_name ?? null,
    fiscal_address: s.company_address ?? null,
    email: s.company_email ?? null,
  }
}

/**
 * Lo que el formulario muestra en "Requisitos" mientras no haya solicitud: el
 * teléfono de la empresa, sus sucursales con dirección y los tipos e-CF
 * equivalentes a la serie B que ya usa. Solo se sugieren los que este POS
 * emite (sin E34: aquí todavía no hay notas de crédito electrónicas).
 */
async function prefillDetails(
  service: SupabaseClient,
  companyId: string,
  branches: Array<{ id: string; name: string; address: string | null }>,
) {
  const { data: settings } = await service
    .from('app_settings')
    .select('company_phone')
    .eq('company_id', companyId)
    .maybeSingle()

  const { data: paper } = branches.length === 0
    ? { data: [] }
    : await service
      .from('ncf_sequences')
      .select('prefix, is_active')
      .in('branch_id', branches.map((b) => b.id))
  const sequences = ((paper ?? []) as Array<{ prefix: string | null; is_active: boolean | null }>)
    .map((r) => ({ ncf_type: r.prefix, is_active: r.is_active }))

  return {
    phone: (settings as { company_phone: string | null } | null)?.company_phone ?? null,
    branches: branches.map((b) => ({ name: b.name, address: b.address ?? '' })),
    ecf_types: suggestEcfTypes(sequences).filter((t) => EMITTABLE_ECF_TYPES.includes(t)),
  }
}

async function actionRequestStatus(ctx: Ctx): Promise<Response> {
  const { service, companyId } = ctx

  const current = await loadOnboarding(service, companyId)
  // Corre mientras se arma la respuesta; notifyPanel nunca lanza.
  const notice = retryPanelNotice(service, current)
  const settings = await loadSettings(service, companyId)

  const { branches, rows } = await loadEcfSequences(service, companyId)
  const usableSequences = hasUsableEcfSequence(toUsabilityRows(rows), todayInSantoDomingo())
  const stage = stageOf(current, settings, usableSequences)

  const branchRows = branches as Array<
    { id: string; name: string; address: string | null; is_active: boolean | null }
  >
  const suggested = current?.ecf_types && current?.branches
    ? null
    : await prefillDetails(service, companyId, branchRows.filter((b) => b.is_active !== false))

  // Sin solicitud todavía, el formulario arranca con lo que la app ya sabe de
  // la empresa en vez de en blanco.
  const data: Partial<TaxpayerData> = current
    ? {
      rnc: current.rnc,
      legal_name: current.legal_name,
      trade_name: current.trade_name,
      fiscal_address: current.fiscal_address,
      province: current.province,
      municipality: current.municipality,
      email: current.email,
    }
    : await prefillFromSettings(service, companyId)

  await notice
  return json({
    stage,
    requested_at: current?.requested_at ?? null,
    contact_name: current?.contact_name ?? null,
    contact_phone: current?.contact_phone ?? null,
    already_authorized: current?.already_authorized ?? null,
    data,
    // La clave de la OFV nunca vuelve: solo si ya hay una guardada.
    details: {
      phone: current?.phone ?? suggested?.phone ?? null,
      legal_rep_name: current?.legal_rep_name ?? null,
      branches: current?.branches ?? suggested?.branches ?? [],
      ecf_types: current?.ecf_types ?? suggested?.ecf_types ?? [],
      ofv_user: current?.ofv_user ?? null,
      ofv_password_saved: Boolean(current?.ofv_password_updated_at),
    },
    mode: settings?.mode ?? 'physical',
    environment: settings?.environment ?? 'sandbox',
    certification_status: settings?.certification_status ?? 'pending',
    alanube_company_id: settings?.alanube_company_id ?? current?.alanube_company_id ?? null,
    ...sequencesPayload(branches, rows),
  })
}

async function actionSubmitRequest(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId, body } = ctx

  const data = validateTaxpayer(body.data ?? {}, { forRegistration: true })
  const contact = validateRequestContact(body)
  const cert = validateCertificate(body.certificate ?? {})
  // Builds viejos no mandan `details`: se les sigue aceptando la solicitud.
  // `hasSavedOfvPassword: true` porque aquí la clave de la OFV es opcional (la
  // certificación la hace el mismo cliente con su usuario de la OFV); si la
  // manda, se guarda cifrada.
  const details = body.details
    ? validateRequestDetails(body.details, { hasSavedOfvPassword: true })
    : null
  const errors = [
    ...(data.ok ? [] : data.errors),
    ...(data.ok && details ? missingForClientRequest(data.value) : []),
    ...(details && !details.ok ? details.errors : []),
    ...(contact.ok ? [] : contact.errors),
    ...(cert.ok ? [] : cert.errors),
    ...(body.accept_terms === true
      ? []
      : ['Falta autorizar el registro de tu certificado con el proveedor.']),
  ]
  if (errors.length > 0 || !data.ok || !contact.ok || !cert.ok || (details && !details.ok)) {
    throw new HttpError(422, 'invalid_request', errors.join(' '), errors)
  }

  const d = details?.ok ? details.value : null
  const newOfvPassword = d?.ofv_password ?? null
  const saveCertificate = body.accept_certificate_storage === true
  // La llave se exige ANTES de guardar nada: sin ella no se guarda a medias.
  const key = newOfvPassword || saveCertificate ? await credentialsKeyOrThrow() : null

  const settings = await loadSettings(service, companyId)
  if (settings && settings.mode !== 'physical') {
    throw new HttpError(409, 'already_active', 'Tu empresa ya tiene la facturación electrónica activada.')
  }

  const current = await loadOnboarding(service, companyId)
  if (current?.alanube_company_id) {
    throw new HttpError(
      409,
      'already_in_progress',
      'Tu solicitud ya está en proceso y tu empresa ya está registrada. Te vamos a contactar.',
    )
  }

  // La solicitud queda guardada aunque el alta con el proveedor falle: así se
  // le puede dar seguimiento en vez de perderla.
  const now = new Date().toISOString()
  const saved = await upsertOnboarding(service, companyId, userId, current, {
    ...data.value,
    ...contact.value,
    already_authorized: body.already_authorized === true,
    ...(saveCertificate && key ? await certificateWrite(key, cert.value, companyId) : {}),
    ...(d
      ? {
        phone: d.phone,
        legal_rep_name: d.legal_rep_name,
        branches: d.branches,
        ecf_types: d.ecf_types,
        ofv_user: d.ofv_user,
      }
      : {}),
    ...(newOfvPassword && key
      ? {
        ofv_password_enc: await sealSecret(key, newOfvPassword, companyId),
        ofv_password_updated_at: now,
      }
      : {}),
    // Un reintento (contraseña equivocada, por ejemplo) no cambia quién ni
    // cuándo lo pidió.
    ...(current?.requested_at ? {} : { requested_at: now, requested_by: userId }),
  })
  await audit(service, userId, companyId, 'submit_request', {
    already_authorized: body.already_authorized === true,
    contact_name: contact.value.contact_name,
    certificate_file: certificateFilename(cert.value),
    certificate_saved: saveCertificate,
    ecf_types: d?.ecf_types ?? null,
    branches: d?.branches.length ?? null,
    ofv_password_changed: Boolean(newOfvPassword),
  })

  try {
    const registered = await registerCompany(ctx, saved)
    await notifyPanel(service, registered)
    return json({ ok: true, company_registered: true, stage: 'certification' })
  } catch (e) {
    if (!(e instanceof HttpError)) throw e

    if (e.code === 'company_exists') {
      // Ya registrada (otro intento, o alguien la dio de alta a mano): se
      // vincula desde soporte.
      await notifyPanel(service, saved)
      return json({
        ok: true,
        company_registered: false,
        stage: 'company',
        message: 'Tu RNC ya estaba registrado con nuestro proveedor. Lo revisamos y te contactamos.',
      })
    }

    if (e.code === 'config_error') {
      // Este servidor todavía no tiene la cuenta del proveedor (ALANUBE_*).
      // No es algo que el cliente pueda arreglar: la solicitud ya quedó
      // guardada, el panel se entera y el operador hace el registro a mano.
      console.error('ecf-onboarding: alta sin proveedor configurado:', e.message)
      await notifyPanel(service, saved)
      return json({
        ok: true,
        company_registered: false,
        stage: 'company',
        message: 'Recibimos tu solicitud. Te vamos a contactar para terminar el registro.',
      })
    }

    if (e.code === 'alanube_rejected') {
      // Casi siempre: contraseña equivocada o un archivo que no es el
      // certificado de firma. El detalle técnico va aparte, no en el mensaje.
      await notifyPanel(service, saved)
      throw new HttpError(
        422,
        'certificate_rejected',
        'No se pudo registrar tu certificado. Revisa que sea tu certificado de firma digital (.p12) ' +
          'y que la contraseña sea la correcta. Tu solicitud quedó guardada.',
        { cause: e.message },
      )
    }
    throw e
  }
}

/**
 * Guarda la autorización e-NCF que la DGII entrega en PDF.
 *
 * Exige sucursal: el rango lo autoriza la DGII al RNC, pero este POS consume
 * las secuencias por sucursal. Dos sucursales sobre el mismo rango emitirían
 * el mismo e-NCF dos veces.
 */
async function actionSaveSequence(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId, body } = ctx

  const branchId = (body.branch_id ?? '').trim()
  if (!UUID_RE.test(branchId)) {
    throw new HttpError(400, 'invalid_request', 'Falta la sucursal donde se usa la secuencia.')
  }
  const { data: branch, error: branchErr } = await service
    .from('branches')
    .select('id')
    .eq('id', branchId)
    .eq('company_id', companyId)
    .maybeSingle()
  if (branchErr) throw new HttpError(500, 'db_error', 'No se pudo leer la sucursal', branchErr.message)
  if (!branch) throw new HttpError(404, 'branch_not_found', 'Esa sucursal no es de tu empresa.')

  const ncfType = ((body.sequence?.ncf_type ?? '') as string).trim().toUpperCase()
  if (!EMITTABLE_ECF_TYPES.includes(ncfType)) {
    throw new HttpError(
      422,
      'invalid_sequence',
      ncfType === 'E34'
        ? 'La nota de crédito electrónica (E34) todavía no se emite desde aquí: no cargues esa secuencia.'
        : `Tipo de comprobante no admitido: ${ncfType || '(vacío)'}. Usa E31, E32, E44 o E45.`,
    )
  }

  const { data: existingRow, error: existingErr } = await service
    .from('ncf_sequences')
    .select('id, current_number, max_number')
    .eq('branch_id', branchId)
    .eq('prefix', ((body.sequence?.ncf_type ?? '') as string).trim().toUpperCase())
    .maybeSingle()
  if (existingErr) {
    throw new HttpError(500, 'db_error', 'No se pudieron leer las secuencias', existingErr.message)
  }

  // `planSequenceWrite` valida el rango y decide si se crea o se extiende;
  // rechaza, entre otras cosas, un rango que termine antes de lo ya consumido.
  // De `existing` solo mira `id` y `current_number`: flutter_shop+ no guarda
  // el inicio del rango, y no hace falta.
  const existing: ExistingSequence | null = existingRow
    ? {
      id: (existingRow as { id: string }).id,
      range_start: 1,
      range_end: Number((existingRow as { max_number: number | null }).max_number ?? 0),
      current_number: Number((existingRow as { current_number: number }).current_number),
    }
    : null

  const plan = planSequenceWrite(body.sequence ?? {}, existing, todayInSantoDomingo())
  if (!plan.ok) {
    throw new HttpError(422, 'invalid_sequence', plan.errors.join(' '), plan.errors)
  }

  if (plan.value.kind === 'update') {
    const { patch } = plan.value
    const { error } = await service
      .from('ncf_sequences')
      .update({
        max_number: patch.range_end,
        expires_on: patch.expiration_date,
        is_active: true,
        // Solo si la DGII reporta un consumo mayor al que lleva el POS.
        ...(patch.current_number === undefined ? {} : { current_number: patch.current_number }),
        updated_by: userId,
      })
      .eq('id', plan.value.id)
    if (error) throw new HttpError(500, 'db_error', 'No se pudo guardar la secuencia', error.message)
    return json({ ok: true, changed: true, ncf_type: (body.sequence?.ncf_type ?? '').toString() })
  }

  const { row } = plan.value
  // `range_start` y `authorized_by` no tienen columna aquí: el arranque del
  // rango ya va dentro de `current_number` (el último consumido).
  const { error } = await service.from('ncf_sequences').insert({
    branch_id: branchId,
    receipt_type: RECEIPT_TYPE_BY_ECF[row.ncf_type] ?? 'fiscal_credit',
    prefix: row.prefix,
    current_number: row.current_number,
    max_number: row.range_end,
    expires_on: row.expiration_date,
    is_active: true,
    created_by: userId,
    updated_by: userId,
  })
  if (error) throw new HttpError(500, 'db_error', 'No se pudo crear la secuencia', error.message)
  return json({ ok: true, changed: true, ncf_type: row.ncf_type })
}

/**
 * El RNC con el que salen las facturas (`app_settings.company_tax_id`, el que
 * manda emit-document) tiene que ser el de la empresa vinculada en Alanube.
 * Si el ULID quedó apuntando a otro contribuyente (vinculado a mano, por
 * ejemplo), los comprobantes se firmarían con el certificado ajeno. Mismo
 * chequeo que `provision-ecf` en mangospos.
 */
async function assertSameRnc(
  service: SupabaseClient,
  companyId: string,
  alanubeCompanyId: string,
): Promise<void> {
  const { data: appSettings, error } = await service
    .from('app_settings')
    .select('company_tax_id')
    .eq('company_id', companyId)
    .maybeSingle()
  if (error) throw new HttpError(500, 'db_error', 'No se pudo leer el RNC de la empresa', error.message)
  const rncInvoices = normalizeRnc((appSettings as { company_tax_id: string | null } | null)?.company_tax_id)
  if (!rncInvoices) {
    throw new HttpError(
      409,
      'missing_rnc',
      'Tu empresa no tiene RNC en Configuración → Información de la Compañía. Sin él no se puede emitir.',
    )
  }

  let company: AssociatedCompany
  try {
    company = await getCompany(alanubeOrThrow(), alanubeCompanyId)
  } catch (e) {
    if (e instanceof HttpError) throw e
    throw new HttpError(
      502,
      'alanube_error',
      'No se pudo confirmar tu empresa con el proveedor. Intenta de nuevo.',
      e instanceof AlanubeError ? e.body : String(e),
    )
  }

  const rncProvider = normalizeRnc(company.identification)
  if (rncProvider !== rncInvoices) {
    throw new HttpError(
      409,
      'rnc_mismatch',
      `El RNC de tus facturas (${rncInvoices}) no es el de la empresa registrada con el proveedor ` +
        `(${rncProvider || 'sin RNC'}). Escríbenos antes de encender la facturación electrónica.`,
      { rnc_facturas: rncInvoices, rnc_proveedor: rncProvider, empresa: company.name ?? null },
    )
  }
}

/**
 * Enciende o apaga la modalidad e-CF.
 *
 * Encenderla sin empresa registrada o sin secuencia usable deja al POS
 * emitiendo serie E que nadie puede firmar: se rechaza antes en vez de
 * fallar en la primera venta.
 */
async function actionSetEcfEnabled(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId, body } = ctx
  if (typeof body.enabled !== 'boolean') {
    throw new HttpError(400, 'invalid_request', 'enabled debe ser true o false')
  }
  const enabled = body.enabled

  const settings = await loadSettings(service, companyId)

  if (enabled) {
    if (!settings?.alanube_company_id) {
      throw new HttpError(
        409,
        'not_registered',
        'Falta registrar tu empresa con el proveedor antes de encender la facturación electrónica.',
      )
    }
    const { rows } = await loadEcfSequences(service, companyId)
    if (!hasUsableEcfSequence(toUsabilityRows(rows), todayInSantoDomingo())) {
      throw new HttpError(
        409,
        'no_sequence',
        'No hay una secuencia e-NCF activa, vigente y con números: la primera venta fallaría.',
      )
    }
    await assertSameRnc(service, companyId, settings.alanube_company_id)
  }

  // 'hybrid' y no 'electronic': el respaldo en papel es lo que salva la venta
  // si el proveedor no responde. Apagar vuelve a 'physical'.
  const mode = enabled ? 'hybrid' : 'physical'
  const { error } = await service
    .from('company_ecf_settings')
    .upsert({ company_id: companyId, mode, updated_by: userId }, { onConflict: 'company_id' })
  if (error) throw new HttpError(500, 'db_error', 'No se pudo cambiar la modalidad', error.message)
  await audit(service, userId, companyId, 'set_ecf_enabled', {
    before: settings?.mode ?? 'physical',
    after: mode,
  })

  // En mangospos aquí se movía `fiscal_settings.default_ncf_type` (E32 ↔ B02).
  // Aquí no hay tal columna y no hace falta: la venta elige por `receipt_type`
  // y `assign_next_ncf` consume la secuencia que corresponda a la modalidad.
  return json({ ok: true, mode })
}

// ── Pantalla de certificación ───────────────────────────────────────────────

async function actionStatus(ctx: Ctx): Promise<Response> {
  const { service, companyId } = ctx
  const [current, settings, sequences] = await Promise.all([
    loadOnboarding(service, companyId),
    loadSettings(service, companyId),
    loadEcfSequences(service, companyId),
  ])
  const usableSequences = hasUsableEcfSequence(toUsabilityRows(sequences.rows), todayInSantoDomingo())

  const alanubeId = current?.alanube_company_id ?? settings?.alanube_company_id ?? null
  let company: ReturnType<typeof summarizeCompany> & { webhooks_ok: boolean } | null = null
  let companyError: string | null = null
  // Los sets solo interesan mientras la certificación está en curso.
  const certifying = Boolean(current) && !current?.dgii_authorized_at
  const [, testSet, approvalSet, simulationSet] = await Promise.all([
    (async () => {
      if (!alanubeId) return
      try {
        const raw = await getCompany(alanubeOrThrow(), alanubeId)
        company = {
          ...summarizeCompany(raw),
          webhooks_ok: JSON.stringify(raw.webhooks ?? {}).includes(WEBHOOK_PATH),
        }
      } catch (e) {
        companyError = describeAlanubeError(e, 'consultar la empresa')
      }
    })(),
    certifying && current?.test_set_loaded_at
      ? testSetSummary(service, companyId, current, 'ecf')
      : Promise.resolve(null),
    certifying && current?.approval_set_loaded_at
      ? testSetSummary(service, companyId, current, 'acecf')
      : Promise.resolve(null),
    certifying && current?.simulation_set_generated_at
      ? testSetSummary(service, companyId, current, 'sim')
      : Promise.resolve(null),
  ])

  return json({
    stage: stageOf(current, settings, usableSequences),
    onboarding: current,
    settings,
    company,
    company_error: companyError,
    test_set: testSet,
    approval_set: approvalSet,
    simulation_set: simulationSet,
    ...sequencesPayload(sequences.branches, sequences.rows),
    environment: environmentFromBaseUrl(Deno.env.get('ALANUBE_BASE_URL') ?? ''),
  })
}

/**
 * Con la empresa ya registrada, el RNC no puede ser otro que el de esa empresa
 * en Alanube: sus comprobantes se firman con ese certificado.
 */
async function assertRncMatchesLinkedCompany(
  ctx: Ctx,
  current: OnboardingRow | null,
  rnc: string | null,
): Promise<void> {
  if (current?.alanube_company_id && current.rnc && normalizeRnc(current.rnc) === normalizeRnc(rnc)) {
    return
  }
  const settings = await loadSettings(ctx.service, ctx.companyId)
  const alanubeId = current?.alanube_company_id ?? settings?.alanube_company_id
  if (!alanubeId) return

  let company: AssociatedCompany
  try {
    company = await getCompany(alanubeOrThrow(), alanubeId)
  } catch (e) {
    throw new HttpError(
      502,
      'alanube_error',
      `No se pudo confirmar el RNC contra tu empresa registrada: ${describeAlanubeError(e, 'consultar la empresa')}`,
    )
  }
  if (normalizeRnc(company.identification) !== normalizeRnc(rnc)) {
    throw new HttpError(
      409,
      'rnc_locked',
      `Tu empresa está registrada con el proveedor con el RNC ${company.identification ?? '(sin RNC)'}. ` +
        'No se puede poner otro RNC.',
    )
  }
}

function pickTaxpayer(row: TaxpayerData): TaxpayerData {
  return {
    rnc: row.rnc,
    legal_name: row.legal_name,
    trade_name: row.trade_name,
    fiscal_address: row.fiscal_address,
    province: row.province,
    municipality: row.municipality,
    email: row.email,
  }
}

async function actionSaveData(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId, body } = ctx
  const v = validateTaxpayer(body.data ?? {})
  if (!v.ok) throw new HttpError(422, 'invalid_data', v.errors.join(' '), v.errors)

  const current = await loadOnboarding(service, companyId)
  await assertRncMatchesLinkedCompany(ctx, current, v.value.rnc)

  const saved = await upsertOnboarding(service, companyId, userId, current, { ...v.value })
  await audit(service, userId, companyId, 'save_data', {
    before: current ? pickTaxpayer(current) : null,
    after: v.value,
  })
  return json({ ok: true, onboarding: saved })
}

async function actionSaveCertificate(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId, body } = ctx
  if (body.accept_certificate_storage !== true) {
    throw new HttpError(
      422,
      'storage_not_authorized',
      'Autoriza que tu certificado se guarde cifrado para firmar las pruebas de la DGII.',
    )
  }
  const result = validateCertificate(body.certificate ?? {})
  if (!result.ok) throw new HttpError(422, 'invalid_certificate', result.errors.join(' '), result.errors)
  // No reemplazar un certificado utilizable por un archivo o clave erróneos.
  await signerOrThrow(result.value)
  const key = await credentialsKeyOrThrow()
  const current = await loadOnboarding(service, companyId)
  const certificate = await certificateWrite(key, result.value, companyId)
  if (!(await audit(service, userId, companyId, 'save_certificate', {
    certificate_file: certificate.certificate_filename,
    replacing: Boolean(current?.certificate_updated_at),
  }))) {
    throw new HttpError(500, 'audit_failed', 'No se pudo registrar la carga; el certificado no se guardó.')
  }
  const saved = await upsertOnboarding(service, companyId, userId, current, certificate)
  return json({ ok: true, onboarding: saved })
}

async function actionSaveOfvCredentials(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId, body } = ctx
  const user = (body.ofv_user ?? '').trim()
  // La clave no se recorta: un espacio puede ser parte de ella.
  const password = body.ofv_password ?? ''
  const errors = [
    ...(user ? [] : ['Falta el usuario de la Oficina Virtual de la DGII.']),
    ...(user.length > 60 ? ['El usuario de la Oficina Virtual es demasiado largo.'] : []),
    ...(password.trim() ? [] : ['Falta la clave de la Oficina Virtual de la DGII.']),
    ...(password.length > 128 ? ['La clave de la Oficina Virtual es demasiado larga.'] : []),
  ]
  if (errors.length > 0) throw new HttpError(422, 'invalid_request', errors.join(' '), errors)

  const key = await credentialsKeyOrThrow()
  const current = await loadOnboarding(service, companyId)
  const saved = await upsertOnboarding(service, companyId, userId, current, {
    ofv_user: user,
    ofv_password_enc: await sealSecret(key, password, companyId),
    ofv_password_updated_at: new Date().toISOString(),
  })
  await audit(service, userId, companyId, 'save_ofv_credentials', {
    ofv_user: user,
    replacing: Boolean(current?.ofv_password_updated_at),
  })
  return json({ ok: true, onboarding: saved })
}

async function actionRevealOfvPassword(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId } = ctx
  const { data, error } = await service
    .from('ecf_onboarding')
    .select('ofv_user, ofv_password_enc')
    .eq('company_id', companyId)
    .maybeSingle()
  if (error) throw onboardingDbError(error, 'No se pudo leer la solicitud')
  const row = data as { ofv_user: string | null; ofv_password_enc: string | null } | null
  if (!row?.ofv_password_enc) {
    throw new HttpError(404, 'not_found', 'No hay una clave de la Oficina Virtual guardada.')
  }

  const key = await credentialsKeyOrThrow()
  let password: string
  try {
    password = await openSecret(key, row.ofv_password_enc, companyId)
  } catch {
    throw new HttpError(
      500,
      'decrypt_failed',
      'No se pudo descifrar la clave. Guárdala de nuevo en "Cambiar".',
    )
  }

  // Ver una clave siempre deja rastro.
  if (!(await audit(service, userId, companyId, 'reveal_ofv_password', {}))) {
    throw new HttpError(500, 'audit_failed', 'No se pudo registrar la consulta; la clave no se muestra.')
  }
  return json({ ofv_user: row.ofv_user, ofv_password: password })
}

// ── Certificación ante la DGII ──────────────────────────────────────────────

async function actionPostulationInfo(ctx: Ctx): Promise<Response> {
  const companyId = await requireCompanyId(ctx)
  const alanube = alanubeOrThrow()

  const [providerRes, companyRes] = await Promise.allSettled([
    alanube.request<unknown>({ method: 'GET', path: '/provider-info' }),
    getCompany(alanube, companyId),
  ])

  if (providerRes.status === 'rejected') {
    throw new HttpError(502, 'alanube_error', describeAlanubeError(providerRes.reason, 'consultar los datos del proveedor'))
  }

  // Sin URLs la pantalla igual sirve: se informa y sigue.
  let companyUrls: ReturnType<typeof summarizeCompany>['company_urls'] = null
  let companyError: string | null = null
  if (companyRes.status === 'fulfilled') {
    companyUrls = summarizeCompany(companyRes.value).company_urls
  } else {
    companyError = describeAlanubeError(companyRes.reason, 'consultar la empresa')
  }

  return json({
    provider: parseProviderInfo(providerRes.value),
    company_urls: companyUrls,
    company_error: companyError,
  })
}

/**
 * Baja el XML firmado del enlace que da Alanube, para que la app lo descargue
 * directo (no tiene url_launcher). Best-effort: si no se puede, la app muestra
 * el enlace.
 */
async function fetchSignedXml(url: string): Promise<string | null> {
  try {
    if (!url.startsWith('https://')) return null
    const res = await fetch(url, { signal: AbortSignal.timeout(20_000) })
    if (!res.ok) return null
    const bytes = new Uint8Array(await res.arrayBuffer())
    if (bytes.length === 0 || bytes.length > MAX_SIGNED_XML_BYTES) return null
    let bin = ''
    for (const b of bytes) bin += String.fromCharCode(b)
    return btoa(bin)
  } catch (e) {
    console.error('ecf-onboarding: no se pudo bajar el XML firmado:', errorText(e))
    return null
  }
}

async function actionSignDocument(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId, body } = ctx
  const xml = validateEnablingXml({ ...(body.xml ?? {}), kind: body.kind })
  if (!xml.ok) throw new HttpError(422, 'invalid_xml', xml.errors.join(' '), xml.errors)

  const alanubeId = await requireCompanyId(ctx)

  const form = new FormData()
  form.append('xml', new Blob([new Uint8Array(xml.value.bytes)], { type: 'application/xml' }), xml.value.filename)

  let signedUrl: string | null = null
  try {
    const res = await alanubeOrThrow().request<{ signedDocumentUrl?: unknown }>({
      method: 'POST',
      path: `/sign-document/idCompany/${encodeURIComponent(alanubeId)}`,
      form,
      timeoutMs: 60_000,
    })
    signedUrl = typeof res?.signedDocumentUrl === 'string' ? res.signedDocumentUrl : null
  } catch (e) {
    if (e instanceof HttpError) throw e
    const status = e instanceof AlanubeError && e.status >= 400 && e.status < 500 ? 422 : 502
    throw new HttpError(status, 'alanube_error', describeAlanubeError(e, 'firmar el documento'), e instanceof AlanubeError ? e.body : undefined)
  }
  if (!signedUrl) {
    throw new HttpError(502, 'alanube_error', 'El proveedor firmó pero no devolvió el enlace del XML firmado.')
  }

  const current = await loadOnboarding(service, companyId)
  const signedAt = new Date().toISOString()
  await upsertOnboarding(service, companyId, userId, current, {
    [SIGNED_AT_COLUMN[xml.value.kind]]: signedAt,
  } as Partial<OnboardingRow>)
  await audit(service, userId, companyId, 'sign_document', {
    kind: xml.value.kind,
    filename: xml.value.filename,
    bytes: xml.value.bytes.length,
  })

  return json({
    ok: true,
    kind: xml.value.kind,
    signed_at: signedAt,
    signed_document_url: signedUrl,
    signed_xml_base64: await fetchSignedXml(signedUrl),
    signed_filename: xml.value.filename,
  })
}

// ── Set de pruebas de la DGII ────────────────────────────────────────────────
//
// La DGII entrega el set en su portal de certificación; aquí se carga, se
// firma con el .p12 del cliente y se manda a CerteCF. Alanube no participa.

const TEST_CASE_COLUMNS =
  'id, kind, position, case_id, ecf_type, encf, total, via, modifies, status, track_id, security_code, ' +
  'messages, sent_at, checked_at'

interface TestCaseRow {
  id: string
  kind: TestSetKind
  position: number
  case_id: string
  ecf_type: string
  encf: string
  total: number | string | null
  via: 'ecf' | 'rfce' | 'acecf'
  modifies: string | null
  status: TestCaseStatus
  track_id: string | null
  security_code: string | null
  messages: DgiiMessage[] | null
  sent_at: string | null
  checked_at: string | null
}

interface TestCaseWithData extends TestCaseRow {
  fields: TestSetField[]
  summary_fields: TestSetField[] | null
}

const BASE64_FILE_RE = /^[A-Za-z0-9+/]+={0,2}$/

function decodeUpload(file: RequestBody['file']): { filename: string; bytes: Uint8Array } {
  const filename = (file?.filename ?? '').trim()
  const content = (file?.content_base64 ?? '').replace(/^data:[^,]*,/, '').replace(/\s+/g, '')
  if (!filename) throw new HttpError(422, 'invalid_file', 'Falta el nombre del archivo.')
  if (!content || content.length % 4 !== 0 || !BASE64_FILE_RE.test(content)) {
    throw new HttpError(422, 'invalid_file', 'El contenido del archivo no es base64 válido.')
  }
  return { filename, bytes: Uint8Array.from(atob(content), (c) => c.charCodeAt(0)) }
}

function testSetDbError(error: { code?: string; message: string }, what: string): HttpError {
  // Tabla, columna, check o función que no existen: la migración 105.
  if (['42P01', 'PGRST205', '42703', 'PGRST204', '23514', 'PGRST202', '42883'].includes(error.code ?? '')) {
    return new HttpError(500, 'migration_missing', MIGRATION_105, error.message)
  }
  return new HttpError(500, 'db_error', what, error.message)
}

function setKindOf(raw: unknown): TestSetKind {
  if (raw === undefined || raw === null || raw === 'ecf') return 'ecf'
  if (raw === 'acecf' || raw === 'sim') return raw
  throw new HttpError(400, 'invalid_request', 'set_kind debe ser ecf, acecf o sim')
}

const SET_NAMES: Record<TestSetKind, string> = {
  ecf: 'el set de pruebas de e-CF',
  acecf: 'las aprobaciones comerciales',
  sim: 'la simulación de e-CF',
}

async function loadTestCases(
  service: SupabaseClient,
  companyId: string,
  kind: TestSetKind,
): Promise<TestCaseWithData[]> {
  const { data, error } = await service
    .from('ecf_test_set_cases')
    .select(`${TEST_CASE_COLUMNS}, fields, summary_fields`)
    .eq('company_id', companyId)
    .eq('kind', kind)
    .order('position')
  if (error) throw testSetDbError(error, 'No se pudo leer el set de pruebas')
  return (data ?? []) as unknown as TestCaseWithData[]
}

async function testSetSummary(
  service: SupabaseClient,
  companyId: string,
  onboarding: OnboardingRow | null,
  kind: TestSetKind,
) {
  const { data, error } = await service
    .from('ecf_test_set_cases')
    .select(TEST_CASE_COLUMNS)
    .eq('company_id', companyId)
    .eq('kind', kind)
    .order('position')
  if (error) throw testSetDbError(error, 'No se pudo leer el set de pruebas')
  const expires = onboarding?.dgii_test_token_expires_at ?? null
  return {
    kind,
    filename: (kind === 'ecf'
      ? onboarding?.test_set_filename
      : kind === 'acecf'
      ? onboarding?.approval_set_filename
      : null) ?? null,
    loaded_at: (kind === 'ecf'
      ? onboarding?.test_set_loaded_at
      : kind === 'acecf'
      ? onboarding?.approval_set_loaded_at
      : onboarding?.simulation_set_generated_at) ?? null,
    // Mientras no venza, "Consultar" no pide el certificado.
    session_expires_at: expires && new Date(expires).getTime() > Date.now() ? expires : null,
    cases: ((data ?? []) as unknown as TestCaseRow[]).map((c) => ({
      ...c,
      total: c.total === null ? null : Number(c.total),
    })),
  }
}

async function updateTestCase(
  service: SupabaseClient,
  c: TestCaseRow,
  patch: Partial<TestCaseRow> & { signed_xml?: string | null },
): Promise<void> {
  const { error } = await service.from('ecf_test_set_cases').update(patch).eq('id', c.id)
  if (error) throw testSetDbError(error, `No se pudo guardar el resultado de ${c.encf}`)
  Object.assign(c, patch)
}

function fieldValue(fields: TestSetField[], column: string): string | null {
  const c = column.toLowerCase()
  return fields.find(([k]) => k.toLowerCase() === c)?.[1].trim() ?? null
}

/** Nombre que pide la DGII: RNC de quien firma (emisor, o comprador en el ACECF) + e-NCF. */
function dgiiFilename(c: TestCaseWithData): string {
  const rnc = fieldValue(c.fields, c.via === 'acecf' ? 'RNCComprador' : 'RNCEmisor') ?? ''
  return `${rnc.replace(/\D/g, '')}${c.encf}.xml`
}

function dgiiErrorMessages(e: unknown): DgiiMessage[] {
  if (e instanceof DgiiError && e.messages.length > 0) return e.messages
  return [{ code: e instanceof DgiiError && e.status > 0 ? String(e.status) : null, message: errorText(e) }]
}

function errorText(e: unknown): string {
  return e instanceof Error ? e.message : String(e)
}

function tokenContext(companyId: string): string {
  return `${companyId}:dgii-test-token`
}

/** Semilla firmada → token de CerteCF. Se guarda cifrado para "Consultar". */
async function authenticateDgii(
  dgii: DgiiCertificationClient,
  signer: DgiiSigner,
  service: SupabaseClient,
  companyId: string,
): Promise<string> {
  let token
  try {
    const seed = await dgii.getSeed()
    token = await dgii.validateSeed(await signXml(canonicalSeed(seed), signer))
  } catch (e) {
    if (e instanceof SignerError) throw new HttpError(502, 'dgii_error', e.message)
    throw new HttpError(502, 'dgii_error', `No se pudo autenticar con la DGII: ${errorText(e)}`, e instanceof DgiiError ? e.body : undefined)
  }
  try {
    const sealed = await sealSecret(await credentialsKeyOrThrow(), token.token, tokenContext(companyId))
    const { error } = await service
      .from('ecf_onboarding')
      .update({ dgii_test_token_enc: sealed, dgii_test_token_expires_at: token.expiresAt.toISOString() })
      .eq('company_id', companyId)
    if (error) console.error('ecf-onboarding: no se guardó el token de la DGII:', error.message)
  } catch (e) {
    // Sin llave igual se manda; solo que "Consultar" pedirá el certificado.
    console.error('ecf-onboarding: no se guardó el token de la DGII:', errorText(e))
  }
  return token.token
}

/** La DGII ya no acepta el token guardado (401): el próximo envío se autentica de nuevo. */
async function forgetDgiiTokenOn401(e: unknown, service: SupabaseClient, companyId: string): Promise<void> {
  if (!(e instanceof DgiiError) || e.status !== 401) return
  await service
    .from('ecf_onboarding')
    .update({ dgii_test_token_enc: null, dgii_test_token_expires_at: null })
    .eq('company_id', companyId)
}

async function storedDgiiToken(service: SupabaseClient, companyId: string): Promise<string | null> {
  const { data, error } = await service
    .from('ecf_onboarding')
    .select('dgii_test_token_enc, dgii_test_token_expires_at')
    .eq('company_id', companyId)
    .maybeSingle()
  if (error) return null
  const row = data as { dgii_test_token_enc: string | null; dgii_test_token_expires_at: string | null } | null
  // Un minuto de margen: que no venza a mitad de la consulta.
  if (!row?.dgii_test_token_enc || !row.dgii_test_token_expires_at) return null
  if (new Date(row.dgii_test_token_expires_at).getTime() < Date.now() + 60_000) return null
  try {
    return await openSecret(await credentialsKeyOrThrow(), row.dgii_test_token_enc, tokenContext(companyId))
  } catch {
    return null
  }
}

/** Firma y manda un caso. Devuelve por qué hay que parar, o null para seguir. */
async function sendTestCase(
  c: TestCaseWithData,
  signer: DgiiSigner,
  dgii: DgiiCertificationClient,
  token: string,
  service: SupabaseClient,
  companyId: string,
): Promise<string | null> {
  const now = new Date().toISOString()
  let signed: string
  let result: DgiiResult
  let code: string
  try {
    if (c.via === 'acecf') {
      signed = await signXml(buildAcecfXml(c.fields), signer)
      code = securityCode(signed)
      result = await dgii.sendCommercialApproval(token, dgiiFilename(c), signed)
    } else {
      signed = await signXml(buildEcfXml(c.fields, dgiiTimestamp()), signer)
      code = securityCode(signed)
      result = c.via === 'rfce'
        ? await dgii.sendSummary(token, dgiiFilename(c), await signXml(buildRfceXml(c.summary_fields ?? [], code), signer))
        : await dgii.sendEcf(token, dgiiFilename(c), signed)
    }
  } catch (e) {
    await forgetDgiiTokenOn401(e, service, companyId)
    await updateTestCase(service, c, {
      status: 'error',
      messages: dgiiErrorMessages(e),
      signed_xml: null,
      sent_at: now,
      checked_at: now,
    })
    return `${c.encf}: ${errorText(e)}`
  }
  await updateTestCase(service, c, {
    status: result.status,
    track_id: result.trackId,
    security_code: code,
    signed_xml: signed,
    messages: result.messages,
    sent_at: now,
    checked_at: isFinalStatus(result.status) ? now : null,
  })
  if (result.status === 'rejected') {
    return `La DGII rechazó ${c.encf}: hay que reiniciar el set en el portal de la DGII y cargar el archivo nuevo.`
  }
  return null
}

/**
 * Consulta los trackId pendientes mientras quede tiempo. Devuelve cuántos
 * siguen en proceso (incluye los que no alcanzó a consultar).
 */
async function refreshTrackIds(
  cases: TestCaseRow[],
  dgii: DgiiCertificationClient,
  token: string,
  service: SupabaseClient,
  companyId: string,
  outOfTime: () => boolean,
): Promise<number> {
  let open = 0
  for (const c of cases) {
    if (c.status !== 'sent' || !c.track_id) continue
    // Cada consulta puede tardar hasta 20 s: sin este corte, unas pocas lentas
    // pasan los 60 s del runtime. Lo que falta lo consulta el siguiente lote.
    if (outOfTime()) {
      open++
      continue
    }
    try {
      const r = await dgii.trackStatus(token, c.track_id)
      const now = new Date().toISOString()
      await updateTestCase(service, c, {
        status: r.status,
        messages: r.messages.length > 0 ? r.messages : c.messages,
        checked_at: now,
      })
      if (r.status === 'sent') open++
    } catch (e) {
      console.error(`ecf-onboarding: consulta de ${c.encf} falló:`, errorText(e))
      if (e instanceof DgiiError && e.status === 401) {
        await forgetDgiiTokenOn401(e, service, companyId)
        throw new HttpError(409, 'dgii_session_expired', 'La sesión con la DGII venció: elige el certificado otra vez.')
      }
      open++
    }
  }
  return open
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

/** Casos como los recibe fn_ecf_replace_test_set_cases. */
function testCaseRows(cases: TestSetCase[]) {
  return cases.map((c) => ({
    position: c.position,
    case_id: c.case_id,
    ecf_type: c.ecf_type,
    encf: c.encf,
    total: c.total,
    via: c.via,
    modifies: c.modifies,
    fields: c.fields,
    summary_fields: c.summary_fields,
    issuer_rnc: c.issuer_rnc ?? null,
  }))
}

/** RNC de la solicitud o, si no lo hay, el de las facturas. */
async function resolveRnc(ctx: Ctx): Promise<string | null> {
  const onboarding = await loadOnboarding(ctx.service, ctx.companyId)
  if (onboarding?.rnc) return onboarding.rnc
  const { data } = await ctx.service
    .from('app_settings')
    .select('company_tax_id')
    .eq('company_id', ctx.companyId)
    .maybeSingle()
  const rnc = normalizeRnc((data as { company_tax_id: string | null } | null)?.company_tax_id)
  return rnc.length > 0 ? rnc : null
}

async function actionImportTestSet(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId, body } = ctx
  const expected = body.set_kind === undefined ? null : setKindOf(body.set_kind)
  const { filename, bytes } = decodeUpload(body.file)
  let file
  try {
    file = await readTestSetFile(filename, bytes)
  } catch (e) {
    throw new HttpError(422, 'invalid_file', errorText(e))
  }
  const kind = file.kind
  if (expected && expected !== kind) {
    throw new HttpError(
      422,
      'wrong_test_set',
      `Ese archivo es ${SET_NAMES[kind]}, no ${SET_NAMES[expected]}. Cárgalo en su paso.`,
    )
  }
  const parsed = file.kind === 'acecf' ? parseApprovalSet(file.rows) : parseTestSet(file.sheets)
  if (!parsed.ok) throw new HttpError(422, 'invalid_test_set', parsed.errors.join(' '), parsed.errors)
  const cases = parsed.value

  // La DGII arma el set para un RNC: el de otro contribuyente no sirve.
  const rnc = await resolveRnc(ctx)
  if (!rnc) throw new HttpError(409, 'incomplete_data', 'Guarda primero el RNC del contribuyente.')
  const fileRnc = cases[0].signer_rnc
  if (normalizeRnc(fileRnc) !== normalizeRnc(rnc)) {
    throw new HttpError(
      409,
      'rnc_mismatch',
      `El archivo es del RNC ${fileRnc || '(sin RNC)'} y tu empresa tiene el ${rnc}.`,
    )
  }

  // Borrar y guardar en una sola transacción: si el set nuevo no entra, el
  // anterior queda como estaba.
  const { error: replaceErr } = await service.rpc('fn_ecf_replace_test_set_cases', {
    p_company_id: companyId,
    p_kind: kind,
    p_cases: testCaseRows(cases),
  })
  if (replaceErr) throw testSetDbError(replaceErr, 'No se pudo guardar el set de pruebas')

  const current = await loadOnboarding(service, companyId)
  const loadedAt = new Date().toISOString()
  const saved = await upsertOnboarding(
    service,
    companyId,
    userId,
    current,
    kind === 'ecf'
      ? { test_set_filename: filename, test_set_loaded_at: loadedAt }
      : { approval_set_filename: filename, approval_set_loaded_at: loadedAt },
  )
  await audit(service, userId, companyId, 'import_test_set', {
    kind,
    filename,
    cases: cases.length,
    summaries: cases.filter((c) => c.via === 'rfce').length,
    rfce_sheet: file.kind === 'ecf' ? file.sheets.rfce !== null : null,
    replaced: (kind === 'ecf' ? current?.test_set_filename : current?.approval_set_filename) ?? null,
  })
  return json({ ok: true, kind, test_set: await testSetSummary(service, companyId, saved, kind) })
}

async function actionSendTestSet(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId, body } = ctx
  const kind = setKindOf(body.set_kind)
  const cert = await certificateFor(ctx)

  const cases = await loadTestCases(service, companyId, kind)
  if (cases.length === 0) {
    throw new HttpError(409, 'no_test_set', `Primero carga el archivo de ${SET_NAMES[kind]} de la DGII.`)
  }
  const rejected = cases.find((c) => c.status === 'rejected')
  if (rejected) {
    throw new HttpError(
      409,
      'test_set_rejected',
      `La DGII rechazó ${rejected.encf}: reinicia el set en el portal de la DGII y carga el archivo nuevo.`,
    )
  }
  const pending = sendOrder(cases.filter((c) => c.status === 'pending' || c.status === 'error'))
  if (pending.length === 0) {
    throw new HttpError(409, 'nothing_to_send', `Ya se mandó todo ${SET_NAMES[kind]}.`)
  }

  const started = Date.now()
  const outOfTime = () => Date.now() - started > TEST_SET_SEND_BUDGET_MS
  const signer = await signerOrThrow(cert)
  const dgii = new DgiiCertificationClient()
  // Los lotes siguientes reusan la sesión de la DGII (dura ~1 h).
  const token = await storedDgiiToken(service, companyId) ??
    await authenticateDgii(dgii, signer, service, companyId)

  const byEncf = new Map(cases.map((c) => [c.encf, c]))
  let sent = 0

  /** Manda en orden hasta que algo obligue a parar o se acabe el tiempo. */
  const sendAll = async (list: TestCaseWithData[]): Promise<{ stop: string | null; timedOut: boolean }> => {
    for (const c of list) {
      if (outOfTime()) return { stop: null, timedOut: true }
      const stop = await sendTestCase(c, signer, dgii, token, service, companyId)
      sent++
      if (stop) return { stop, timedOut: false }
    }
    return { stop: null, timedOut: false }
  }

  // Primero los comprobantes; las notas después de que la DGII acepte lo que
  // modifican. Las aprobaciones comerciales no esperan nada.
  const notes = kind === 'acecf' ? [] : pending.filter((c) => isAdjustmentNote(c.ecf_type))
  const referenceReady = (n: TestCaseWithData) => {
    const ref = n.modifies ? byEncf.get(n.modifies) : undefined
    return !ref || ref.status === 'accepted' || ref.status === 'conditional'
  }
  const referenceRejected = (n: TestCaseWithData) => {
    const ref = n.modifies ? byEncf.get(n.modifies) : undefined
    return ref?.status === 'rejected' || ref?.status === 'error'
  }

  let run = await sendAll(pending.filter((c) => !notes.includes(c)))
  let stopped = run.stop
  let more = run.timedOut
  if (!stopped && !more && notes.length > 0) {
    while (!notes.every(referenceReady) && !notes.some(referenceRejected) && !outOfTime()) {
      await sleep(TEST_SET_POLL_INTERVAL_MS)
      await refreshTrackIds(cases, dgii, token, service, companyId, outOfTime)
    }
    run = await sendAll(notes.filter(referenceReady))
    stopped = run.stop
    more = run.timedOut
    const blocked = notes.filter((n) => n.status === 'pending' && referenceRejected(n))
    if (!stopped && blocked.length > 0) {
      stopped = `No se mandaron ${blocked.map((n) => n.encf).join(', ')}: el comprobante que modifican no fue aceptado.`
    } else if (!stopped && notes.some((n) => n.status === 'pending')) {
      more = true // Todavía en proceso en la DGII: el siguiente lote las manda.
    }
  }

  // Lo recién mandado suele quedar listo en segundos.
  while (cases.some((c) => c.status === 'sent') && !outOfTime()) {
    await sleep(TEST_SET_POLL_INTERVAL_MS)
    await refreshTrackIds(cases, dgii, token, service, companyId, outOfTime)
  }

  await audit(service, userId, companyId, 'send_test_set', {
    kind,
    sent,
    more,
    stopped,
    certificate_subject: signer.subject,
    statuses: Object.fromEntries(cases.map((c) => [c.encf, c.status])),
  })
  const onboarding = await loadOnboarding(service, companyId)
  return json({
    ok: true,
    sent,
    more: more && !stopped,
    stopped_reason: stopped,
    test_set: await testSetSummary(service, companyId, onboarding, kind),
  })
}

async function actionCheckTestSet(ctx: Ctx): Promise<Response> {
  const { service, companyId, body } = ctx
  // Solo los e-CF quedan "en proceso": el resumen y la aprobación comercial responden en el acto.
  const kind = setKindOf(body.set_kind)
  if (kind === 'acecf') throw new HttpError(400, 'invalid_request', 'Las aprobaciones comerciales no se consultan.')
  const cases = await loadTestCases(service, companyId, kind)
  if (cases.some((c) => c.status === 'sent' && c.track_id)) {
    const started = Date.now()
    const outOfTime = () => Date.now() - started > TEST_SET_SEND_BUDGET_MS
    const dgii = new DgiiCertificationClient()
    let token = await storedDgiiToken(service, companyId)
    if (!token) {
      let cert: ValidCertificate
      try {
        cert = await certificateFor(ctx)
      } catch (e) {
        if (e instanceof HttpError && e.code === 'certificate_not_found') {
          throw new HttpError(
            409,
            'dgii_session_expired',
            'La sesión con la DGII venció: carga tu certificado para consultar.',
          )
        }
        throw e
      }
      token = await authenticateDgii(dgii, await signerOrThrow(cert), service, companyId)
    }
    await refreshTrackIds(cases, dgii, token, service, companyId, outOfTime)
  }
  const onboarding = await loadOnboarding(service, companyId)
  return json({ ok: true, test_set: await testSetSummary(service, companyId, onboarding, kind) })
}

async function actionTestCaseXml(ctx: Ctx): Promise<Response> {
  const { service, companyId, body } = ctx
  const id = body.case_id?.trim() ?? ''
  if (!UUID_RE.test(id)) throw new HttpError(400, 'invalid_request', 'case_id debe ser un UUID')
  const { data, error } = await service
    .from('ecf_test_set_cases')
    .select('encf, case_id, via, fields, signed_xml')
    .eq('company_id', companyId)
    .eq('id', id)
    .maybeSingle()
  if (error) throw testSetDbError(error, 'No se pudo leer el comprobante')
  const row = data as
    | { encf: string; case_id: string; via: string; fields: TestSetField[]; signed_xml: string | null }
    | null
  if (!row) throw new HttpError(404, 'not_found', 'Ese comprobante no es del set cargado.')
  if (!row.signed_xml) throw new HttpError(409, 'not_signed', `${row.encf} todavía no se ha firmado.`)
  let print = null
  if (row.via !== 'acecf') {
    try {
      print = buildPrintModel(row.fields, row.signed_xml)
    } catch (e) {
      console.error(`ecf-onboarding: RI de ${row.encf} falló:`, errorText(e))
    }
  }
  return json({
    filename: `${row.case_id.endsWith(row.encf) ? row.case_id : row.encf}.xml`,
    xml: row.signed_xml,
    print,
  })
}

/**
 * e-NCF que ya usaron OTRAS empresas de esta base con el mismo RNC. La DGII
 * cuenta los números por RNC, así que la simulación no puede repetirlos. Solo
 * se leen números: nada de sus datos sale de aquí.
 */
async function usedEncfOfSameRnc(
  service: SupabaseClient,
  companyId: string,
  rnc: string,
): Promise<{ used: Array<{ ecf_type: string; encf: string }>; sequences: Array<Record<string, number>> }> {
  const { data, error } = await service
    .from('ecf_onboarding')
    .select('company_id, simulation_sequences')
    .eq('rnc', rnc)
    .neq('company_id', companyId)
  if (error) throw onboardingDbError(error, 'No se pudieron leer las otras altas del RNC')
  const rows = (data ?? []) as Array<{ company_id: string; simulation_sequences: Record<string, number> | null }>
  if (rows.length === 0) return { used: [], sequences: [] }
  const { data: used, error: usedErr } = await service
    .from('ecf_test_set_cases')
    .select('ecf_type, encf')
    .in('company_id', rows.map((r) => r.company_id))
    .in('kind', ['ecf', 'sim'])
  if (usedErr) throw testSetDbError(usedErr, 'No se pudieron leer los e-NCF ya usados del RNC')
  return {
    used: (used ?? []) as Array<{ ecf_type: string; encf: string }>,
    sequences: rows.map((r) => r.simulation_sequences ?? {}),
  }
}

/**
 * Paso 4: e-CF de simulación con el set de datos de la empresa como modelo
 * (o el genérico de la DGII, si se certifica con proveedor y no pasó por las
 * pruebas de datos). Volver a generar reemplaza los casos y SIEMPRE usa e-NCF
 * nuevos.
 */
async function actionGenerateSimulationSet(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId, body } = ctx
  const onboarding = await loadOnboarding(service, companyId)
  if (!onboarding?.rnc || !onboarding.legal_name || !onboarding.fiscal_address) {
    throw new HttpError(409, 'incomplete_data', 'Faltan el RNC, la razón social o la dirección fiscal del contribuyente.')
  }
  const rnc = normalizeRnc(onboarding.rnc)
  const others = await usedEncfOfSameRnc(service, companyId, rnc)
  const own = await loadTestCases(service, companyId, 'ecf')
  const templates: SimulationTemplate[] = own.length > 0
    ? own as unknown as SimulationTemplate[]
    : DGII_SIMULATION_TEMPLATES.map((t) => ({ ...t, fields: [...t.fields] }))
  const templateSource = own.length > 0 ? 'own' : 'dgii'
  const current = await loadTestCases(service, companyId, 'sim')
  let models = templates
  if (body.counts && typeof body.counts === 'object') {
    const picked = selectSimulationTemplates(models, body.counts)
    if (!picked.ok) throw new HttpError(422, 'invalid_counts', picked.errors.join(' '), picked.errors)
    models = picked.value
  }

  // Primer número libre por tipo: después de todo lo ya usado, aunque se haya borrado.
  const next: Record<string, number> = {}
  const bump = (type: string, n: number) => {
    next[type] = Math.max(next[type] ?? 1, n + 1)
  }
  for (const c of [...templates, ...current, ...others.used]) bump(c.ecf_type, encfNumber(c.encf))
  for (const seq of [onboarding.simulation_sequences ?? {}, ...others.sequences]) {
    for (const [type, n] of Object.entries(seq)) bump(type, Number(n))
  }

  const built = buildSimulationCases(
    models,
    {
      rnc,
      legalName: onboarding.legal_name,
      tradeName: onboarding.trade_name ?? null,
      address: onboarding.fiscal_address,
      province: onboarding.province ?? null,
      municipality: onboarding.municipality ?? null,
      phone: onboarding.phone ?? onboarding.contact_phone ?? null,
      email: onboarding.email ?? null,
    },
    dgiiTimestamp().slice(0, 10),
    next,
  )
  if (!built.ok) throw new HttpError(422, 'invalid_simulation', built.errors.join(' '), built.errors)
  const { cases, lastNumbers } = built.value

  // Reservar los números y reemplazar los casos en una transacción, con la fila
  // del alta bloqueada: si otra simulación reservó números mientras se armaba
  // esta, se aborta sin tocar nada (si no, las dos usarían los mismos e-NCF).
  const sequences: Record<string, number> = { ...(onboarding.simulation_sequences ?? {}) }
  for (const [type, n] of Object.entries(lastNumbers)) sequences[type] = Math.max(sequences[type] ?? 0, n)
  const { error: replaceErr } = await service.rpc('fn_ecf_replace_simulation_set', {
    p_company_id: companyId,
    p_user_id: userId,
    p_expected_sequences: onboarding.simulation_sequences ?? {},
    p_sequences: sequences,
    p_cases: testCaseRows(cases),
  })
  if (replaceErr) {
    if (replaceErr.message?.includes('SIMULATION_CONFLICT')) {
      throw new HttpError(
        409,
        'simulation_conflict',
        'Se generó otra simulación al mismo tiempo. Vuelve a tocar Generar.',
      )
    }
    throw testSetDbError(replaceErr, 'No se pudo guardar la simulación')
  }
  const saved = await loadOnboarding(service, companyId)

  await audit(service, userId, companyId, 'generate_simulation_set', {
    template_source: templateSource,
    cases: cases.length,
    encf: cases.map((c) => c.encf),
    replaced: current.map((c) => ({ encf: c.encf, status: c.status })),
  })
  return json({ ok: true, kind: 'sim', test_set: await testSetSummary(service, companyId, saved, 'sim') })
}

async function actionSetDgiiAuthorized(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId, body } = ctx
  if (typeof body.authorized !== 'boolean') {
    throw new HttpError(400, 'invalid_request', 'authorized debe ser true o false')
  }
  const current = await loadOnboarding(service, companyId)
  const value = body.authorized ? new Date().toISOString() : null
  const saved = await upsertOnboarding(service, companyId, userId, current, { dgii_authorized_at: value })
  await audit(service, userId, companyId, 'set_dgii_authorized', {
    before: current?.dgii_authorized_at ?? null,
    after: value,
  })
  return json({ ok: true, onboarding: saved })
}

// ── Bitácora ────────────────────────────────────────────────────────────────

/**
 * Best-effort: una falla de la bitácora no deshace el paso ya hecho. Devuelve
 * si quedó registrada (usar el certificado guardado o ver la clave de la OFV
 * sin rastro NO se permite: esas acciones abortan).
 */
async function audit(
  service: SupabaseClient,
  userId: string,
  companyId: string,
  action: string,
  payload: unknown,
): Promise<boolean> {
  const { error } = await service.from('ecf_onboarding_audit').insert({
    company_id: companyId,
    user_id: userId,
    action: `ecf.onboarding.${action}`,
    payload,
  })
  if (error) console.error(`ecf-onboarding: bitácora ${action} falló:`, error.message)
  return !error
}

// ── Entrada ─────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return fail(405, 'method_not_allowed', 'Use POST')
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !ANON_KEY) {
    return fail(500, 'config_error', 'Faltan las variables de Supabase.')
  }

  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader.startsWith('Bearer ')) return fail(401, 'unauthorized', 'Falta el Bearer token')

  let body: RequestBody
  try {
    body = await req.json()
  } catch {
    return fail(400, 'invalid_request', 'El body debe ser JSON')
  }

  const action = body.action ?? ''
  if (!CLIENT_ACTIONS.has(action)) {
    return fail(400, 'invalid_request', `Acción desconocida: ${action || '(vacía)'}`)
  }

  const companyId = (body.company_id ?? '').trim()
  if (!UUID_RE.test(companyId)) {
    return fail(400, 'invalid_request', 'company_id debe ser un UUID')
  }

  // ── Autorización ──────────────────────────────────────────────────────────
  // La RLS de `companies` usa has_company_access: si el caller no pertenece a
  // la empresa, la fila no es visible. Y solo admin: la facturación
  // electrónica compromete a la empresa ante la DGII.
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: { user: caller }, error: authError } = await userClient.auth.getUser()
  if (authError || !caller) return fail(401, 'unauthorized', 'No se pudo resolver el usuario')

  const { data: companyRow, error: companyErr } = await userClient
    .from('companies')
    .select('id')
    .eq('id', companyId)
    .maybeSingle()
  if (companyErr) return fail(500, 'db_error', 'No se pudo leer la empresa', companyErr.message)
  if (!companyRow) return fail(403, 'forbidden', 'No tienes acceso a esta empresa.')

  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: profile, error: profileErr } = await service
    .from('profiles')
    .select('role')
    .eq('id', caller.id)
    .maybeSingle()
  if (profileErr) return fail(500, 'db_error', 'No se pudo leer el perfil', profileErr.message)
  if ((profile as { role: string } | null)?.role !== 'admin') {
    return fail(403, 'forbidden', 'Solo un administrador puede gestionar la facturación electrónica.')
  }

  const ctx: Ctx = { service, userId: caller.id, companyId, body }

  try {
    switch (action) {
      case 'request_status':
        return await actionRequestStatus(ctx)
      case 'submit_request':
        return await actionSubmitRequest(ctx)
      case 'save_sequence':
        return await actionSaveSequence(ctx)
      case 'set_ecf_enabled':
        return await actionSetEcfEnabled(ctx)
      case 'status':
        return await actionStatus(ctx)
      case 'save_data':
        return await actionSaveData(ctx)
      case 'save_certificate':
        return await actionSaveCertificate(ctx)
      case 'save_ofv_credentials':
        return await actionSaveOfvCredentials(ctx)
      case 'reveal_ofv_password':
        return await actionRevealOfvPassword(ctx)
      case 'postulation_info':
        return await actionPostulationInfo(ctx)
      case 'sign_document':
        return await actionSignDocument(ctx)
      case 'import_test_set':
        return await actionImportTestSet(ctx)
      case 'send_test_set':
        return await actionSendTestSet(ctx)
      case 'check_test_set':
        return await actionCheckTestSet(ctx)
      case 'test_case_xml':
        return await actionTestCaseXml(ctx)
      case 'generate_simulation_set':
        return await actionGenerateSimulationSet(ctx)
      case 'set_dgii_authorized':
        return await actionSetDgiiAuthorized(ctx)
      default:
        return fail(400, 'invalid_request', `Acción desconocida: ${action}`)
    }
  } catch (e) {
    if (e instanceof HttpError) return fail(e.status, e.code, e.message, e.detail)
    console.error(`ecf-onboarding ${action} falló:`, e)
    return fail(500, 'internal_error', e instanceof Error ? e.message : String(e))
  }
})
