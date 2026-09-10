#!/usr/bin/env python3
"""Tide local update server.

Serves a download page for the packaged app, the .zip itself, and a release feed with the same
JSON shape as GitHub's `releases/latest`, so the app's updater can be pointed at it:

    defaults write com.charlessantos.tide updateFeedURL http://localhost:8787/releases/latest

Package first with `./build.sh --package` (writes build.nosync/dist/), then `python3 tools/serve.py`.
"""
import argparse, datetime, html, http.server, json, os, socket, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "build.nosync", "dist")
ICON = os.path.join(ROOT, "docs", "icon.png")


def load_release():
    path = os.path.join(DIST, "release.json")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        rel = json.load(f)
    zip_path = os.path.join(DIST, rel["asset"])
    if not os.path.exists(zip_path):
        return None
    rel["size"] = os.path.getsize(zip_path)
    return rel


def lan_addresses():
    addrs = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127."):
                addrs.add(ip)
    except socket.gaierror:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        addrs.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    return sorted(addrs)


PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>Tide {version}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{{margin:0;min-height:100vh;font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",Helvetica,Arial,sans-serif;
background:linear-gradient(180deg,#d4e6ff 0%,#eaf2ff 60%,#f4f8ff 100%);color:#12203a;display:flex;align-items:center;justify-content:center}}
@media(prefers-color-scheme:dark){{body{{background:linear-gradient(180deg,#0d1730,#121c36 60%,#171f33);color:#e8eefc}}}}
.card{{width:min(560px,92vw);padding:36px 40px;border-radius:28px;background:rgba(255,255,255,.55);backdrop-filter:blur(30px) saturate(160%);
-webkit-backdrop-filter:blur(30px) saturate(160%);border:1px solid rgba(255,255,255,.7);box-shadow:0 20px 60px rgba(30,70,160,.18)}}
@media(prefers-color-scheme:dark){{.card{{background:rgba(30,45,80,.45);border-color:rgba(255,255,255,.12)}}}}
h1{{margin:0;font-size:34px;letter-spacing:-.02em}} .sub{{opacity:.7;margin:4px 0 22px}}
.icon{{width:96px;height:96px;float:right;margin:-8px -8px 0 16px}}
a.btn{{display:inline-block;padding:12px 22px;border-radius:999px;background:#2f7bf6;color:#fff;text-decoration:none;font-weight:600;box-shadow:0 8px 20px rgba(47,123,246,.35)}}
a.btn:hover{{background:#2468d6}}
.meta{{font-size:12px;opacity:.65;margin-top:14px;word-break:break-all}} code{{font-family:Menlo,monospace;font-size:12px}}
.notes{{margin-top:22px;padding-top:18px;border-top:1px solid rgba(0,0,0,.08);white-space:pre-wrap;font-size:14px;line-height:1.5}}
h3{{margin:24px 0 8px;font-size:13px;text-transform:uppercase;letter-spacing:.08em;opacity:.6}}
ol{{padding-left:20px;line-height:1.6;font-size:14px}}
</style></head><body><div class="card">
<img class="icon" src="/icon.png" alt="">
<h1>Tide</h1><div class="sub">Version {version} · {size_mb} MB · macOS 14 or later · Liquid Glass on macOS 26</div>
<a class="btn" href="/download">Download Tide.app</a>
<div class="meta">SHA-256 <code>{sha}</code></div>
<h3>Install</h3><ol><li>Unzip, drag <b>Tide.app</b> to Applications.</li>
<li>First launch: right-click the app and choose <b>Open</b> (it is signed locally, not by Apple), or run
<code>xattr -dr com.apple.quarantine /Applications/Tide.app</code>.</li>
<li>After that, Tide updates itself from GitHub Releases. To test updates against this server instead:
<code>defaults write com.charlessantos.tide updateFeedURL {feed}</code></li></ol>
<div class="notes">{notes}</div>
</div></body></html>"""


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIST, **kwargs)

    def base_url(self):
        host = self.headers.get("Host") or "localhost"
        return f"http://{host}"

    def send_text(self, body, ctype="text/html; charset=utf-8", code=200):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        rel = load_release()
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            if not rel:
                self.send_text("<h1>No package yet</h1><p>Run <code>./build.sh --package</code> first.</p>", code=503)
                return
            self.send_text(PAGE.format(version=html.escape(rel["version"]), size_mb=f"{rel['size'] / 1e6:.1f}",
                                       sha=html.escape(rel.get("sha256", "")), feed=f"{self.base_url()}/releases/latest",
                                       notes=html.escape(rel.get("notes", "")).strip() or "No release notes."))
        elif path in ("/releases/latest", "/latest.json"):
            if not rel:
                self.send_text('{"error":"no package"}', "application/json", 503)
                return
            feed = {
                "tag_name": "v" + rel["version"],
                "name": "Tide " + rel["version"],
                "body": rel.get("notes", ""),
                "published_at": rel.get("date", ""),
                "html_url": self.base_url() + "/",
                "assets": [{
                    "name": rel["asset"],
                    "browser_download_url": f"{self.base_url()}/{rel['asset']}",
                    "size": rel["size"],
                    "content_type": "application/zip",
                    "sha256": rel.get("sha256", ""),
                }],
            }
            self.send_text(json.dumps(feed, indent=2), "application/json")
        elif path == "/download":
            if not rel:
                self.send_text("no package", "text/plain", 503)
                return
            self.send_response(302)
            self.send_header("Location", "/" + rel["asset"])
            self.end_headers()
        elif path == "/icon.png" and os.path.exists(ICON):
            with open(ICON, "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            super().do_GET()

    def log_message(self, fmt, *args):
        sys.stdout.write("%s %s\n" % (datetime.datetime.now().strftime("%H:%M:%S"), fmt % args))
        sys.stdout.flush()


def main():
    try:
        sys.stdout.reconfigure(line_buffering=True)   # readable logs when redirected to a file
    except (AttributeError, ValueError):
        pass
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--host", default="0.0.0.0", help="bind address (0.0.0.0 = reachable from the LAN)")
    args = ap.parse_args()
    rel = load_release()
    if rel:
        print(f"serving Tide {rel['version']} ({rel['asset']}, {rel['size'] / 1e6:.1f} MB) from {DIST}")
    else:
        print(f"no package in {DIST} yet — run ./build.sh --package (the server picks it up when it appears)")
    print(f"  page:  http://localhost:{args.port}/")
    print(f"  feed:  http://localhost:{args.port}/releases/latest")
    for ip in lan_addresses():
        print(f"  LAN:   http://{ip}:{args.port}/")
    http.server.ThreadingHTTPServer.allow_reuse_address = True
    with http.server.ThreadingHTTPServer((args.host, args.port), Handler) as srv:
        try:
            srv.serve_forever()
        except KeyboardInterrupt:
            print("\nbye")


if __name__ == "__main__":
    main()
