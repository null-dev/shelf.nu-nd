#!/usr/bin/env bash
# shelf.nu + Self-Hosted Supabase — First-time setup script
#
# This script:
#   1. Downloads the required Supabase Docker volume files from GitHub
#   2. Creates the env files from their examples (if they don't exist yet)
#   3. Prints next steps
#
# Run from the docker/ directory:  sh setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPABASE_TAG="master"
SUPABASE_BASE="https://raw.githubusercontent.com/supabase/supabase/${SUPABASE_TAG}/docker"

info()    { echo "[setup] $*"; }
success() { echo "[setup] ✓ $*"; }
warn()    { echo "[setup] ⚠ $*"; }

# ---------------------------------------------------------------------------
# 1. Download Supabase volume files
# ---------------------------------------------------------------------------

info "Downloading Supabase Docker volume files (tag: ${SUPABASE_TAG})..."

download() {
  local src="$1"
  local dst="${SCRIPT_DIR}/$2"
  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ]; then
    info "  Skipping (already exists): $2"
    return
  fi
  info "  Downloading: $2"
  curl -fsSL "${SUPABASE_BASE}/${src}" -o "$dst"
}

# Kong API gateway config
download "volumes/api/kong.yml"             "volumes/api/kong.yml"
download "volumes/api/kong-entrypoint.sh"   "volumes/api/kong-entrypoint.sh"
chmod +x "${SCRIPT_DIR}/volumes/api/kong-entrypoint.sh"

# Postgres init SQL scripts
download "volumes/db/realtime.sql"   "volumes/db/realtime.sql"
download "volumes/db/webhooks.sql"   "volumes/db/webhooks.sql"
download "volumes/db/roles.sql"      "volumes/db/roles.sql"
download "volumes/db/jwt.sql"        "volumes/db/jwt.sql"
download "volumes/db/_supabase.sql"  "volumes/db/_supabase.sql"
download "volumes/db/logs.sql"       "volumes/db/logs.sql"
download "volumes/db/pooler.sql"     "volumes/db/pooler.sql"

# Vector log configuration
download "volumes/logs/vector.yml"   "volumes/logs/vector.yml"

# Supavisor pooler configuration
download "volumes/pooler/pooler.exs" "volumes/pooler/pooler.exs"

success "Supabase volume files ready."

# ---------------------------------------------------------------------------
# 2. Create env files from examples
# ---------------------------------------------------------------------------

copy_env() {
  local example="${SCRIPT_DIR}/$1"
  local target="${SCRIPT_DIR}/$2"
  if [ -f "$target" ]; then
    info "$2 already exists — skipping. Edit it manually if needed."
  else
    cp "$example" "$target"
    success "$2 created from $1."
  fi
}

copy_env ".env.supabase.example" ".env.supabase"
copy_env ".env.shelf.example"    ".env.shelf"
copy_env ".env.mail.example"     ".env.mail"

generate_dotenv() {
  # Docker Compose auto-loads .env for YAML variable interpolation (URL
  # construction, port mappings, etc.). We generate it by concatenating all
  # three env files so compose has access to every variable at parse time.
  # Edit .env.supabase / .env.shelf / .env.mail and re-run setup.sh to update.
  cat \
    "${SCRIPT_DIR}/.env.supabase" \
    "${SCRIPT_DIR}/.env.shelf" \
    "${SCRIPT_DIR}/.env.mail" \
    > "${SCRIPT_DIR}/.env"
  success ".env generated from all env files (used by Docker Compose for interpolation)."
}

generate_dotenv

cat <<'MSG'

  ┌─────────────────────────────────────────────────────────────────────┐
  │  IMPORTANT: Edit the env files before starting the stack!           │
  │                                                                     │
  │  docker/.env.supabase — Supabase infrastructure secrets:           │
  │    • POSTGRES_PASSWORD      — strong database password             │
  │    • JWT_SECRET             — random string (32+ chars)            │
  │    • DASHBOARD_PASSWORD     — Supabase Studio login password       │
  │    • SECRET_KEY_BASE        — random string (64+ hex chars)        │
  │    • VAULT_ENC_KEY          — exactly 32 characters               │
  │    • PG_META_CRYPTO_KEY     — 32+ character key                   │
  │    • LOGFLARE_*_ACCESS_TOKEN — random strings                      │
  │    • ANON_KEY / SERVICE_ROLE_KEY — generate fresh JWTs for prod   │
  │                                                                     │
  │  docker/.env.shelf — shelf.nu app secrets:                         │
  │    • SESSION_SECRET         — random string for shelf.nu sessions  │
  │    • INVITE_TOKEN_SECRET    — random string                        │
  │                                                                     │
  │  docker/.env.mail — Inbucket ports (defaults are fine for dev)    │
  │                                                                     │
  │  See the Supabase self-hosting guide for key generation:           │
  │  https://supabase.com/docs/guides/self-hosting/docker              │
  └─────────────────────────────────────────────────────────────────────┘
MSG

# ---------------------------------------------------------------------------
# 3. Ensure required directories exist
# ---------------------------------------------------------------------------

mkdir -p \
  "${SCRIPT_DIR}/volumes/storage" \
  "${SCRIPT_DIR}/volumes/functions" \
  "${SCRIPT_DIR}/volumes/snippets"

success "Volume directories ready."

# ---------------------------------------------------------------------------
# 4. Print next steps
# ---------------------------------------------------------------------------

cat <<'STEPS'

Setup complete! Next steps:

  1. Edit the env files with your secrets (see warnings above).

  2. Build and start the stack:
       cd docker
       docker compose up -d

     On the first run, Docker will:
       • Pull all Supabase service images
       • Build the shelf.nu webapp image from source
       • Run Prisma database migrations
       • Create the required Supabase storage buckets

  3. Wait ~2 minutes for all services to become healthy, then open:
       http://localhost:3000  — shelf.nu webapp
       http://localhost:3001  — Supabase Studio (dashboard)
       http://localhost:9000  — Inbucket mail UI (dev only)

  4. Create your first shelf.nu user via the signup page or Supabase Studio.

  Tip: watch startup progress with:
       docker compose logs -f webapp

STEPS
