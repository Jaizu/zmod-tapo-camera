#!/usr/prog/Python-3.8.2/bin/python3

import os
import signal
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import quote

CONFIG = os.environ.get(
    "TAPO_CONFIG",
    "/root/printer_data/config/tapo_camera.conf"
)

FFMPEG = "/usr/prog/ffmpeg-4.0.2/bin/ffmpeg"
FFMPEG_LD = "/usr/prog/ffmpeg-4.0.2/lib:/usr/prog/x264/lib"

DEFAULTS = {
    "HOST": "",
    "PORT": "554",
    "USERNAME": "",
    "PASSWORD": "",
    "STREAM": "stream2",
    "WIDTH": "640",
    "HEIGHT": "360",
    "FPS": "10",
    "JPEG_QUALITY": "6",
    "HTTP_HOST": "0.0.0.0",
    "HTTP_PORT": "8090",
}


def load_config():
    cfg = dict(DEFAULTS)

    if os.path.exists(CONFIG):
        with open(CONFIG, "r") as f:
            for raw in f:
                line = raw.strip()

                if not line or line.startswith("#") or "=" not in line:
                    continue

                k, v = line.split("=", 1)
                cfg[k.strip().upper()] = v.strip().strip('"').strip("'")

    return cfg


def rtsp_url(cfg):
    user = quote(cfg["USERNAME"], safe="")
    password = quote(cfg["PASSWORD"], safe="")
    host = cfg["HOST"]
    port = cfg["PORT"]
    stream = cfg["STREAM"].lstrip("/")

    return "rtsp://{}:{}@{}:{}/{}".format(
        user,
        password,
        host,
        port,
        stream,
    )


def ffmpeg_cmd(cfg, source):
    return [
        FFMPEG,
        "-hide_banner",
        "-loglevel", "warning",
        "-rtsp_transport", "tcp",
        "-i", source,
        "-an",
        "-vf", "scale={}:{}:flags=fast_bilinear".format(
            cfg["WIDTH"],
            cfg["HEIGHT"],
        ),
        "-r", cfg["FPS"],
        "-c:v", "mjpeg",
        "-q:v", cfg["JPEG_QUALITY"],
        "-f", "mpjpeg",
        "pipe:1",
    ]


def test_cmd(cfg):
    return [
        FFMPEG,
        "-hide_banner",
        "-loglevel", "warning",
        "-f", "lavfi",
        "-i",
        "testsrc=size={}x{}:rate={}".format(
            cfg["WIDTH"],
            cfg["HEIGHT"],
            cfg["FPS"],
        ),
        "-c:v", "mjpeg",
        "-q:v", cfg["JPEG_QUALITY"],
        "-f", "mpjpeg",
        "pipe:1",
    ]


CFG = load_config()

SOURCE = (
    test_cmd(CFG)
    if os.environ.get("TEST_SOURCE") == "1"
    else ffmpeg_cmd(CFG, rtsp_url(CFG))
)

env = os.environ.copy()
env["LD_LIBRARY_PATH"] = FFMPEG_LD + (
    ":" + env["LD_LIBRARY_PATH"]
    if env.get("LD_LIBRARY_PATH")
    else ""
)

proc = None


def spawn_ffmpeg():
    global proc

    proc = subprocess.Popen(
        SOURCE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
        env=env,
    )

    return proc


class Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if self.path not in ("/", "/stream", "/stream/"):
            self.send_error(404)
            return

        self.send_response(200)
        self.send_header(
            "Content-Type",
            "multipart/x-mixed-replace; boundary=ffmpeg"
        )
        self.send_header(
            "Cache-Control",
            "no-cache, no-store, must-revalidate"
        )
        self.send_header("Pragma", "no-cache")
        self.send_header("Connection", "close")
        # Mainsail fetches this URL cross-origin (different port), requiring CORS.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        global proc

        while True:
            if proc is None or proc.poll() is not None:
                try:
                    spawn_ffmpeg()
                except Exception:
                    return

            try:
                chunk = proc.stdout.read(16384)

                if not chunk:
                    return

                self.wfile.write(chunk)
                self.wfile.flush()

            except (
                BrokenPipeError,
                ConnectionResetError,
                ConnectionAbortedError,
            ):
                return

            except Exception:
                return


class ReusableServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def stop(*_args):
    global proc

    if proc is not None:
        try:
            proc.terminate()
        except Exception:
            pass

    raise SystemExit(0)


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)


if not os.environ.get("TEST_SOURCE") and not CFG.get("HOST"):
    print(
        "Tapo camera HOST is not configured",
        file=sys.stderr,
    )
    sys.exit(2)


HTTP_HOST = CFG.get("HTTP_HOST", "0.0.0.0")
HTTP_PORT = int(CFG["HTTP_PORT"])

server = ReusableServer(
    (HTTP_HOST, HTTP_PORT),
    Handler,
)

spawn_ffmpeg()

print(
    "Tapo camera HTTP server listening on {}:{}".format(
        HTTP_HOST,
        HTTP_PORT,
    ),
    flush=True,
)

server.serve_forever()
