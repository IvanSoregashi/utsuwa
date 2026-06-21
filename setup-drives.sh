#!/bin/bash
# ==============================================================================
# Utsuwa: Interactive Disk Setup Wizard (with Rich Scan Diagnostics)
# This script scans for unused block devices and guides the user through setting
# up either an Ext4 single partition or a ZFS storage pool (Single or Mirror).
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

# --- Root Privilege Check ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run with root privileges (sudo).${NC}"
    echo "Please execute: sudo $0"
    exit 1
fi

# Locate the active system user (to assign folder ownership later)
SYS_USER=${SUDO_USER:-$(id -un 1000 2>/dev/null || echo "$USER")}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPERS_DIR="${SCRIPT_DIR}/helpers"

# Ensure helpers directory exists
mkdir -p "$HELPERS_DIR"

# --- Helper Functions ---

# Perform full analysis on a disk and populate reasons if not suitable
analyze_disk_suitability() {
    local disk_name="$1" # e.g. nvme0n1 or sda
    local dev_path="/dev/${disk_name}"
    local -n reasons_arr=$2
    
    # 1. Check if the disk itself or any partition under it is currently mounted
    local active_mounts
    active_mounts=$(lsblk -no MOUNTPOINT "$dev_path" 2>/dev/null | grep -v '^$' || true)
    if [ -n "$active_mounts" ]; then
        local formatted_mounts
        formatted_mounts=$(echo "$active_mounts" | paste -sd, -)
        reasons_arr+=("Device or child partition is actively mounted at: ${formatted_mounts}")
    fi
    
    # 2. Check if any partition of this disk is mounted on system-critical paths like / or /boot
    local mps
    mps=$(lsblk -rno MOUNTPOINT "$dev_path" 2>/dev/null | grep -v '^$' || true)
    for mp in $mps; do
        if [ "$mp" = "/" ]; then
            reasons_arr+=("Contains the active root filesystem (/)")
        elif [ "$mp" = "/boot" ]; then
            reasons_arr+=("Contains the active system boot directory (/boot)")
        elif [[ "$mp" == /boot/* ]]; then
            reasons_arr+=("Contains system bootloader partition (${mp})")
        fi
    done
    
    # 3. Check if it's already part of a ZFS pool
    local fstypes
    fstypes=$(lsblk -no FSTYPE "$dev_path" 2>/dev/null | grep -v '^$' || true)
    if echo "$fstypes" | grep -q 'zfs_member'; then
        reasons_arr+=("ZFS member signature detected (belongs to a pool)")
    fi
    if command -v zpool &>/dev/null; then
        if zpool status -v 2>/dev/null | grep -q "$disk_name"; then
            reasons_arr+=("Device is claimed by an active ZFS pool")
        fi
    fi
    
    # 4. Check for swap space
    if echo "$fstypes" | grep -q 'swap'; then
        reasons_arr+=("Contains virtual memory swap space")
    fi
    
    # 5. Filter out read-only devices
    if [ -f "/sys/block/${disk_name}/ro" ]; then
        if [ "$(cat "/sys/block/${disk_name}/ro")" = "1" ]; then
            reasons_arr+=("Device is write-protected / read-only")
        fi
    fi
    
    # 6. Filter out virtual or bootloader/hardware partitions/special disks
    if [[ "$disk_name" =~ ^loop ]]; then
        reasons_arr+=("Virtual loopback device")
    fi
    if [[ "$disk_name" =~ ^ram ]]; then
        reasons_arr+=("System RAM disk")
    fi
    if [[ "$disk_name" =~ ^dm- ]]; then
        reasons_arr+=("Device Mapper block volume (LVM, LUKS, or mdadm)")
    fi
    if [[ "$disk_name" =~ ^md ]]; then
        reasons_arr+=("Software RAID (mdadm) volume")
    fi
    if [[ "$disk_name" =~ boot[0-9]$ ]]; then
        reasons_arr+=("Hardware bootloader partition (mmcblk boot layer)")
    fi
}

# Draw beautiful header
print_header() {
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}                     UTSUWA DISK SETUP WIZARD                         ${NC}"
    echo -e "      Guides you through setting up unmounted NVMe/SATA drives.      "
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "Detected active user: ${GREEN}${SYS_USER}${NC}"
    echo ""
}

# Scan and print detailed diagnostics for EVERY disk on the system
run_storage_diagnostics() {
    local -n suitable_ref=$1
    suitable_ref=()
    
    echo -e "${BOLD}[SCAN DIAGNOSTICS] Evaluating system storage devices...${NC}"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    
    # Loop over all block devices of type disk
    # We use mapfile to safely parse line-by-line
    local raw_disks
    mapfile -t raw_disks < <(lsblk -pdno NAME,SIZE,TYPE 2>/dev/null | grep -w 'disk' || true)
    
    for row in "${raw_disks[@]}"; do
        [ -z "$row" ] && continue
        
        # Read fields: path, size, type
        local dev_path size type
        read -r dev_path size type <<< "$row"
        local dev_name
        dev_name=$(basename "$dev_path")
        
        local model
        model=$(lsblk -dno MODEL "$dev_path" 2>/dev/null | xargs || echo "Unknown Model")
        
        # Evaluate suitability
        local reasons=()
        analyze_disk_suitability "$dev_name" reasons
        
        echo -e "Evaluating ${CYAN}/dev/${dev_name}${NC} [${size}] - ${model}:"
        
        if [ ${#reasons[@]} -eq 0 ]; then
            echo -e "  --> Status: ${GREEN}${BOLD}✔ SUITABLE${NC} (Unused & ready for provisioning)"
            # Save to suitable list
            suitable_ref+=("${dev_name};${size};${model}")
        else
            echo -e "  --> Status: ${RED}${BOLD}✘ NOT SUITABLE${NC}"
            echo -e "  --> Reason(s):"
            for r in "${reasons[@]}"; do
                echo -e "      * ${r}"
            done
        fi
        echo ""
    done
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo ""
}

# Display menu of available disks
display_suitable_disks() {
    local -n disk_arr=$1
    echo -e "${BOLD}Suitable / Ready-to-use Disks Found:${NC}"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    printf "  %-4s  %-12s  %-10s  %-30s\n" "ID" "Device Name" "Size" "Model / Hardware Details"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    
    local idx=1
    for item in "${disk_arr[@]}"; do
        IFS=';' read -r name size model <<< "$item"
        printf "  %-4d  %-12s  %-10s  %-30s\n" "$idx" "/dev/$name" "$size" "$model"
        idx=$((idx + 1))
    done
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo ""
}

# --- Main Logic Loop ---

while true; do
    print_header

    # Run diagnostics and gather suitable disks
    suitable_disks=()
    run_storage_diagnostics suitable_disks
    num_disks=${#suitable_disks[@]}

    if [ "$num_disks" -eq 0 ]; then
        echo -e "${YELLOW}No unused or unmounted physical disks detected on this system.${NC}"
        echo "Please make sure your drives are connected and not currently in use."
        echo ""
        read -r -p "Press Enter to exit or try scanning again..." _
        exit 0
    fi

    display_suitable_disks suitable_disks

    echo -e "${BOLD}What would you like to configure?${NC}"
    echo "  1) Set up an Ext4 Partition (Single disk - great for bulk/unencrypted storage)"
    echo "  2) Set up a ZFS Storage Pool (Supports mirrors or single disks)"
    echo "  3) Rescan Disks"
    echo "  4) Exit"
    echo ""
    read -r -p "Select option [1-4]: " menu_choice

    case "$menu_choice" in
        1)
            # Setup Ext4 Partition
            echo ""
            echo -e "${CYAN}--> Preparing Ext4 Partition Setup...${NC}"
            read -r -p "Select a disk by ID [1-${num_disks}]: " disk_id
            
            if ! [[ "$disk_id" =~ ^[0-9]+$ ]] || [ "$disk_id" -lt 1 ] || [ "$disk_id" -gt "$num_disks" ]; then
                echo -e "${RED}Invalid selection.${NC}"
                read -r -p "Press Enter to return to main menu..." _
                continue
            fi
            
            selected_disk_entry="${suitable_disks[$((disk_id - 1))]}"
            IFS=';' read -r selected_disk _ model <<< "$selected_disk_entry"
            
            # Execute Ext4 helper script
            if [ -f "${HELPERS_DIR}/setup-ext4.sh" ]; then
                echo -e "${CYAN}--> Executing setup-ext4.sh...${NC}"
                bash "${HELPERS_DIR}/setup-ext4.sh" "$SYS_USER" "$selected_disk"
            else
                echo -e "${RED}Error: setup-ext4.sh helper script not found in helpers/ directory.${NC}"
            fi
            read -r -p "Press Enter to return to main menu..." _
            ;;
        2)
            # Setup ZFS Pool
            echo ""
            echo -e "${CYAN}--> Preparing ZFS Storage Pool Setup...${NC}"
            echo "Choose ZFS configuration type:"
            echo "  1) Single Disk Pool (No redundancy)"
            echo "  2) Mirrored Pool (Requires 2 disks of equal size recommended)"
            echo "  3) Return to Main Menu"
            echo ""
            read -r -p "Select ZFS layout [1-3]: " zfs_choice
            
            if [ "$zfs_choice" = "1" ]; then
                read -r -p "Select a disk by ID for the ZFS pool [1-${num_disks}]: " disk_id
                if ! [[ "$disk_id" =~ ^[0-9]+$ ]] || [ "$disk_id" -lt 1 ] || [ "$disk_id" -gt "$num_disks" ]; then
                    echo -e "${RED}Invalid selection.${NC}"
                    read -r -p "Press Enter to return to main menu..." _
                    continue
                fi
                selected_disk_entry="${suitable_disks[$((disk_id - 1))]}"
                IFS=';' read -r selected_disk _ model <<< "$selected_disk_entry"
                
                # Execute ZFS helper script for single disk
                if [ -f "${HELPERS_DIR}/setup-zfs.sh" ]; then
                    echo -e "${CYAN}--> Executing setup-zfs.sh...${NC}"
                    bash "${HELPERS_DIR}/setup-zfs.sh" "$SYS_USER" "single" "$selected_disk"
                else
                    echo -e "${RED}Error: setup-zfs.sh helper script not found in helpers/ directory.${NC}"
                fi
                
            elif [ "$zfs_choice" = "2" ]; then
                if [ "$num_disks" -lt 2 ]; then
                    echo -e "${RED}Error: A mirrored pool requires at least 2 available disks.${NC}"
                    read -r -p "Press Enter to return to main menu..." _
                    continue
                fi
                
                read -r -p "Select the FIRST disk by ID [1-${num_disks}]: " disk1_id
                read -r -p "Select the SECOND disk by ID [1-${num_disks}]: " disk2_id
                
                if [ "$disk1_id" = "$disk2_id" ]; then
                    echo -e "${RED}Error: You must select two distinct disks to build a mirror.${NC}"
                    read -r -p "Press Enter to return to main menu..." _
                    continue
                fi
                
                if ! [[ "$disk1_id" =~ ^[0-9]+$ ]] || [ "$disk1_id" -lt 1 ] || [ "$disk1_id" -gt "$num_disks" ] || \
                   ! [[ "$disk2_id" =~ ^[0-9]+$ ]] || [ "$disk2_id" -lt 1 ] || [ "$disk2_id" -gt "$num_disks" ]; then
                    echo -e "${RED}Invalid selection.${NC}"
                    read -r -p "Press Enter to return to main menu..." _
                    continue
                fi
                
                disk1_entry="${suitable_disks[$((disk1_id - 1))]}"
                disk2_entry="${suitable_disks[$((disk2_id - 1))]}"
                IFS=';' read -r disk1 _ model1 <<< "$disk1_entry"
                IFS=';' read -r disk2 _ model2 <<< "$disk2_entry"
                
                # Execute ZFS helper script for mirror
                if [ -f "${HELPERS_DIR}/setup-zfs.sh" ]; then
                    echo -e "${CYAN}--> Executing setup-zfs.sh...${NC}"
                    bash "${HELPERS_DIR}/setup-zfs.sh" "$SYS_USER" "mirror" "$disk1" "$disk2"
                else
                    echo -e "${RED}Error: setup-zfs.sh helper script not found in helpers/ directory.${NC}"
                fi
            else
                continue
            fi
            
            read -r -p "Press Enter to return to main menu..." _
            ;;
        3)
            # Rescan
            continue
            ;;
        4)
            echo "Exiting wizard. Goodbye!"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option selected. Please choose 1, 2, 3, or 4.${NC}"
            sleep 2
            ;;
    esac
done
