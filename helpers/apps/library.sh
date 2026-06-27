#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Library (Calibre-Web, WebDAV)
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
DATA_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Library (Calibre-Web + WebDAV)..."

mkdir -p "${SECURE_PATH}/apps/calibre-config"
mkdir -p "${SECURE_PATH}/webdav"
mkdir -p "${DATA_PATH}/books"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/apps/calibre-config"
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/webdav"
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}/books"

echo "  Library directories initialized successfully."
