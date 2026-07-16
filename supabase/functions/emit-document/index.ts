// emit-document: procesa ecf_emit_outbox (emisión e-CF vía Alanube).
// Disparado por cron (cada 60s), por el POS en modo sync, o manualmente.
//
// Modos:
//   * sync  — body { fiscal_document_id }: procesa solo ese doc y devuelve el
//             snapshot del documento para que el POS arme el ticket/QR.
//   * batch — sin body: drena hasta BATCH_SIZE jobs pendientes (cron).
//
// Adaptado de mangopos-backend/emit-document a las tablas de flutter_shop+:
//   alanube_emit_outbox → ecf_emit_outbox (sin settings_id: los settings se
//   resuelven vía company_id), business_alanube_settings → company_ecf_settings,
//   order_items → sale_items, fiscal_settings/businesses → app_settings/branches.

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { createAlanubeClient, AlanubeClient, AlanubeError } from '../_shared/alanube-client.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required')
}

const BATCH_SIZE = 10
const MAX_ATTEMPTS = 5
const BACKOFF_MINUTES = [1, 5, 15, 60, 240]

interface OutboxRow {
  id: string
  fiscal_document_id: string
  branch_id: string
  company_id: string
  attempts: number
}

interface FiscalDocument {
  id: string
  branch_id: string
  sale_id: string | null
  receipt_type: string
  ncf: string
  ecf_status: string | null
  customer_name: string | null
  customer_document_number: string | null
  customer_address: string | null
  subtotal: number | null
  discount_amount: number | null
  exempt_amount: number | null
  taxable_amount: number | null
  tax_amount: number | null
  total_amount: number | null
  is_electronic: boolean
  alanube_document_id: string | null
  issued_at: string | null
  idempotency_key: string | null
}

interface Settings {
  alanube_company_id: string | null
  environment: string
  mode: string
}

interface Sender {
  rnc: string
  companyName: string
  tradename?: string
  address: string
  branchOffice?: string
  mail?: string
}

interface SaleItem {
  id: string
  description: string | null
  quantity: number
  unit_price: number
  discount_amount: number | null
  tax_rate: number | null
  line_subtotal: number | null
  line_tax: number | null
  line_total: number | null
}

interface EcfTaxBreakdown {
  itbisAmount: number
  taxableAmount: number
  effectiveRatePct: number
}

// El código e-CF se deriva del propio NCF: E31/E32/E44/E45/E46 = ncf.slice(0,3).
function getEndpointForNcfType(ncfType: string): string | null {
  switch (ncfType) {
    case 'E31': return '/fiscal-invoices'
    case 'E32': return '/invoices'
    case 'E44': return '/special-regimes'
    case 'E45': return '/gubernamentals'
    default: return null
  }
}

// billingIndicator DGII por tasa ITBIS: 18%→1, 16%→2, gravado 0%→3, exento→4.
// En flutter_shop+ sale_items.tax_rate es porcentaje (18.00) y NO existe flag
// para distinguir "gravado a tasa 0" (indicador 3) de "exento": tratamos
// tax_rate=0 como exento (indicador 4). Simplificación documentada.
function billingIndicatorFromTaxRate(rate: number | null | undefined): 1 | 2 | 3 | 4 {
  const pct = Number(rate ?? 0)
  if (pct >= 17 && pct <= 19) return 1
  if (pct >= 15 && pct < 17) return 2
  return 4
}

interface AlanubeSubmitResponse {
  id?: string
  trackId?: string
  securityCode?: string
  signedAt?: string
  status?: string
  publicUrl?: string
  xmlUrl?: string
  pdfUrl?: string
}

function nextAttemptAt(attemptsAfterIncrement: number): string {
  const idx = Math.min(attemptsAfterIncrement - 1, BACKOFF_MINUTES.length - 1)
  const minutes = BACKOFF_MINUTES[Math.max(0, idx)]
  return new Date(Date.now() + minutes * 60_000).toISOString()
}

// Adaptación de computeEcfBreakdown de mangospos: allí los impuestos vivían en
// order_item_tax_lines con flag taxes.include_in_ecf. En flutter_shop+ el ITBIS
// está denormalizado en sale_items (line_tax + tax_rate) y no existe un flag
// por impuesto, así que TODO line_tax > 0 se considera ITBIS declarable
// (simplificación: no hay propinas legales ni impuestos no-ITBIS por línea).
// Base gravada por línea = line_subtotal - discount_amount.
function computeEcfBreakdown(items: SaleItem[]): EcfTaxBreakdown | null {
  if (items.length === 0) return null

  let itbisAmount = 0
  let taxableAmount = 0
  let weightedRateNum = 0
  let weightedRateDen = 0

  for (const it of items) {
    const tax = Number(it.line_tax ?? 0)
    if (tax <= 0) continue
    const base = Math.max(0, Number(it.line_subtotal ?? 0) - Number(it.discount_amount ?? 0))
    const rate = Number(it.tax_rate ?? 0)
    itbisAmount += tax
    taxableAmount += base
    weightedRateNum += rate * tax
    weightedRateDen += tax
  }

  if (itbisAmount <= 0) return null

  const effectiveRatePct = weightedRateDen > 0
    ? Math.round(weightedRateNum / weightedRateDen)
    : 18

  return {
    itbisAmount: Number(itbisAmount.toFixed(2)),
    taxableAmount: Number(taxableAmount.toFixed(2)),
    effectiveRatePct,
  }
}

function buildAlanubePayload(
  doc: FiscalDocument,
  sender: Sender,
  items: SaleItem[],
  ecfBreakdown: EcfTaxBreakdown | null,
): Record<string, unknown> {
  const ncfType = doc.ncf.slice(0, 3)
  const stampDate = (doc.issued_at ?? new Date().toISOString()).slice(0, 10)
  const isE31OrCreditDoc = ncfType === 'E31'
  const totalAbove250k = Number(doc.total_amount ?? 0) >= 250_000
  const buyerRequired = isE31OrCreditDoc || (ncfType === 'E32' && totalAbove250k)

  const idDoc: Record<string, unknown> = {
    encf: doc.ncf,
    paymentType: 1,
    incomeType: 1,
  }
  if (ncfType !== 'E32') {
    const oneYearAhead = new Date()
    oneYearAhead.setFullYear(oneYearAhead.getFullYear() + 1)
    idDoc.sequenceDueDate = oneYearAhead.toISOString().slice(0, 10)
  }

  const senderPayload: Record<string, unknown> = {
    rnc: sender.rnc,
    companyName: sender.companyName,
    address: sender.address,
    stampDate,
  }
  if (sender.tradename) senderPayload.tradename = sender.tradename
  if (sender.branchOffice) senderPayload.branchOffice = sender.branchOffice
  if (sender.mail) senderPayload.mail = sender.mail

  // Datos del comprador YA vienen snapshoteados en fiscal_documents
  // (customer_name, customer_document_number = RNC/cédula, customer_address).
  let buyer: Record<string, unknown> | undefined
  const hasNamedCustomer = doc.customer_name != null &&
    doc.customer_name !== '' &&
    doc.customer_name !== 'Consumidor Final'
  if (buyerRequired || doc.customer_document_number || hasNamedCustomer) {
    buyer = { companyName: doc.customer_name || 'Consumidor Final' }
    if (doc.customer_document_number) buyer.rnc = doc.customer_document_number
    if (doc.customer_address) buyer.address = doc.customer_address
  }

  const itemDetails = items.length > 0
    ? items.map((it, idx) => {
        const qty = Number(it.quantity ?? 1)
        const unitPrice = Number(it.unit_price ?? 0)
        // itemAmount = base neta de descuento, para que la suma de líneas
        // cuadre con totalTaxedAmount/exemptAmount del breakdown.
        const gross = Number(it.line_subtotal ?? qty * unitPrice)
        const itemAmount = Math.max(0, gross - Number(it.discount_amount ?? 0))
        return {
          lineNumber: idx + 1,
          billingIndicator: billingIndicatorFromTaxRate(it.tax_rate),
          itemName: (it.description ?? 'Producto').slice(0, 80),
          goodServiceIndicator: 1,
          quantityItem: qty,
          unitPriceItem: unitPrice,
          itemAmount,
        }
      })
    : [{
        lineNumber: 1,
        billingIndicator: billingIndicatorFromTaxRate(18),
        itemName: 'Venta general',
        goodServiceIndicator: 1,
        quantityItem: 1,
        unitPriceItem: Number(doc.total_amount ?? 0),
        itemAmount: Number(doc.total_amount ?? 0),
      }]

  // Fallback a los montos snapshoteados del documento si no hay breakdown.
  const itbis = ecfBreakdown?.itbisAmount ?? Number(doc.tax_amount ?? 0)
  const taxable = ecfBreakdown?.taxableAmount ?? Number(doc.taxable_amount ?? 0)
  const exempt = Number(doc.exempt_amount ?? 0)
  const itbisRate = Math.round(ecfBreakdown?.effectiveRatePct ?? 18)

  const declaredTotal = ecfBreakdown != null
    ? Number((taxable + itbis + exempt).toFixed(2))
    : Number(doc.total_amount ?? 0)

  const totals: Record<string, unknown> = {
    totalAmount: declaredTotal,
  }
  if (taxable > 0) {
    totals.totalTaxedAmount = taxable
    totals.i1AmountTaxed = taxable
    totals.itbisS1 = itbisRate
    totals.itbis1Total = itbis
    totals.itbisTotal = itbis
  }
  if (exempt > 0) totals.exemptAmount = exempt

  const payload: Record<string, unknown> = {
    idDoc,
    sender: senderPayload,
    totals,
    itemDetails,
  }
  if (buyer) payload.buyer = buyer

  return payload
}

async function claimBatch(supabase: SupabaseClient): Promise<OutboxRow[]> {
  const now = new Date().toISOString()

  const { data: candidates, error } = await supabase
    .from('ecf_emit_outbox')
    .select('id, fiscal_document_id, branch_id, company_id, attempts')
    .eq('status', 'pending')
    .lte('next_attempt_at', now)
    .order('created_at', { ascending: true })
    .limit(BATCH_SIZE)

  if (error) {
    console.error('claim select failed:', error)
    return []
  }

  const claimed: OutboxRow[] = []
  for (const c of candidates ?? []) {
    const { data: row, error: updErr } = await supabase
      .from('ecf_emit_outbox')
      .update({
        status: 'processing',
        attempts: c.attempts + 1,
        last_attempt_at: now,
      })
      .eq('id', c.id)
      .eq('status', 'pending')
      .select('id, fiscal_document_id, branch_id, company_id, attempts')
      .maybeSingle()

    if (updErr) {
      console.error(`claim update failed for ${c.id}:`, updErr)
      continue
    }
    if (row) claimed.push(row as OutboxRow)
  }

  return claimed
}

async function loadContext(
  supabase: SupabaseClient,
  outbox: OutboxRow,
): Promise<{ doc: FiscalDocument; settings: Settings; sender: Sender; items: SaleItem[] } | null> {
  // Sin settings_id en el outbox: los settings e-CF se resuelven por company_id.
  const [docRes, settingsRes, appSettingsRes, branchRes] = await Promise.all([
    supabase
      .from('fiscal_documents')
      .select(
        'id, branch_id, sale_id, receipt_type, ncf, ecf_status, customer_name, customer_document_number, customer_address, subtotal, discount_amount, exempt_amount, taxable_amount, tax_amount, total_amount, is_electronic, alanube_document_id, issued_at, idempotency_key',
      )
      .eq('id', outbox.fiscal_document_id)
      .single(),
    supabase
      .from('company_ecf_settings')
      .select('alanube_company_id, environment, mode')
      .eq('company_id', outbox.company_id)
      .maybeSingle(),
    supabase
      .from('app_settings')
      .select('id, company_name, company_legal_name, company_tax_id, company_address, company_phone, company_email')
      .eq('company_id', outbox.company_id)
      .maybeSingle(),
    supabase
      .from('branches')
      .select('name, address')
      .eq('id', outbox.branch_id)
      .single(),
  ])

  if (docRes.error || !docRes.data) {
    console.error('load fiscal_document failed:', docRes.error)
    return null
  }
  if (settingsRes.error || !settingsRes.data) {
    console.error('load company_ecf_settings failed:', settingsRes.error)
    return null
  }
  if (branchRes.error || !branchRes.data) {
    console.error('load branch failed:', branchRes.error)
    return null
  }

  // Emisor: app_settings de la empresa, con fallback a la fila legacy id=1.
  let appSettings = appSettingsRes.data as {
    company_name: string
    company_legal_name: string | null
    company_tax_id: string | null
    company_address: string | null
    company_phone: string | null
    company_email: string | null
  } | null
  if (!appSettings) {
    const { data: legacy, error: legacyErr } = await supabase
      .from('app_settings')
      .select('company_name, company_legal_name, company_tax_id, company_address, company_phone, company_email')
      .eq('id', 1)
      .maybeSingle()
    if (legacyErr) {
      console.error('load app_settings fallback failed:', legacyErr)
      return null
    }
    appSettings = legacy
  }

  const branch = branchRes.data as { name: string; address: string | null }

  const rnc = (appSettings?.company_tax_id ?? '').replace(/\D/g, '')
  if (!rnc) {
    console.error(`app_settings.company_tax_id (RNC) missing for company ${outbox.company_id}`)
    return null
  }

  const address = appSettings?.company_address ?? branch.address
  if (!address) {
    console.error(`no address available (app_settings.company_address / branches.address) for company ${outbox.company_id}`)
    return null
  }

  const sender: Sender = {
    rnc,
    companyName: appSettings?.company_legal_name || appSettings?.company_name || branch.name,
    tradename: appSettings?.company_name || undefined,
    address,
    branchOffice: branch.name,
    mail: appSettings?.company_email || undefined,
  }

  const doc = docRes.data as FiscalDocument

  // Ítems: sale_items por sale_id (en mangospos eran order_items por order_id).
  let items: SaleItem[] = []
  if (doc.sale_id) {
    const { data: itemRows, error: itemsErr } = await supabase
      .from('sale_items')
      .select('id, description, quantity, unit_price, discount_amount, tax_rate, line_subtotal, line_tax, line_total')
      .eq('sale_id', doc.sale_id)

    if (itemsErr) {
      console.error('load sale_items failed:', itemsErr)
      return null
    }
    items = (itemRows ?? []) as SaleItem[]
  }

  return { doc, settings: settingsRes.data as Settings, sender, items }
}

async function submitOne(
  supabase: SupabaseClient,
  alanube: AlanubeClient,
  outbox: OutboxRow,
): Promise<{ ok: true } | { ok: false; retryable: boolean; error: string }> {
  const ctx = await loadContext(supabase, outbox)
  if (!ctx) {
    return { ok: false, retryable: false, error: 'context load failed' }
  }
  const { doc, settings, sender, items } = ctx

  if (doc.alanube_document_id) {
    console.log(`doc ${doc.id} already submitted (alanube_id=${doc.alanube_document_id})`)
    return { ok: true }
  }

  if (!doc.is_electronic) {
    return { ok: false, retryable: false, error: 'doc is not electronic' }
  }
  if (settings.mode === 'physical') {
    return { ok: false, retryable: false, error: 'settings.mode=physical, should not be in queue' }
  }
  if (!settings.alanube_company_id) {
    return {
      ok: false,
      retryable: false,
      error: 'company_ecf_settings.alanube_company_id vacío: registra la empresa con register-company primero',
    }
  }

  const ncfType = doc.ncf.slice(0, 3)
  const path = getEndpointForNcfType(ncfType)
  if (!path) {
    return {
      ok: false,
      retryable: false,
      error: `tipo ${ncfType} sin endpoint Alanube mapeado (receipt_type=${doc.receipt_type})`,
    }
  }

  const ecfBreakdown = computeEcfBreakdown(items)
  const payload = buildAlanubePayload(doc, sender, items, ecfBreakdown)
  const idemKey = doc.idempotency_key ?? doc.id

  let resp: AlanubeSubmitResponse
  try {
    resp = await alanube.request<AlanubeSubmitResponse>({
      method: 'POST',
      path,
      body: payload,
      idempotencyKey: idemKey,
      companyId: settings.alanube_company_id,
    })
  } catch (e) {
    const err = e as AlanubeError
    const bodyStr = JSON.stringify(err.body ?? '')
    const isDgiiTransient =
      bodyStr.includes('AEP2009') ||
      bodyStr.includes('DGII service') ||
      bodyStr.includes('network path') ||
      bodyStr.includes('timed out')
    const retryable = err.isRetryable || isDgiiTransient

    console.error(
      `Alanube error for doc ${doc.id}: status=${err.status} retryable=${retryable} (orig=${err.isRetryable}, dgii_transient=${isDgiiTransient}) body=${bodyStr}`,
    )
    return { ok: false, retryable, error: `${err.message} | ${bodyStr}` }
  }

  const mappedStatus = mapAlanubeStatus(resp.status)

  const { error: updErr } = await supabase
    .from('fiscal_documents')
    .update({
      alanube_document_id: resp.id ?? resp.trackId ?? null,
      ecf_tracking_number: resp.trackId ?? null,
      ecf_security_code: resp.securityCode ?? null,
      ecf_signed_at: resp.signedAt ?? null,
      ecf_status: mappedStatus,
      submitted_at: new Date().toISOString(),
      public_url: resp.publicUrl ?? null,
      xml_url: resp.xmlUrl ?? null,
      pdf_url: resp.pdfUrl ?? null,
      last_error: null,
    })
    .eq('id', doc.id)

  if (updErr) {
    console.error(`Failed to persist Alanube response for doc ${doc.id}:`, updErr)
    return { ok: false, retryable: true, error: `persist failed: ${updErr.message}` }
  }

  await supabase.from('fiscal_document_status_events').insert({
    fiscal_document_id: doc.id,
    branch_id: doc.branch_id,
    previous_status: doc.ecf_status ?? 'pending',
    new_status: mappedStatus,
    source: 'api_response',
    note: `Alanube id=${resp.id ?? resp.trackId ?? 'unknown'}; raw_status=${resp.status ?? 'n/a'}`,
  })

  console.log(`doc ${doc.id} submitted OK, alanube_id=${resp.id ?? resp.trackId}`)
  return { ok: true }
}

function mapAlanubeStatus(raw: string | undefined): 'pending' | 'sent' | 'accepted' | 'rejected' {
  if (!raw) return 'sent'
  const s = raw.toLowerCase()
  if (s.includes('accept') || s.includes('aprob')) return 'accepted'
  if (s.includes('reject') || s.includes('rechaz') || s.includes('error')) return 'rejected'
  if (s.includes('pending') || s.includes('pendient')) return 'pending'
  return 'sent'
}

async function completeOutbox(
  supabase: SupabaseClient,
  outbox: OutboxRow,
  result: { ok: true } | { ok: false; retryable: boolean; error: string },
) {
  if (result.ok) {
    await supabase
      .from('ecf_emit_outbox')
      .update({ status: 'done', error: null, next_attempt_at: null })
      .eq('id', outbox.id)
    return
  }

  const isDead = !result.retryable || outbox.attempts >= MAX_ATTEMPTS
  if (isDead) {
    await supabase
      .from('ecf_emit_outbox')
      .update({ status: 'failed', error: result.error.slice(0, 2000) })
      .eq('id', outbox.id)

    await supabase
      .from('fiscal_documents')
      .update({ last_error: result.error.slice(0, 2000), ecf_status: 'rejected' })
      .eq('id', outbox.fiscal_document_id)
  } else {
    await supabase
      .from('ecf_emit_outbox')
      .update({
        status: 'pending',
        error: result.error.slice(0, 2000),
        next_attempt_at: nextAttemptAt(outbox.attempts),
      })
      .eq('id', outbox.id)
  }
}

// Reclamar una sola row de outbox por fiscal_document_id. Mismo patron de
// claim atomico que claimBatch (UPDATE...WHERE status='pending') para evitar
// que dos invocaciones simultaneas (ej. el POS sync + el cron) procesen
// el mismo doc en paralelo.
async function claimSingle(
  supabase: SupabaseClient,
  fiscalDocumentId: string,
): Promise<OutboxRow | null> {
  const now = new Date().toISOString()
  const { data: candidate, error } = await supabase
    .from('ecf_emit_outbox')
    .select('id, fiscal_document_id, branch_id, company_id, attempts')
    .eq('fiscal_document_id', fiscalDocumentId)
    .eq('status', 'pending')
    .order('created_at', { ascending: true })
    .limit(1)
    .maybeSingle()

  if (error) {
    console.error('claimSingle select failed:', error)
    return null
  }
  if (!candidate) return null

  const { data: row, error: updErr } = await supabase
    .from('ecf_emit_outbox')
    .update({
      status: 'processing',
      attempts: candidate.attempts + 1,
      last_attempt_at: now,
    })
    .eq('id', candidate.id)
    .eq('status', 'pending')
    .select('id, fiscal_document_id, branch_id, company_id, attempts')
    .maybeSingle()

  if (updErr) {
    console.error(`claimSingle update failed for ${candidate.id}:`, updErr)
    return null
  }
  return row as OutboxRow | null
}

// Lee del fiscal_documents los campos que el caller (POS) necesita para
// imprimir el ticket inmediatamente sin tener que hacer otro round-trip.
async function loadDocSnapshotForResponse(
  supabase: SupabaseClient,
  fiscalDocumentId: string,
): Promise<Record<string, unknown> | null> {
  const { data, error } = await supabase
    .from('fiscal_documents')
    .select('id, ecf_status, ecf_security_code, ecf_signed_at, alanube_document_id, public_url, last_error')
    .eq('id', fiscalDocumentId)
    .maybeSingle()
  if (error) {
    console.error('loadDocSnapshotForResponse error:', error)
    return null
  }
  return data as Record<string, unknown> | null
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const jsonHeaders = { ...corsHeaders, 'Content-Type': 'application/json' }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  let alanube: AlanubeClient
  try {
    alanube = createAlanubeClient()
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, error: e instanceof Error ? e.message : String(e) }),
      { status: 500, headers: jsonHeaders },
    )
  }

  // Parse opcional del body. Si trae fiscal_document_id, modo sync per-doc:
  // procesa solo ese y devuelve el snapshot del doc para que el POS arme
  // el ticket. Sin body → modo batch (drena la queue, lo que dispara el cron).
  let targetDocId: string | null = null
  try {
    if (req.method === 'POST') {
      const ct = req.headers.get('content-type') ?? ''
      if (ct.includes('application/json')) {
        const raw = await req.text()
        if (raw.length > 0) {
          const body = JSON.parse(raw) as Record<string, unknown>
          const id = body.fiscal_document_id
          if (typeof id === 'string' && id.length > 0) targetDocId = id
        }
      }
    }
  } catch (e) {
    console.error('body parse error (continuando en modo batch):', e)
  }

  const startedAt = Date.now()

  // ─── Modo sync per-doc ──────────────────────────────────────────────────
  if (targetDocId !== null) {
    // La invocacion explicita per-doc es una accion deliberada (POS al cobrar,
    // o boton "Emitir a DGII" en comprobantes): un job agotado (failed) se
    // rehabilita para reintentarlo, reseteando el contador de intentos.
    const { error: reviveErr } = await supabase
      .from('ecf_emit_outbox')
      .update({ status: 'pending', attempts: 0, next_attempt_at: new Date().toISOString() })
      .eq('fiscal_document_id', targetDocId)
      .eq('status', 'failed')
    if (reviveErr) {
      console.error('revive failed outbox error:', reviveErr)
    }

    const claimed = await claimSingle(supabase, targetDocId)
    if (!claimed) {
      // No hay outbox row 'pending' — puede ser que ya se proceso (otro
      // invocador gano el race) o que el trigger no creo la row. Devolvemos
      // el snapshot actual del doc para que el caller decida.
      const snapshot = await loadDocSnapshotForResponse(supabase, targetDocId)
      return new Response(
        JSON.stringify({
          ok: snapshot !== null,
          mode: 'sync',
          claimed: false,
          fiscal_document_id: targetDocId,
          doc: snapshot,
          duration_ms: Date.now() - startedAt,
        }, null, 2),
        { headers: jsonHeaders },
      )
    }

    let result: { ok: true } | { ok: false; retryable: boolean; error: string }
    try {
      result = await submitOne(supabase, alanube, claimed)
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e)
      console.error(`sync: unexpected error for outbox ${claimed.id}:`, e)
      result = { ok: false, retryable: true, error: errMsg }
    }
    await completeOutbox(supabase, claimed, result)
    const snapshot = await loadDocSnapshotForResponse(supabase, targetDocId)

    return new Response(
      JSON.stringify({
        ok: result.ok,
        mode: 'sync',
        claimed: true,
        fiscal_document_id: targetDocId,
        doc: snapshot,
        ...(result.ok ? {} : { retryable: result.retryable, error: result.error }),
        duration_ms: Date.now() - startedAt,
      }, null, 2),
      { headers: jsonHeaders },
    )
  }

  // ─── Modo batch (cron / fallback) ───────────────────────────────────────
  const claimed = await claimBatch(supabase)
  const results: Array<{ outbox_id: string; doc_id: string; ok: boolean; retryable?: boolean; error?: string }> = []

  for (const row of claimed) {
    try {
      const r = await submitOne(supabase, alanube, row)
      await completeOutbox(supabase, row, r)
      results.push({
        outbox_id: row.id,
        doc_id: row.fiscal_document_id,
        ok: r.ok,
        ...(r.ok ? {} : { retryable: r.retryable, error: r.error }),
      })
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e)
      console.error(`unexpected error processing outbox ${row.id}:`, e)
      await completeOutbox(supabase, row, { ok: false, retryable: true, error: errMsg })
      results.push({ outbox_id: row.id, doc_id: row.fiscal_document_id, ok: false, retryable: true, error: errMsg })
    }
  }

  return new Response(
    JSON.stringify({
      ok: true,
      mode: 'batch',
      claimed: claimed.length,
      results,
      duration_ms: Date.now() - startedAt,
      runtime: { deno: Deno.version.deno },
    }, null, 2),
    { headers: jsonHeaders },
  )
})
