#!/bin/bash

# TeslaUSB Music Sync Installation Script
# Run this script on your TeslaUSB device

set -e

echo "TeslaUSB Music Sync Installation"
echo "================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Check if we're on a TeslaUSB device
if [ ! -d "/var/www/html/fs/Music" ]; then
    echo "Warning: /var/www/html/fs/Music not found. Are you on a TeslaUSB device?"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Installing TeslaUSB Music Sync components..."

# Create directories
mkdir -p /root/bin

# Copy scripts
echo "Installing sync script..."
cp sync-music.sh /root/bin/
chmod +x /root/bin/sync-music.sh

echo "Installing API server..."
cp teslausb-api.py /root/bin/
chmod +x /root/bin/teslausb-api.py

echo "Installing systemd service..."
cp teslausb-api.service /etc/systemd/system/
systemctl daemon-reload

echo ""
echo "Installation complete!"
echo ""
echo "NEXT STEPS:"
echo "==========="
echo "1. Edit /root/bin/sync-music.sh and update these variables:"
echo "   - SOURCE_HOST (your NAS hostname/IP)"
echo "   - SOURCE_PATH (path to music on your NAS)"
echo "   - SSH_KEY (path to SSH key file)"
echo "   - HA_TOKEN (your Home Assistant long-lived access token)"
echo "   - HA_URL (your Home Assistant URL)"
echo ""
echo "2. Set up SSH key for your NAS:"
echo "   ssh-keygen -t rsa -b 4096 -f /root/.ssh/your_nas_key -N \"\""
echo "   ssh-copy-id -i /root/.ssh/your_nas_key.pub user@your-nas"
echo ""
echo "3. Test the configuration:"
echo "   /root/bin/sync-music.sh -t"
echo ""
echo "4. Start the API service:"
echo "   systemctl enable teslausb-api"
echo "   systemctl start teslausb-api"
echo ""
echo "5. Configure Home Assistant using the files in homeassistant/"
echo ""
echo "For detailed instructions, see: https://github.com/nickpdawson/teslausb-musicsync"
