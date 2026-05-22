# ── Stage 1: Build Flutter web ────────────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# Cache pub dependencies separately from source changes
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Build args — override in Coolify "Build Variables" for production.
ARG SUPABASE_URL=https://supabase.busiposweb.com
ARG SUPABASE_PUBLISHABLE_KEY=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc3OTQ2MTI4MCwiZXhwIjo0OTM1MTM0ODgwLCJyb2xlIjoiYW5vbiJ9.CdZEf7Ux9iGEvc2TXl-hMTOyqpZ3AFTCiN7yD1saswI

# Copy source and compile
COPY . .

RUN flutter build web --release \
      --dart-define=SUPABASE_URL=${SUPABASE_URL} \
      --dart-define=SUPABASE_PUBLISHABLE_KEY=${SUPABASE_PUBLISHABLE_KEY}

# ── Stage 2: Serve with Nginx ─────────────────────────────────────────────────
FROM nginx:alpine AS runner

COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
