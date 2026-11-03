import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  buildSimulationCases,
  dgiiPhone,
  encfFor,
  encfNumber,
  selectSimulationTemplates,
  simulationCategory,
  SimulationIssuer,
  SimulationTemplate,
} from "./ecf-simulation.ts";
import { locationCodes, locationName, unitName } from "./dgii-catalogs.ts";
import { TestSetField } from "./ecf-test-set.ts";

// Casos con la forma del set de datos de la DGII (columnas recortadas).
function tpl(position: number, encf: string, extra: Record<string, string>): SimulationTemplate {
  const base: Record<string, string> = {
    CasoPrueba: `101000001${encf}`,
    Version: "1.0",
    TipoeCF: encf.slice(1, 3),
    ENCF: encf,
    RNCEmisor: "101000001",
    RazonSocialEmisor: "DOCUMENTOS ELECTRONICOS DE 02",
    NombreComercial: "DOCUMENTOS ELECTRONICOS DE 02",
    DireccionEmisor: "AVE. ISABEL AGUIAR NO. 269",
    Municipio: "010100",
    Provincia: "010000",
    "TelefonoEmisor[1]": "809-472-7676",
    "TelefonoEmisor[2]": "809-491-1918",
    WebSite: "www.facturaelectronica.com",
    CodigoVendedor: "AA0000000100000000010000000002",
    FechaEmision: "01-04-2020",
    RNCComprador: "131880681",
    RazonSocialComprador: "DOCUMENTOS ELECTRONICOS DE 03",
    MontoTotal: "1180.00",
    "NumeroLinea[1]": "1",
    "IndicadorFacturacion[1]": "1",
    "NombreItem[1]": "LAPICES",
    "IndicadorBienoServicio[1]": "1",
    "MontoItem[1]": "1000.00",
    ...extra,
  };
  return { position, ecf_type: encf.slice(1, 3), encf, fields: Object.entries(base) as TestSetField[] };
}

const TEMPLATES = [
  tpl(1, "E340000000001", {
    IndicadorNotaCredito: "1",
    NCFModificado: "E310000000001",
    FechaNCFModificado: "01-01-2020",
    CodigoModificacion: "3",
    FechaEmision: "02-04-2020",
  }),
  tpl(2, "E310000000001", { FechaVencimientoSecuencia: "31-12-2028", FechaEntrega: "10-04-2020", FechaOrdenCompra: "25-03-2020" }),
  tpl(3, "E310000000012", { FechaVencimientoSecuencia: "31-12-2028" }),
  tpl(4, "E320000000011", { MontoTotal: "40120.00" }),
];

const ISSUER: SimulationIssuer = {
  rnc: "101000001",
  legalName: "TROPELLA COFFEE SRL",
  tradeName: "Tropella Coffee",
  address: "GREGORIO LUPERON, No. B 4, GURABO",
  province: "Santiago",
  municipality: "Santiago",
  phone: "(809) 555-1234",
  email: "facturas@tropella.do",
};

function field(fields: TestSetField[], column: string): string | undefined {
  return fields.find(([c]) => c === column)?.[1];
}

Deno.test("simulacion: e-NCF nuevos despues de lo usado, en el orden del set", () => {
  const r = buildSimulationCases(TEMPLATES, ISSUER, "09-10-2026", { "31": 13, "32": 16, "34": 2 });
  assert(r.ok, JSON.stringify(!r.ok && r.errors));
  assertEquals(r.value.cases.map((c) => c.encf), ["E340000000002", "E310000000013", "E310000000014", "E320000000016"]);
  assertEquals(r.value.lastNumbers, { "34": 2, "31": 14, "32": 16 });
  assertEquals(r.value.cases.map((c) => c.via), ["ecf", "ecf", "ecf", "rfce"]);
  assert(r.value.cases[3].summary_fields !== null);
});

Deno.test("simulacion: emisor real y sin los datos de relleno de la DGII", () => {
  const r = buildSimulationCases(TEMPLATES, ISSUER, "09-10-2026", {});
  assert(r.ok);
  const f = r.value.cases[1].fields;
  assertEquals(field(f, "RazonSocialEmisor"), "TROPELLA COFFEE SRL");
  assertEquals(field(f, "NombreComercial"), "Tropella Coffee");
  assertEquals(field(f, "DireccionEmisor"), "GREGORIO LUPERON, No. B 4, GURABO");
  assertEquals(field(f, "Municipio"), "250100");
  assertEquals(field(f, "Provincia"), "250000");
  assertEquals(field(f, "TelefonoEmisor[1]"), "809-555-1234");
  assertEquals(field(f, "CorreoEmisor"), "facturas@tropella.do");
  for (const gone of ["CasoPrueba", "TelefonoEmisor[2]", "WebSite", "CodigoVendedor"]) assertEquals(field(f, gone), undefined);
  // El comprador de prueba se queda.
  assertEquals(field(f, "RNCComprador"), "131880681");
});

Deno.test("simulacion: hoy como fecha de emision, las demas corridas igual", () => {
  const r = buildSimulationCases(TEMPLATES, ISSUER, "09-10-2026", {});
  assert(r.ok);
  const f = r.value.cases[1].fields;
  assertEquals(field(f, "FechaEmision"), "09-10-2026");
  assertEquals(field(f, "FechaEntrega"), "18-10-2026"); // +9 dias
  assertEquals(field(f, "FechaOrdenCompra"), "02-10-2026"); // -7 dias
  assertEquals(field(f, "FechaVencimientoSecuencia"), "31-12-2028");
});

Deno.test("simulacion: la nota apunta a la factura nueva, emitida hoy", () => {
  const r = buildSimulationCases(TEMPLATES, ISSUER, "09-10-2026", { "31": 13 });
  assert(r.ok);
  const note = r.value.cases[0];
  assertEquals(note.modifies, "E310000000013");
  assertEquals(field(note.fields, "NCFModificado"), "E310000000013");
  assertEquals(field(note.fields, "FechaNCFModificado"), "09-10-2026");
  assertEquals(field(note.fields, "IndicadorNotaCredito"), "0");
});

Deno.test("simulacion: sin provincia reconocible ni telefono valido, no se inventan", () => {
  const r = buildSimulationCases(TEMPLATES, { ...ISSUER, province: "Narnia", municipality: null, phone: "555", email: "no" }, "09-10-2026", {});
  assert(r.ok);
  const f = r.value.cases[1].fields;
  for (const gone of ["Municipio", "Provincia", "TelefonoEmisor[1]", "CorreoEmisor"]) assertEquals(field(f, gone), undefined);
});

Deno.test("simulacion: sin datos del emisor o sin modelo no arma nada", () => {
  assert(!buildSimulationCases(TEMPLATES, { ...ISSUER, address: " " }, "09-10-2026", {}).ok);
  assert(!buildSimulationCases([], ISSUER, "09-10-2026", {}).ok);
});

Deno.test("e-NCF y telefono", () => {
  assertEquals(encfFor("31", 13), "E310000000013");
  assertEquals(encfNumber("E320000000016"), 16);
  assertEquals(dgiiPhone("1-809-555-1234"), "809-555-1234");
  assertEquals(dgiiPhone("555-1234"), null);
});

Deno.test("catalogos: provincia y municipio por nombre, y de vuelta en palabras", () => {
  assertEquals(locationCodes("Distrito Nacional", "Santo Domingo de Guzmán"), { province: "010000", municipality: "010100" });
  assertEquals(locationCodes(null, "Jarabacoa"), { province: "130000", municipality: "130300" });
  assertEquals(locationCodes("Narnia", "Nada"), { province: null, municipality: null });
  assertEquals(locationName("250000"), "SANTIAGO");
  assertEquals(locationName("010100"), "SANTO DOMINGO DE GUZMÁN");
  assertEquals(unitName("43"), "Unidad");
  assertEquals(unitName("999"), null);
});

// ── Cantidades que pide el portal ───────────────────────────────────────────

const SET = [
  tpl(1, "E340000000018", { NCFModificado: "E460000000009", CodigoModificacion: "2" }),
  tpl(2, "E340000000001", { NCFModificado: "E310000000001", CodigoModificacion: "2" }),
  tpl(3, "E460000000009", {}),
  tpl(4, "E310000000001", {}),
  tpl(5, "E310000000005", {}),
  tpl(6, "E320000000011", { MontoTotal: "40120.00" }),
  tpl(7, "E320000000006", { MontoTotal: "413785.30" }),
  tpl(8, "E460000000011", {}),
];

Deno.test("cantidades: el E32 se cuenta como lo cuenta el portal", () => {
  assertEquals(SET.map(simulationCategory), ["34", "34", "46", "31", "31", "32rfce", "32", "46"]);
});

Deno.test("cantidades: 1 de cada uno, la nota con su factura", () => {
  const r = selectSimulationTemplates(SET, { "31": 1, "32": 1, "32rfce": 1, "34": 1, "46": 1 });
  assert(r.ok, JSON.stringify(!r.ok && r.errors));
  assertEquals(r.value.map((t) => t.encf), ["E340000000018", "E460000000009", "E310000000001", "E320000000011", "E320000000006"]);
});

Deno.test("cantidades: si la factura de la nota no va, la nota pasa a otra del mismo tipo", () => {
  // Sin E46: la nota que modificaba un E46 no tiene pareja; con 2 notas, la
  // segunda modifica el E31 elegido.
  const r = selectSimulationTemplates(SET, { "31": 1, "34": 1, "46": 0 });
  assert(r.ok, JSON.stringify(!r.ok && r.errors));
  assertEquals(r.value.map((t) => t.encf), ["E340000000001", "E310000000001"]);

  const moved = selectSimulationTemplates(
    [tpl(1, "E340000000001", { NCFModificado: "E310000000005" }), tpl(2, "E310000000001", {}), tpl(3, "E310000000005", {})],
    { "31": 1, "34": 1 },
  );
  assert(moved.ok);
  assertEquals(moved.value[0].fields.find(([c]) => c === "NCFModificado")?.[1], "E310000000001");
});

Deno.test("cantidades: errores claros", () => {
  assert(!selectSimulationTemplates(SET, {}).ok);
  assert(!selectSimulationTemplates(SET, { "31": 3 }).ok); // el set trae 2
  assert(!selectSimulationTemplates(SET, { "99": 1 }).ok);
  assert(!selectSimulationTemplates(SET, { "31": 1.5 }).ok);
  // Una nota cuya factura no tiene a nadie de su tipo.
  assert(!selectSimulationTemplates(SET, { "34": 1 }).ok);
});


// ── Modelo generico de la DGII ──────────────────────────────────────────────

Deno.test("modelo generico: el set de la DGII sin datos de ningun contribuyente", async () => {
  const { DGII_SIMULATION_TEMPLATES } = await import("./ecf-simulation-templates.ts");
  assertEquals(DGII_SIMULATION_TEMPLATES.length, 25);
  for (const t of DGII_SIMULATION_TEMPLATES) {
    assertEquals(field(t.fields, "CasoPrueba"), undefined);
    assertEquals(field(t.fields, "RNCEmisor"), "000000000");
  }
  const byCategory = new Map<string, number>();
  for (const t of DGII_SIMULATION_TEMPLATES) {
    const c = simulationCategory(t)!;
    byCategory.set(c, (byCategory.get(c) ?? 0) + 1);
  }
  // Lo que pidio el portal la primera vez (4 E31, 2 de casi todo, 4 resumenes).
  assertEquals(Object.fromEntries(byCategory), {
    "31": 4, "32": 2, "32rfce": 4, "33": 1, "34": 2, "41": 2, "43": 2, "44": 2, "45": 2, "46": 2, "47": 2,
  });
});

Deno.test("modelo generico: 1 de cada uno para un contribuyente nuevo", async () => {
  const { DGII_SIMULATION_TEMPLATES } = await import("./ecf-simulation-templates.ts");
  const templates = DGII_SIMULATION_TEMPLATES.map((t) => ({ ...t, fields: [...t.fields] }));
  const counts = Object.fromEntries(["31", "32", "32rfce", "33", "34", "41", "43", "44", "45", "46", "47"].map((k) => [k, 1]));
  const picked = selectSimulationTemplates(templates, counts);
  assert(picked.ok, JSON.stringify(!picked.ok && picked.errors));
  const r = buildSimulationCases(picked.value, { ...ISSUER, rnc: "131831151" }, "22-10-2026", {});
  assert(r.ok, JSON.stringify(!r.ok && r.errors));
  assertEquals(r.value.cases.length, 11);
  for (const c of r.value.cases) {
    assertEquals(field(c.fields, "RNCEmisor"), "131831151");
    assert(c.fields.every(([, v]) => v !== "000000000"), c.encf); // el RNC en blanco del modelo no queda
  }
  // Las notas, con una factura de esta tanda.
  const encfs = new Set(r.value.cases.map((c) => c.encf));
  for (const c of r.value.cases.filter((c) => c.modifies)) assert(encfs.has(c.modifies!), c.encf);
});
