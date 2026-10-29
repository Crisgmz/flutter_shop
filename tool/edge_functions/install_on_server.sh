#!/usr/bin/env bash
# ============================================================================
# Instala las Edge Functions de Busi Pos Web en el Supabase propio (Coolify,
# servidor 2.24.119.32 → supabase.busiposweb.com).
#
# Corre DENTRO del servidor, desde lo que sale de descomprimir el paquete que
# arma tool/deploy_edge_functions.sh en la Mac:
#
#   cd ~ && tar xzf edge-functions.tar.gz && bash edge-functions/install_on_server.sh
#
# Qué hace:
#   1. Encuentra el contenedor de Edge Functions (el que monta
#      /home/deno/functions) y la carpeta del servidor montada ahí.
#   2. Respalda en ~/edge-functions-backups/ las carpetas que va a reemplazar.
#   3. Reemplaza SOLO las carpetas que trae el paquete. No toca `main` (el
#      router del runtime) ni ninguna otra función que ya esté allí.
#   4. Reinicia el contenedor y comprueba que ecf-onboarding responda.
#
# Uso: bash install_on_server.sh [carpeta-de-funciones]
#   Sin argumento, la carpeta se detecta sola.
# Para revertir: descomprimir el respaldo encima de la carpeta y reiniciar.
# ============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/functions"
DEST="${1:-}"
CONTAINER=""

# Para comprobar al final. La clave es la pública (anon) que ya va en la app.
CHECK_URL="${SUPABASE_URL:-https://supabase.busiposweb.com}"
CHECK_KEY="${SUPABASE_ANON_KEY:-eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3OTQ2MTI4MCwiZXhwIjo0OTM1MTM0ODgwLCJyb2xlIjoiYW5vbiJ9.CdZEf7Ux9iGEvc2TXl-hMTOyqpZ3AFTCiN7yD1saswI}"

[[ -d "$SRC" ]] || { echo "✗ No encuentro $SRC: corre el script desde el paquete descomprimido."; exit 1; }
[[ -f "$HERE/VERSION" ]] && echo "Paquete: $(cat "$HERE/VERSION")"

# ── 1. Contenedor y carpeta ────────────────────────────────────────────────
if command -v docker >/dev/null 2>&1; then
  for c in $(docker ps --format '{{.Names}}' 2>/dev/null || true); do
    src=$(docker inspect "$c" \
      --format '{{range .Mounts}}{{if eq .Destination "/home/deno/functions"}}{{.Source}}{{end}}{{end}}' \
      2>/dev/null || true)
    if [[ -n "$src" ]]; then
      CONTAINER="$c"
      [[ -z "$DEST" ]] && DEST="$src"
      break
    fi
  done
fi

if [[ -z "$DEST" ]]; then
  echo "✗ No encontré el contenedor de Edge Functions (ninguno monta /home/deno/functions)."
  echo "  Pasa la carpeta a mano:  bash $0 /ruta/a/volumes/functions"
  exit 1
fi
echo "→ Carpeta de funciones: $DEST"
[[ -n "$CONTAINER" ]] && echo "→ Contenedor: $CONTAINER"

# El router `main` vive ahí: si no está, es la carpeta equivocada.
if [[ ! -d "$DEST/main" ]]; then
  echo "✗ $DEST no tiene la carpeta main/ (el router del runtime). No parece la carpeta"
  echo "  de funciones: no copio nada. Revisa la ruta."
  exit 1
fi

FNS=()
for d in "$SRC"/*/; do FNS+=("$(basename "$d")"); done
echo "→ Funciones del paquete: ${FNS[*]}"

# ── 2. Respaldo ────────────────────────────────────────────────────────────
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/edge-functions-backups"
existing=()
for fn in "${FNS[@]}"; do
  [[ -e "$DEST/$fn" ]] && existing+=("$fn")
done
if ((${#existing[@]} > 0)); then
  mkdir -p "$BACKUP_DIR"
  tar czf "$BACKUP_DIR/functions-$STAMP.tar.gz" -C "$DEST" "${existing[@]}"
  echo "→ Respaldo de ${existing[*]}: $BACKUP_DIR/functions-$STAMP.tar.gz"
else
  echo "→ No había ninguna de estas funciones en el servidor: nada que respaldar."
fi

# ── 3. Copiar (solo las carpetas del paquete) ─────────────────────────────
for fn in "${FNS[@]}"; do
  rm -rf "$DEST/.$fn.new"
  cp -R "$SRC/$fn" "$DEST/.$fn.new"
  rm -rf "$DEST/$fn"
  mv "$DEST/.$fn.new" "$DEST/$fn"
done
echo "✓ Copiadas."

# ── 4. Reiniciar y comprobar ──────────────────────────────────────────────
if [[ -z "$CONTAINER" ]]; then
  echo "⚠ No sé qué contenedor reiniciar: reinicia el servicio de Edge Functions"
  echo "  desde Coolify (o docker restart <contenedor>) y prueba la app."
  exit 0
fi

echo "→ Reiniciando $CONTAINER…"
docker restart "$CONTAINER" >/dev/null

echo "→ Variables que necesitan las funciones (solo se muestra si están, no su valor):"
docker exec "$CONTAINER" sh -c '
  for v in SUPABASE_URL SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY \
           ALANUBE_BASE_URL ALANUBE_JWT ALANUBE_WEBHOOK_SECRET \
           ECF_PANEL_NOTIFY_URL ECF_PANEL_NOTIFY_SECRET; do
    if [ -n "$(printenv "$v")" ]; then echo "  ✓ $v"; else echo "  ✗ $v"; fi
  done
  echo "  VERIFY_JWT=$(printenv VERIFY_JWT)"
' 2>/dev/null || echo "  (no pude leerlas dentro del contenedor)"
echo "  Las SUPABASE_* son obligatorias. Sin ALANUBE_* la solicitud igual se recibe,"
echo "  pero la empresa no se registra sola con el proveedor ni se emite e-CF."
echo "  Con VERIFY_JWT=true, el webhook de Alanube (que no manda JWT) recibe 401."

echo "→ Comprobando ecf-onboarding…"
resp=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 3
  resp=$(curl -s -m 15 -X POST "$CHECK_URL/functions/v1/ecf-onboarding" \
    -H "Authorization: Bearer $CHECK_KEY" -H "apikey: $CHECK_KEY" \
    -H 'Content-Type: application/json' \
    -d '{"action":"request_status","company_id":"00000000-0000-0000-0000-000000000000"}' \
    || true)
  # Mientras reinicia, el proxy responde vacío o con un 502.
  [[ "$resp" == *'"error"'* || "$resp" == *'"msg"'* ]] && break
done

if [[ "$resp" == *'could not find an appropriate entrypoint'* ]]; then
  echo "✗ El runtime sigue sin ver ecf-onboarding. ¿Es la carpeta que monta el contenedor?"
  echo "  Respuesta: $resp"
  exit 1
elif [[ "$resp" == *'"msg"'* ]]; then
  echo "✗ La función no arrancó. Respuesta del runtime:"
  echo "  $resp"
  exit 1
elif [[ "$resp" == *'"error"'* ]]; then
  # Con la clave pública no hay usuario: la función contesta "unauthorized".
  # Que conteste así es la prueba de que está publicada y arranca.
  echo "✓ ecf-onboarding responde: $resp"
  echo "✓ Listo. En la app: Configuración → Facturación electrónica → Reintentar."
else
  echo "⚠ No obtuve respuesta clara de $CHECK_URL. Prueba la app en un momento."
  echo "  Respuesta: ${resp:-(vacía)}"
  exit 1
fi
