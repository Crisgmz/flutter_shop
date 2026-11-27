import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  alanubeDocumentBody,
  documentStatusUpdate,
  mapAlanubeStatus,
} from "./ecf-alanube-status.ts";

// Forma real del documento en Alanube (aviso y consulta), verificada 2026-05-06.
const aceptado = {
  id: "01M6H0ABE9ZE4Z1HYSV6CWCS8X",
  legalStatus: "ACCEPTED",
  status: "FINISHED",
  securityCode: "Ab12Cd",
  signatureDate: "03-11-2026 11:26:55",
  documentStampUrl: "https://ecf.dgii.gov.do/ecf/ConsultaTimbre?x=1",
  documentNumber: "E320000000003",
};

Deno.test("aceptado: estado, codigo, firma, URL de consulta y accepted_at", () => {
  const c = documentStatusUpdate(aceptado, "sent")!;
  assertEquals(c.newStatus, "accepted");
  assertEquals(c.rawLegalStatus, "ACCEPTED");
  assertEquals(c.updates.ecf_status, "accepted");
  assertEquals(c.updates.last_error, null);
  assertEquals(c.updates.ecf_security_code, "Ab12Cd");
  assertEquals(c.updates.ecf_signed_at, "2026-11-03T11:26:55-04:00");
  assertEquals(c.updates.accepted_at, "2026-11-03T11:26:55-04:00");
  assertEquals(c.updates.public_url, "https://ecf.dgii.gov.do/ecf/ConsultaTimbre?x=1");
});

Deno.test("rechazado: el motivo de la DGII queda en last_error", () => {
  const c = documentStatusUpdate({
    legalStatus: "REJECTED",
    governmentResponse: { code: 2, value: [{ codigo: "1960", valor: "El campo MontoExento no es valido" }] },
  }, "sent")!;
  assertEquals(c.newStatus, "rejected");
  assertEquals(c.updates.last_error, "[1960] El campo MontoExento no es valido");
});

Deno.test("aceptado con observaciones: queda marcado en last_error", () => {
  const c = documentStatusUpdate({
    legalStatus: "ACCEPTED_WITH_OBSERVATIONS",
    governmentResponse: { value: [{ codigo: "11153", valor: "ValorPagar no coincide" }] },
  }, "sent")!;
  assertEquals(c.newStatus, "accepted");
  assertEquals(c.updates.last_error, "[Aceptado con observaciones] [11153] ValorPagar no coincide");
});

Deno.test("en proceso sigue en sent", () => {
  assertEquals(documentStatusUpdate({ legalStatus: "IN_PROCESS" }, "sent")!.newStatus, "sent");
  assertEquals(mapAlanubeStatus(""), "sent");
  assertEquals(mapAlanubeStatus("FINISHED"), "sent");
});

Deno.test("no retrocede: un 'sent' tardio no pisa un aceptado", () => {
  assertEquals(documentStatusUpdate({ legalStatus: "IN_PROCESS" }, "accepted"), null);
});

Deno.test("sin legalStatus usa status", () => {
  assertEquals(documentStatusUpdate({ status: "REJECTED" }, "sent")!.newStatus, "rejected");
});

Deno.test("la respuesta envuelta en `document` se desenvuelve; la plana queda igual", () => {
  assertEquals(alanubeDocumentBody({ document: aceptado }), aceptado);
  assertEquals(alanubeDocumentBody(aceptado), aceptado);
  assertEquals(alanubeDocumentBody(null), {});
});
