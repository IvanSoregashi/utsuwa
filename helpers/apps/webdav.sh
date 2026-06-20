#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: WebDAV Server
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
DATA_PATH="$2"
SYS_USER="$3"

echo "--> Initializing WebDAV..."

# Create data directories for WebDAV access
mkdir -p "${DATA_PATH}/gallery"
mkdir -p "${DATA_PATH}/books"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}/gallery"
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}/books"
echo "  WebDAV directories initialized successfully."
