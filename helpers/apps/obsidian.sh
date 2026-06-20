#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Obsidian Notebook
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
BULK_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Obsidian personal knowledge-base..."

# Create secure Notebook vault
mkdir -p "${SECURE_PATH}/vault"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/vault"
echo "  Obsidian vault initialized successfully."
