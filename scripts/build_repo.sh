#!/bin/bash
set -e

REPO_DIR="${1:-repo}"
DEB_DIR="${2:-packages}"

mkdir -p "$REPO_DIR/debs"
touch "$REPO_DIR/.nojekyll"

cp "$DEB_DIR"/*.deb "$REPO_DIR/debs/" 2>/dev/null || true

if [ -z "$(ls -A "$REPO_DIR/debs/" 2>/dev/null)" ]; then
    echo "ERROR: No .deb files found in $DEB_DIR/"
    exit 1
fi

cd "$REPO_DIR"

# Exact same format as Frida official repo (https://build.frida.re/)
dpkg-scanpackages debs /dev/null > Packages
gzip -9c Packages > Packages.gz

cat > Release << 'EOF'
Origin: GumJS WebSocket Repo
Label: GumJS WebSocket
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm64
Components: main
Description: GumJS WebSocket iOS tweak repository
EOF

mkdir -p depiction
cat > depiction/com.gjws.gumjswebsocket.html << 'HTMLEOF'
<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>GumJS WebSocket</title>
<style>body{font-family:-apple-system,sans-serif;padding:16px;background:#f5f5f5;color:#333}h1{font-size:22px}h2{font-size:18px;margin-top:24px}p,li{font-size:14px;line-height:1.6}.badge{display:inline-block;background:#007aff;color:#fff;padding:2px 8px;border-radius:4px;font-size:12px}code{background:#e8e8e8;padding:2px 6px;border-radius:3px;font-size:13px}</style>
</head><body>
<h1>GumJS WebSocket <span class="badge">v1.0.0</span></h1>
<p>Inject Frida GumJS scripts into iOS apps via WebSocket with hot-reload support.</p>
<h2>Features</h2><ul>
<li>Settings.app configuration</li><li>Hot-reload from PC</li><li>Stealth Frida devkit</li><li>Big script chunked transfer</li></ul>
<h2>Usage</h2><ol>
<li>Settings → GumJS WebSocket → Enable</li><li>Add target Bundle ID</li>
<li>Set WebSocket URI</li><li>PC: <code>python server.py script.js</code></li><li>Launch target app</li></ol>
</body></html>
HTMLEOF

cat > index.html << 'INDEXEOF'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>GumJS WebSocket Repo</title>
<style>body{font-family:-apple-system,sans-serif;padding:20px;background:#1a1a2e;color:#eee;max-width:600px;margin:0 auto}h1{color:#00d2ff}code{background:#333;padding:4px 8px;border-radius:4px;font-size:14px;color:#0f0}a{color:#00d2ff}.card{background:#16213e;padding:20px;border-radius:12px;margin:20px 0}</style>
</head><body><h1>GumJS WebSocket</h1>
<div class="card"><h2>Add to Sileo</h2><p>Source URL:</p><code>https://rickbrian.github.io/gumjs_ios_websocket/</code></div>
<div class="card"><h2>Direct Download</h2><p><a href="debs/">Browse .deb packages</a></p></div>
</body></html>
INDEXEOF

echo "[+] Repo built: $(ls debs/*.deb | wc -l) deb(s)"
