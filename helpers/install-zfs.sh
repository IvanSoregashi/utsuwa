#!/bin/bash
# ==============================================================================
# Utsuwa: ZFS Installer & Repo Configurator
# Ensures Debian repository components are set for ZFS and installs necessary packages.
# ==============================================================================

set -euo pipefail

# --- Color Constants ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "--> Checking ZFS installation requirements..."

# Robust checker to enable contrib/non-free on Debian
enable_debian_non_free_contrib() {
    echo "  Verifying package repository components..."
    if apt-cache show zfsutils-linux &>/dev/null; then
        echo "  ZFS packages are already visible."
        return 0
    fi
    
    echo -e "${YELLOW}Warning: 'zfsutils-linux' is not visible in current package sources.${NC}"
    read -r -p "Automatically enable 'contrib' and 'non-free' sources? (y/n) [y]: " enable_repo
    enable_repo=${enable_repo:-y}
    
    if [[ ! "$enable_repo" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Error: Cannot proceed without enabling ZFS packages.${NC}"
        exit 1
    fi
    
    echo "--> Appending contrib, non-free, and non-free-firmware to sources..."
    # Modern DEB822 format (Debian 12+)
    if [ -f "/etc/apt/sources.list.d/debian.sources" ]; then
        sed -i -E 's/^(Components:.*main)(.*)/\1 contrib non-free non-free-firmware\2/' /etc/apt/sources.list.d/debian.sources
        sed -i -E 's/contrib contrib/contrib/g; s/non-free non-free/non-free/g; s/non-free-firmware non-free-firmware/non-free-firmware/g' /etc/apt/sources.list.d/debian.sources
    fi
    
    # Legacy format
    if [ -f "/etc/apt/sources.list" ]; then
        sed -i -E '/^deb/ s/ main/ main contrib non-free non-free-firmware/g' /etc/apt/sources.list
        sed -i -E 's/contrib contrib/contrib/g; s/non-free non-free/non-free/g; s/non-free-firmware non-free-firmware/non-free-firmware/g' /etc/apt/sources.list
    fi
    
    apt-get update
    
    if ! apt-cache show zfsutils-linux &>/dev/null; then
        echo -e "${RED}Error: ZFS packages still not visible. Check internet connection.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✔ Repository components enabled.${NC}"
}

enable_debian_non_free_contrib

echo -e "${YELLOW}Note: Compiling ZFS kernel modules via DKMS may take several minutes.${NC}"
read -r -p "Install ZFS utilities now? (y/n) [y]: " inst_zfs
inst_zfs=${inst_zfs:-y}

if [[ "$inst_zfs" =~ ^[Yy]$ ]]; then
    echo "--> Installing ZFS packages..."
    apt-get install -y linux-headers-amd64 zfs-dkms zfsutils-linux
    
    echo "--> Loading ZFS kernel module..."
    modprobe zfs || { echo -e "${RED}Error loading ZFS module. Reboot may be required.${NC}"; exit 1; }
    echo -e "${GREEN}✔ ZFS installed and loaded.${NC}"
else
    echo -e "${RED}Aborted: ZFS setup cannot proceed.${NC}"
    exit 1
fi
