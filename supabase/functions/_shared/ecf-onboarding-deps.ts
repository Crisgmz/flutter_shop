// Las dos funciones puras que `ecf-onboarding.ts` necesita de mangospos.
//
// En mangospos viven en `ecf-preflight.ts` y `ecf-payload.ts`, dos modulos
// grandes atados a SUS tablas. Copiarlos enteros aqui traeria codigo muerto,
// asi que se copian solo estas dos piezas y `ecf-onboarding.ts` queda byte a
// byte igual al de alla salvo su linea de imports.
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
export const TYPES_WITH_SEQUENCE_DUE_DATE = ["E31", "E44", "E45"];

/** Tipos que este POS puede emitir electronicamente. */
export const EMITTABLE_ECF_TYPES = ["E31", "E32", "E44", "E45"];

/** `sandbox` salvo que el base URL de Alanube apunte a produccion. */
export function environmentFromBaseUrl(baseUrl: string): "sandbox" | "production" {
  return /sandbox/i.test(baseUrl) ? "sandbox" : "production";
}
