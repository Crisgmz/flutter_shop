#!/usr/bin/env bash
# ============================================================================
# Edge Functions → Supabase SELF-HOSTED (supabase.busiposweb.com, servidor
# 2.24.119.32, Coolify)
# ============================================================================
# En self-hosted NO existe `supabase functions deploy` (eso es solo cloud).
# Las funciones viven montadas en el volumen del contenedor edge-runtime y el
# router `main` las sirve. Ojo: una función que falta allí NO da 404, da 500
# con {"msg": "...could not find an appropriate entrypoint"}.
#
# Este script arma un paquete con las funciones y el instalador
# (tool/edge_functions/install_on_server.sh), que corre DENTRO del servidor:
# respalda, copia solo esas carpetas, reinicia el contenedor y comprueba.
#
# Uso:
#   tool/deploy_edge_functions.sh
#       → solo arma build/edge-functions.tar.gz y dice cómo subirlo a mano:
#           scp build/edge-functions.tar.gz root@2.24.119.32:
#           ssh root@2.24.119.32
#           cd ~ && rm -rf edge-functions && tar xzf edge-functions.tar.gz \
#             && bash edge-functions/install_on_server.sh
#   tool/deploy_edge_functions.sh --subir [usuario@host]
#       → además lo sube e instala (pide la clave del servidor una sola vez).
#
# ANTES de instalar: las migraciones 101 (la piden emit-document y
# alanube-webhook) y 102 (la pide ecf-onboarding) tienen que estar corridas.
#
# Variables del servicio de Edge Functions en Coolify:
#   SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY (las pone el
#   compose de Supabase), y para e-CF:
#   ALANUBE_BASE_URL=https://sandbox.alanube.co/dom/v1
#   ALANUBE_JWT=<jwt del proveedor>
#   ALANUBE_WEBHOOK_SECRET=<secreto que configures en Alanube>
#   ECF_PANEL_NOTIFY_URL / ECF_PANEL_NOTIFY_SECRET (opcionales: avisar al
#   panel de MangoPOS cuando entra una solicitud)
# ============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/supabase/functions"
OUT="$ROOT/build"
STAGE="$OUT/edge-functions"
PACKAGE="$OUT/edge-functions.tar.gz"

FUNCTIONS=(_shared register-company emit-document alanube-webhook alanube-health ecf-onboarding create-employee)

PUSH=false
HOST="root@2.24.119.32"
if [[ "${1:-}" == "--subir" ]]; then
  PUSH=true
  HOST="${2:-$HOST}"
elif [[ -n "${1:-}" ]]; then
  echo "Uso: $0 [--subir [usuario@host]]"
  exit 1
fi

# ── Paquete ────────────────────────────────────────────────────────────────
rm -rf "$STAGE"
mkdir -p "$STAGE/functions"
for fn in "${FUNCTIONS[@]}"; do
  [[ -d "$SRC/$fn" ]] || { echo "✗ Falta supabase/functions/$fn"; exit 1; }
  # Sin pruebas ni .env: al servidor solo va lo que corre.
  rsync -a --exclude '*_test.ts' --exclude '.env*' --exclude '.DS_Store' \
    "$SRC/$fn/" "$STAGE/functions/$fn/"
done
cp "$ROOT/tool/edge_functions/install_on_server.sh" "$STAGE/"

commit="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo 'sin git')"
dirty=""
git -C "$ROOT" diff --quiet -- supabase/functions 2>/dev/null || dirty=" + cambios sin commit"
echo "$commit$dirty — $(date '+%Y-%m-%d %H:%M')" > "$STAGE/VERSION"

# Sin lo que macOS mete en los tar: COPYFILE_DISABLE quita los archivos ._* y
# --no-xattrs/--no-mac-metadata los atributos (com.apple.provenance), que el
# tar del servidor reporta como "Ignoring unknown extended header keyword".
COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -czf "$PACKAGE" -C "$OUT" edge-functions
echo "✓ Paquete: $PACKAGE ($(du -h "$PACKAGE" | cut -f1)) — $(cat "$STAGE/VERSION")"
echo "  Funciones: ${FUNCTIONS[*]}"

if ! $PUSH; then
  cat <<EOF

Para instalarlo:
  scp "$PACKAGE" $HOST:
  ssh $HOST
  cd ~ && rm -rf edge-functions && tar xzf edge-functions.tar.gz && bash edge-functions/install_on_server.sh
EOF
  exit 0
fi

# ── Subir e instalar (una sola conexión: la clave se pide una vez) ─────────
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=/tmp/busipos-%C" -o ControlPersist=120)
echo "→ Subiendo a $HOST…"
scp "${SSH_OPTS[@]}" "$PACKAGE" "$HOST:"
echo "→ Instalando…"
ssh "${SSH_OPTS[@]}" "$HOST" \
  'cd ~ && rm -rf edge-functions && tar xzf edge-functions.tar.gz && bash edge-functions/install_on_server.sh'
