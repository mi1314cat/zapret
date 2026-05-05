#!/usr/bin/env bash
set -euo pipefail

BASE="/root/catmi/Zapret2"
BIN="$BASE/bin"
BUILD_DIR="/tmp/zapret_build"

echo "============================================================"
echo "🔧 自动编译 nfqws2（最终修复版）"
echo "============================================================"

apt update -y
apt install -y git build-essential pkg-config libmnl-dev libnetfilter-queue-dev

rm -rf "$BUILD_DIR"
git clone --depth=1 https://github.com/bol-van/zapret "$BUILD_DIR"

cd "$BUILD_DIR"

echo "🔨 编译 nfqws2..."
make nfqws2

cp nfqws2 "$BIN/nfqws2"
chmod +x "$BIN/nfqws2"

echo "✔ nfqws2 编译完成：$BIN/nfqws2"
