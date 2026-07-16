// register-company
// Crea una company en Alanube y persiste el mapping en company_ecf_settings.
// Idempotente: si la empresa ya tiene alanube_company_id, retorna 409.
//
// Adaptación de mangopos-backend/register-company a flutter_shop+:
//   * El body solo recibe { company_id } (+ overrides opcionales). RNC, razón
//     social, dirección y email se toman de app_settings de esa empresa
//     (company_tax_id, company_legal_name/company_name, company_address,
//     company_email), con fallback a la fila legacy id=1.
//   * business_alanube_settings → company_ecf_settings (clave company_id).
//   * Acceso validado con RLS del caller sobre `companies` (equivale al RPC
//     has_company_access: la policy de SELECT usa esa misma función).
//   * province/municipality no existen en app_settings: se aceptan opcionales
//     en el body y se omiten del payload Alanube si no vienen.
//
// Auth: requiere JWT Supabase del caller. Writes con service_role solo
// después de validar el acceso del caller a la empresa.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const ALANUBE_BASE_URL = Deno.env.get('ALANUBE_BASE_URL') ?? 'https://sandbox.alanube.co/dom/v1'
const ALANUBE_JWT = Deno.env.get('ALANUBE_JWT') ?? ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''

interface RegisterCompanyBody {
  company_id: string
  environment?: 'sandbox' | 'production'
  mode?: 'physical' | 'electronic' | 'hybrid'
  // Sin equivalente en app_settings — opcionales, requeridos por Alanube
  // según ambiente; si faltan, Alanube responderá 422 y se reporta al caller.
  province?: string
  municipality?: string
}

interface AlanubeCompanyPayload {
  rnc: string
  legalName: string
  tradeName: string
  address: string
  province?: string
  municipality?: string
  email?: string
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  // Config sanity (falla ruidoso, no a sandbox por defecto)
  if (!ALANUBE_JWT) return json({ error: 'config_error', detail: 'ALANUBE_JWT missing' }, 500)
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !ANON_KEY) {
    return json({ error: 'config_error', detail: 'Supabase env vars missing' }, 500)
  }

  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader.startsWith('Bearer ')) {
    return json({ error: 'unauthorized' }, 401)
  }

  // Parse + validate body
  let body: RegisterCompanyBody
  try {
    body = await req.json()
  } catch {
    return json({ error: 'invalid_json' }, 400)
  }

  const validation = validateBody(body)
  if (validation) return json({ error: 'validation_error', detail: validation }, 400)

  // 1) Cliente con JWT del caller: verifica identidad + acceso a la empresa
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: { user: caller }, error: authError } = await userClient.auth.getUser()
  if (authError || !caller) {
    return json({ error: 'unauthorized' }, 401)
  }

  // RLS de companies usa has_company_access: si el caller no pertenece a la
  // empresa, la fila no es visible.
  const { data: companyRow, error: companyErr } = await userClient
    .from('companies')
    .select('id, name')
    .eq('id', body.company_id)
    .maybeSingle()

  if (companyErr) {
    return json({ error: 'db_error', detail: companyErr.message }, 500)
  }
  if (!companyRow) {
    return json({ error: 'forbidden' }, 403)
  }

  // 2) Cliente service_role para escrituras y lecturas privilegiadas
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  // Idempotencia: company_ecf_settings tiene UNIQUE(company_id) y puede
  // existir una fila previa (p.ej. creada solo para fijar mode) sin
  // alanube_company_id. Solo es conflicto si ya hay alanube_company_id.
  const { data: existing, error: existingErr } = await adminClient
    .from('company_ecf_settings')
    .select('id, alanube_company_id, environment, certification_status, mode')
    .eq('company_id', body.company_id)
    .maybeSingle()

  if (existingErr) {
    return json({ error: 'db_error', detail: existingErr.message }, 500)
  }
  if (existing && existing.alanube_company_id) {
    return json({
      error: 'already_registered',
      detail: 'company_ecf_settings ya tiene alanube_company_id para esta empresa',
      existing,
    }, 409)
  }

  // 3) Datos del emisor desde app_settings (empresa), fallback fila legacy id=1
  let { data: settings, error: settingsErr } = await adminClient
    .from('app_settings')
    .select('company_name, company_legal_name, company_tax_id, company_address, company_email')
    .eq('company_id', body.company_id)
    .maybeSingle()

  if (settingsErr) {
    return json({ error: 'db_error', detail: settingsErr.message }, 500)
  }
  if (!settings) {
    const fallback = await adminClient
      .from('app_settings')
      .select('company_name, company_legal_name, company_tax_id, company_address, company_email')
      .eq('id', 1)
      .maybeSingle()
    if (fallback.error) {
      return json({ error: 'db_error', detail: fallback.error.message }, 500)
    }
    settings = fallback.data
  }
  if (!settings) {
    return json({
      error: 'settings_missing',
      detail: 'No hay app_settings para esta empresa. Completa Configuración › Compañía primero.',
    }, 422)
  }

  const rnc = (settings.company_tax_id ?? '').replace(/\D/g, '')
  const razonSocial = settings.company_legal_name || settings.company_name || companyRow.name
  const nombreComercial = settings.company_name || razonSocial
  const address = settings.company_address ?? ''
  const email = settings.company_email ?? undefined

  if (!/^\d{9,11}$/.test(rnc)) {
    return json({
      error: 'validation_error',
      detail: 'app_settings.company_tax_id (RNC) debe tener 9-11 dígitos. Configúralo en Configuración › Compañía.',
    }, 422)
  }
  if (!razonSocial) {
    return json({
      error: 'validation_error',
      detail: 'Falta company_legal_name/company_name en app_settings.',
    }, 422)
  }
  if (!address) {
    return json({
      error: 'validation_error',
      detail: 'Falta company_address en app_settings.',
    }, 422)
  }
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ error: 'validation_error', detail: 'app_settings.company_email inválido' }, 422)
  }

  // 4) Crear company en Alanube
  const alanubePayload: AlanubeCompanyPayload = {
    rnc,
    legalName: razonSocial,
    tradeName: nombreComercial,
    address,
  }
  if (body.province) alanubePayload.province = body.province
  if (body.municipality) alanubePayload.municipality = body.municipality
  if (email) alanubePayload.email = email

  const alanubeRes = await callAlanube(alanubePayload)
  if (!alanubeRes.ok) {
    return json({
      error: 'alanube_error',
      status: alanubeRes.status,
      detail: alanubeRes.body,
    }, alanubeRes.status >= 500 ? 502 : 422)
  }

  const alanubeCompanyId = extractAlanubeId(alanubeRes.body)
  if (!alanubeCompanyId) {
    return json({
      error: 'alanube_response_unexpected',
      detail: 'no id field in Alanube response',
      response: alanubeRes.body,
    }, 502)
  }

  // 5) Persistir mapping en company_ecf_settings (service_role, bypassea RLS).
  //    UPDATE si ya existía fila sin alanube_company_id, INSERT si no.
  const settingsPatch = {
    alanube_company_id: alanubeCompanyId,
    environment: body.environment ?? 'sandbox',
    mode: body.mode ?? 'hybrid',
    updated_by: caller.id,
  }

  const writeRes = existing
    ? await adminClient
        .from('company_ecf_settings')
        .update(settingsPatch)
        .eq('id', existing.id)
        .select('id, alanube_company_id, environment, certification_status, mode')
        .single()
    : await adminClient
        .from('company_ecf_settings')
        .insert({
          company_id: body.company_id,
          ...settingsPatch,
          created_by: caller.id,
        })
        .select('id, alanube_company_id, environment, certification_status, mode')
        .single()

  if (writeRes.error) {
    // Caso raro: company creada en Alanube pero falla persistencia local.
    // Logueamos el alanube_company_id en el response para reconciliacion manual.
    console.error('Alanube company orphan: persistencia local fallo', {
      alanube_company_id: alanubeCompanyId,
      company_id: body.company_id,
      error: writeRes.error.message,
    })
    return json({
      error: 'db_insert_failed',
      detail: writeRes.error.message,
      orphan_alanube_company_id: alanubeCompanyId,
    }, 500)
  }

  return json({
    success: true,
    settings: writeRes.data,
    company: { id: companyRow.id, name: companyRow.name },
  }, 201)
})

function validateBody(b: Partial<RegisterCompanyBody>): string | null {
  if (!b || typeof b !== 'object') return 'body must be an object'
  if (!b.company_id || typeof b.company_id !== 'string') return 'company_id required (uuid)'
  if (b.environment && !['sandbox', 'production'].includes(b.environment)) {
    return 'environment must be sandbox|production'
  }
  if (b.mode && !['physical', 'electronic', 'hybrid'].includes(b.mode)) {
    return 'mode must be physical|electronic|hybrid'
  }
  return null
}

interface AlanubeResult {
  ok: boolean
  status: number
  body: unknown
}

async function callAlanube(payload: AlanubeCompanyPayload): Promise<AlanubeResult> {
  try {
    const res = await fetch(`${ALANUBE_BASE_URL}/companies`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${ALANUBE_JWT}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(15_000),
    })

    const text = await res.text()
    let parsed: unknown = text
    try { parsed = JSON.parse(text) } catch { /* keep as text */ }

    return { ok: res.ok, status: res.status, body: parsed }
  } catch (err) {
    return {
      ok: false,
      status: 504,
      body: { error: err instanceof Error ? `${err.name}: ${err.message}` : String(err) },
    }
  }
}

function extractAlanubeId(body: unknown): string | null {
  if (!body || typeof body !== 'object') return null
  const obj = body as Record<string, unknown>
  // Alanube convencion: campo "id" (ULID) en respuesta de creacion
  if (typeof obj.id === 'string') return obj.id
  if (typeof obj.companyId === 'string') return obj.companyId
  return null
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  })
}
