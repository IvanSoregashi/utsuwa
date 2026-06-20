#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Net Library (Calibre, ePUB etc.)
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
DATA_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Net Library..."

# Create data books directory
mkdir -p "${DATA_PATH}/books"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}/books"
echo "  Net Library directories initialized successfully."
