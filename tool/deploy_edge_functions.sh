#!/usr/bin/env bash
# ============================================================================
# Despliegue de Edge Functions a Supabase SELF-HOSTED (supabase.busiposweb.com)
# ============================================================================
# En self-hosted NO existe `supabase functions deploy` (eso es solo cloud).
# Las funciones viven montadas en el volumen del contenedor edge-runtime:
#     <SUPABASE_DIR>/volumes/functions/<nombre>/index.ts
# y el runtime las sirve vía el router `main`. Este script copia las carpetas
# de supabase/functions/ al servidor y reinicia el contenedor.
#
# Uso:
#   tool/deploy_edge_functions.sh [usuario@host] [ruta-supabase-en-servidor]
#
# Defaults: root@31.97.40.114 y autodetección de la ruta (busca el compose de
# supabase en /root, /opt y /home). Para encontrarla a mano en el servidor:
#   docker ps --format '{{.Names}}' | grep -i functions
#   docker inspect <contenedor> --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' | grep functions
#
# Variables de entorno de Alanube (agrégalas al .env del docker-compose de
# Supabase en el servidor, sección del servicio functions/edge-runtime):
#   ALANUBE_BASE_URL=https://sandbox.alanube.co/dom/v1
#   ALANUBE_JWT=<jwt del proveedor>
#   ALANUBE_WEBHOOK_SECRET=<secreto que configures en Alanube>
# ============================================================================

set -euo pipefail

HOST="${1:-root@31.97.40.114}"
REMOTE_DIR="${2:-}"
LOCAL_FUNCTIONS_DIR="$(cd "$(dirname "$0")/.." && pwd)/supabase/functions"

FUNCTIONS=(_shared register-company emit-document alanube-webhook alanube-health create-employee)

if [[ -z "$REMOTE_DIR" ]]; then
  echo "→ Autodetectando la carpeta de funciones en $HOST…"
  REMOTE_DIR=$(ssh "$HOST" '
    for c in $(docker ps --format "{{.Names}}" | grep -iE "functions|edge"); do
      docker inspect "$c" --format "{{range .Mounts}}{{.Source}}|{{.Destination}}{{\"\n\"}}{{end}}" \
        | grep -E "\|/home/deno/functions$" | cut -d"|" -f1 && exit 0
    done
    exit 1
  ') || {
    echo "✗ No pude autodetectar la ruta. Pásala como 2º argumento, ej.:"
    echo "  tool/deploy_edge_functions.sh $HOST /root/supabase/docker/volumes/functions"
    exit 1
  }
  echo "  Detectada: $REMOTE_DIR"
fi

echo "→ Copiando funciones a $HOST:$REMOTE_DIR"
for fn in "${FUNCTIONS[@]}"; do
  if [[ -d "$LOCAL_FUNCTIONS_DIR/$fn" ]]; then
    rsync -av --delete \
      --exclude '.env' --exclude '.env.example' \
      "$LOCAL_FUNCTIONS_DIR/$fn/" "$HOST:$REMOTE_DIR/$fn/"
  fi
done

echo "→ Reiniciando el contenedor de edge functions…"
ssh "$HOST" '
  c=$(docker ps --format "{{.Names}}" | grep -iE "functions|edge" | head -1)
  if [[ -n "$c" ]]; then docker restart "$c"; else
    echo "No encontré el contenedor de functions; reinícialo a mano (docker compose restart functions)"; fi
'

echo "✓ Listo. Prueba con:"
echo "  curl -s https://supabase.busiposweb.com/functions/v1/alanube-health -H \"Authorization: Bearer <ANON_KEY>\""
