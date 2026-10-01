# Z-Mod Tapo Camera

A Z-Mod plugin for FlashForge AD5X/AD5M/AD5M Pro that exposes a network Tapo camera in Mainsail using the printer's built-in FFmpeg, Python and Nginx.

## Status

**Prototype / alpha.** The complete pipeline has been tested on an AD5X with Z-Mod:

`FFmpeg test pattern -> MPJPEG -> Python HTTP -> LAN browser`

The Tapo RTSP input and automatic Z-Mod installation still need to be tested on real hardware.

## Architecture

```text
Tapo C210 RTSP (H.264)
        |
        v
FFmpeg on printer
        |
        v
multipart MJPEG
        |
        v
Python HTTP server :8090 (localhost)
        |
        v
Z-Mod Nginx /webcam/
        |
        v
Mainsail
```

TP-Link documents Tapo RTSP as `/stream1` (high quality) and `/stream2` (standard quality), using a separate camera account and port 554 by default.

## Configuration

The plugin creates `/root/printer_data/config/tapo_camera.conf`, which is editable in Mainsail under **Machine > Configuration Files**. Enter the camera details there; the settings take effect after restarting the service. Existing configurations at the former `/usr/data/config/mod_data/tapo_camera.conf` location are migrated during installation.

Example:

```ini
ENABLED=1
HOST=192.168.0.50
PORT=554
USERNAME=tapo_user
PASSWORD=tapo_password
STREAM=stream2
WIDTH=640
HEIGHT=360
FPS=10
JPEG_QUALITY=6
HTTP_PORT=8090
```

The RTSP URL is generated as:

```text
rtsp://USER:PASSWORD@HOST:PORT/STREAM
```

Credentials are URL-escaped by the launcher.

## Installation

Add the plugin to Z-Mod's Moonraker plugin configuration:

```ini
[update_manager tapo_camera]
type: git_repo
channel: dev
path: /root/printer_data/config/mod_data/plugins/tapo_camera
origin: https://github.com/Jaizu/zmod-tapo-camera.git
is_system_service: False
primary_branch: main
```

Then enable it:

```gcode
ENABLE_PLUGIN name=tapo_camera
```

The configuration is a plain key/value file in Mainsail's configuration editor, not a custom Mainsail settings form.

## Development install

Copy the repository to:

```text
/usr/data/config/mod_data/plugins/tapo_camera
```

Then run:

```sh
./install.sh
```

## Testing without a Tapo

The included server can use FFmpeg's `testsrc` instead of RTSP:

```sh
TEST_SOURCE=1 ./tapo_camera.sh start
```

Then open:

```text
http://PRINTER_IP:8090/
```

## Security

The HTTP server binds to `127.0.0.1` by default, so the camera stream is not directly exposed to the LAN. Nginx is intended to proxy it through the printer's existing Mainsail endpoint.

Do not expose the Tapo RTSP port to the Internet. TP-Link recommends using a VPN rather than port forwarding for remote RTSP access.
