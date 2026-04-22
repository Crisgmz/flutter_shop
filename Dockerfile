# ── Stage 1: Build Flutter web ────────────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# Cache pub dependencies separately from source changes
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Build args — set these in Coolify under "Build Variables"
ARG SUPABASE_URL
ARG SUPABASE_ANON_KEY

# Copy source and compile
COPY . .

RUN flutter build web --release \
      --dart-define=SUPABASE_URL=${SUPABASE_URL} \
      --dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}

# ── Stage 2: Serve with Nginx ─────────────────────────────────────────────────
FROM nginx:alpine AS runner

COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
