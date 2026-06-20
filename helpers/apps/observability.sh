#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Observability (Grafana, Prometheus, etc.)
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
DATA_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Observability Suite (Metrics & Logs)..."

# Create monitoring metrics state directory
mkdir -p "${SECURE_PATH}/app/observability"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/app/observability"
echo "  Observability directories initialized successfully."
