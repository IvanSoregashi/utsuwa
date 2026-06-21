#!/bin/bash
# ==============================================================================
# Utsuwa: Ext4 Partition Setup Helper
# Wipes, partitions, formats and mounts a drive as Ext4.
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
DISK_NAME="${2}" # e.g. nvme0n1

# --- Helper to log and run system commands ---
run() {
    echo -e "${BLUE}--> Running: ${BOLD}$*${NC}"
    "$@"
}

echo -e "${CYAN}======================================================================${NC}"
echo -e "                   EXT4 STORAGE PROVISIONING                         "
echo -e "Target Device: ${YELLOW}/dev/${DISK_NAME}${NC}"
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
            # For partitions, prefer ones containing "-part"
            if [[ "$dev_name" =~ [0-9]+$ ]]; then
                if [[ "$base_link" == *"-part"* ]]; then
                    echo "$link"
                    return 0
                fi
            else
                # For whole disks, avoid "-part", "nvme-eui.", or "wwn-"
                if [[ "$base_link" != *"-part"* ]] && [[ "$base_link" != nvme-eui.* ]] && [[ "$base_link" != wwn-* ]]; then
                    echo "$link"
                    return 0
                fi
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

# 1. Resolve whole disk persistent path
DISK_BY_ID=$(get_disk_by_id "$DISK_NAME")
echo -e "Persistent Disk Path resolved: ${GREEN}${DISK_BY_ID}${NC}"

# 2. Check for parted installation
if ! command -v parted &>/dev/null; then
    echo -e "${YELLOW}'parted' utility is required but not installed.${NC}"
    read -r -p "Would you like to install parted now? (y/n) [y]: " inst_parted
    inst_parted=${inst_parted:-y}
    if [[ "$inst_parted" =~ ^[Yy]$ ]]; then
        echo "--> Updating package repository and installing parted..."
        apt-get update
        apt-get install -y parted
    else
        echo -e "${RED}Aborted: parted is required to set up partitions.${NC}"
        exit 1
    fi
fi

# 3. Warning & Confirmation
echo -e "${RED}${BOLD}!!! WARNING !!! WARNING !!! WARNING !!!${NC}"
echo -e "${RED}This operation will DESTROY all data on /dev/${DISK_NAME} (${DISK_BY_ID}).${NC}"
echo -e "Are you absolutely sure you want to proceed?"
echo ""
read -r -p "Type 'yes' to proceed, or anything else to abort: " confirm_wipe

if [ "$confirm_wipe" != "yes" ]; then
    echo -e "${YELLOW}Operation aborted by user.${NC}"
    exit 0
fi

# 4. Partitioning
echo -e "\n--> Creating GPT Partition Table on ${DISK_BY_ID}..."
run parted "$DISK_BY_ID" mklabel gpt

echo -e "--> Creating primary ext4 partition spanning 100% of the drive..."
run parted "$DISK_BY_ID" mkpart primary ext4 0% 100%

# Wait for udev to create new devnodes and links
echo "--> Waiting for partition creation and udev synchronization..."
sleep 2

# Find the newly created partition name
# (Typically p1 for nvme/mmcblk, or 1 for sdX)
PART_NAME=""
if [ -b "/dev/${DISK_NAME}p1" ]; then
    PART_NAME="${DISK_NAME}p1"
elif [ -b "/dev/${DISK_NAME}1" ]; then
    PART_NAME="${DISK_NAME}1"
else
    # Fallback search
    for p in "/dev/${DISK_NAME}"*; do
        if [ -b "$p" ] && [ "$p" != "/dev/${DISK_NAME}" ]; then
            PART_NAME=$(basename "$p")
            break
        fi
    done
fi

if [ -z "$PART_NAME" ]; then
    echo -e "${RED}Error: Could not locate the newly created partition device.${NC}"
    exit 1
fi

# Resolve partition persistent by-id path
PART_BY_ID=$(get_disk_by_id "$PART_NAME")
echo -e "Detected partition: ${GREEN}/dev/${PART_NAME}${NC} -> ${GREEN}${PART_BY_ID}${NC}"

# 5. Format Filesystem
echo -e "\n--> Formatting ${PART_BY_ID} as ext4..."
run mkfs.ext4 "$PART_BY_ID"

# 6. Mount & Auto-Mount Options
echo ""
read -r -p "Enter desired mount point path [default: /bulk]: " MOUNT_POINT
MOUNT_POINT=${MOUNT_POINT:-/bulk}

# Create mount folder if it doesn't exist
if [ ! -d "$MOUNT_POINT" ]; then
    echo "--> Creating mount directory: ${MOUNT_POINT}"
    mkdir -p "$MOUNT_POINT"
fi

# Check if already mounted
if mountpoint -q "$MOUNT_POINT"; then
    echo -e "${YELLOW}Warning: ${MOUNT_POINT} is already mounted. Attempting to unmount first...${NC}"
    umount "$MOUNT_POINT" || true
fi

echo "--> Mounting partition to ${MOUNT_POINT}..."
run mount "$PART_BY_ID" "$MOUNT_POINT"

# Update /etc/fstab for boot mount persistence
read -r -p "Configure automatic mounting on boot in /etc/fstab? (y/n) [y]: " configure_fstab
configure_fstab=${configure_fstab:-y}

if [[ "$configure_fstab" =~ ^[Yy]$ ]]; then
    # Prevent duplicate fstab entries
    if grep -qF "$MOUNT_POINT" /etc/fstab; then
        echo -e "${YELLOW}An entry for ${MOUNT_POINT} already exists in /etc/fstab. Skipping insertion.${NC}"
    else
        echo -e "--> Appending mount entry to /etc/fstab..."
        echo "${PART_BY_ID} ${MOUNT_POINT} ext4 defaults 0 2" | run tee -a /etc/fstab > /dev/null
        echo "  Successfully configured fstab auto-mount."
    fi
fi

# 7. Permissions & Ownership alignment
echo -e "--> Changing folder ownership to system user ${GREEN}${SYS_USER}${NC}..."
run chown -R "${SYS_USER}:${SYS_USER}" "$MOUNT_POINT"

echo -e "\n${GREEN}✔ Ext4 Partition successfully created, formatted, and mounted!${NC}"
echo -e "Details:"
echo -e "  Device:      ${PART_BY_ID}"
echo -e "  Mount Point: ${MOUNT_POINT}"
echo -e "  Owner:       ${SYS_USER}"
echo -e "======================================================================\n"
