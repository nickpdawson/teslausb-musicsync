#!/bin/bash

# TeslaUSB Music Sync Script with Home Assistant Integration
# Version 3.0 - Two-Pass Sync (M4A preferred, FLAC fallback)
set -e

SCRIPT_VERSION="3.0-HA"
LOG_FILE="/mutable/music_sync.log"
LOCK_FILE="/mutable/music_sync.lock"
MUSIC_MOUNT="/var/www/html/fs/Music"
DEST_PATH="$MUSIC_MOUNT"

# Home Assistant Integration
HA_TOKEN="YOUR_HA_LONG_LIVED_ACCESS_TOKEN"
HA_URL="https://YOUR_HA_INSTANCE:8123"  # Update with your HA URL
HA_ENTITY="sensor.teslausb_music_sync"
STATUS_FILE="/mutable/teslausb_status.json"

# Source configuration - UPDATE THESE FOR YOUR SETUP
SOURCE_HOST="YOUR_NAS_HOSTNAME"  # e.g., nas.local or IP address
SOURCE_PATH="/path/to/your/music/"  # Path to music on your NAS/server
SSH_KEY="/root/.ssh/your_nas_key"  # SSH key for NAS access
MAX_RETRIES=3
RETRY_WAIT=300

show_help() {
    echo "TeslaUSB Music Sync Script v${SCRIPT_VERSION}"
    echo ""
    echo "USAGE:"
    echo "    $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "    -h, --help          Show this help message"
    echo "    -p, --print-config  Print configuration and paths"
    echo "    -c, --cleanup-only  Run filename cleanup only"
    echo "    -s, --sync          Run full music sync from NAS"
    echo "    -t, --test          Test configuration and exit"
    echo "    --ha-status         Output status in Home Assistant JSON format"
    echo "    --check-tesla       Check if Tesla is connected via USB"
    echo "    --reboot-after      Reboot system after successful operation"
    echo "    --send-ha-status    Send current status to Home Assistant"
    echo "    --artist ARTIST     Sync specific artist only"
    echo ""
    echo "SYNC BEHAVIOR:"
    echo "    Two-pass sync: M4A/AAC preferred, FLAC as fallback"
    echo "    Pass 1: Sync M4A and AAC files"
    echo "    Pass 2: Sync FLAC only where M4A/AAC missing"
    echo ""
    echo "HOME ASSISTANT INTEGRATION:"
    echo "    Status file:        $STATUS_FILE"
    echo "    HA Entity:          $HA_ENTITY"
    echo ""
    echo "EXAMPLES:"
    echo "    $0 -s                                # Full sync"
    echo "    $0 -s --artist \"Dire Straits\"       # Sync one artist"
    echo "    $0 -s --reboot-after                # Sync and reboot"
    echo "    $0 -c --reboot-after                # Cleanup and reboot"
}

get_tesla_connection_status() {
    # Check if Tesla is connected by examining USB gadget status
    if [ -f "/sys/kernel/config/usb_gadget/teslausb/UDC" ]; then
        local udc_content=$(cat /sys/kernel/config/usb_gadget/teslausb/UDC 2>/dev/null || echo "")
        if [ -n "$udc_content" ] && [ "$udc_content" != "none" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

get_wifi_status() {
    # Check if connected to WiFi (simplified check)
    if ip route | grep -q "default"; then
        echo "true"
    else
        echo "false"
    fi
}

get_sync_state() {
    if [ -f "$LOCK_FILE" ]; then
        echo "syncing"
    elif [ -f "/mutable/music_sync_last_run" ]; then
        local last_run=$(cat /mutable/music_sync_last_run 2>/dev/null || echo "")
        if echo "$last_run" | grep -q "successfully"; then
            echo "completed"
        elif echo "$last_run" | grep -q "failed"; then
            echo "failed"
        else
            echo "idle"
        fi
    else
        echo "idle"
    fi
}

get_disk_usage() {
    if [ -d "$MUSIC_MOUNT" ]; then
        df "$MUSIC_MOUNT" | awk 'NR==2 {gsub(/%/, "", $5); print $5}'
    else
        echo "0"
    fi
}

generate_status_json() {
    local tesla_connected=$(get_tesla_connection_status)
    local wifi_connected=$(get_wifi_status)
    local sync_state=$(get_sync_state)
    local disk_usage=$(get_disk_usage)
    local timestamp=$(date -Iseconds)

    local total_files=0
    local total_artists=0

    if [ -d "$MUSIC_MOUNT" ]; then
        total_files=$(find "$MUSIC_MOUNT" -type f -name "*.flac" -o -name "*.m4a" -o -name "*.aac" | wc -l)
        total_artists=$(find "$MUSIC_MOUNT" -maxdepth 1 -type d ! -name "." ! -name ".." | wc -l)
    fi

    local last_sync=""
    if [ -f "/mutable/music_sync_last_run" ]; then
        last_sync=$(head -1 /mutable/music_sync_last_run | cut -d' ' -f1-2)
    fi

    cat << EOF
{
  "state": "$sync_state",
  "attributes": {
    "tesla_connected": $tesla_connected,
    "wifi_connected": $wifi_connected,
    "music_files": $total_files,
    "total_artists": $total_artists,
    "disk_usage_percent": $disk_usage,
    "last_sync": "$last_sync",
    "script_version": "$SCRIPT_VERSION",
    "timestamp": "$timestamp",
    "friendly_name": "TeslaUSB Music Sync"
  }
}
EOF
}

send_status_to_ha() {
    local status_json=$(generate_status_json)

    # Save to local file for web access
    echo "$status_json" > "$STATUS_FILE"

    # Send to Home Assistant if curl is available
    if command -v curl >/dev/null 2>&1; then
        curl -X POST "$HA_URL/api/states/$HA_ENTITY" \
             -H "Authorization: Bearer $HA_TOKEN" \
             -H "Content-Type: application/json" \
             -d "$status_json" \
             --connect-timeout 5 \
             --max-time 10 \
             --silent >/dev/null 2>&1 || echo "Warning: Could not send status to Home Assistant"
    fi
}

print_config() {
    echo "=== TeslaUSB Music Sync Configuration ==="
    echo "Script Version:    $SCRIPT_VERSION"
    echo "Music Mount:       $MUSIC_MOUNT"
    echo "Mount Exists:      $(test -d "$MUSIC_MOUNT" && echo "YES" || echo "NO")"
    echo "Tesla Connected:   $(get_tesla_connection_status)"
    echo "WiFi Connected:    $(get_wifi_status)"
    echo "Sync State:        $(get_sync_state)"
    echo "Disk Usage:        $(get_disk_usage)%"

    if [ -d "$MUSIC_MOUNT" ]; then
        echo "Total Artists:     $(find "$MUSIC_MOUNT" -maxdepth 1 -type d ! -name "." ! -name ".." | wc -l)"
        echo "Total Files:       $(find "$MUSIC_MOUNT" -type f -name "*.flac" -o -name "*.m4a" -o -name "*.aac" | wc -l)"
    fi

    echo ""
    echo "=== Source Configuration ==="
    echo "Source Host:       $SOURCE_HOST"
    echo "Source Path:       $SOURCE_PATH"
    echo "SSH Key:           $SSH_KEY"
    echo "SSH Key Exists:    $(test -f "$SSH_KEY" && echo "YES" || echo "NO")"

    echo ""
    echo "=== Home Assistant Integration ==="
    echo "HA URL:            $HA_URL"
    echo "HA Entity:         $HA_ENTITY"
    echo "Status File:       $STATUS_FILE"
    echo "Status File Exists: $(test -f "$STATUS_FILE" && echo "YES" || echo "NO")"
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    # Update HA status when logging important events
    case "$1" in
        *"Starting"*|*"completed"*|*"failed"*|*"Cleanup"*|*"Pass 1"*|*"Pass 2"*)
            send_status_to_ha
            ;;
    esac
}

check_connection() {
    ping -c1 -W2 "$SOURCE_HOST" &>/dev/null
}

verify_music_mount() {
    if [ ! -d "$MUSIC_MOUNT" ]; then
        log "ERROR: Music mount point $MUSIC_MOUNT does not exist"
        return 1
    fi

    if ! touch "$MUSIC_MOUNT/.mount_test" 2>/dev/null; then
        log "ERROR: Music mount point $MUSIC_MOUNT is not writable"
        return 1
    fi

    rm -f "$MUSIC_MOUNT/.mount_test"
    log "Music mount point $MUSIC_MOUNT is accessible and writable"
    return 0
}

cleanup_metadata() {
    log "Cleaning up macOS metadata files"
    find "$DEST_PATH" -name '._*' -delete 2>/dev/null || true
    find "$DEST_PATH" -name '.DS_Store' -delete 2>/dev/null || true
    find "$DEST_PATH" -name 'Thumbs.db' -delete 2>/dev/null || true
    find "$DEST_PATH" -name '*.jpg' -delete 2>/dev/null || true
    find "$DEST_PATH" -name '*.txt' -delete 2>/dev/null || true
}

sanitize_filenames() {
    log "Sanitizing filenames and directories for FAT32 compatibility"

    # Fix directory names first
    find "$DEST_PATH" -depth -type d | while IFS= read -r dirname; do
        if [ "$dirname" = "$DEST_PATH" ]; then
            continue
        fi

        parent=$(dirname "$dirname")
        base=$(basename "$dirname")

        # Clean up directory name for FAT32
        newbase=$(echo "$base" | sed 's/^[ ]*//' | sed 's/[ ]*$//' | sed 's/…/_/g')

        # Simple length check
        if [ $(echo -n "$newbase" | wc -c) -gt 200 ]; then
            newbase=$(echo -n "$newbase" | cut -c1-200)
        fi

        newname="$parent/$newbase"

        if [ "$dirname" != "$newname" ] && [ ! -e "$newname" ]; then
            log "Renaming directory: $base -> $newbase"
            mv "$dirname" "$newname" 2>/dev/null || log "Failed to rename directory: $dirname"
        fi
    done

    # Fix file names
    find "$DEST_PATH" -depth -type f | while IFS= read -r fname; do
        dir=$(dirname "$fname")
        base=$(basename "$fname")

        # Clean up filename
        newbase=$(echo "$base" | sed 's/^[ ]*//' | sed 's/[ ]*$//' | sed 's/…/_/g')

        # Simple length check
        if [ $(echo -n "$newbase" | wc -c) -gt 200 ]; then
            newbase=$(echo -n "$newbase" | cut -c1-200)
        fi

        newname="$dir/$newbase"

        if [ "$fname" != "$newname" ] && [ ! -e "$newname" ]; then
            log "Renaming file: $base -> $newbase"
            mv "$fname" "$newname" 2>/dev/null || log "Failed to rename: $fname"
        fi
    done
}

do_sync() {
    local artist_filter="${1:-}"

    log "Starting two-pass music sync from $SOURCE_HOST"
    touch "$LOCK_FILE"

    if ! verify_music_mount; then
        log "Failed to verify music mount"
        rm -f "$LOCK_FILE"
        return 1
    fi

    # Check available space
    available_space=$(df "$MUSIC_MOUNT" | awk 'NR==2 {print $4}')
    log "Available space: ${available_space}KB"

    for attempt in $(seq 1 $MAX_RETRIES); do
        log "Sync attempt $attempt/$MAX_RETRIES"

        if ! check_connection; then
            log "Host $SOURCE_HOST unreachable, retrying in ${RETRY_WAIT}s..."
            sleep $RETRY_WAIT
            continue
        fi

        # Prepare source path
        local source_path="$SOURCE_PATH"
        if [ -n "$artist_filter" ]; then
            source_path="${SOURCE_PATH}${artist_filter}/"
            log "Syncing specific artist: $artist_filter"
        fi

        log "=== PASS 1: Syncing M4A and AAC files (preferred formats) ==="

        # Pass 1: Sync M4A and AAC files first (preferred)
        if timeout 3600 rsync -av \
            --no-group --no-perms --no-owner --no-times \
            --inplace --delete-excluded \
            --iconv=utf8,ascii//TRANSLIT \
            -e "ssh -i $SSH_KEY -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3" \
            --include="*/" \
            --include="*.m4a" \
            --include="*.aac" \
            --exclude=".*" \
            --exclude="*" \
            "azuser@$SOURCE_HOST:$source_path" "$DEST_PATH/"; then

            log "Pass 1 (M4A/AAC) completed successfully"

            log "=== PASS 2: Syncing FLAC files (fallback where M4A missing) ==="

            # Pass 2: Sync FLAC files only where M4A/AAC doesn't exist
            if timeout 3600 rsync -av \
                --no-group --no-perms --no-owner --no-times \
                --inplace --ignore-existing \
                --iconv=utf8,ascii//TRANSLIT \
                -e "ssh -i $SSH_KEY -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3" \
                --include="*/" \
                --include="*.flac" \
                --exclude=".*" \
                --exclude="*" \
                "azuser@$SOURCE_HOST:$source_path" "$DEST_PATH/"; then

                log "Pass 2 (FLAC fallback) completed successfully"
                log "Two-pass sync completed successfully"
                break
            else
                log "Pass 2 (FLAC) failed, but Pass 1 succeeded - continuing"
                break
            fi
        else
            log "Pass 1 (M4A/AAC) failed, retrying in ${RETRY_WAIT}s..."
            if [ $attempt -lt $MAX_RETRIES ]; then
                sleep $RETRY_WAIT
            fi
        fi
    done

    # Post-processing
    log "Starting post-processing cleanup"
    cleanup_metadata
    sanitize_filenames

    # Cleanup
    rm -f "$LOCK_FILE"

    # Log final stats
    total_files=$(find "$DEST_PATH" -type f -name "*.m4a" -o -name "*.flac" -o -name "*.aac" | wc -l)
    m4a_files=$(find "$DEST_PATH" -name "*.m4a" | wc -l)
    flac_files=$(find "$DEST_PATH" -name "*.flac" | wc -l)
    aac_files=$(find "$DEST_PATH" -name "*.aac" | wc -l)

    log "Sync completed successfully!"
    log "Total files: $total_files (M4A: $m4a_files, FLAC: $flac_files, AAC: $aac_files)"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Sync completed successfully" > /mutable/music_sync_last_run
    return 0
}

cleanup_only() {
    log "Starting cleanup-only mode"

    if ! verify_music_mount; then
        log "Failed to verify music mount"
        return 1
    fi

    cleanup_metadata
    sanitize_filenames

    total_files=$(find "$DEST_PATH" -type f -name "*.m4a" -o -name "*.flac" -o -name "*.aac" | wc -l)
    log "Cleanup completed. Total music files: $total_files"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Cleanup completed successfully" > /mutable/music_sync_last_run
    return 0
}

test_config() {
    echo "=== Configuration Test ==="

    errors=0

    # Test SSH key
    if [ ! -f "$SSH_KEY" ]; then
        echo "[FAIL] SSH key not found: $SSH_KEY"
        errors=$(expr $errors + 1)
    else
        echo "[PASS] SSH key found: $SSH_KEY"
    fi

    # Test music mount
    if [ ! -d "$MUSIC_MOUNT" ]; then
        echo "[FAIL] Music mount not found: $MUSIC_MOUNT"
        errors=$(expr $errors + 1)
    else
        echo "[PASS] Music mount found: $MUSIC_MOUNT"

        if touch "$MUSIC_MOUNT/.test" 2>/dev/null && rm "$MUSIC_MOUNT/.test" 2>/dev/null; then
            echo "[PASS] Music mount is writable"
        else
            echo "[FAIL] Music mount is not writable"
            errors=$(expr $errors + 1)
        fi
    fi

    # Test connectivity
    if check_connection; then
        echo "[PASS] Can reach source host: $SOURCE_HOST"
    else
        echo "[FAIL] Cannot reach source host: $SOURCE_HOST"
        errors=$(expr $errors + 1)
    fi

    # Test HA connectivity
    if command -v curl >/dev/null 2>&1; then
        echo "[PASS] curl available for HA integration"

        # Test HA connection
        if curl -s --connect-timeout 3 "$HA_URL/api/" -H "Authorization: Bearer $HA_TOKEN" >/dev/null 2>&1; then
            echo "[PASS] Home Assistant API accessible"
        else
            echo "[WARN] Home Assistant API not accessible (check URL/token)"
        fi
    else
        echo "[WARN] curl not available - HA integration limited"
    fi

    echo ""
    echo "=== Current Status ==="
    echo "Tesla Connected:   $(get_tesla_connection_status)"
    echo "WiFi Connected:    $(get_wifi_status)"
    echo "Sync State:        $(get_sync_state)"

    echo ""
    if [ $errors -eq 0 ]; then
        echo "SUCCESS: All critical tests passed!"
        return 0
    else
        echo "WARNING: Found $errors critical errors."
        return 1
    fi
}

check_tesla_connection() {
    local connected=$(get_tesla_connection_status)
    echo "Tesla USB connection: $connected"

    if [ "$connected" = "true" ]; then
        echo "Tesla is currently connected via USB"
        echo "Safe to sync - Tesla is connected and ready for music"
        return 0
    else
        echo "Tesla is not connected - sync may not be useful"
        return 1
    fi
}

reboot_system() {
    log "System reboot requested - rebooting in 5 seconds..."
    send_status_to_ha
    sleep 5
    reboot
}

# Parse command line arguments
REBOOT_AFTER=false
SYNC_MODE=false
CLEANUP_ONLY=false
ARTIST_FILTER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--print-config)
            print_config
            exit 0
            ;;
        -c|--cleanup-only)
            CLEANUP_ONLY=true
            shift
            ;;
        -s|--sync)
            SYNC_MODE=true
            shift
            ;;
        -t|--test)
            test_config
            exit $?
            ;;
        --ha-status)
            generate_status_json
            exit 0
            ;;
        --check-tesla)
            check_tesla_connection
            exit $?
            ;;
        --send-ha-status)
            send_status_to_ha
            echo "Status sent to Home Assistant and saved to $STATUS_FILE"
            exit 0
            ;;
        --reboot-after)
            REBOOT_AFTER=true
            shift
            ;;
        --artist)
            ARTIST_FILTER="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
    esac
done

# Main execution
if [ "$CLEANUP_ONLY" = "true" ]; then
    if cleanup_only; then
        send_status_to_ha
        if [ "$REBOOT_AFTER" = "true" ]; then
            reboot_system
        fi
        exit 0
    else
        send_status_to_ha
        exit 1
    fi
elif [ "$SYNC_MODE" = "true" ]; then
    if do_sync "$ARTIST_FILTER"; then
        send_status_to_ha
        if [ "$REBOOT_AFTER" = "true" ]; then
            reboot_system
        fi
        exit 0
    else
        send_status_to_ha
        exit 1
    fi
else
    echo "Please specify an operation:"
    echo "  -s, --sync          Run full music sync"
    echo "  -c, --cleanup-only  Run cleanup only"
    echo "  -h, --help          Show help"
    exit 1
fi
