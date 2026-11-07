#!/usr/bin/env bash

set -e

BACKUP_DIR="/mnt/nas-primary/Resolve Project Library/Resolve_DB_Backups"
BACKUP_SCRIPT="/usr/local/bin/backup_postgres.sh"

echo "=== DaVinci Resolve PostgreSQL & Backup Setup ==="

# 1. Install PostgreSQL
echo "[*] Installing PostgreSQL..."
sudo apt update && sudo apt install -y postgresql postgresql-contrib

# 2. Configure Database User & Superuser Permissions
echo "[*] Configuring 'postgres' user for DaVinci Resolve..."
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'DaVinci';"
sudo -u postgres psql -c "ALTER USER postgres WITH SUPERUSER;"

# 3. Configure Remote Network Connections (IPv4 + IPv6)
echo "[*] Enabling IPv4 and IPv6 network access in postgresql.conf and pg_hba.conf..."

PG_CONF=$(find /etc/postgresql/ -name "postgresql.conf" | head -n 1)
PG_HBA=$(find /etc/postgresql/ -name "pg_hba.conf" | head -n 1)

# Set listen_addresses to '*'
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" "$PG_CONF"
sudo sed -i "s/listen_addresses = 'localhost'/listen_addresses = '*'/g" "$PG_CONF"

# Add IPv4 subnet access rule if not already present
if ! grep -q "0.0.0.0/0" "$PG_HBA"; then
    echo "host    all             all             0.0.0.0/0               md5" | sudo tee -a "$PG_HBA" > /dev/null
fi

# Add IPv6 subnet access rule if not already present (fixes Windows mDNS fe80::/IPv6 connection errors)
if ! grep -q "::/0" "$PG_HBA"; then
    echo "host    all             all             ::/0                    md5" | sudo tee -a "$PG_HBA" > /dev/null
fi

echo "[*] Restarting PostgreSQL service..."
sudo systemctl restart postgresql

# 4. Create the Daily Backup Script
echo "[*] Creating backup script at $BACKUP_SCRIPT..."

sudo bash -c "cat <<'EOF' > $BACKUP_SCRIPT
#!/usr/bin/env bash

# ==============================================================================
# HOW TO RESTORE A BACKUP:
# 1. Stop DaVinci Resolve on all connected machines.
# 2. Locate your desired backup file (.sql.gz) in the backup directory:
#    /mnt/nas-primary/Resolve Project Library/Resolve_DB_Backups/
# 3. Run the following command in terminal (replace FILENAME with your backup file):
#    gunzip -c \"/mnt/nas-primary/Resolve Project Library/Resolve_DB_Backups/FILENAME.sql.gz\" | sudo -u postgres psql
# 4. Open DaVinci Resolve and reconnect to the PostgreSQL network library.
# ==============================================================================

BACKUP_DIR=\"/mnt/nas-primary/Resolve Project Library/Resolve_DB_Backups\"
TIMESTAMP=\$(date +\"%Y-%m-%d_%H%M%S\")
BACKUP_FILE=\"\${BACKUP_DIR}/postgres_backup_\${TIMESTAMP}.sql.gz\"
RETENTION_DAYS=14

# Ensure target backup folder exists
mkdir -p \"\${BACKUP_DIR}\"

# Dump all PostgreSQL databases and compress
sudo -u postgres pg_dumpall | gzip > \"\${BACKUP_FILE}\"

# Remove backups older than 14 days
find \"\${BACKUP_DIR}\" -name \"postgres_backup_*.sql.gz\" -type f -mtime +\${RETENTION_DAYS} -delete
EOF"

sudo chmod +x "$BACKUP_SCRIPT"

# 5. Add Daily Cron Job at 2:00 AM
echo "[*] Configuring cron job for daily 2:00 AM backups..."
CRON_JOB="0 2 * * * $BACKUP_SCRIPT > /dev/null 2>&1"

(sudo crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT"; echo "$CRON_JOB") | sudo crontab -

# 6. Run an Initial Backup Test
echo "[*] Testing backup execution..."
sudo "$BACKUP_SCRIPT"

if [ -f "$BACKUP_SCRIPT" ]; then
    echo "[✓] Setup complete!"
    echo "======================================================================"
    echo "PostgreSQL Address: rpi4b-nas.local (or your Pi's IP)"
    echo "Username:           postgres"
    echo "Password:           DaVinci"
    echo "Backup Location:    $BACKUP_DIR"
    echo "======================================================================"
fi
