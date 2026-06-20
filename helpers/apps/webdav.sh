#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: WebDAV Server
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
BULK_PATH="$2"
SYS_USER="$3"

echo "--> Initializing WebDAV..."

# Create application state directory
mkdir -p "${SECURE_PATH}/app/webdav"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/app/webdav"
echo "  WebDAV directories initialized successfully."
