#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Gitea (Git Service)
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
DATA_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Gitea Git Repositories..."

# Create secure app data directory for Gitea
mkdir -p "${SECURE_PATH}/app/gitea/repos"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/app/gitea"
echo "  Gitea directories initialized successfully."
