#!/usr/bin/env bash
set -euo pipefail

BASE="/root/catmi/Zapret2"
BIN="$BASE/bin"
BUILD_DIR="/tmp/zapret2_build"

echo "============================================================"
echo "🔧 自动编译 nfqws2（zapret2 正确版）"
echo "============================================================"

apt update -y
apt install -y git build-essential pkg-config libmnl-dev libnetfilter-queue-dev

rm -rf "$BUILD_DIR"
git clone --depth=1 https://github.com/bol-van/zapret2 "$BUILD_DIR"

cd "$BUILD_DIR/nfq2"

echo "🔨 编译 nfqws2..."
make

if [[ ! -f "$BUILD_DIR/nfq2/nfqws2" ]]; then
    echo "❌ 编译完成但未找到 nfqws2，可手动检查 $BUILD_DIR/nfq2"
    exit 1
fi

cp "$BUILD_DIR/nfq2/nfqws2" "$BIN/nfqws2"
chmod +x "$BIN/nfqws2"

echo "✔ nfqws2 编译完成：$BIN/nfqws2"
