#!/bin/bash
set -e

REPO_DIR="${1:-repo}"
DEB_DIR="${2:-packages}"

mkdir -p "$REPO_DIR/debs"

# Disable Jekyll processing so extensionless files (Packages, Release) are served correctly
touch "$REPO_DIR/.nojekyll"

# Copy all .deb files
cp "$DEB_DIR"/*.deb "$REPO_DIR/debs/" 2>/dev/null || true

if [ -z "$(ls -A "$REPO_DIR/debs/" 2>/dev/null)" ]; then
    echo "ERROR: No .deb files found in $DEB_DIR/"
    exit 1
fi

# Generate Packages index
cd "$REPO_DIR"
dpkg-scanpackages debs /dev/null > Packages
gzip -9c Packages > Packages.gz
bzip2 -9kf Packages || true
xz -9kf Packages || true

# Build Release file with hash entries so APT can validate the index
{
    cat << 'HEADER'
Origin: GumJS WebSocket Repo
Label: GumJS WebSocket
Suite: ./
Version: 1.0
Architectures: iphoneos-arm64
Description: GumJS WebSocket iOS tweak repository
HEADER

    echo "MD5Sum:"
    for f in Packages Packages.gz Packages.bz2 Packages.xz; do
        if [ -f "$f" ]; then
            hash=$(md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1)
            size=$(wc -c < "$f" | tr -d ' ')
            printf " %s %16d %s\n" "$hash" "$size" "$f"
        fi
    done

    echo "SHA256:"
    for f in Packages Packages.gz Packages.bz2 Packages.xz; do
        if [ -f "$f" ]; then
            hash=$(shasum -a 256 "$f" 2>/dev/null | cut -d' ' -f1 || sha256sum "$f" | cut -d' ' -f1)
            size=$(wc -c < "$f" | tr -d ' ')
            printf " %s %16d %s\n" "$hash" "$size" "$f"
        fi
    done
} > Release

# Sileo featured banner
cat > sileo-featured.json << 'JSONEOF'
{
  "class": "FeaturedBannersView",
  "itemSize": "{263, 148}",
  "itemCornerRadius": 8,
  "banners": [
    {
      "url": "depiction/com.gjws.gumjswebsocket.html",
      "title": "GumJS WebSocket",
      "package": "com.gjws.gumjswebsocket",
      "hideShadow": false
    }
  ]
}
JSONEOF

# Simple depiction page
mkdir -p depiction
cat > depiction/com.gjws.gumjswebsocket.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GumJS WebSocket</title>
<style>
body { font-family: -apple-system, sans-serif; padding: 16px; background: #f5f5f5; color: #333; }
h1 { font-size: 22px; }
h2 { font-size: 18px; margin-top: 24px; }
p, li { font-size: 14px; line-height: 1.6; }
.badge { display: inline-block; background: #007aff; color: white; padding: 2px 8px; border-radius: 4px; font-size: 12px; }
code { background: #e8e8e8; padding: 2px 6px; border-radius: 3px; font-size: 13px; }
</style>
</head>
<body>
<h1>GumJS WebSocket <span class="badge">v1.0.0</span></h1>
<p>Inject Frida GumJS scripts into iOS apps via WebSocket with hot-reload support.</p>

<h2>Features</h2>
<ul>
<li>Settings.app configuration — select apps and input WebSocket URI</li>
<li>Hot-reload — edit JS on PC, auto-push to device</li>
<li>Stealth Frida devkit — lower detection risk</li>
<li>Big script chunked transfer support</li>
</ul>

<h2>Usage</h2>
<ol>
<li>Open <b>Settings → GumJS WebSocket</b></li>
<li>Enable the master switch</li>
<li>Add target app Bundle ID</li>
<li>Set WebSocket URI (e.g. <code>ws://192.168.1.100:14725/ws</code>)</li>
<li>On PC: <code>python server.py your_script.js</code></li>
<li>Launch the target app</li>
</ol>

<h2>Uninstall</h2>
<p>All files including config are automatically cleaned up on removal.</p>
</body>
</html>
HTMLEOF

# Simple index page for browser access
cat > index.html << 'INDEXEOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GumJS WebSocket Repo</title>
<style>
body { font-family: -apple-system, sans-serif; padding: 20px; background: #1a1a2e; color: #eee; max-width: 600px; margin: 0 auto; }
h1 { color: #00d2ff; }
code { background: #333; padding: 4px 8px; border-radius: 4px; font-size: 14px; color: #0f0; }
a { color: #00d2ff; }
.card { background: #16213e; padding: 20px; border-radius: 12px; margin: 20px 0; }
</style>
</head>
<body>
<h1>GumJS WebSocket</h1>
<div class="card">
<h2>Add to Sileo / Cydia</h2>
<p>Add this URL as a source:</p>
<code>https://rickbrian.github.io/gumjs_ios_websocket/</code>
</div>
<div class="card">
<h2>Direct Download</h2>
<p><a href="debs/">Browse .deb packages</a></p>
</div>
<p><a href="depiction/com.gjws.gumjswebsocket.html">Package Details</a></p>
</body>
</html>
INDEXEOF

echo "[+] Repo built at $REPO_DIR/"
echo "    Packages: $(ls debs/*.deb | wc -l) deb(s)"
