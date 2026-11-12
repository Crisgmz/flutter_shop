# ── Stage 1: Build Flutter web ────────────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# Cache pub dependencies separately from source changes
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Build args — override in Coolify "Build Variables" for production.
ARG SUPABASE_URL=https://supabase.busiposweb.com
ARG SUPABASE_PUBLISHABLE_KEY=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3OTQ2MTI4MCwiZXhwIjo0OTM1MTM0ODgwLCJyb2xlIjoiYW5vbiJ9.CdZEf7Ux9iGEvc2TXl-hMTOyqpZ3AFTCiN7yD1saswI

# Nombre de la plataforma (pestaña, login, PDF). Ej.: APP_NAME=Shop+
ARG APP_NAME="Busi Pos Web"

# Copy source and compile
COPY . .

# index.html y manifest.json no leen dart-define: se les cambia el nombre aquí.
RUN NAME_SED=$(printf '%s' "$APP_NAME" | sed 's/[&|\\]/\\&/g') && \
    sed -i "s|Busi Pos Web|${NAME_SED}|g" web/index.html web/manifest.json

RUN flutter build web --release \
      --dart-define=SUPABASE_URL=${SUPABASE_URL} \
      --dart-define=SUPABASE_PUBLISHABLE_KEY=${SUPABASE_PUBLISHABLE_KEY} \
      "--dart-define=APP_NAME=${APP_NAME}"

# ── Stage 2: Serve with Nginx ─────────────────────────────────────────────────
FROM nginx:alpine AS runner

COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
