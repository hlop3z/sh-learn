#!/usr/bin/env bash
set -e

APP_NAME="myapp"
GO_INPUT="./cmd/${APP_NAME}"
OUTPUT_DIR="bin"
mkdir -p "$OUTPUT_DIR"

# === Version Resolution ===
VERSION=${VERSION:-$(cat VERSION 2>/dev/null || echo "dev")}

# === Detect OS and define output filename ===
case "$(uname -s)" in
Linux*) GO_OUTPUT="${OUTPUT_DIR}/${APP_NAME}-linux-v${VERSION}" ;;
Darwin*) GO_OUTPUT="${OUTPUT_DIR}/${APP_NAME}-macos-v${VERSION}" ;;
MINGW* | MSYS* | CYGWIN*) GO_OUTPUT="${OUTPUT_DIR}/${APP_NAME}-windows-v${VERSION}.exe" ;;
*)
    echo "[Go] ❌ Unsupported OS"
    exit 1
    ;;
esac

echo "[Go] 🚀 Building: $GO_OUTPUT"
go build -ldflags="-s -w" -trimpath -o "$GO_OUTPUT" "$GO_INPUT"
echo "[Go] ✅ Done: $GO_OUTPUT"
