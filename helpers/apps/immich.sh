#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Immich Photo Gallery
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
DATA_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Immich (Self-hosted Photo/Video Management)..."

# Create secure database state directory
mkdir -p "${SECURE_PATH}/apps/immich/db"

# Create data directories (photos + uploads)
mkdir -p "${DATA_PATH}/gallery/immich"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/apps/immich"
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}/gallery/immich"
echo "  Immich directories initialized successfully."
