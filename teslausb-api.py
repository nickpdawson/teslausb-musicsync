#!/usr/bin/env python3
"""
TeslaUSB Web API Server
Provides REST endpoints for Home Assistant integration
"""

import json
import subprocess
import signal
import os
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
import threading

class TeslaUSBHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        """Override to log to file instead of stderr"""
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        with open('/mutable/teslausb_api.log', 'a') as f:
            f.write(f"{timestamp} - {format % args}\n")

    def do_GET(self):
        """Handle GET requests"""
        path = urlparse(self.path).path

        if path == '/status':
            self.handle_status()
        elif path == '/':
            self.handle_root()
        else:
            self.send_error(404, "Not found")

    def do_POST(self):
        """Handle POST requests"""
        path = urlparse(self.path).path

        if path == '/sync':
            self.handle_sync()
        elif path == '/cleanup':
            self.handle_cleanup()
        elif path == '/reboot':
            self.handle_reboot()
        elif path == '/stop':
            self.handle_stop()
        else:
            self.send_error(404, "Not found")

    def handle_status(self):
        """Return current status JSON"""
        try:
            # Try to read status file
            if os.path.exists('/mutable/teslausb_status.json'):
                with open('/mutable/teslausb_status.json', 'r') as f:
                    status = f.read()
            else:
                # Generate status if file doesn't exist
                result = subprocess.run(['/root/bin/sync-music.sh', '--ha-status'],
                                      capture_output=True, text=True, timeout=10)
                status = result.stdout if result.returncode == 0 else '{"state": "error"}'

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(status.encode())

        except Exception as e:
            self.send_error(500, f"Status error: {str(e)}")

    def handle_sync(self):
        """Start music sync"""
        try:
            # Check if sync is already running
            if self.is_sync_running():
                response = {"status": "error", "message": "Sync already running"}
                self.send_json_response(400, response)
                return

            # Check if Tesla is connected (GOOD - means we should sync)
            if not self.is_tesla_connected():
                response = {"status": "error", "message": "Tesla not connected - no point syncing"}
                self.send_json_response(400, response)
                return

            # Start sync in background
            def run_sync():
                try:
                    subprocess.run(['/root/bin/sync-music.sh', '-s', '--reboot-after'],
                                 timeout=7200)  # 2 hour timeout
                except subprocess.TimeoutExpired:
                    self.log_message("Sync timeout after 2 hours")
                except Exception as e:
                    self.log_message("Sync error: %s", str(e))

            thread = threading.Thread(target=run_sync, daemon=True)
            thread.start()

            response = {"status": "success", "message": "Sync started"}
            self.send_json_response(200, response)

        except Exception as e:
            response = {"status": "error", "message": str(e)}
            self.send_json_response(500, response)

    def handle_cleanup(self):
        """Run cleanup only"""
        try:
            if self.is_sync_running():
                response = {"status": "error", "message": "Sync already running"}
                self.send_json_response(400, response)
                return

            # Start cleanup in background
            def run_cleanup():
                try:
                    subprocess.run(['/root/bin/sync-music.sh', '-c', '--reboot-after'],
                                 timeout=600)  # 10 minute timeout
                except Exception as e:
                    self.log_message("Cleanup error: %s", str(e))

            thread = threading.Thread(target=run_cleanup, daemon=True)
            thread.start()

            response = {"status": "success", "message": "Cleanup started"}
            self.send_json_response(200, response)

        except Exception as e:
            response = {"status": "error", "message": str(e)}
            self.send_json_response(500, response)

    def handle_stop(self):
        """Gracefully stop running sync"""
        try:
            stopped = False

            # Try to stop rsync processes
            try:
                result = subprocess.run(['pkill', '-TERM', 'rsync'],
                                      capture_output=True, timeout=5)
                if result.returncode == 0:
                    stopped = True
                    self.log_message("Stopped rsync processes")
            except:
                pass

            # Remove lock file to allow new syncs
            try:
                if os.path.exists('/mutable/music_sync.lock'):
                    os.remove('/mutable/music_sync.lock')
                    stopped = True
                    self.log_message("Removed sync lock file")
            except:
                pass

            # Try to stop sync script
            try:
                subprocess.run(['pkill', '-TERM', '-f', 'sync-music.sh'],
                             capture_output=True, timeout=5)
                stopped = True
                self.log_message("Stopped sync script")
            except:
                pass

            if stopped:
                # Update status to reflect stop
                try:
                    subprocess.run(['/root/bin/sync-music.sh', '--send-ha-status'],
                                 timeout=10)
                except:
                    pass

                response = {"status": "success", "message": "Sync stopped gracefully"}
                self.send_json_response(200, response)
            else:
                response = {"status": "info", "message": "No sync running to stop"}
                self.send_json_response(200, response)

        except Exception as e:
            response = {"status": "error", "message": str(e)}
            self.send_json_response(500, response)

    def handle_reboot(self):
        """Reboot system"""
        try:
            response = {"status": "success", "message": "Reboot initiated"}
            self.send_json_response(200, response)

            # Reboot after sending response
            def delayed_reboot():
                time.sleep(2)
                subprocess.run(['reboot'])

            thread = threading.Thread(target=delayed_reboot, daemon=True)
            thread.start()

        except Exception as e:
            response = {"status": "error", "message": str(e)}
            self.send_json_response(500, response)

    def handle_root(self):
        """Root endpoint with API info"""
        info = {
            "service": "TeslaUSB API",
            "version": "1.0",
            "endpoints": {
                "GET /status": "Get current status",
                "POST /sync": "Start music sync",
                "POST /cleanup": "Run cleanup only",
                "POST /stop": "Stop running sync",
                "POST /reboot": "Reboot system"
            }
        }
        self.send_json_response(200, info)

    def send_json_response(self, code, data):
        """Send JSON response"""
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def is_sync_running(self):
        """Check if sync is currently running"""
        try:
            # Check for lock file
            if os.path.exists('/mutable/music_sync.lock'):
                return True

            # Check for running rsync processes
            result = subprocess.run(['pgrep', '-f', 'rsync.*'],
                                  capture_output=True, timeout=5)
            return result.returncode == 0

        except:
            return False

    def is_tesla_connected(self):
        """Check if Tesla is connected via USB"""
        try:
            with open('/sys/kernel/config/usb_gadget/teslausb/UDC', 'r') as f:
                udc_content = f.read().strip()
                return udc_content and udc_content != "none"
        except:
            return False

def main():
    """Start the web server"""
    server_address = ('', 9999)
    httpd = HTTPServer(server_address, TeslaUSBHandler)

    print(f"TeslaUSB API Server starting on port 9999")
    print("Endpoints:")
    print("  GET  /status  - Get current status")
    print("  POST /sync    - Start music sync")
    print("  POST /cleanup - Run cleanup only")
    print("  POST /stop    - Stop running sync")
    print("  POST /reboot  - Reboot system")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        httpd.shutdown()

if __name__ == '__main__':
    main()
