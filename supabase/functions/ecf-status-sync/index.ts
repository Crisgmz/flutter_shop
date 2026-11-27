// ecf-status-sync: le PREGUNTA a Alanube en qué quedó cada e-CF que lleva rato
// en 'sent' y guarda la respuesta de la DGII.
//
// Por qué existe (27-nov-2026): el estado final (aceptado / rechazado) llega
// por el aviso de Alanube (alanube-webhook), y el aviso se configura por
// empresa en Alanube. A Maranatha (48 e-CF desde el 05-nov) y Soluciones
// Plásticas (14 desde el 12-nov) nunca les llegó ni uno: no hay fila en
// ecf_webhook_inbox ni intento rechazado en los logs. Se quedaban en 'sent'
// para siempre. Adaptada de mangospos/ecf-status-sync (16-nov, mismo problema).
//
// POST /functions/v1/ecf-status-sync
//   {}                          → hasta BATCH documentos en 'sent', con
//                                 alanube_document_id, enviados hace más de
//                                 MIN_AGE_MINUTES y emitidos en los últimos
//                                 MAX_AGE_DAYS; los que hace más que no se
//                                 consultan primero (ecf_status_checked_at).
//   { fiscal_document_id }      → solo ese, sin mirar la antigüedad
//                                 (solo con la llave service_role).
//
// Lo que se guarda sale de _shared/ecf-alanube-status.ts, igual que el aviso.
// Solo escribe si la DGII ya respondió (aceptado / rechazado) y el documento
// sigue en 'sent': si el aviso llega a la vez, gana el primero y no se pisa.
// Cada consulta marca ecf_status_checked_at, respondan o no.
//
// La llama el cron ecf-status-sync cada 15 min con la llave anon, como
// ecf-emit-batch (migración 112). Con la anon solo corre el lote: lo peor que
// hace un tercero es adelantar consultas que el cron haría igual.

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { AlanubeClient, AlanubeError, createAlanubeClient } from '../_shared/alanube-client.ts'
import { alanubeEndpointForNcfType } from '../_shared/ecf-payload.ts'
import { alanubeDocumentBody, documentStatusUpdate } from '../_shared/ecf-alanube-status.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

const BATCH = 20
const MIN_AGE_MINUTES = 15
const MAX_AGE_DAYS = 45
/** El gateway corta a los 60 s; Alanube puede tardar varios por consulta. */
const BUDGET_MS = 40_000

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

interface DocRow {
  id: string
  branch_id: string
  ncf: string
  alanube_document_id: string
  ecf_status: string
}

type Outcome = 'accepted' | 'rejected' | 'still_sent' | 'not_configured' | 'alanube_error' | 'db_error'

interface Result {
  fiscal_document_id: string
  ncf: string
  outcome: Outcome
  detail?: string
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return json({ error: 'config_error', message: 'Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.' }, 500)
  }

  const auth = req.headers.get('Authorization') ?? ''
  const isService = auth === `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`
  const isAnon = Boolean(SUPABASE_ANON_KEY) && auth === `Bearer ${SUPABASE_ANON_KEY}`
  if (!isService && !isAnon) return json({ error: 'unauthorized' }, 401)

  let targetId: string | null = null
  try {
    const raw = await req.text()
    if (raw.trim().length > 0) {
      const body = JSON.parse(raw) as Record<string, unknown>
      if (body.fiscal_document_id != null) {
        if (typeof body.fiscal_document_id !== 'string' || !UUID_RE.test(body.fiscal_document_id)) {
          return json({ error: 'invalid_request', message: 'fiscal_document_id debe ser un UUID' }, 400)
        }
        if (!isService) return json({ error: 'unauthorized', message: 'Un documento suelto pide service_role' }, 401)
        targetId = body.fiscal_document_id
      }
    }
  } catch {
    return json({ error: 'invalid_request', message: 'El body debe ser JSON' }, 400)
  }

  const service = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  let alanube: AlanubeClient
  try {
    alanube = createAlanubeClient()
  } catch (e) {
    return json({ error: 'config_error', message: e instanceof Error ? e.message : String(e) }, 500)
  }

  const now = Date.now()
  let query = service
    .from('fiscal_documents')
    .select('id, branch_id, ncf, alanube_document_id, ecf_status')
    .eq('ecf_status', 'sent')
    .not('alanube_document_id', 'is', null)
  if (targetId) {
    query = query.eq('id', targetId)
  } else {
    query = query
      .lt('submitted_at', new Date(now - MIN_AGE_MINUTES * 60_000).toISOString())
      .gte('issued_at', new Date(now - MAX_AGE_DAYS * 86_400_000).toISOString())
      .order('ecf_status_checked_at', { ascending: true, nullsFirst: true })
      .order('submitted_at', { ascending: true })
      .limit(BATCH)
  }
  const { data: docRows, error: docsErr } = await query
  if (docsErr) return json({ error: 'db_error', message: docsErr.message }, 500)
  const docs = (docRows ?? []) as DocRow[]

  let companies: Map<string, string>
  try {
    companies = await alanubeCompanyByBranch(service, [...new Set(docs.map((d) => d.branch_id))])
  } catch (e) {
    return json({ error: 'db_error', message: e instanceof Error ? e.message : String(e) }, 500)
  }

  const results: Result[] = []
  for (const doc of docs) {
    if (Date.now() - now > BUDGET_MS) break
    results.push(await syncOne(service, alanube, doc, companies.get(doc.branch_id) ?? null))
  }

  const count = (o: Outcome) => results.filter((r) => r.outcome === o).length
  return json({
    ok: true,
    checked: results.length,
    pending_in_batch: docs.length - results.length,
    accepted: count('accepted'),
    rejected: count('rejected'),
    still_sent: count('still_sent'),
    errors: results.length - count('accepted') - count('rejected') - count('still_sent'),
    results,
  }, 200)
})

/** Sucursal → id de la empresa en Alanube (branches.company_id → company_ecf_settings). */
async function alanubeCompanyByBranch(
  service: SupabaseClient,
  branchIds: string[],
): Promise<Map<string, string>> {
  const result = new Map<string, string>()
  if (branchIds.length === 0) return result

  const { data: branches, error: brErr } = await service
    .from('branches')
    .select('id, company_id')
    .in('id', branchIds)
  if (brErr) throw new Error(`No se pudieron leer las sucursales: ${brErr.message}`)
  const companyOf = new Map(
    ((branches ?? []) as Array<{ id: string; company_id: string | null }>)
      .filter((b) => b.company_id)
      .map((b) => [b.id, b.company_id as string]),
  )

  const companyIds = [...new Set(companyOf.values())]
  if (companyIds.length === 0) return result
  const { data: settings, error: setErr } = await service
    .from('company_ecf_settings')
    .select('company_id, alanube_company_id')
    .in('company_id', companyIds)
  if (setErr) throw new Error(`No se pudo leer company_ecf_settings: ${setErr.message}`)
  const alanubeOf = new Map(
    ((settings ?? []) as Array<{ company_id: string; alanube_company_id: string | null }>)
      .filter((s) => s.alanube_company_id)
      .map((s) => [s.company_id, s.alanube_company_id as string]),
  )

  for (const [branchId, companyId] of companyOf) {
    const alanubeId = alanubeOf.get(companyId)
    if (alanubeId) result.set(branchId, alanubeId)
  }
  return result
}

async function syncOne(
  service: SupabaseClient,
  alanube: AlanubeClient,
  doc: DocRow,
  alanubeCompanyId: string | null,
): Promise<Result> {
  const base = { fiscal_document_id: doc.id, ncf: doc.ncf }
  const checkedAt = new Date().toISOString()
  const markChecked = async () => {
    const { error } = await service
      .from('fiscal_documents')
      .update({ ecf_status_checked_at: checkedAt })
      .eq('id', doc.id)
    if (error) console.error(`ecf-status-sync: no se marcó la consulta de ${doc.id}:`, error.message)
  }

  const endpoint = alanubeEndpointForNcfType(doc.ncf.slice(0, 3))
  if (!alanubeCompanyId || !endpoint) {
    await markChecked()
    return {
      ...base,
      outcome: 'not_configured',
      detail: alanubeCompanyId ? `tipo ${doc.ncf.slice(0, 3)}` : 'sin empresa en Alanube',
    }
  }
  const path = `${endpoint}/${encodeURIComponent(doc.alanube_document_id)}/idCompany/${
    encodeURIComponent(alanubeCompanyId)
  }`

  let body: unknown
  try {
    body = await alanube.request<unknown>({ method: 'GET', path })
  } catch (e) {
    await markChecked()
    const status = e instanceof AlanubeError ? e.status : 0
    return { ...base, outcome: 'alanube_error', detail: `Alanube ${status || 'sin respuesta'}` }
  }

  const data = alanubeDocumentBody(body)
  const change = documentStatusUpdate(data, doc.ecf_status)
  if (change === null || change.newStatus === 'sent' || change.newStatus === 'pending') {
    await markChecked()
    return { ...base, outcome: 'still_sent', detail: change?.rawLegalStatus || undefined }
  }

  // Solo si sigue en 'sent': si el aviso llegó mientras tanto, ya está escrito.
  const { data: updated, error: updErr } = await service
    .from('fiscal_documents')
    .update({ ...change.updates, ecf_status_checked_at: checkedAt })
    .eq('id', doc.id)
    .eq('ecf_status', 'sent')
    .select('id')
  if (updErr) {
    console.error(`ecf-status-sync: no se guardó el estado de ${doc.id}:`, updErr.message)
    return { ...base, outcome: 'db_error', detail: updErr.message }
  }
  if (!updated || updated.length === 0) {
    return { ...base, outcome: 'still_sent', detail: 'el aviso llegó primero' }
  }

  const { error: evErr } = await service.from('fiscal_document_status_events').insert({
    fiscal_document_id: doc.id,
    branch_id: doc.branch_id,
    previous_status: doc.ecf_status,
    new_status: change.newStatus,
    source: 'reconciliation',
    note: `ecf-status-sync: consulta a Alanube legalStatus=${change.rawLegalStatus}; ` +
      `securityCode=${(data.securityCode as string | undefined) ?? 'n/a'}`,
  })
  if (evErr) console.error(`ecf-status-sync: sin evento para ${doc.id}:`, evErr.message)

  console.log(`ecf-status-sync: ${doc.ncf} ${doc.ecf_status} -> ${change.newStatus} (${change.rawLegalStatus})`)
  return {
    ...base,
    outcome: change.newStatus === 'accepted' ? 'accepted' : 'rejected',
    detail: change.newStatus === 'rejected' ? String(change.updates.last_error ?? '') : undefined,
  }
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  })
}
