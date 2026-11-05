// Lo que `ecf-onboarding.ts` importa de mangospos fuera de si mismo.
//
// En mangospos vive en `ecf-preflight.ts` (atado a SUS tablas: aqui se copian
// solo `normalizeRnc` y `normalizeText`) y en `ecf-payload.ts`, que SI esta
// copiado verbatim (lo usa emit-document) y del que se reexporta la lista de
// tipos con vencimiento. Asi `ecf-onboarding.ts` queda byte a byte igual al de
// alla salvo su linea de imports.
//
// Si cambian alla, cambian aqui.

/** Solo los digitos: el RNC se compara sin guiones ni espacios. */
export function normalizeRnc(v: string | null | undefined): string {
  return (v ?? "").replace(/\D/g, "");
}

/** Mayusculas, sin acentos ni puntuacion, espacios colapsados. */
export function normalizeText(v: string | null | undefined): string {
  return (v ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toUpperCase()
    .replace(/[^A-Z0-9 ]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Tipos de e-CF cuya secuencia lleva fecha de vencimiento ante la DGII. */
export { TYPES_WITH_SEQUENCE_DUE_DATE } from "./ecf-payload.ts";

/** Tipos que este POS puede emitir electronicamente. */
export const EMITTABLE_ECF_TYPES = ["E31", "E32", "E44", "E45"];

/** `sandbox` salvo que el base URL de Alanube apunte a produccion. */
export function environmentFromBaseUrl(baseUrl: string): "sandbox" | "production" {
  return /sandbox/i.test(baseUrl) ? "sandbox" : "production";
}
