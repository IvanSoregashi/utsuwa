#!/bin/bash
# ==============================================================================
# Utsuwa: Platform Directory & Application Setup Orchestrator
# Sets up standardized system mount layers (/srv/*), checks mount point safety,
# and interactively initializes application directory trees.
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

# --- 1. Argument Validation ---
if [ "$#" -ne 2 ]; then
    echo -e "${RED}Error: Missing required paths.${NC}"
    echo "Usage: $0 <path_to_secure_volume> <path_to_unencrypted_volume>"
    echo "Example: $0 /vault/secure /bulk"
    exit 1
fi

# Check if the raw directories even exist on the system
if [ ! -d "$1" ] || [ ! -d "$2" ]; then
    echo -e "${RED}Error: One or both of the provided directory paths do not exist on the filesystem.${NC}"
    echo "Please ensure the storage pools are mounted."
    exit 1
fi

SECURE_PATH=$(realpath "$1")
DATA_PATH=$(realpath "$2")

echo -e "${CYAN}======================================================================${NC}"
echo -e "${BOLD}                 UTSUWA DIRECTORY & APP INITIALIZATION                ${NC}"
echo -e "Secure Path: ${GREEN}$SECURE_PATH${NC}"
echo -e "Data Path:   ${GREEN}$DATA_PATH${NC}"
echo -e "${CYAN}======================================================================${NC}"

# Define the user to own all directories (UID/GID 1000)
# 1. Try to find the user who typed sudo
# 2. Fall back to the user with UID 1000 (standard primary user)
# 3. Fall back to the active user ($USER)
SYS_USER=${SUDO_USER:-$(id -un 1000 2>/dev/null || echo "$USER")}
echo -e "Detected active system user: ${GREEN}$SYS_USER${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_HELPERS_DIR="${SCRIPT_DIR}/helpers/apps"

# --- 2. Smart, Universal Mount Verification ---
check_mount_safety() {
    local target_path="$1"
    local path_type="$2"

    # A. If it is currently mounted (via standard mount or ZFS), it is 100% safe.
    if mountpoint -q "$target_path" || (command -v zfs &>/dev/null && zfs mount | grep -F -q "$target_path"); then
        echo -e "  $path_type path ($target_path) is actively mounted. ${GREEN}Safe.${NC}"
        return 0
    fi

    # B. If not mounted, check if the system expects it to be a mount point.
    # Check /etc/fstab
    if grep -F -q "$target_path" /etc/fstab; then
        echo -e "${RED}CRITICAL ERROR: $path_type path ($target_path) is defined in /etc/fstab but is NOT mounted!${NC}"
        echo "Running this script now would write files directly to your system drive."
        exit 1
    fi

    # Check ZFS datasets (if ZFS is installed)
    if command -v zfs &>/dev/null && zfs list -H -o mountpoint | grep -x -q "$target_path"; then
        echo -e "${RED}CRITICAL ERROR: $path_type path ($target_path) is an unmounted ZFS dataset!${NC}"
        echo "Please unlock and mount your ZFS pool first."
        exit 1
    fi

    # C. If not mounted and not expected to be a mount (e.g., on a VPS),
    # check if the directory is writeable.
    if [ -w "$target_path" ]; then
        echo -e "  $path_type path ($target_path) is a standard writeable directory. ${GREEN}Safe.${NC}"
        return 0
    else
        echo -e "${RED}ERROR: $path_type path ($target_path) is not writeable by this script.${NC}"
        exit 1
    fi
}

echo "--> Verifying drive mount safety..."
check_mount_safety "$SECURE_PATH" "Secure"
check_mount_safety "$DATA_PATH" "Data"


# --- 3. Setup Standardized /srv Mounts ---
echo -e "\n--> Preparing standardized /srv bind mounts..."
sudo mkdir -p /srv/encrypted
sudo mkdir -p /srv/data

# Helper function to append to /etc/fstab safely if the mount point isn't already mapped
add_fstab_entry() {
    local src="$1"
    local dst="$2"
    if ! grep -qs "$dst" /etc/fstab; then
        echo "Appending fstab bind mount for $dst..."
        echo "$src    $dst    none    bind,nofail    0    0" | sudo tee -a /etc/fstab > /dev/null
    else
        echo "fstab entry for $dst already exists. Skipping."
    fi
}

add_fstab_entry "$SECURE_PATH" "/srv/encrypted"
add_fstab_entry "$DATA_PATH" "/srv/data"

# --- 4. Mount the new paths (Idempotent check) ---
echo "--> Mounting standardized /srv layers..."

if ! mountpoint -q /srv/encrypted; then
    sudo mount /srv/encrypted || echo -e "${YELLOW}Warning: /srv/encrypted could not mount automatically (is the pool locked?)${NC}"
else
    echo "  /srv/encrypted is already mounted. Skipping."
fi

if ! mountpoint -q /srv/data; then
    sudo mount /srv/data || echo -e "${YELLOW}Warning: /srv/data could not mount.${NC}"
else
    echo "  /srv/data is already mounted. Skipping."
fi


# --- 5. Interactive Application Setup Selection ---
run_app_setup() {
    local script_path="$1"
    local script_name
    script_name=$(basename "$script_path" .sh)

    echo -e "\n${CYAN}------------------------------------------------------------${NC}"
    echo -e "Executing: ${BOLD}${script_name^^}${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    bash "$script_path" "$SECURE_PATH" "$DATA_PATH" "$SYS_USER"
}

if [ -d "$APPS_HELPERS_DIR" ]; then
    # Find all helper scripts in the apps folder
    mapfile -t app_scripts < <(find "$APPS_HELPERS_DIR" -type f -name "*.sh" | sort)

    if [ ${#app_scripts[@]} -eq 0 ]; then
        echo -e "${YELLOW}Warning: No application setup scripts found under ${APPS_HELPERS_DIR}.${NC}"
    else
        echo -e "\n${BOLD}Application Selection:${NC}"
        declare -a pretty_names
        for i in "${!app_scripts[@]}"; do
            script="${app_scripts[i]}"
            script_name=$(basename "$script" .sh)
            # format name nicely for printing (e.g. net-library -> Net Library)
            pretty_name=$(echo "$script_name" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')
            pretty_names[i]="$pretty_name"
            echo -e "  $((i + 1))) $pretty_name"
        done
        echo -e "  ${BOLD}A) ALL Applications${NC}"
        echo -e "  ${BOLD}S) SKIP (Base storage layers only)${NC}"
        echo ""

        while true; do
            read -r -p "Select apps [1-${#app_scripts[@]}], 'A' for all, or 'S' to skip: " user_input
            
            # Handle empty or Skip
            if [ -z "${user_input// /}" ] || [[ "$user_input" =~ ^[Ss]$ ]]; then
                echo -e "\nSkipping application provisioning as requested."
                break
            fi

            # Handle ALL
            if [[ "$user_input" =~ ^[Aa]$ ]]; then
                echo -e "\n--> Initializing ALL applications..."
                for script in "${app_scripts[@]}"; do
                    run_app_setup "$script"
                done
                break
            fi

            # Handle Selection
            cleaned_input="${user_input//,/ }"
            selected_indices=()
            invalid_input=false
            
            for choice in $cleaned_input; do
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#app_scripts[@]}" ]; then
                    selected_indices+=("$((choice - 1))")
                else
                    echo -e "${RED}Invalid selection: $choice${NC}"
                    invalid_input=true
                fi
            done

            if [ "$invalid_input" = true ]; then
                echo -e "Please try again with valid numbers, 'A', or 'S'.\n"
                continue
            fi

            # Deduplicate indices
            declare -A seen
            dedup_indices=()
            for idx in "${selected_indices[@]}"; do
                if [ -z "${seen[$idx]+_}" ]; then
                    seen[$idx]=1
                    dedup_indices+=("$idx")
                fi
            done

            # Sort indices to run apps in alphabetical/listed order
            sorted_indices=($(for idx in "${dedup_indices[@]}"; do echo "$idx"; done | sort -n))

            echo -e "\nYou selected:"
            for idx in "${sorted_indices[@]}"; do
                echo -e "  - ${pretty_names[idx]}"
            done
            echo ""

            read -r -p "Proceed with initializing these applications? (y/n) [y]: " confirm_install
            confirm_install=${confirm_install:-y}
            if [[ "$confirm_install" =~ ^[Yy]$ ]]; then
                echo -e "\n--> Initializing chosen applications..."
                for idx in "${sorted_indices[@]}"; do
                    run_app_setup "${app_scripts[idx]}"
                done
                break
            else
                echo -e "Selection discarded.\n"
            fi
        done
    fi
else
    echo -e "${YELLOW}Warning: Application helpers directory does not exist at ${APPS_HELPERS_DIR}.${NC}"
fi

# Align base permissions as fallback
echo -e "\n--> Aligning system volume permissions..."
sudo chown "${SYS_USER}:${SYS_USER}" "$SECURE_PATH" || true
sudo chown "${SYS_USER}:${SYS_USER}" "$DATA_PATH" || true

echo -e "\n======================================================================"
echo -e "${GREEN}✔ Initialization Complete!${NC}"
echo -e "Standardized system-level mappings:"
echo -e "  /srv/encrypted  -> $SECURE_PATH"
echo -e "  /srv/data       -> $DATA_PATH"
echo -e "======================================================================\n"
