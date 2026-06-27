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
mkdir -p "${SECURE_PATH}/webdav"
mkdir -p "${SECURE_PATH}/apps"
mkdir -p "${DATA_PATH}/gallery"
mkdir -p "${DATA_PATH}/books"
mkdir -p "${DATA_PATH}/downloads"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/vault"
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/webdav"
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/apps"
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}/gallery"
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}/books"
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}/downloads"

echo "  Samba shares initialized successfully."
