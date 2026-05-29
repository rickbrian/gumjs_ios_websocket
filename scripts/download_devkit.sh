#!/bin/bash
set -e

DEVKIT_DIR="lib"
DEVKIT_URL="${DEVKIT_URL:-https://github.com/rickbrian/frida_me/releases/download/17.9.11-ios-stealth/stealth-frida-gumjs-devkit-17.9.11-ios-arm64.tar.xz}"

mkdir -p "$DEVKIT_DIR"

if [ -f "$DEVKIT_DIR/frida-gumjs.h" ] && [ -f "$DEVKIT_DIR/libfrida-gumjs.a" ]; then
    echo "[+] DevKit already present in $DEVKIT_DIR/"
    exit 0
fi

echo "[*] Downloading devkit from: $DEVKIT_URL"
curl -fSL "$DEVKIT_URL" -o /tmp/devkit.tar.xz

echo "[*] Extracting..."
tar xf /tmp/devkit.tar.xz -C "$DEVKIT_DIR/"

# Rename to add lib prefix for the linker
if [ -f "$DEVKIT_DIR/frida-gumjs.a" ]; then
    mv "$DEVKIT_DIR/frida-gumjs.a" "$DEVKIT_DIR/libfrida-gumjs.a"
fi

rm -f /tmp/devkit.tar.xz

echo "[+] DevKit ready:"
ls -lh "$DEVKIT_DIR/"
