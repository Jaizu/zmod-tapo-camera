# Z-Mod Tapo Camera

A Z-Mod plugin for Flashforge AD5X that publishes an RTSP camera as a native
Mainsail webcam. It was developed with a Tapo C210, which is used in the
examples, but it can also work with other camera models and brands that expose
an RTSP stream compatible with the URL settings and FFmpeg input used here. It
relays the stream with go2rtc without transcoding and does not modify Nginx or
internal Z-Mod files.

This is not a universal camera integration: the camera must provide RTSP
access, and its host, port, credentials, and stream path must fit the
configuration below. The video must be H.264 (H.265 cannot be played by most
browsers over WebRTC). ONVIF discovery and manufacturer-specific setup are not
implemented; check your camera's RTSP URL and codec before using it.

## Architecture

```text
Tapo C210 RTSP (H.264)
        |   pulled only while someone is watching
        v
go2rtc on the printer (bin/go2rtc, no transcoding)
        |
        +--> Moonraker [webcam Tapo C210], service: webrtc-go2rtc
        |
        v
Browser plays the H.264 stream over WebRTC (ports 1984 + 8555)
```

[go2rtc](https://github.com/AlexxIT/go2rtc) relays the camera's own H.264
stream to the browser, which decodes it. The printer never decodes or encodes
video, and go2rtc only connects to the camera while a viewer is open, so the
plugin uses almost no CPU or Wi-Fi bandwidth when nobody is watching. The
`linux_mipsel` build of go2rtc is shipped in `bin/` (see `bin/VERSION` and
`bin/go2rtc.LICENSE`), because the plugin is installed with git and the printer
may lack an HTTPS-capable downloader.

The binary has one byte changed: its ELF header is marked NaN2008, which the
AD5X kernel requires. Without it the kernel refuses to run it and the log shows
`line 1: syntax error: unexpected ")"`.

Snapshots (`/api/frame.jpeg`, used by timelapse and notifications) are made on
demand with the printer's built-in FFmpeg from a single key frame.

Mainsail and Fluidd connect to go2rtc directly from the browser, so the
printer address must be reachable from the browser. Moonraker only stores the
webcam metadata. The installed Moonraker reads the plugin's marked webcam
section from `/usr/data/config/mod_data/user.moonraker.conf`, included by
Z-Mod's Moonraker configuration. The plugin does not edit any file tracked by
Z-Mod, so Z-Mod's own repositories are never reported as dirty.

go2rtc's configuration is regenerated in `/tmp/tapo_camera/go2rtc.yaml` on
every start (mode 600, never written to persistent storage). Its HTTP API only
allows `/api/ws`, `/api/webrtc` and `/api/frame.jpeg`; the web UI and the
endpoints that can change streams or the configuration are blocked, and the
RTSP and SRTP servers are disabled.

## Configuration

The plugin creates `/root/printer_data/config/tapo_camera.conf`, editable under **Machine > Configuration Files** in Mainsail. After changing settings, run `ENABLE_PLUGIN name=tapo_camera` in the printer console to rerun the plugin installer and restart the camera service. The installer uses `HTTP_PUBLIC_HOST=auto` to find the printer's default-route IPv4 address and writes the resulting browser URLs into the marked Moonraker webcam section. Set `HTTP_PUBLIC_HOST` to a fixed IP or LAN hostname if automatic detection is unsuitable.

```ini
ENABLED=1
HOST=192.168.0.50
PORT=554
USERNAME=tapo_user
PASSWORD=tapo_password
STREAM=stream2
ASPECT_RATIO=16:9
FPS=15
API_PORT=1984
WEBRTC_PORT=8555
HTTP_PUBLIC_HOST=auto
```

The RTSP URL is generated as `rtsp://USER:PASSWORD@HOST:PORT/STREAM`; credentials are URL-escaped. `stream2` is the camera's 640x360 sub-stream and is the lightest option on Wi-Fi; `stream1` is full resolution. Since the video is not transcoded, both cost the printer the same CPU. `FPS` is only a hint for the web interface. Settings from older versions (`WIDTH`, `HEIGHT`, `JPEG_QUALITY`, `HTTP_HOST`, `HTTP_PORT`) are ignored. Do not commit real credentials.

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

Moonraker should list the webcam at `http://PRINTER_IP:7125/server/webcams/list`
with `service: webrtc-go2rtc`. A snapshot can be checked at
`http://PRINTER_IP:1984/api/frame.jpeg?src=tapo`. The service log is
`/usr/data/logs/tapo_camera.log`.

If the printer's IP changes, update `HTTP_PUBLIC_HOST` (or leave it on `auto`),
run `ENABLE_PLUGIN name=tapo_camera` in the printer console, and reboot the
printer so Moonraker reloads the webcam URLs. The stream has no authentication
or TLS; keep it on a trusted LAN and do not expose ports 1984 and 8555 or the
camera's RTSP port to the Internet.
