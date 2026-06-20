#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Net Library (Calibre, ePUB etc.)
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
BULK_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Net Library..."

# Create secure database/state directory
mkdir -p "${SECURE_PATH}/app/net_library"

# Create bulk raw ePUB book storage
mkdir -p "${BULK_PATH}/net_library_books"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/app/net_library"
chown -R "${SYS_USER}:${SYS_USER}" "${BULK_PATH}/net_library_books"
echo "  Net Library directories initialized successfully."
