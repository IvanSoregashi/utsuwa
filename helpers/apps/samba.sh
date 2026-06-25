#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Samba
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
DATA_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Samba Server configuration & shares..."

# Create data shared folders
mkdir -p "${SECURE_PATH}/vault"
mkdir -p "${SECURE_PATH}/app"
mkdir -p "${DATA_PATH}/gallery"
mkdir -p "${DATA_PATH}/books"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/vault"
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/app"
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}/gallery"
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}/books"

echo "  Samba shares initialized successfully."
