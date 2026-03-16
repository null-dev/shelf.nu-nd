#!/bin/sh
# Creates the required Supabase storage buckets for shelf.nu.
# Runs once after the storage service is healthy.

set -e

SUPABASE_URL="${SUPABASE_URL:-http://kong:8000}"
AUTH_HEADER="Authorization: Bearer ${SERVICE_ROLE_KEY}"

echo "Initializing shelf.nu storage buckets..."

# Helper: create a bucket, ignoring "already exists" errors
create_bucket() {
  local name="$1"
  local public="$2"

  echo "  Creating bucket: ${name} (public=${public})"

  response=$(curl -sf \
    -X POST \
    "${SUPABASE_URL}/storage/v1/bucket" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "{\"id\": \"${name}\", \"name\": \"${name}\", \"public\": ${public}, \"file_size_limit\": 52428800}" \
    2>&1) || true

  # Supabase returns 409 if the bucket already exists — that's fine
  echo "    -> ${response:-ok}"
}

# profile-pictures: public bucket (URLs embedded directly in HTML)
create_bucket "profile-pictures" "true"

# assets: private bucket (access via signed URLs, 24-hour expiry)
create_bucket "assets" "false"

# kits: private bucket (same pattern as assets)
create_bucket "kits" "false"

# files: public bucket (used for audit images, location images, etc.)
create_bucket "files" "true"

echo "Storage bucket initialization complete."
