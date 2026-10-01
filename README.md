# Z-Mod Tapo Camera

A Z-Mod plugin for Flashforge AD5X that publishes an RTSP camera as a native
Mainsail webcam. It was developed with a Tapo C210, which is used in the
examples, but it can also work with other camera models and brands that expose
an RTSP stream compatible with the URL settings and FFmpeg input used here. It
uses the printer's built-in FFmpeg and Python 3.8 and does not modify Nginx or
internal Z-Mod files.

This is not a universal camera integration: the camera must provide RTSP
access, and its host, port, credentials, and stream path must fit the
configuration below. The RTSP stream must use a format supported by the
printer's FFmpeg build. ONVIF discovery and manufacturer-specific setup are not
implemented; check your camera's RTSP URL and codec before using it.

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

The plugin creates `/root/printer_data/config/tapo_camera.conf`, editable under **Machine > Configuration Files** in Mainsail. After changing settings, run `ENABLE_PLUGIN name=tapo_camera` in the printer console to rerun the plugin installer and restart the camera service. The installer uses `HTTP_PUBLIC_HOST=auto` to find the printer's default-route IPv4 address and writes the resulting browser URL into the marked Moonraker webcam section. Set `HTTP_PUBLIC_HOST` to a fixed IP or LAN hostname if automatic detection is unsuitable, then rerun the plugin as described below.

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

No SSH is needed. These steps assume Z-Mod is already installed. In Mainsail,
open **Machine > Configuration Files** and edit
`/usr/data/config/mod_data/user.moonraker.conf`. Add this repository entry:

```ini
[update_manager tapo_camera]
type: git_repo
channel: dev
path: /usr/data/config/mod_data/plugins/tapo_camera
origin: https://github.com/Jaizu/zmod-tapo-camera.git
is_system_service: False
primary_branch: main
```

Save the file, then reboot the printer from Mainsail or Fluidd's power
controls. This reloads Moonraker's configuration; Z-Mod's plugin command
restarts Klipper, not Moonraker. After the printer is back online, enter
`ENABLE_PLUGIN name=tapo_camera` in the printer console. Z-Mod downloads the
plugin, runs its installer, and restarts Klipper. The first run creates
`/root/printer_data/config/tapo_camera.conf`.

In **Machine > Configuration Files**, edit `tapo_camera.conf` with the
camera's RTSP host, port, username, password, and stream path, then set
`ENABLED=1`. Run `ENABLE_PLUGIN name=tapo_camera` again to apply the settings.
The installer restarts the camera service, registers the webcam with
Moonraker, and adds the startup hook. Reboot the printer once more so Moonraker
loads the new webcam entry. Do not add a separate `[webcam Tapo C210]` section;
the installer manages it. Z-Mod runs `update.sh` after plugin updates, so
routine plugin updates also apply the installer without SSH.

Repeated installs and updates replace only the plugin's marked blocks,
preserve the camera configuration, and do not create another server process.
To remove the plugin, enter `DISABLE_PLUGIN name=tapo_camera` in the printer
console. Z-Mod runs the uninstaller, which removes the webcam block and service
hook, stops the service, restores the original startup hook (or removes it if
the plugin created it), and removes the plugin configuration and files. Reboot
the printer so Moonraker drops the webcam entry.

## Testing

Open `http://PRINTER_IP:8090/` from a device on the same LAN to test the stream
directly. Moonraker should list the webcam at
`http://PRINTER_IP:7125/server/webcams/list`.

The `mjpegstreamer` adapter requires `stream_url` only; no snapshot URL is
configured, so this integration provides live video only. If the printer's IP
changes, update `HTTP_PUBLIC_HOST`, run `ENABLE_PLUGIN name=tapo_camera` in the
printer console, and reboot the printer so Moonraker reloads the webcam URL.
This direct HTTP stream has no authentication or TLS; keep it on a trusted LAN
and do not expose port 8090 or the camera's RTSP port to the Internet.
