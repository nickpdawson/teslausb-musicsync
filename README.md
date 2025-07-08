# TeslaUSB Music Sync with Home Assistant Integration

A comprehensive music synchronization system for TeslaUSB with full Home Assistant integration, real-time monitoring, and intelligent automation.

## Features

🎵 **Two-Pass Sync Strategy** - M4A/AAC preferred, FLAC as fallback  
🏠 **Home Assistant Integration** - Real-time status monitoring and control  
🛡️ **Smart Safety Logic** - Sync when Tesla is connected and charging  
🔄 **Graceful Stop Capability** - Emergency stop without corruption  
📱 **Rich Notifications** - Status updates with interactive buttons  
🤖 **Intelligent Automation** - Auto-start/stop based on Tesla behavior  
🌐 **REST API** - Full remote control capabilities  

## Components

- **sync-music.sh** - Enhanced TeslaUSB sync script with HA integration
- **teslausb-api.py** - REST API server for remote control
- **Home Assistant Configuration** - Sensors, templates, and automations
- **Smart Automation** - Cable disconnect + door open detection

## Prerequisites

- **TeslaUSB** - Working TeslaUSB installation
- **Home Assistant** - With Tesla integration (Teslemetry recommended)
- **NAS/Server** - Music source with SSH access
- **Linux Knowledge** - Comfortable with SSH, systemd, file editing

## Quick Start

### 1. Clone Repository

```bash
ssh pi@your-teslausb-device
cd /root
git clone https://github.com/nickpdawson/teslausb-musicsync.git
cd teslausb-musicsync
```

### 2. Install Components

```bash
# Copy scripts
sudo cp sync-music.sh /root/bin/
sudo cp teslausb-api.py /root/bin/
sudo cp teslausb-api.service /etc/systemd/system/

# Make executable
sudo chmod +x /root/bin/sync-music.sh
sudo chmod +x /root/bin/teslausb-api.py
```

### 3. Configure Your Settings

Edit the configuration variables in `/root/bin/sync-music.sh`:

```bash
sudo nano /root/bin/sync-music.sh
```

Update these variables:
```bash
# Your music server details
SOURCE_HOST="your-nas-hostname.local"
SOURCE_PATH="/path/to/your/music/"
SSH_KEY="/root/.ssh/your_nas_key"

# Your Home Assistant details  
HA_TOKEN="your_ha_long_lived_access_token"
HA_URL="https://your-ha-instance:8123"
```

### 4. Set Up SSH Keys

Generate SSH key for your NAS:
```bash
ssh-keygen -t rsa -b 4096 -f /root/.ssh/your_nas_key -N ""
ssh-copy-id -i /root/.ssh/your_nas_key.pub user@your-nas-hostname
```

Test connectivity:
```bash
ssh -i /root/.ssh/your_nas_key user@your-nas-hostname "ls /path/to/your/music"
```

### 5. Test Configuration

```bash
# Test script configuration
sudo /root/bin/sync-music.sh -t

# Test Home Assistant integration
sudo /root/bin/sync-music.sh --send-ha-status
```

### 6. Enable API Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable teslausb-api
sudo systemctl start teslausb-api
sudo systemctl status teslausb-api
```

### 7. Configure Home Assistant

Add the configuration snippets to your Home Assistant:

#### rest.yaml
```yaml
# TeslaUSB REST Commands
teslausb_sync:
  url: "http://YOUR_TESLAUSB_IP:9999/sync"
  method: POST
  timeout: 30
teslausb_stop:
  url: "http://YOUR_TESLAUSB_IP:9999/stop"  
  method: POST
  timeout: 10
teslausb_cleanup:
  url: "http://YOUR_TESLAUSB_IP:9999/cleanup"
  method: POST
  timeout: 15
teslausb_reboot:
  url: "http://YOUR_TESLAUSB_IP:9999/reboot"
  method: POST
  timeout: 10
```

#### sensors.yaml
```yaml
# TeslaUSB Status Sensor
- platform: rest
  name: "TeslaUSB Music Sync"
  resource: "http://YOUR_TESLAUSB_IP:9999/status"
  scan_interval: 30
  value_template: "{{ value_json.state }}"
  json_attributes:
    - tesla_connected
    - wifi_connected
    - music_files
    - total_artists
    - disk_usage_percent
    - last_sync
    - script_version
    - timestamp
```

#### templates.yaml
Copy the template sensors from `homeassistant/templates.yaml` in this repo.

#### automations.yaml
Copy the smart sync automation from `homeassistant/automations.yaml` in this repo.

**Important**: Update entity names in the automation to match your Tesla integration:
- Replace `binary_sensor.joules_*` with your Tesla entity names
- Replace `person.nick` with your person entity
- Replace `notify.mobile_app_nickphone13` with your mobile app notify service

## Usage

### Manual Sync Control

```bash
# Start full sync
sudo /root/bin/sync-music.sh -s

# Sync specific artist
sudo /root/bin/sync-music.sh -s --artist "Artist Name"

# Cleanup only (no sync)
sudo /root/bin/sync-music.sh -c

# Check Tesla connection
sudo /root/bin/sync-music.sh --check-tesla

# View configuration
sudo /root/bin/sync-music.sh -p
```

### Home Assistant Control

Use the REST commands in Home Assistant:
- `rest_command.teslausb_sync` - Start sync
- `rest_command.teslausb_stop` - Stop sync  
- `rest_command.teslausb_cleanup` - Cleanup only
- `rest_command.teslausb_reboot` - Reboot TeslaUSB

### API Endpoints

Direct API access on port 9999:
```bash
# Get status
curl http://YOUR_TESLAUSB_IP:9999/status

# Start sync
curl -X POST http://YOUR_TESLAUSB_IP:9999/sync

# Stop sync
curl -X POST http://YOUR_TESLAUSB_IP:9999/stop
```

## How It Works

### Sync Logic
1. **Pass 1**: Sync M4A and AAC files (Tesla's preferred formats)
2. **Pass 2**: Sync FLAC files only where M4A/AAC missing (fallback)
3. **Post-processing**: Cleanup metadata files and sanitize filenames

### Safety Features
- **Tesla Connected Check**: Only syncs when Tesla is plugged in
- **Sync Lock Prevention**: Prevents multiple simultaneous syncs
- **Graceful Stop**: Can interrupt long syncs without corruption
- **Mount Verification**: Ensures music mount is accessible

### Smart Automation
The included automation uses Tesla cable + door sensors to:
- **Auto-start sync** when charging cable connects
- **Auto-stop sync** when cable disconnects AND driver door opens (leaving)
- **Send notifications** with sync status and interactive controls

## Configuration Reference

### Script Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SOURCE_HOST` | Your NAS/server hostname | `nas.local` |
| `SOURCE_PATH` | Path to music on server | `/volume1/music/` |
| `SSH_KEY` | SSH key path | `/root/.ssh/nas_key` |
| `HA_TOKEN` | Home Assistant token | `eyJhbGc...` |
| `HA_URL` | Home Assistant URL | `https://ha.local:8123` |
| `MAX_RETRIES` | Sync retry attempts | `3` |
| `RETRY_WAIT` | Wait between retries (seconds) | `300` |

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/status` | GET | Get current sync status |
| `/sync` | POST | Start music sync |
| `/stop` | POST | Stop running sync |
| `/cleanup` | POST | Run cleanup only |
| `/reboot` | POST | Reboot system |

## Troubleshooting

### Common Issues

**Sync won't start**: Check Tesla connection and safety logic
```bash
sudo /root/bin/sync-music.sh --check-tesla
```

**SSH connection fails**: Verify key setup and permissions
```bash
ssh -i /root/.ssh/your_nas_key user@your-nas "echo success"
```

**Home Assistant integration not working**: Check network connectivity
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" https://your-ha:8123/api/
```

**Service not starting**: Check logs
```bash
sudo journalctl -u teslausb-api -f
```

### Log Files

- Sync logs: `/mutable/music_sync.log`
- API logs: `/mutable/teslausb_api.log`
- Service logs: `journalctl -u teslausb-api`

## Advanced Configuration

### Custom Sync Filters

Modify the rsync includes/excludes in the script for custom file filtering:
```bash
--include="*.m4a" \
--include="*.aac" \
--include="*.mp3" \  # Add MP3 support
--exclude="*live*" \ # Exclude live recordings
```

### Network Optimization

For slow networks, adjust timeout and retry settings:
```bash
MAX_RETRIES=5
RETRY_WAIT=600  # 10 minutes
```

### Home Assistant Customization

Customize notification messages, add more sensors, or create additional automations based on your needs.

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly on your TeslaUSB setup
4. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Credits

Built for the TeslaUSB community. Thanks to all TeslaUSB contributors and the Home Assistant community for making this integration possible.
