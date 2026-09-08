#!/bin/bash
# ==============================================================================
# Automated Setup Script: High-Performance Google Drive 2-Way Sync
# ==============================================================================

set -euo pipefail

# --- Configuration Variables ---
REMOTE_NAME="gdrive"
LOCAL_DIR="$HOME/GoogleDrive"
SCRIPT_DIR="$HOME/.local/bin"
SCRIPT_PATH="$SCRIPT_DIR/gdrive-sync.sh"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
LOG_DIR="$HOME/.local/share/rclone/logs"
AUDIT_LOG="$LOG_DIR/audit.log"
CHANGES_LOG="$LOG_DIR/changes.log"

echo "=== Google Drive Fast 2-Way Sync Setup ==="
echo ""

# --- Step 1: Install Dependencies ---
echo "[1/6] Installing required dependencies (rclone, inotify-tools, util-linux)..."
sudo apt update && sudo apt install -y rclone inotify-tools util-linux

# --- Step 2: Configure Rclone Remote ---
echo ""
echo "[2/6] Checking Rclone configuration..."
if ! rclone listremotes | grep -q "^${REMOTE_NAME}:$"; then
    echo "Remote '${REMOTE_NAME}:' not found."
    echo "================================================================="
    echo " RCLONE CONFIGURATION GUIDANCE:"
    echo "================================================================="
    echo " 1. Type 'n' for 'New remote'"
    echo " 2. Name: 'gdrive'"
    echo " 3. Storage Type: Choose 'Google Drive' (type 'drive' or its number)"
    echo " 4. Client ID / Secret: Enter your custom ID/Secret (or hit Enter for default)"
    echo " 5. Scope: Select '1' (drive - Full access all files)"
    echo " 6. Service Account File: Hit Enter (leave blank)"
    echo " 7. Advanced Config: Type 'n' (No)"
    echo " 8. Auto Config: Type 'y' and authenticate in your web browser"
    echo " 9. Shared Drive: Type 'n' (No)"
    echo "10. Keep remote: Type 'y' (Yes)"
    echo "================================================================="
    echo ""
    read -rp "Press Enter to launch 'rclone config'..."
    rclone config
else
    echo "Remote '${REMOTE_NAME}:' already exists. Skipping config wizard."
fi

if ! rclone listremotes | grep -q "^${REMOTE_NAME}:$"; then
    echo "ERROR: Remote '${REMOTE_NAME}:' was not configured. Exiting."
    exit 1
fi

mkdir -p "$LOCAL_DIR" "$LOG_DIR" "$SCRIPT_DIR" "$SYSTEMD_USER_DIR"

# --- Step 3: Stop Existing Background Services (Guard) ---
echo ""
echo "[3/6] Stopping existing systemd services (if running)..."
systemctl --user stop gdrive-watcher.service gdrive-poll.timer gdrive-poll.service 2>/dev/null || true
rm -f /tmp/gdrive_bisync.lock 2>/dev/null || true
rm -f "$HOME/.cache/rclone/bisync/"*.lck 2>/dev/null || true
echo "Existing background jobs stopped and locks cleared."

# --- Step 4: Create Sync Script with Native Audit Logging & Background Delta Tail ---
echo ""
echo "[4/6] Writing sync engine script to ${SCRIPT_PATH}..."

cat << 'EOF' > "$SCRIPT_PATH"
#!/bin/bash
LOCAL_DIR="$HOME/GoogleDrive"
REMOTE="gdrive:"
LOCK_FILE="/tmp/gdrive_bisync.lock"
LOG_DIR="$HOME/.local/share/rclone/logs"
AUDIT_LOG="$LOG_DIR/audit.log"
CHANGES_LOG="$LOG_DIR/changes.log"

mkdir -p "$LOG_DIR"

do_sync() {
    # Blocking kernel-level lock using flock (queues execution until active pass completes)
    (
        flock 200

        # Automatically clear lingering rclone cache locks if no bisync process is active
        if ! pgrep -f "rclone bisync" > /dev/null; then
            rm -f "$HOME/.cache/rclone/bisync/"*.lck 2>/dev/null
        fi

        # Use native rclone --log-file to guarantee standard YYYY/MM/DD HH:MM:SS timestamps
        rclone bisync "$REMOTE" "$LOCAL_DIR"             --drive-skip-gdocs             --drive-skip-shortcuts             --fast-list             --checkers 32             --transfers 8             --drive-list-chunk 1000             --drive-chunk-size 128M             --buffer-size 64M             --log-level INFO             --log-file="$AUDIT_LOG"             --stats 0 &
        
        RCLONE_PID=$!

        # Stream file deltas from the official audit log into changes.log in real-time
        tail -n 0 -f "$AUDIT_LOG" --pid="$RCLONE_PID" | grep -E --line-buffered "(Copied|Deleted|Queue copy|Queue delete|Failed|ERROR)" >> "$CHANGES_LOG" &

        wait $RCLONE_PID
    ) 200>"$LOCK_FILE"
}

# Single execution mode (used by gdrive-poll systemd service)
if [ "${1:-}" = "--once" ]; then
    do_sync
    exit 0
fi

# Initial baseline sync on service start
do_sync

# Continuous local filesystem watcher with 5-second debounce
inotifywait -m -r -e modify,create,delete,move "$LOCAL_DIR" --exclude '\.rclone' | while read -r path action file; do
    sleep 5
    do_sync
done
EOF

chmod +x "$SCRIPT_PATH"

# --- Step 5: Perform Baseline Resync ---
echo ""
echo "[5/6] Executing initial baseline resync..."
echo "Running fast baseline sync ('rclone bisync --resync')..."

set +e
rclone bisync "${REMOTE_NAME}:" "$LOCAL_DIR"     --resync     --drive-skip-gdocs     --drive-skip-shortcuts     --fast-list     --checkers 32     --transfers 8     --drive-list-chunk 1000     --drive-chunk-size 128M     --buffer-size 64M     --log-file="$AUDIT_LOG"     --log-level INFO     --stats 0
SET_STATUS=$?
set -e

if [ $SET_STATUS -ne 0 ]; then
    echo "Notice: Baseline resync exited with code $SET_STATUS. Proceeding to service activation..."
else
    echo "Initial baseline sync completed successfully!"
fi

# --- Step 6: Create and Enable Systemd Units ---
echo ""
echo "[6/6] Creating and activating systemd user services..."

# 1. Watcher Service (runs inotify loop)
cat << EOF > "$SYSTEMD_USER_DIR/gdrive-watcher.service"
[Unit]
Description=Google Drive Realtime Local Watcher
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/gdrive-sync.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

# 2. Polling Service (calls gdrive-sync.sh with lock file protection)
cat << EOF > "$SYSTEMD_USER_DIR/gdrive-poll.service"
[Unit]
Description=Google Drive Cloud Sync Check

[Service]
Type=oneshot
ExecStart=%h/.local/bin/gdrive-sync.sh --once
EOF

# 3. Polling Timer (runs every 1 minute)
cat << EOF > "$SYSTEMD_USER_DIR/gdrive-poll.timer"
[Unit]
Description=Check Google Drive for remote updates every 1 minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload daemon configuration and restart services cleanly
systemctl --user daemon-reload
systemctl --user enable --now gdrive-watcher.service
systemctl --user enable --now gdrive-poll.timer
systemctl --user restart gdrive-watcher.service gdrive-poll.service

echo ""
echo "=== Setup Complete! ==="
echo "Performance & Safeguard optimizations applied:"
echo "  * Native Timestamp Logging: Uses rclone --log-file to guarantee standard date/time stamps"
echo "  * Concurrent Delta Tailing: Streams file changes to changes.log via background tail"
echo "  * Dual Log Streams:         Full audit log -> ${AUDIT_LOG}"
echo "                              Filtered changes -> ${CHANGES_LOG}"
echo "  * Mixed Workload Tuning:    --transfers 8, --checkers 32, --drive-chunk-size 128M, --buffer-size 64M"
echo "  * Directory Listing:        --drive-list-chunk 1000 & --fast-list enabled"
echo "  * Timer Frequency:          1-minute polling interval"
echo "  * Blocking Lock Queue:      Queues overlapping sync operations cleanly using flock"
echo ""
echo "Useful commands:"
echo "  * Tail changes log:          tail -f ~/.local/share/rclone/logs/changes.log"
echo "  * Tail full audit log:       tail -f ~/.local/share/rclone/logs/audit.log"
echo "  * Check watcher status:      systemctl --user status gdrive-watcher.service"
echo "  * Check timer status:        systemctl --user status gdrive-poll.timer"
