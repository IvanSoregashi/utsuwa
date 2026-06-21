#!/bin/bash
# ==============================================================================
# Utsuwa: eMMC Hardening Orchestrator
# Executes all hardening sub-scripts.
# ==============================================================================

set -euo pipefail

# --- Color Constants ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Must run as root.${NC}"
    exit 1
fi

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_data_volume>"
    exit 1
fi

DATA_PATH=$(realpath "$1")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARDEN_DIR="${SCRIPT_DIR}/helpers/harden"

echo -e "Starting eMMC Hardening Suite..."

# Run sub-scripts
bash "${HARDEN_DIR}/memory.sh" "$DATA_PATH"
bash "${HARDEN_DIR}/logs.sh"
bash "${HARDEN_DIR}/filesystem.sh"
bash "${HARDEN_DIR}/docker.sh" "$DATA_PATH"

echo -e "\n${GREEN}✔ Hardening complete. Please monitor your system logs for any issues.${NC}"
