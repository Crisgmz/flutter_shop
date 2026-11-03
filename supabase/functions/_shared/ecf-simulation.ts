// Paso 4 de la certificacion: "Pruebas de simulacion e-CF". La DGII ya no da
// los datos: el contribuyente manda e-CF de su operacion, con la misma
// composicion que el set de pruebas de datos (4 E31, 2 E32 >= 250 mil, 1 E33,
// 2 E34, 2 de cada uno de 41/43/44/45/46/47 y 4 E32 menores de 250 mil, que van
// como resumen).
//
// Se arman con los casos del set de datos que la DGII ya acepto (montos,
// impuestos e items que cuadran) y se cambia lo que tiene que ser del
// contribuyente y de hoy:
//   - e-NCF nuevos: la DGII da del 1 al 10,000,000 por tipo y no deja repetir
//     ni entre intentos, asi que se sigue despues del mayor ya usado.
//   - el emisor: razon social, nombre comercial, direccion, municipio y
//     provincia (codigos DGII), telefono y correo del alta e-CF. Los datos de
//     relleno del set (codigo de vendedor, web, zona de venta...) se quitan:
//     son opcionales.
//   - FechaEmision = hoy; las demas fechas se corren lo mismo para que no
//     cambie el orden entre ellas. FechaVencimientoSecuencia queda igual.
//   - las notas de credito/debito apuntan al e-NCF nuevo de lo que modifican.
// Los compradores (RNC de prueba de la DGII) se quedan: el ambiente de
// certificacion los conoce.

import { locationCodes } from "./dgii-catalogs.ts";
import {
  buildEcfXml,
  CONSUMPTION_SUMMARY_LIMIT,
  isAdjustmentNote,
  summaryFieldsFrom,
  TestSetCase,
  TestSetField,
} from "./ecf-test-set.ts";

export interface SimulationIssuer {
  rnc: string;
  legalName: string;
  tradeName: string | null;
  address: string;
  province: string | null;
  municipality: string | null;
  phone: string | null;
  email: string | null;
}

export interface SimulationTemplate {
  position: number;
  ecf_type: string;
  encf: string;
  fields: TestSetField[];
}

/**
 * Lo que cuenta el portal de la DGII en la simulacion: cada tipo, con el E32
 * partido en "32 >= 250Mil" (`32`) y "32 RFCE" (`32rfce`, menores de 250 mil).
 */
export const SIMULATION_CATEGORIES = ["31", "32", "32rfce", "33", "34", "41", "43", "44", "45", "46", "47"] as const;
export type SimulationCategory = typeof SIMULATION_CATEGORIES[number];

function fieldOf(fields: TestSetField[], column: string): string | null {
  const c = column.toLowerCase();
  return fields.find(([k]) => k.trim().toLowerCase() === c)?.[1]?.trim() ?? null;
}

export function simulationCategory(t: { ecf_type: string; fields: TestSetField[] }): SimulationCategory | null {
  if (t.ecf_type === "32") {
    const total = Number(fieldOf(t.fields, "MontoTotal"));
    return Number.isFinite(total) && total < CONSUMPTION_SUMMARY_LIMIT ? "32rfce" : "32";
  }
  return (SIMULATION_CATEGORIES as readonly string[]).includes(t.ecf_type) ? t.ecf_type as SimulationCategory : null;
}

/**
 * Modelos para las cantidades que pide el portal (cambian entre intentos: la
 * primera vez fueron 4 E31 y 2 de casi todo, al reiniciar 1 de cada uno).
 * Facturas: las primeras del set. Notas: primero las que modifican una factura
 * que tambien va; si la suya no quedo, pasa a modificar otra elegida del mismo
 * tipo, para que la DGII la encuentre.
 */
export function selectSimulationTemplates(
  templates: SimulationTemplate[],
  counts: Record<string, unknown>,
): Validation<SimulationTemplate[]> {
  const errors: string[] = [];
  const wanted: Partial<Record<SimulationCategory, number>> = {};
  for (const [key, raw] of Object.entries(counts)) {
    if (!(SIMULATION_CATEGORIES as readonly string[]).includes(key)) {
      errors.push(`Tipo desconocido en las cantidades: ${key}.`);
      continue;
    }
    if (!Number.isInteger(raw) || (raw as number) < 0) {
      errors.push(`La cantidad del tipo ${key} tiene que ser un entero desde 0.`);
      continue;
    }
    if ((raw as number) > 0) wanted[key as SimulationCategory] = raw as number;
  }
  if (errors.length === 0 && Object.keys(wanted).length === 0) errors.push("Indica cuantos e-CF de cada tipo pide el portal.");
  if (errors.length > 0) return { ok: false, errors };

  const ordered = [...templates].sort((a, b) => a.position - b.position);
  const byCategory = new Map<SimulationCategory, SimulationTemplate[]>();
  for (const t of ordered) {
    const c = simulationCategory(t);
    if (c) byCategory.set(c, [...(byCategory.get(c) ?? []), t]);
  }
  for (const [c, n] of Object.entries(wanted) as Array<[SimulationCategory, number]>) {
    const available = byCategory.get(c)?.length ?? 0;
    if (n > available) errors.push(`El set de datos de la DGII solo trae ${available} de "${c}" para usar de modelo (piden ${n}).`);
  }
  if (errors.length > 0) return { ok: false, errors };

  const isNoteCategory = (c: SimulationCategory) => isAdjustmentNote(c);
  const selected: SimulationTemplate[] = [];
  for (const [c, n] of Object.entries(wanted) as Array<[SimulationCategory, number]>) {
    if (!isNoteCategory(c)) selected.push(...byCategory.get(c)!.slice(0, n));
  }
  const chosen = new Set(selected.map((t) => t.encf));
  const referenceOf = (t: SimulationTemplate) => fieldOf(t.fields, "NCFModificado")?.toUpperCase() ?? null;

  for (const [c, n] of Object.entries(wanted) as Array<[SimulationCategory, number]>) {
    if (!isNoteCategory(c)) continue;
    const candidates = [...byCategory.get(c)!].sort((a, b) =>
      Number(!chosen.has(referenceOf(a) ?? "")) - Number(!chosen.has(referenceOf(b) ?? "")) || a.position - b.position
    );
    for (const note of candidates.slice(0, n)) {
      const reference = referenceOf(note);
      const original = reference ? ordered.find((t) => t.encf === reference) : undefined;
      if (!reference || chosen.has(reference) || !original) {
        selected.push(note);
        continue;
      }
      // Lo que modificaba no va: otra elegida de la misma categoria.
      const category = simulationCategory(original);
      const substitute = selected.find((t) => !isAdjustmentNote(t.ecf_type) && simulationCategory(t) === category);
      if (!substitute) {
        errors.push(`La nota ${note.encf} modifica un "${category}" y no se esta generando ninguno.`);
        continue;
      }
      selected.push({
        ...note,
        fields: note.fields.map(([k, v]): TestSetField => [k, k.trim().toLowerCase() === "ncfmodificado" ? substitute.encf : v]),
      });
    }
  }
  if (errors.length > 0) return { ok: false, errors };
  return { ok: true, value: selected.sort((a, b) => a.position - b.position) };
}

/** Columnas de relleno del set de la DGII que no van en una operacion real. */
const DROPPED_COLUMNS = new Set([
  "casoprueba",
  "sucursal",
  "website",
  "actividadeconomica",
  "codigovendedor",
  "numerofacturainterna",
  "numeropedidointerno",
  "zonaventa",
  "rutaventa",
  "informacionadicionalemisor",
  "telefonoemisor[2]",
  "telefonoemisor[3]",
]);

/** Fechas dd-MM-yyyy que se corren junto con FechaEmision. */
const SHIFTED_DATE_COLUMNS = /^(fechaemision|fechalimitepago|fechadesde|fechahasta|fechaentrega|fechaordencompra|fechaembarque|fechaelaboracion\[\d+\]|fechavencimientoitem\[\d+\])$/;

const DATE_RE = /^(\d{2})-(\d{2})-(\d{4})$/;

function parseDate(v: string): number | null {
  const m = DATE_RE.exec(v.trim());
  if (!m) return null;
  const t = Date.UTC(Number(m[3]), Number(m[2]) - 1, Number(m[1]));
  return Number.isFinite(t) ? t : null;
}

function formatDate(t: number): string {
  const d = new Date(t);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${p(d.getUTCDate())}-${p(d.getUTCMonth() + 1)}-${d.getUTCFullYear()}`;
}

/** Telefono como lo pide el XSD (999-999-9999), o null si no se puede. */
export function dgiiPhone(raw: string | null | undefined): string | null {
  let digits = (raw ?? "").replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("1")) digits = digits.slice(1);
  if (digits.length !== 10) return null;
  return `${digits.slice(0, 3)}-${digits.slice(3, 6)}-${digits.slice(6)}`;
}

export function encfFor(type: string, n: number): string {
  return `E${type}${String(n).padStart(10, "0")}`;
}

/** Numero de un e-NCF (E310000000012 → 12). */
export function encfNumber(encf: string): number {
  return Number(encf.slice(3));
}

const MAX_SEQUENCE = 10_000_000;

type Validation<T> = { ok: true; value: T } | { ok: false; errors: string[] };

export interface SimulationResult {
  cases: TestSetCase[];
  /** Ultimo numero usado por tipo, para no repetirlo en otro intento. */
  lastNumbers: Record<string, number>;
}

/**
 * Arma el set de simulacion. [nextNumbers] es el primer numero libre por tipo;
 * [today] va en dd-MM-yyyy.
 */
export function buildSimulationCases(
  templates: SimulationTemplate[],
  issuer: SimulationIssuer,
  today: string,
  nextNumbers: Record<string, number>,
): Validation<SimulationResult> {
  const errors: string[] = [];
  const todayT = parseDate(today);
  if (todayT === null) return { ok: false, errors: [`Fecha de hoy invalida: ${today}`] };
  if (!issuer.legalName.trim() || !issuer.address.trim()) {
    return { ok: false, errors: ["Faltan la razon social o la direccion fiscal del contribuyente."] };
  }
  if (templates.length === 0) {
    return { ok: false, errors: ["No hay casos del set de datos de la DGII para usar de modelo."] };
  }

  // e-NCF nuevos, en el orden del set.
  const ordered = [...templates].sort((a, b) => a.position - b.position);
  const counters: Record<string, number> = { ...nextNumbers };
  const lastNumbers: Record<string, number> = {};
  const newEncf = new Map<string, string>();
  for (const t of ordered) {
    const n = Math.max(1, counters[t.ecf_type] ?? 1);
    if (n > MAX_SEQUENCE) {
      errors.push(`Se agoto la secuencia de prueba del tipo ${t.ecf_type} (maximo ${MAX_SEQUENCE}).`);
      continue;
    }
    newEncf.set(t.encf, encfFor(t.ecf_type, n));
    lastNumbers[t.ecf_type] = n;
    counters[t.ecf_type] = n + 1;
  }
  if (errors.length > 0) return { ok: false, errors };

  const codes = locationCodes(issuer.province, issuer.municipality);
  const phone = dgiiPhone(issuer.phone);
  const email = issuer.email?.trim() && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(issuer.email.trim())
    ? issuer.email.trim().slice(0, 80)
    : null;
  const issuerValues: Record<string, string | null> = {
    razonsocialemisor: issuer.legalName.trim().slice(0, 150),
    nombrecomercial: (issuer.tradeName?.trim() || issuer.legalName.trim()).slice(0, 150),
    direccionemisor: issuer.address.trim().slice(0, 100),
    municipio: codes.municipality,
    provincia: codes.province,
    "telefonoemisor[1]": phone,
    correoemisor: email,
  };

  const cases: TestSetCase[] = [];
  for (const t of ordered) {
    const encf = newEncf.get(t.encf)!;
    const emission = parseDate(t.fields.find(([c]) => c.toLowerCase() === "fechaemision")?.[1] ?? "");
    const shift = emission === null ? 0 : todayT - emission;
    const reference = t.fields.find(([c]) => c.toLowerCase() === "ncfmodificado")?.[1]?.trim().toUpperCase() ?? null;
    const newReference = reference ? newEncf.get(reference) ?? reference : null;

    const fields: TestSetField[] = [];
    const seen = new Set<string>();
    for (const [column, value] of t.fields) {
      const key = column.trim().toLowerCase();
      seen.add(key);
      if (DROPPED_COLUMNS.has(key)) continue;
      if (key === "encf") {
        fields.push([column, encf]);
      } else if (key === "rncemisor") {
        fields.push([column, issuer.rnc]);
      } else if (key in issuerValues) {
        const v = issuerValues[key];
        if (v) fields.push([column, v]);
      } else if (key === "ncfmodificado") {
        fields.push([column, newReference ?? value]);
      } else if (key === "fechancfmodificado") {
        // Lo modificado se emite hoy tambien (si es del set).
        fields.push([column, reference && newEncf.has(reference) ? today : value]);
      } else if (key === "indicadornotacredito") {
        // 0 = dentro de los 30 dias del comprobante modificado (hoy mismo).
        fields.push([column, reference && newEncf.has(reference) ? "0" : value]);
      } else if (SHIFTED_DATE_COLUMNS.test(key)) {
        const d = parseDate(value);
        fields.push([column, d === null ? value : formatDate(d + shift)]);
      } else {
        fields.push([column, value]);
      }
    }
    // Datos del emisor que el modelo no traia (el XSD los pone despues de los
    // que si trae; buildEcfXml ordena por el XSD).
    for (const [key, column] of [
      ["nombrecomercial", "NombreComercial"],
      ["municipio", "Municipio"],
      ["provincia", "Provincia"],
      ["telefonoemisor[1]", "TelefonoEmisor[1]"],
      ["correoemisor", "CorreoEmisor"],
    ] as const) {
      const v = issuerValues[key];
      if (!seen.has(key) && v) fields.push([column, v]);
    }

    try {
      buildEcfXml(fields, "01-01-2000 00:00:00");
    } catch (e) {
      errors.push(`${encf} (modelo ${t.encf}): ${e instanceof Error ? e.message : String(e)}`);
      continue;
    }

    const totalRaw = fields.find(([c]) => c.toLowerCase() === "montototal")?.[1];
    const total = totalRaw !== undefined && Number.isFinite(Number(totalRaw)) ? Number(totalRaw) : null;
    const via = t.ecf_type === "32" && total !== null && total < CONSUMPTION_SUMMARY_LIMIT ? "rfce" : "ecf";
    cases.push({
      position: cases.length + 1,
      case_id: `${issuer.rnc}${encf}`,
      ecf_type: t.ecf_type,
      encf,
      signer_rnc: issuer.rnc,
      total,
      via,
      modifies: isAdjustmentNote(t.ecf_type) ? newReference : null,
      fields,
      summary_fields: via === "rfce" ? summaryFieldsFrom(fields) : null,
    });
  }

  if (errors.length > 0) return { ok: false, errors: errors.slice(0, 15) };
  return { ok: true, value: { cases, lastNumbers } };
}
