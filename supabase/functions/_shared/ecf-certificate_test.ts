import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  CertificateAccessError,
  certificateFilename,
  openCertificate,
  resolveCertificate,
  sealCertificate,
} from "./ecf-certificate.ts";
import { validateCertificate, ValidCertificate } from "./ecf-onboarding.ts";
import { importSecretKey, sealSecret } from "./secret-box.ts";

const BIZ = "38a0dfd6-f342-4e8c-b9d6-daf9e07d60da";
const KEY_B64 = btoa(
  String.fromCharCode(...Array.from({ length: 32 }, (_, i) => i)),
);
const INPUT = {
  filename: "cliente.p12",
  content_base64: btoa(String.fromCharCode(0x30, 0x03, 0x02, 0x01, 0x01)),
  password: "  Clave de prueba Ñ  ",
};

function certificate(): ValidCertificate {
  const result = validateCertificate(INPUT);
  assert(result.ok);
  return result.value;
}

Deno.test("certificado guardado: roundtrip exacto y sin contenido en claro", async () => {
  const key = await importSecretKey(KEY_B64);
  const expected = certificate();
  const sealed = await sealCertificate(key, expected, BIZ);
  assert(sealed.startsWith("v1:"));
  assert(!sealed.includes(INPUT.password));
  assert(!sealed.includes(INPUT.content_base64));
  assertEquals(await openCertificate(key, sealed, BIZ), expected);
  assertEquals(certificateFilename(expected), INPUT.filename);
});

Deno.test("certificado guardado: aislado del otro negocio y de la clave OFV", async () => {
  const key = await importSecretKey(KEY_B64);
  const sealed = await sealCertificate(key, certificate(), BIZ);
  await assertRejects(
    () => openCertificate(key, sealed, "otro-negocio"),
    CertificateAccessError,
    "No se pudo leer",
  );
  const ofvCipher = await sealSecret(key, JSON.stringify(INPUT), BIZ);
  await assertRejects(
    () => openCertificate(key, ofvCipher, BIZ),
    CertificateAccessError,
  );
});

Deno.test("certificado guardado: corrupción y payload descifrado inválido fallan sin filtrar secretos", async () => {
  const key = await importSecretKey(KEY_B64);
  const sealed = await sealCertificate(key, certificate(), BIZ);
  const raw = atob(sealed.slice(3));
  const flipped = raw.slice(0, -1) +
    String.fromCharCode(raw.charCodeAt(raw.length - 1) ^ 1);
  const malformed = await sealSecret(
    key,
    JSON.stringify({ password: INPUT.password }),
    `${BIZ}:ecf-certificate`,
  );
  for (
    const value of ["texto-plano", "v1:roto", "v1:" + btoa(flipped), malformed]
  ) {
    const error = await assertRejects(
      () => openCertificate(key, value, BIZ),
      CertificateAccessError,
    );
    assertEquals(
      (error as CertificateAccessError).code,
      "certificate_decrypt_failed",
    );
    assert(!error.message.includes(INPUT.password));
  }
});

Deno.test("resolver: el certificado explícito no lee ni descifra el guardado", async () => {
  const unexpectedRead = () =>
    Promise.reject(new Error("No debe leer el guardado"));
  const unexpectedKey = () =>
    Promise.reject(new Error("No debe cargar la llave"));
  const result = await resolveCertificate(
    INPUT,
    unexpectedRead,
    unexpectedKey,
    BIZ,
  );
  assertEquals(result, { certificate: certificate(), stored: false });
});

Deno.test("resolver: el certificado explícito inválido no usa un guardado como sustituto", async () => {
  let reads = 0;
  const invalidInputs = [
    { ...INPUT, password: "" },
    { ...INPUT, filename: "foto.png" },
    { ...INPUT, content_base64: "no es base64" },
  ];
  for (const input of invalidInputs) {
    const error = await assertRejects(
      () =>
        resolveCertificate(input, () => {
          reads++;
          return Promise.resolve(null);
        }, () =>
          importSecretKey(KEY_B64), BIZ),
      CertificateAccessError,
    );
    assertEquals((error as CertificateAccessError).code, "invalid_certificate");
  }
  assertEquals(reads, 0);
});

Deno.test("resolver: sin carga explícita usa el certificado cifrado del negocio", async () => {
  const key = await importSecretKey(KEY_B64);
  const sealed = await sealCertificate(key, certificate(), BIZ);
  const result = await resolveCertificate(
    undefined,
    () => Promise.resolve(sealed),
    () => Promise.resolve(key),
    BIZ,
  );
  assertEquals(result, { certificate: certificate(), stored: true });
});

Deno.test("resolver: un certificado ausente es distinto de uno corrupto", async () => {
  const key = await importSecretKey(KEY_B64);
  const absent = await assertRejects(
    () =>
      resolveCertificate(
        undefined,
        () => Promise.resolve(null),
        () => Promise.resolve(key),
        BIZ,
      ),
    CertificateAccessError,
  );
  assertEquals(
    (absent as CertificateAccessError).code,
    "certificate_not_found",
  );
  const corrupt = await assertRejects(
    () =>
      resolveCertificate(
        undefined,
        () => Promise.resolve("v1:corrupto"),
        () => Promise.resolve(key),
        BIZ,
      ),
    CertificateAccessError,
  );
  assertEquals(
    (corrupt as CertificateAccessError).code,
    "certificate_decrypt_failed",
  );
});
