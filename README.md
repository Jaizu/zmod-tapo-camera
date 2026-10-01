# Z-Mod Tapo Camera

A Z-Mod plugin for Flashforge AD5X that publishes a Tapo C210 RTSP camera as a native Mainsail webcam. It uses the printer's built-in FFmpeg and Python 3.8 and does not modify Nginx or internal Z-Mod files.

## Architecture

```text
Tapo C210 RTSP (H.264)
        |
        v
FFmpeg on printer
        |
        v
Python multipart-MJPEG server on 0.0.0.0:8090
        |
        +--> Moonraker [webcam Tapo C210], service: mjpegstreamer
        |
        v
Browser loads http://PRINTER_IP:8090/ directly
```

Moonraker stores webcam metadata and exposes it through `/server/webcams/list`; it does not proxy this stream. Mainsail's `mjpegstreamer` adapter fetches the URL directly from the browser and parses the multipart MJPEG frames the server emits, so the address must be reachable from the browser. `HTTP_HOST=0.0.0.0` makes the stream available on the printer's network interfaces. Note that Mainsail's `ipstream` service type (listed in Moonraker's docs) is not actually implemented by Mainsail's current front-end code, which is why `mjpegstreamer` is used instead.

The installed Moonraker reads the plugin's marked webcam section from `/usr/data/config/mod_data/user.moonraker.conf`, included by Z-Mod's Moonraker configuration. The plugin does not edit the included system configuration itself.

## Configuration

The plugin creates `/root/printer_data/config/tapo_camera.conf`, editable under **Machine > Configuration Files** in Mainsail. Settings for FFmpeg take effect after `tapo_camera.sh restart`. The installer uses `HTTP_PUBLIC_HOST=auto` to find the printer's default-route IPv4 address and writes the resulting browser URL into the marked Moonraker webcam section. Set `HTTP_PUBLIC_HOST` to a fixed IP or LAN hostname if automatic detection is unsuitable; rerun `install.sh` after changing it.

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
HTTP_HOST=0.0.0.0
HTTP_PORT=8090
HTTP_PUBLIC_HOST=auto
```

The RTSP URL is generated as `rtsp://USER:PASSWORD@HOST:PORT/STREAM`; credentials are URL-escaped by the server. Do not commit real credentials.

## Installation

Add the plugin to Z-Mod's Moonraker plugin configuration:

```ini
[update_manager tapo_camera]
type: git_repo
channel: dev
path: /usr/data/config/mod_data/plugins/tapo_camera
origin: https://github.com/Jaizu/zmod-tapo-camera.git
is_system_service: False
primary_branch: main
```

Enable it with `ENABLE_PLUGIN name=tapo_camera`, or run `install.sh` from the plugin directory once to create the configuration. Enter the Tapo settings and set `ENABLED=1`, then run `install.sh` again; this restarts the service and registers the enabled webcam. Z-Mod runs `update.sh` automatically after plugin updates, so updates restart the camera service without requiring SSH. Restart Moonraker from Mainsail once after the webcam is first registered so it loads the new webcam section. The service autostarts through a marked block in `/usr/data/config/mod_data/power_on.sh`.

Repeated installs and updates replace only the plugin's marked blocks, preserve the camera configuration, and do not create another server process. Uninstall removes the webcam block and service hook, stops the service, restores the original startup hook (or removes it if the plugin created it), and removes the plugin configuration and files. Restart Moonraker from Mainsail after uninstall so Mainsail drops the webcam entry.

## Testing

From the plugin directory, the service supports:

```sh
./tapo_camera.sh start
./tapo_camera.sh status
./tapo_camera.sh restart
./tapo_camera.sh stop
```

Open `http://PRINTER_IP:8090/` from a device on the same LAN to test the stream directly. Moonraker should list the webcam at `http://PRINTER_IP:7125/server/webcams/list`. To test without a Tapo, stop the normal service first, then run `TEST_SOURCE=1 ./tapo_camera.sh start`.

The `mjpegstreamer` adapter requires `stream_url` only; no snapshot URL is configured, so this integration provides live video only. If the printer's IP changes, update `HTTP_PUBLIC_HOST` and rerun the installer. This direct HTTP stream has no authentication or TLS; keep it on a trusted LAN and do not expose port 8090 or the Tapo RTSP port to the Internet.
