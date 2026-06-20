#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Immich Photo Gallery
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
BULK_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Immich (Self-hosted Photo/Video Management)..."

# Create secure database state directory
mkdir -p "${SECURE_PATH}/app/immich_db"

# Create bulk system caches and library paths
mkdir -p "${BULK_PATH}/gallery"
mkdir -p "${BULK_PATH}/immich_system"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/app/immich_db"
chown -R "${SYS_USER}:${SYS_USER}" "${BULK_PATH}/gallery"
chown -R "${SYS_USER}:${SYS_USER}" "${BULK_PATH}/immich_system"
echo "  Immich directories initialized successfully."
