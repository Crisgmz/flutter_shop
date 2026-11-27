// COPIA de mangospos/supabase/functions/_shared/ecf-alanube-status.ts (con su
// prueba): las dos apps leen a Alanube igual. Aqui la usan alanube-webhook y
// ecf-status-sync (migracion 112).
//
// Estado DGII de un e-CF tal como lo cuenta Alanube, traducido a lo que se
// guarda en `fiscal_documents`. Logica PURA, compartida por:
//   - alanube-webhook: Alanube AVISA cuando la DGII responde;
//   - ecf-status-sync: MangoPOS PREGUNTA por los que se quedaron en 'sent'
//     porque el aviso nunca llego (16-nov-2026: 20 facturas, ninguna con aviso
//     en alanube_webhook_inbox).
// Las dos fuentes tienen que dejar el documento igual: por eso viven aqui.

export type EcfStatus = "pending" | "sent" | "accepted" | "rejected";

export interface DocumentStatusUpdate {
  newStatus: EcfStatus;
  /** Lo que dijo Alanube (legalStatus), para la auditoria. */
  rawLegalStatus: string;
  /** Columnas de `fiscal_documents` a escribir. */
  updates: Record<string, unknown>;
}

/**
 * Algunas respuestas de Alanube envuelven el documento en `document`; el aviso
 * y la consulta lo traen plano. Se aceptan las dos formas.
 */
export function alanubeDocumentBody(body: unknown): Record<string, unknown> {
  const b = (body ?? {}) as Record<string, unknown>;
  return (b.document && typeof b.document === "object" ? b.document : b) as Record<string, unknown>;
}

/**
 * Que cambia en `fiscal_documents` con lo que Alanube dice del documento, o null
 * si seria retroceder (p. ej. un 'sent' tardio sobre un 'accepted').
 *
 * legalStatus es la verdad final de la DGII (ACCEPTED / REJECTED / IN_PROCESS);
 * `status` (FINISHED / IN_PROGRESS) es del flujo interno de Alanube y solo se
 * usa si no hay legalStatus.
 */
export function documentStatusUpdate(
  data: Record<string, unknown>,
  previousStatus: string,
): DocumentStatusUpdate | null {
  const rawLegalStatus = (data.legalStatus ?? data.status ?? data.documentStatus ?? "") as string;
  const newStatus = mapAlanubeStatus(rawLegalStatus);
  if (!isForwardTransition(previousStatus, newStatus)) return null;

  const updates: Record<string, unknown> = {
    ecf_status: newStatus,
    last_error: null,
  };

  // URLs (Alanube usa documentStampUrl para la URL pública DGII verificable).
  if (typeof data.documentStampUrl === "string") {
    updates.public_url = data.documentStampUrl;
  } else if (typeof data.publicUrl === "string") {
    updates.public_url = data.publicUrl;
  }
  if (typeof data.xmlUrl === "string") updates.xml_url = data.xmlUrl;
  if (typeof data.pdfUrl === "string") updates.pdf_url = data.pdfUrl;

  // Track ID DGII (puede venir null en sandbox).
  if (typeof data.trackId === "string") updates.ecf_tracking_number = data.trackId;
  if (typeof data.dgiiTrackId === "string") updates.ecf_tracking_number = data.dgiiTrackId;

  // Codigo de Seguridad y Fecha de Firma Digital (datos visibles en el QR/ticket).
  if (typeof data.securityCode === "string") updates.ecf_security_code = data.securityCode;

  // signatureDate viene como "DD-MM-YYYY HH:MM:SS" — parseamos a ISO para
  // que TIMESTAMPTZ de Postgres lo acepte. Si falla, dejamos como null.
  const signedRaw = (data.signatureDate ?? data.signedAt) as string | undefined;
  if (typeof signedRaw === "string" && signedRaw.length > 0) {
    const iso = parseAlanubeDateToIso(signedRaw);
    if (iso !== null) updates.ecf_signed_at = iso;
  }

  if (newStatus === "accepted") {
    updates.accepted_at =
      (updates.ecf_signed_at as string | undefined) ??
        new Date().toISOString();

    // "Aceptado con observaciones": el comprobante ES valido, pero la DGII
    // senala algo mal armado. Si no se guarda, la observacion solo se ve
    // entrando al portal de Alanube — y un negocio puede pasar meses
    // emitiendo con el mismo defecto sin enterarse. Se deja en last_error
    // para que quede a la vista, marcado como observacion y no como fallo.
    if (rawLegalStatus.toUpperCase().includes("OBSERVA")) {
      const detalle = extractRejectionReason(data);
      updates.last_error = detalle !== null
        ? `[Aceptado con observaciones] ${detalle}`
        : `[Aceptado con observaciones] ${rawLegalStatus}`;
    }
  }
  if (newStatus === "rejected") {
    updates.last_error = extractRejectionReason(data) ?? `DGII rejected: ${rawLegalStatus}`;
  }

  return { newStatus, rawLegalStatus, updates };
}

/// Extrae la razon de rechazo del governmentResponse de DGII.
/// Shape: { code: 2, value: [ { codigo: "04", valor: "El RNC..." } ] }
export function extractRejectionReason(data: Record<string, unknown>): string | null {
  const gr = data.governmentResponse as Record<string, unknown> | undefined;
  if (gr === undefined || gr === null) return null;
  const value = gr.value;
  if (Array.isArray(value) && value.length > 0) {
    const first = value[0] as Record<string, unknown>;
    const valor = first.valor as string | undefined;
    const codigo = first.codigo as string | undefined;
    if (valor !== undefined) {
      return codigo !== undefined ? `[${codigo}] ${valor}` : valor;
    }
  }
  return null;
}

/// Convierte "DD-MM-YYYY HH:MM:SS" (formato Alanube) a ISO 8601.
/// Devuelve null si el formato no calza.
export function parseAlanubeDateToIso(raw: string): string | null {
  // "06-05-2026 14:20:38"
  const match = raw.match(
    /^(\d{2})-(\d{2})-(\d{4})\s+(\d{2}):(\d{2}):(\d{2})$/,
  );
  if (match === null) {
    // Si ya es ISO, devolverlo.
    if (raw.includes("T") && raw.includes("-")) return raw;
    return null;
  }
  const [, dd, mm, yyyy, hh, mi, ss] = match;
  // Asumimos hora local Dominicana (AST = UTC-4). En lugar de hacer math
  // manual, dejamos el offset explicito en el ISO.
  return `${yyyy}-${mm}-${dd}T${hh}:${mi}:${ss}-04:00`;
}

export function mapAlanubeStatus(raw: string): EcfStatus {
  if (!raw) return "sent";
  const s = raw.toLowerCase();
  // Alanube DOM legalStatus: ACCEPTED, REJECTED, IN_PROCESS
  if (s === "accepted" || s.includes("accept") || s.includes("aprob")) {
    return "accepted";
  }
  if (s === "rejected" || s.includes("reject") || s.includes("rechaz")) {
    return "rejected";
  }
  if (s === "in_process" || s === "in_progress" ||
      s.includes("pending") || s.includes("pendient") ||
      s.includes("process")) {
    return "sent";
  }
  // 'finished' no es status final; depende de legalStatus que ya manejamos arriba.
  if (s === "finished") return "sent";
  return "sent";
}

export function isForwardTransition(prev: string, next: string): boolean {
  const order: Record<string, number> = {
    pending: 0,
    sent: 1,
    accepted: 2,
    rejected: 2,
  };
  const prevRank = order[prev] ?? -1;
  const nextRank = order[next] ?? -1;
  return nextRank >= prevRank;
}
