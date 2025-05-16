#!/usr/bin/env bash
set -e

APP_NAME="myapp"
OUTPUT_DIR="bin"
mkdir -p "$OUTPUT_DIR"

# === Version Resolution ===
VERSION=${VERSION:-$(cat VERSION 2>/dev/null || echo "dev")}

# === Detect OS and define output filename ===
case "$(uname -s)" in
Linux*) RUST_OUTPUT="${OUTPUT_DIR}/${APP_NAME}-linux-v${VERSION}" ;;
Darwin*) RUST_OUTPUT="${OUTPUT_DIR}/${APP_NAME}-macos-v${VERSION}" ;;
MINGW* | MSYS* | CYGWIN*) RUST_OUTPUT="${OUTPUT_DIR}/${APP_NAME}-windows-v${VERSION}.exe" ;;
*)
    echo "[Rust] ❌ Unsupported OS"
    exit 1
    ;;
esac

echo "[Rust] 🚀 Building: $RUST_OUTPUT"
cargo build --release --quiet

# === Copy binary to output ===
if [[ "$RUST_OUTPUT" == *.exe ]]; then
    cp "target/release/${APP_NAME}.exe" "$RUST_OUTPUT"
else
    cp "target/release/${APP_NAME}" "$RUST_OUTPUT"
fi

echo "[Rust] ✅ Done: $RUST_OUTPUT"
