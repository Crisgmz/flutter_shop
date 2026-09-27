// ecf-onboarding: la empresa pide su facturación electrónica desde
// Configuración → Facturación electrónica.
//
// POST /functions/v1/ecf-onboarding
//   { action, company_id, ...params }
//
// Acciones:
//   request_status    → en qué va la facturación electrónica de la empresa
//   submit_request    { data, certificate, contact_name, contact_phone,
//                       already_authorized, accept_terms }
//                     → guarda la solicitud y registra la empresa en Alanube
//   save_sequence     { branch_id, sequence } — la autorización e-NCF de la DGII
//   set_ecf_enabled   { enabled } — enciende/apaga la modalidad e-CF
//
// PORTADO DE mangospos (`supabase/functions/ecf-onboarding`), que es donde
// este flujo ya está probado contra la DGII. Las dos apps comparten la misma
// cuenta de Alanube y las MISMAS reglas: toda la lógica de validación y de
// armado vive en `_shared/ecf-onboarding.ts`, copia verbatim de allá. Acá solo
// está el I/O, que es lo único que cambia porque las tablas son distintas:
//
//   mangospos                      flutter_shop+
//   ──────────────────────────     ────────────────────────────────
//   businesses / business_id       companies / company_id
//   business_alanube_settings      company_ecf_settings
//   fiscal_settings                app_settings (por empresa)
//   ncf_sequences(ncf_type,        ncf_sequences(prefix, receipt_type,
//     range_end, expiration_date)    max_number, expires_on) POR SUCURSAL
//   ecf_onboarding(business_id)    ecf_onboarding(company_id)
//
// El certificado (.p12) y su contraseña viajan a Alanube en la misma petición
// y NO se guardan ni se registran en ningún lado.
//
// Auth: JWT del usuario. La empresa se valida con la RLS del propio caller
// sobre `companies` (misma vía que `register-company`), y además se exige rol
// admin: pedir la facturación electrónica compromete a la empresa ante la
// DGII.

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { createAlanubeClient, AlanubeClient, AlanubeError } from '../_shared/alanube-client.ts'
import {
  AssociatedCompany,
  buildCompanyPayload,
  buildWebhooks,
  companiesMatchingRnc,
  ExistingSequence,
  hasUsableEcfSequence,
  ONBOARDING_SEQUENCE_TYPES,
  parseAssociatedPage,
  planSequenceWrite,
  requestStage,
  summarizeCompany,
  TaxpayerData,
  validateCertificate,
  validateRequestContact,
  validateTaxpayer,
} from '../_shared/ecf-onboarding.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
const WEBHOOK_URL = Deno.env.get('ALANUBE_WEBHOOK_URL') ?? `${SUPABASE_URL}/functions/v1/alanube-webhook`
const WEBHOOK_SECRET = Deno.env.get('ALANUBE_WEBHOOK_SECRET') ?? ''

// Aviso al panel de soporte cuando entra una solicitud. Opcional: sin estas
// variables la solicitud igual se guarda y se registra en Alanube, solo que
// nadie afuera se entera automáticamente.
const PANEL_NOTIFY_URL = Deno.env.get('ECF_PANEL_NOTIFY_URL') ?? ''
const PANEL_NOTIFY_SECRET = Deno.env.get('ECF_PANEL_NOTIFY_SECRET') ?? ''

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** Acciones que puede hacer el dueño/admin de la empresa. */
const CLIENT_ACTIONS = new Set([
  'request_status',
  'submit_request',
  'save_sequence',
  'set_ecf_enabled',
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
  data?: Record<string, unknown>
  sequence?: Record<string, unknown>
  certificate?: Record<string, unknown>
  contact_name?: string
  contact_phone?: string
  already_authorized?: boolean
  accept_terms?: boolean
  enabled?: boolean
}

interface Ctx {
  service: SupabaseClient
  userId: string
  companyId: string
  body: RequestBody
}

// ── Fila de ecf_onboarding ──────────────────────────────────────────────────

interface OnboardingRow extends TaxpayerData {
  company_id: string
  alanube_company_id: string | null
  company_linked_via: string | null
  company_linked_at: string | null
  requested_at: string | null
  requested_by: string | null
  contact_name: string | null
  contact_phone: string | null
  already_authorized: boolean | null
  notified_at: string | null
}

async function loadOnboarding(
  service: SupabaseClient,
  companyId: string,
): Promise<OnboardingRow | null> {
  const { data, error } = await service
    .from('ecf_onboarding')
    .select('*')
    .eq('company_id', companyId)
    .maybeSingle()
  if (error) throw new HttpError(500, 'db_error', 'No se pudo leer la solicitud', error.message)
  return (data as OnboardingRow) ?? null
}

async function upsertOnboarding(
  service: SupabaseClient,
  companyId: string,
  userId: string,
  current: OnboardingRow | null,
  patch: Partial<OnboardingRow>,
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
    .select('*')
    .single()
  if (error) throw new HttpError(500, 'db_error', 'No se pudo guardar la solicitud', error.message)
  return data as OnboardingRow
}

// ── Secuencias: e-CF ↔ el modelo por sucursal de flutter_shop+ ───────────────
//
// En mangospos una secuencia es (business_id, ncf_type). Acá es
// (branch_id, receipt_type, prefix): el tipo vive en `prefix` ('E31') y
// `receipt_type` es la clasificación semántica que ya usa el POS.
//
// La DGII autoriza el rango al RNC, o sea a la EMPRESA, pero este POS consume
// las secuencias por sucursal. Por eso `save_sequence` exige la sucursal: dos
// sucursales compartiendo el mismo rango emitirían el mismo e-NCF dos veces.
// Si el negocio tiene varias, reparte el rango entre ellas.

const RECEIPT_TYPE_BY_ECF: Record<string, string> = {
  E31: 'fiscal_credit',
  E32: 'consumer_final',
  E34: 'fiscal_credit', // nota de crédito: hereda la clasificación del afectado
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
    .select('id, name')
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
  const { data: settings } = await service
    .from('company_ecf_settings')
    .select('alanube_company_id')
    .eq('company_id', companyId)
    .maybeSingle()
  if (settings && (settings as { alanube_company_id: string | null }).alanube_company_id) {
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

  // El ULID también va a company_ecf_settings, que es de donde lo lee
  // `emit-document` al emitir.
  const { error: setErr } = await service
    .from('company_ecf_settings')
    .upsert(
      {
        company_id: companyId,
        alanube_company_id: alanubeId,
        webhooks_configured: true,
        updated_by: userId,
      },
      { onConflict: 'company_id' },
    )
  if (setErr) {
    // La empresa YA quedó creada en Alanube: fallar acá dejaría el ULID
    // huérfano y el próximo intento chocaría con "company_exists". Queda en
    // ecf_onboarding y se reconcilia.
    console.error('ecf-onboarding: no se pudo guardar el ULID en company_ecf_settings', setErr.message)
  }

  return saved
}

// ── Aviso al panel de soporte ───────────────────────────────────────────────
//
// Servidor a servidor, con secreto compartido. Nunca bloquea la solicitud: si
// el panel no contesta, la solicitud igual quedó guardada y registrada, y
// `notified_at` en null marca que falta avisar.

async function notifyPanel(
  service: SupabaseClient,
  row: OnboardingRow,
  companyName: string,
  companyRegistered: boolean,
): Promise<void> {
  if (!PANEL_NOTIFY_URL || !PANEL_NOTIFY_SECRET) return
  try {
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
        alanube_company_id: row.alanube_company_id,
        company_registered: companyRegistered,
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

// ── Acciones ────────────────────────────────────────────────────────────────

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

async function actionRequestStatus(ctx: Ctx): Promise<Response> {
  const { service, companyId } = ctx

  const current = await loadOnboarding(service, companyId)
  const { data: settingsRow } = await service
    .from('company_ecf_settings')
    .select('alanube_company_id, environment, certification_status, mode')
    .eq('company_id', companyId)
    .maybeSingle()
  const settings = settingsRow as {
    alanube_company_id: string | null
    environment: string
    certification_status: string
    mode: string
  } | null

  const { branches, rows } = await loadEcfSequences(service, companyId)
  const today = new Date().toISOString().slice(0, 10)
  const usableSequences = hasUsableEcfSequence(toUsabilityRows(rows), today)

  const hasCompany = Boolean(current?.alanube_company_id ?? settings?.alanube_company_id)
  const stage = requestStage({
    requested: Boolean(current?.requested_at),
    hasCompany,
    dgiiAuthorized: settings?.certification_status === 'certified' ||
      current?.already_authorized === true,
    usableSequences,
    provisioned: Boolean(settings?.alanube_company_id),
    ecfEnabled: (settings?.mode ?? 'physical') !== 'physical',
  })

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

  return json({
    stage,
    requested_at: current?.requested_at ?? null,
    contact_name: current?.contact_name ?? null,
    contact_phone: current?.contact_phone ?? null,
    already_authorized: current?.already_authorized ?? null,
    data,
    mode: settings?.mode ?? 'physical',
    environment: settings?.environment ?? 'sandbox',
    certification_status: settings?.certification_status ?? 'pending',
    alanube_company_id: settings?.alanube_company_id ?? current?.alanube_company_id ?? null,
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
  })
}

async function actionSubmitRequest(ctx: Ctx): Promise<Response> {
  const { service, companyId, userId, body } = ctx

  const data = validateTaxpayer(body.data ?? {}, { forRegistration: true })
  const contact = validateRequestContact(body)
  const cert = validateCertificate(body.certificate ?? {})
  const errors = [
    ...(data.ok ? [] : data.errors),
    ...(contact.ok ? [] : contact.errors),
    ...(cert.ok ? [] : cert.errors),
    ...(body.accept_terms === true
      ? []
      : ['Falta autorizar el registro de tu certificado con el proveedor.']),
  ]
  if (errors.length > 0 || !data.ok || !contact.ok) {
    throw new HttpError(422, 'invalid_request', errors.join(' '), errors)
  }

  const { data: settingsRow } = await service
    .from('company_ecf_settings')
    .select('mode')
    .eq('company_id', companyId)
    .maybeSingle()
  if (settingsRow && (settingsRow as { mode: string }).mode !== 'physical') {
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
    // Un reintento (contraseña equivocada, por ejemplo) no cambia quién ni
    // cuándo lo pidió.
    ...(current?.requested_at ? {} : { requested_at: now, requested_by: userId }),
  } as Partial<OnboardingRow>)

  const { data: companyRow } = await service
    .from('companies')
    .select('name')
    .eq('id', companyId)
    .maybeSingle()
  const companyName = (companyRow as { name: string } | null)?.name ?? ''

  try {
    const registered = await registerCompany(ctx, saved)
    await notifyPanel(service, registered, companyName, true)
    return json({ ok: true, company_registered: true, stage: 'certification' })
  } catch (e) {
    if (!(e instanceof HttpError)) throw e

    if (e.code === 'company_exists') {
      // Ya registrada (otro intento, o alguien la dio de alta a mano): se
      // vincula desde soporte.
      await notifyPanel(service, saved, companyName, false)
      return json({
        ok: true,
        company_registered: false,
        stage: 'company',
        message: 'Tu RNC ya estaba registrado con nuestro proveedor. Lo revisamos y te contactamos.',
      })
    }

    if (e.code === 'alanube_rejected') {
      // Casi siempre: contraseña equivocada o un archivo que no es el
      // certificado de firma. El detalle técnico va aparte, no en el mensaje.
      await notifyPanel(service, saved, companyName, false)
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

  const today = new Date().toISOString().slice(0, 10)
  const plan = planSequenceWrite(body.sequence ?? {}, existing, today)
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
  // `range_start` y `authorized_by` no tienen columna acá: el arranque del
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

  const { data: settingsRow } = await service
    .from('company_ecf_settings')
    .select('alanube_company_id, mode')
    .eq('company_id', companyId)
    .maybeSingle()
  const settings = settingsRow as { alanube_company_id: string | null; mode: string } | null

  if (enabled) {
    if (!settings?.alanube_company_id) {
      throw new HttpError(
        409,
        'not_registered',
        'Falta registrar tu empresa con el proveedor antes de encender la facturación electrónica.',
      )
    }
    const { rows } = await loadEcfSequences(service, companyId)
    const today = new Date().toISOString().slice(0, 10)
    if (!hasUsableEcfSequence(toUsabilityRows(rows), today)) {
      throw new HttpError(
        409,
        'no_sequence',
        'No hay una secuencia e-NCF activa, vigente y con números: la primera venta fallaría.',
      )
    }
  }

  // 'hybrid' y no 'electronic': el respaldo en papel es lo que salva la venta
  // si el proveedor no responde. Apagar vuelve a 'physical'.
  const mode = enabled ? 'hybrid' : 'physical'
  const { error } = await service
    .from('company_ecf_settings')
    .upsert({ company_id: companyId, mode, updated_by: userId }, { onConflict: 'company_id' })
  if (error) throw new HttpError(500, 'db_error', 'No se pudo cambiar la modalidad', error.message)

  // En mangospos acá se movía `fiscal_settings.default_ncf_type` (E32 ↔ B02).
  // Acá no hay tal columna y no hace falta: la venta elige por `receipt_type`
  // y `assign_next_ncf` consume la secuencia que corresponda a la modalidad.
  return json({ ok: true, mode })
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
  // la empresa, la fila no es visible. Y solo admin: pedir la facturación
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
      default:
        return fail(400, 'invalid_request', `Acción desconocida: ${action}`)
    }
  } catch (e) {
    if (e instanceof HttpError) return fail(e.status, e.code, e.message, e.detail)
    console.error(`ecf-onboarding ${action} falló:`, e)
    return fail(500, 'internal_error', e instanceof Error ? e.message : String(e))
  }
})
