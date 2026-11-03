// El certificado de la solicitud se conserva cifrado para que el operador
// pueda firmar en el servidor sin descargar la llave privada al navegador.
import {
  CertificateInput,
  validateCertificate,
  ValidCertificate,
} from "./ecf-onboarding.ts";
import { openSecret, sealSecret } from "./secret-box.ts";

export class CertificateAccessError extends Error {
  constructor(
    public code:
      | "invalid_certificate"
      | "certificate_not_found"
      | "certificate_decrypt_failed",
    message: string,
  ) {
    super(message);
  }
}

export function certificateFilename(certificate: ValidCertificate): string {
  return `${certificate.name}.${certificate.extension}`;
}

function certificateInput(certificate: ValidCertificate): CertificateInput {
  return {
    filename: certificateFilename(certificate),
    content_base64: certificate.content,
    password: certificate.password,
  };
}

function validatedCertificate(input: unknown): ValidCertificate {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    throw new CertificateAccessError(
      "invalid_certificate",
      "Falta el certificado .p12 y su contraseña.",
    );
  }
  const row = input as Record<string, unknown>;
  for (const field of ["filename", "content_base64", "password"]) {
    if (row[field] != null && typeof row[field] !== "string") {
      throw new CertificateAccessError(
        "invalid_certificate",
        "El certificado recibido no es válido.",
      );
    }
  }
  const result = validateCertificate(row as CertificateInput);
  if (!result.ok) {
    throw new CertificateAccessError(
      "invalid_certificate",
      result.errors.join(" "),
    );
  }
  return result.value;
}

export async function sealCertificate(
  key: CryptoKey,
  certificate: ValidCertificate,
  businessId: string,
): Promise<string> {
  return await sealSecret(
    key,
    JSON.stringify(certificateInput(certificate)),
    `${businessId}:ecf-certificate`,
  );
}

export async function openCertificate(
  key: CryptoKey,
  sealed: string,
  businessId: string,
): Promise<ValidCertificate> {
  try {
    const plain = await openSecret(
      key,
      sealed,
      `${businessId}:ecf-certificate`,
    );
    return validatedCertificate(JSON.parse(plain));
  } catch {
    throw new CertificateAccessError(
      "certificate_decrypt_failed",
      "No se pudo leer el certificado guardado. Vuelve a cargar el .p12 y su contraseña.",
    );
  }
}

/** Un certificado explícito tiene prioridad; si es inválido no se sustituye. */
export async function resolveCertificate(
  input: CertificateInput | undefined,
  readStored: () => Promise<string | null>,
  key: () => Promise<CryptoKey>,
  businessId: string,
): Promise<{ certificate: ValidCertificate; stored: boolean }> {
  if (input !== undefined) {
    return { certificate: validatedCertificate(input), stored: false };
  }
  const sealed = await readStored();
  if (!sealed) {
    throw new CertificateAccessError(
      "certificate_not_found",
      "No hay un certificado guardado para este negocio. Carga el archivo .p12 y su contraseña.",
    );
  }
  return {
    certificate: await openCertificate(await key(), sealed, businessId),
    stored: true,
  };
}
