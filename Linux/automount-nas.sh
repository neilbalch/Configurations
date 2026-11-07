#!/usr/bin/env bash

setup_autofs_nas() {
    local target_host="rpi4b-nas.local"
    local share_path="NAS Primary"
    local creds_file="/etc/smbcredentials"
    local auto_master="/etc/auto.master"
    local auto_map="/etc/auto.nas"
    
    # Identify the current logged-in user's UID and GID
    local current_uid
    local current_gid
    current_uid=$(id -u "${SUDO_USER:-$USER}")
    current_gid=$(id -g "${SUDO_USER:-$USER}")

    echo "=== Autofs SMB Auto-Mount Setup ==="

    # 1. Ensure required packages are installed
    if ! command -v automount &>/dev/null || ! command -v mount.cifs &>/dev/null; then
        echo "[*] Installing autofs and cifs-utils..."
        sudo apt update && sudo apt install -y autofs cifs-utils
    fi

    # 2. Prompt for SMB credentials securely
    echo ""
    read -rp "Enter SMB Username: " smb_user
    read -srp "Enter SMB Password: " smb_pass
    echo ""

    if [[ -z "$smb_user" || -z "$smb_pass" ]]; then
        echo "[!] Error: Username and password cannot be empty."
        return 1
    fi

    # 3. Create secure credentials file
    echo "[*] Saving credentials to $creds_file..."
    sudo bash -c "cat <<EOF > $creds_file
username=$smb_user
password=$smb_pass
EOF"
    sudo chmod 600 "$creds_file"

    # 4. Configure /etc/auto.master
    if ! grep -q "/mnt /etc/auto.nas" "$auto_master"; then
        echo "[*] Updating $auto_master..."
        echo "/mnt /etc/auto.nas --timeout=60 --ghost" | sudo tee -a "$auto_master" > /dev/null
    fi

    # 5. Create the mapping entry in /etc/auto.nas
    # Handles space in 'NAS Primary' by escaping it as 'NAS\ Primary' in the map key
    echo "[*] Creating map entry in $auto_map..."
    sudo bash -c "cat <<EOF > $auto_map
NAS\\ Primary -fstype=cifs,credentials=$creds_file,uid=$current_uid,gid=$current_gid,iocharset=utf8,noperm ://$target_host/$share_path
EOF"

    # 6. Restart Autofs service
    echo "[*] Restarting autofs service..."
    sudo systemctl restart autofs
    sudo systemctl enable autofs

    # 7. Test mount connection
    echo "[*] Testing access at /mnt/NAS Primary..."
    if ls "/mnt/NAS Primary" &>/dev/null; then
        echo "[✓] SMB share successfully mounted and ready at /mnt/NAS Primary"
    else
        echo "[!] Warning: Directory accessed, but could not list contents. Check host reachability or credentials."
    fi
}

# Run the function
setup_autofs_nas
