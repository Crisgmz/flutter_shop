// alanube-webhook
// Receptor publico de webhooks de Alanube. Validacion via header X-Webhook-Secret.
// Guarda el webhook crudo en ecf_webhook_inbox, localiza el fiscal_document
// (por alanube_document_id, o por eNCF como fallback) y aplica SOLO
// transiciones forward de ecf_status (pending → sent → accepted/rejected).

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { documentStatusUpdate } from '../_shared/ecf-alanube-status.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
const WEBHOOK_SECRET = Deno.env.get('ALANUBE_WEBHOOK_SECRET')

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required')
}
if (!WEBHOOK_SECRET) {
  throw new Error('ALANUBE_WEBHOOK_SECRET required')
}

interface WebhookPayload {
  event?: string
  eventType?: string
  data?: Record<string, unknown>
  message?: string
  documentId?: string
  id?: string
  status?: string
  trackId?: string
  publicUrl?: string
  xmlUrl?: string
  pdfUrl?: string
  signedAt?: string
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405)
  }

  const startedAt = Date.now()

  const text = await req.text()
  let body: WebhookPayload
  try {
    body = JSON.parse(text)
  } catch {
    console.error('invalid JSON in webhook body:', text.slice(0, 500))
    return json({ error: 'invalid_json' }, 400)
  }

  if (body.message === 'Test message') {
    console.log('Alanube webhook handshake received')
    return json({ ok: true, ack: 'test' }, 200)
  }

  const providedSecret = req.headers.get('x-webhook-secret') ?? ''
  if (providedSecret !== WEBHOOK_SECRET) {
    console.error('webhook auth failed: invalid X-Webhook-Secret')
    return json({ error: 'unauthorized' }, 401)
  }

  const headersObj: Record<string, string> = {}
  req.headers.forEach((value, key) => {
    const k = key.toLowerCase()
    if (k !== 'authorization' && k !== 'x-webhook-secret' && k !== 'cookie') {
      headersObj[k] = value
    }
  })

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const eventType = body.event ?? body.eventType ?? 'unknown'

  const { data: inboxRow, error: inboxErr } = await supabase
    .from('ecf_webhook_inbox')
    .insert({
      event_type: eventType,
      payload: body,
      headers: headersObj,
      signature_valid: true,
    })
    .select('id')
    .single()

  if (inboxErr || !inboxRow) {
    console.error('inbox insert failed:', inboxErr)
    return json({ error: 'inbox_failed', detail: inboxErr?.message }, 500)
  }

  let processError: string | null = null
  try {
    await processWebhook(supabase, eventType, body)
  } catch (e) {
    processError = e instanceof Error ? e.message : String(e)
    console.error(`processWebhook failed for inbox ${inboxRow.id}:`, e)
  }

  await supabase
    .from('ecf_webhook_inbox')
    .update({
      processed: !processError,
      processed_at: new Date().toISOString(),
      error: processError?.slice(0, 2000) ?? null,
    })
    .eq('id', inboxRow.id)

  return json({
    ok: !processError,
    inbox_id: inboxRow.id,
    event_type: eventType,
    processed: !processError,
    error: processError,
    duration_ms: Date.now() - startedAt,
  }, 200)
})

interface DocRow {
  id: string
  branch_id: string
  ecf_status: string | null
  alanube_document_id: string | null
}

const onlyDigits = (v: unknown): string => (typeof v === 'string' ? v.replace(/\D/g, '') : '')

/**
 * El aviso no trae un id de Alanube conocido: la respuesta del envío se perdió
 * (doc 'uncertain', o todavía en vuelo). Se busca por e-NCF, pero cada empresa
 * numera su propia serie E desde el 1, así que el mismo e-NCF existe en varias
 * (y en otras apps que comparten la cuenta de Alanube: el 5 nov 2026 los
 * avisos de una empresa de aquí llegaban al webhook de MangoPOS).
 *
 * Solo se adopta UN documento:
 *   - sin id de Alanube y que no esté rechazado ni aceptado (un rechazado por
 *     la validación de Alanube nunca le llegó: un aviso con su número es de
 *     otro emisor);
 *   - de la empresa cuyo RNC es el del aviso (`companyIdentification`), si el
 *     aviso lo trae.
 * Ambiguo o sin coincidencia → no se toca (se resuelve a mano en Comprobantes).
 */
async function adoptByEncf(
  supabase: SupabaseClient,
  encf: string,
  companyIdentification: unknown,
): Promise<DocRow | null> {
  const { data: rows, error } = await supabase
    .from('fiscal_documents')
    .select('id, branch_id, ecf_status, alanube_document_id, branches(company_id)')
    .eq('ncf', encf)
    .is('alanube_document_id', null)
    .not('ecf_status', 'in', '(rejected,accepted)')
    .limit(20)
  if (error) throw new Error(`db error finding doc by ncf: ${error.message}`)

  let candidates = (rows ?? []) as unknown as Array<DocRow & { branches: { company_id: string } | null }>

  const rnc = onlyDigits(companyIdentification)
  if (rnc && candidates.length > 0) {
    const companyIds = [...new Set(candidates.map((c) => c.branches?.company_id).filter(Boolean))] as string[]
    const { data: settings, error: setErr } = await supabase
      .from('app_settings')
      .select('company_id, company_tax_id')
      .in('company_id', companyIds)
    if (setErr) throw new Error(`db error reading company RNC: ${setErr.message}`)
    const sameRnc = new Set(
      ((settings ?? []) as Array<{ company_id: string; company_tax_id: string | null }>)
        .filter((s) => onlyDigits(s.company_tax_id) === rnc)
        .map((s) => s.company_id),
    )
    candidates = candidates.filter((c) => c.branches && sameRnc.has(c.branches.company_id))
  }

  if (candidates.length !== 1) {
    if (candidates.length > 1) {
      console.warn(`webhook: e-NCF ${encf} coincide con varios documentos sin id de Alanube; no se adopta`)
    }
    return null
  }
  const { id, branch_id, ecf_status, alanube_document_id } = candidates[0]
  return { id, branch_id, ecf_status, alanube_document_id }
}

async function processWebhook(
  supabase: SupabaseClient,
  eventType: string,
  body: WebhookPayload,
) {
  // Shape REAL de Alanube DOM (verificado 2026-05-06): payload flat sin wrapper
  // event/data. Trae directamente:
  //   id (alanube_document_id), legalStatus, securityCode, signatureDate,
  //   documentStampUrl, documentNumber, governmentResponse, status, type
  // No hay campo `event` — Alanube manda webhook unico por documento.
  // Por eso eventType viene como 'unknown' y antes saltabamos por la guarda.
  const data = (body.data ?? body) as Record<string, unknown>

  const alanubeDocId = (
    data.id ?? data.documentId ?? data.alanubeDocumentId ?? data.alanube_document_id
  ) as string | undefined

  // eNCF del payload (documentNumber en Alanube DOM; ncf/encf por robustez)
  // — fallback de localización cuando el doc aún no tiene alanube_document_id
  // persistido (ej. respuesta del POST se perdió antes de persistir).
  const encf = (data.ncf ?? data.documentNumber ?? data.encf) as string | undefined

  // Si no hay id ni eNCF, no es un webhook de documento — log y skip sin error.
  if ((!alanubeDocId || typeof alanubeDocId !== 'string') && (!encf || typeof encf !== 'string')) {
    console.log(
      `webhook sin id/eNCF de documento, skip: ${JSON.stringify(data).slice(0, 200)}`,
    )
    return
  }

  let docRow: DocRow | null = null

  if (alanubeDocId && typeof alanubeDocId === 'string') {
    const { data: found, error: docErr } = await supabase
      .from('fiscal_documents')
      .select('id, branch_id, ecf_status, alanube_document_id')
      .eq('alanube_document_id', alanubeDocId)
      .maybeSingle()
    if (docErr) throw new Error(`db error finding doc: ${docErr.message}`)
    docRow = found as DocRow | null
  }

  if (!docRow && encf && typeof encf === 'string') {
    docRow = await adoptByEncf(supabase, encf, data.companyIdentification)
  }

  if (!docRow) {
    console.log(
      `fiscal_document no encontrado para alanube_id=${alanubeDocId ?? 'n/a'} ncf=${encf ?? 'n/a'} — posible doc creado en otro entorno`,
    )
    return
  }

  // Qué se escribe sale de _shared/ecf-alanube-status.ts, lo mismo que usa
  // ecf-status-sync cuando el aviso no llega: las dos fuentes dejan igual el doc.
  const previousStatus = docRow.ecf_status ?? 'pending'
  const change = documentStatusUpdate(data, previousStatus)
  if (change === null) {
    console.log(`skipping backward transition for doc ${docRow.id} (estaba en ${previousStatus})`)
    return
  }
  const { newStatus, rawLegalStatus, updates } = change

  // Si localizamos por eNCF y el doc no tenía alanube_document_id, persistirlo.
  if (alanubeDocId && !docRow.alanube_document_id) {
    updates.alanube_document_id = alanubeDocId
  }

  const { error: updErr } = await supabase
    .from('fiscal_documents')
    .update(updates)
    .eq('id', docRow.id)

  if (updErr) throw new Error(`update fiscal_documents failed: ${updErr.message}`)

  // Migración 101: el webhook es la prueba de que Alanube lo tiene. Un envío
  // que había quedado incierto queda conciliado.
  if (previousStatus === 'uncertain') {
    const { error: outboxErr } = await supabase
      .from('ecf_emit_outbox')
      .update({
        status: 'done',
        next_attempt_at: null,
        error: null,
        resolution: 'webhook_match',
        resolved_at: new Date().toISOString(),
      })
      .eq('fiscal_document_id', docRow.id)
      .eq('status', 'uncertain')
    if (outboxErr) console.error(`webhook: no se pudo cerrar la outbox de ${docRow.id}:`, outboxErr.message)
  }

  await supabase.from('fiscal_document_status_events').insert({
    fiscal_document_id: docRow.id,
    branch_id: docRow.branch_id,
    previous_status: previousStatus,
    new_status: newStatus,
    source: 'webhook',
    note:
      `Alanube webhook legalStatus=${rawLegalStatus}; ` +
      `securityCode=${data.securityCode ?? 'n/a'}; ` +
      `eventType=${eventType}`,
  })

  console.log(
    `webhook updated doc ${docRow.id}: ${previousStatus} -> ${newStatus} (alanube_id=${alanubeDocId ?? 'n/a'}, legalStatus=${rawLegalStatus})`,
  )
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  })
}
