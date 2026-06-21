#!/bin/bash
# ==============================================================================
# Utsuwa: ZFS Storage Pool Setup Helper
# Installs ZFS, creates pools (single/mirror), configures optimal settings,
# sets up encrypted datasets, and configures ARC cache limit.
# ==============================================================================

set -euo pipefail

# --- Color Constants ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Parameters ---
SYS_USER="${1}"
POOL_TYPE="${2}" # "single" or "mirror"
DISK1_NAME="${3}" # e.g. nvme1n1
DISK2_NAME="${4:-}" # e.g. nvme2n1 (only if mirror)

# --- Helper to log and run system commands ---
run() {
    echo -e "${BLUE}--> Running: ${BOLD}$*${NC}"
    "$@"
}

echo -e "${CYAN}======================================================================${NC}"
echo -e "                   ZFS STORAGE POOL PROVISIONING                      "
echo -e "Configuration: ${YELLOW}${POOL_TYPE^^}${NC}"
echo -e "Primary Device: ${YELLOW}/dev/${DISK1_NAME}${NC}"
if [ "$POOL_TYPE" = "mirror" ]; then
    echo -e "Mirror Device:  ${YELLOW}/dev/${DISK2_NAME}${NC}"
fi
echo -e "${CYAN}======================================================================${NC}"

# --- Helper to resolve /dev/disk/by-id ---
get_disk_by_id() {
    local dev_name="$1"
    local real_dev
    real_dev=$(readlink -f "/dev/${dev_name}")
    
    local candidate=""
    for link in /dev/disk/by-id/*; do
        if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$real_dev" ]; then
            local base_link
            base_link=$(basename "$link")
            # Avoid partition-specific, nvme-eui., or wwn- links
            if [[ "$base_link" != *"-part"* ]] && [[ "$base_link" != nvme-eui.* ]] && [[ "$base_link" != wwn-* ]]; then
                echo "$link"
                return 0
            fi
            candidate="$link"
        fi
    done
    
    if [ -n "$candidate" ]; then
        echo "$candidate"
    else
        echo "/dev/${dev_name}"
    fi
}

# Resolve persistent disk paths
DISK1_BY_ID=$(get_disk_by_id "$DISK1_NAME")
DISK2_BY_ID=""
if [ "$POOL_TYPE" = "mirror" ]; then
    DISK2_BY_ID=$(get_disk_by_id "$DISK2_NAME")
fi

echo -e "Resolved Primary: ${GREEN}${DISK1_BY_ID}${NC}"
if [ -n "$DISK2_BY_ID" ]; then
    echo -e "Resolved Mirror:  ${GREEN}${DISK2_BY_ID}${NC}"
fi

# 1. Check for ZFS utility installation
if ! command -v zfs &>/dev/null || ! command -v zpool &>/dev/null; then
    bash "$(dirname "${BASH_SOURCE[0]}")/install-zfs.sh"
fi

# Ensure ZFS module is loaded
if ! lsmod | grep -q zfs; then
    echo "--> Loading ZFS kernel module..."
    run modprobe zfs || true
fi

# 2. Gather parameters
echo ""
read -r -p "Enter name for the new ZFS pool [default: vault]: " POOL_NAME
POOL_NAME=${POOL_NAME:-vault}

# Check if pool name already exists
if zpool list "$POOL_NAME" &>/dev/null; then
    echo -e "${RED}Error: A ZFS pool named '${POOL_NAME}' already exists on this system.${NC}"
    exit 1
fi

read -r -p "Create an encrypted dataset inside '${POOL_NAME}'? (y/n) [y]: " create_encrypted
create_encrypted=${create_encrypted:-y}

DATASET_NAME=""
if [[ "$create_encrypted" =~ ^[Yy]$ ]]; then
    read -r -p "Enter dataset name [default: secure]: " DATASET_NAME
    DATASET_NAME=${DATASET_NAME:-secure}
fi

# 3. Calculate recommended ARC limit (25% of total RAM, minimum 512MB)
ARC_RECOMMENDED="1G"
TOTAL_RAM_BYTES=0
if [ -f /proc/meminfo ]; then
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_BYTES=$((TOTAL_RAM_KB * 1024))
    # Suggest 25% of RAM
    SUGGEST_BYTES=$((TOTAL_RAM_BYTES / 4))
    SUGGEST_GB=$((SUGGEST_BYTES / 1024 / 1024 / 1024))
    if [ "$SUGGEST_GB" -gt 0 ]; then
        ARC_RECOMMENDED="${SUGGEST_GB}G"
    else
        ARC_RECOMMENDED="512M"
    fi
fi

echo ""
read -r -p "Configure ZFS RAM limit (ARC cache)? (y/n) [y]: " limit_arc
limit_arc=${limit_arc:-y}

ARC_LIMIT_INPUT=""
if [[ "$limit_arc" =~ ^[Yy]$ ]]; then
    echo -e "Total System Memory detected: ${CYAN}$((TOTAL_RAM_BYTES / 1024 / 1024 / 1024)) GB${NC}"
    read -r -p "Enter ARC RAM Limit (e.g., 3G, 4G, 512M) [default: ${ARC_RECOMMENDED}]: " ARC_LIMIT_INPUT
    ARC_LIMIT_INPUT=${ARC_LIMIT_INPUT:-$ARC_RECOMMENDED}
fi

# Helper to parse RAM string to bytes
parse_to_bytes() {
    local input="$1"
    input=$(echo "$input" | xargs | tr '[:lower:]' '[:upper:]')
    if [[ "$input" =~ ^[0-9]+G$ ]]; then
        local num="${input%G}"
        echo "$((num * 1024 * 1024 * 1024))"
    elif [[ "$input" =~ ^[0-9]+M$ ]]; then
        local num="${input%M}"
        echo "$((num * 1024 * 1024))"
    elif [[ "$input" =~ ^[0-9]+K$ ]]; then
        local num="${input%K}"
        echo "$((num * 1024))"
    elif [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "$input"
    else
        echo "0"
    fi
}

# 4. Confirmation
echo -e "\n${RED}${BOLD}!!! WARNING !!! WARNING !!! WARNING !!!${NC}"
echo -e "${RED}This operation will DESTROY all data on the following selected disk(s):${NC}"
echo -e "  - ${DISK1_BY_ID}"
if [ -n "$DISK2_BY_ID" ]; then
    echo -e "  - ${DISK2_BY_ID}"
fi
echo ""
echo -e "${BOLD}Setup Summary:${NC}"
echo -e "  Pool Name:        ${GREEN}${POOL_NAME}${NC}"
echo -e "  Pool Layout:      ${GREEN}${POOL_TYPE^^}${NC}"
if [[ "$create_encrypted" =~ ^[Yy]$ ]]; then
    echo -e "  Encrypt Dataset:  ${GREEN}${POOL_NAME}/${DATASET_NAME}${NC} (Passphrase key)"
else
    echo -e "  Encrypt Dataset:  ${YELLOW}No (unencrypted only)${NC}"
fi
if [[ "$limit_arc" =~ ^[Yy]$ ]]; then
    echo -e "  ZFS ARC RAM Limit:${GREEN}${ARC_LIMIT_INPUT}${NC}"
fi
echo ""
read -r -p "Type 'yes' to proceed with layout creation: " confirm_zfs

if [ "$confirm_zfs" != "yes" ]; then
    echo -e "${YELLOW}Operation aborted by user.${NC}"
    exit 0
fi

# 5. Execute Pool Creation
echo -e "\n--> Creating ZFS Pool '${POOL_NAME}'..."

if [ "$POOL_TYPE" = "mirror" ]; then
    run zpool create -f -o ashift=12 \
      -O acltype=posixacl \
      -O xattr=sa \
      -O dnodesize=auto \
      -O normalization=formD \
      -O devices=off \
      "$POOL_NAME" \
      mirror \
      "$DISK1_BY_ID" \
      "$DISK2_BY_ID"
else
    run zpool create -f -o ashift=12 \
      -O acltype=posixacl \
      -O xattr=sa \
      -O dnodesize=auto \
      -O normalization=formD \
      -O devices=off \
      "$POOL_NAME" \
      "$DISK1_BY_ID"
fi

echo -e "${GREEN}✔ ZFS Pool '${POOL_NAME}' created successfully.${NC}"

# 6. Create Encrypted Dataset
if [[ "$create_encrypted" =~ ^[Yy]$ ]]; then
    echo -e "\n--> Creating Encrypted Dataset '${POOL_NAME}/${DATASET_NAME}'..."
    echo -e "${YELLOW}Please enter a secure passphrase for the encrypted volume when prompted below.${NC}"
    
    # We must allow user keyboard interaction for passphrase entry
    run zfs create \
      -o encryption=on \
      -o keyformat=passphrase \
      -o keylocation=prompt \
      "${POOL_NAME}/${DATASET_NAME}"
      
    echo -e "${GREEN}✔ Encrypted dataset '${POOL_NAME}/${DATASET_NAME}' created successfully.${NC}"
fi

# 7. Setup ZFS RAM Limit (ARC)
if [[ "$limit_arc" =~ ^[Yy]$ ]] && [ -n "$ARC_LIMIT_INPUT" ]; then
    ARC_BYTES=$(parse_to_bytes "$ARC_LIMIT_INPUT")
    if [ "$ARC_BYTES" -gt 0 ]; then
        echo -e "\n--> Limiting ZFS ARC Memory cache to ${ARC_LIMIT_INPUT} (${ARC_BYTES} bytes)..."
        run mkdir -p /etc/modprobe.d
        echo "options zfs zfs_arc_max=${ARC_BYTES}" | run tee /etc/modprobe.d/zfs.conf > /dev/null
        
        echo "--> Updating system initramfs boot configuration..."
        run update-initramfs -u -k all
        echo -e "${GREEN}✔ ARC Limit successfully written & system initramfs updated.${NC}"
    else
        echo -e "${YELLOW}Warning: Could not parse '${ARC_LIMIT_INPUT}' to valid byte size. Skipping ARC limit config.${NC}"
    fi
fi

# 8. Align Permissions & Ownership
echo -e "\n--> Aligning mount directories permission to active user: ${GREEN}${SYS_USER}${NC}..."
run chown -R "${SYS_USER}:${SYS_USER}" "/${POOL_NAME}"
if [[ "$create_encrypted" =~ ^[Yy]$ ]]; then
    # ZFS auto-mounts datasets inside the pool path
    run chown -R "${SYS_USER}:${SYS_USER}" "/${POOL_NAME}/${DATASET_NAME}"
fi

echo -e "\n${GREEN}✔ ZFS Pool provisioned successfully!${NC}"
echo -e "Summary:"
echo -e "  Pool Name:  ${POOL_NAME}"
echo -e "  Mount Point: /${POOL_NAME}"
if [[ "$create_encrypted" =~ ^[Yy]$ ]]; then
    echo -e "  Secure Vol:  /${POOL_NAME}/${DATASET_NAME} (Encrypted)"
fi
echo -e "======================================================================\n"
