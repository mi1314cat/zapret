#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 自动编译 nfqws2（支持所有架构）
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
BIN="$BASE/bin"
BUILD_DIR="/tmp/zapret_build"
REPO="https://github.com/bol-van/zapret.git"

NFQWS2_TARGET="$BIN/nfqws2"
BACKUP="$BIN/nfqws2.bak"

mkdir -p "$BIN"

# -------------------------------
# 彩色输出
# -------------------------------
green() { echo -e "\e[32m$*\e[0m"; }
yellow(){ echo -e "\e[33m$*\e[0m"; }
red()   { echo -e "\e[31m$*\e[0m"; }

echo "============================================================"
echo "🔧 自动编译 nfqws2（支持 ARM64 / ARMv7 / x86_64 / MIPS / RISC-V）"
echo "============================================================"

# -------------------------------
# 1. 安装依赖
# -------------------------------
yellow "📦 安装依赖..."

apt update -y
apt install -y git build-essential pkg-config libmnl-dev libnetfilter-queue-dev

green "✔ 依赖安装完成"

# -------------------------------
# 2. 克隆 zapret 作者仓库
# -------------------------------
rm -rf "$BUILD_DIR"
git clone --depth=1 "$REPO" "$BUILD_DIR"

green "✔ 源码下载完成"

# -------------------------------
# 3. 编译 nfqws2
# -------------------------------
cd "$BUILD_DIR"

yellow "🔨 开始编译 nfqws2..."

make nfqws || {
    red "❌ 编译失败"
    exit 1
}

green "✔ 编译成功"

# -------------------------------
# 4. 安装 nfqws2
# -------------------------------
if [[ -f "$NFQWS2_TARGET" ]]; then
    cp "$NFQWS2_TARGET" "$BACKUP"
    yellow "⚠ 已备份旧版本：$BACKUP"
fi

cp "$BUILD_DIR/nfqws" "$NFQWS2_TARGET"
chmod +x "$NFQWS2_TARGET"

green "✔ nfqws2 已安装到：$NFQWS2_TARGET"

# -------------------------------
# 5. 清理
# -------------------------------
rm -rf "$BUILD_DIR"

# -------------------------------
# 6. 可选：重启 zapret2 服务
# -------------------------------
if systemctl is-active --quiet zapret2; then
    yellow "🔁 重启 zapret2 服务..."
    systemctl restart zapret2
    green "✔ zapret2 已重启"
fi

echo ""
green "🎉 nfqws2 编译 & 安装完成！"
echo "路径：$NFQWS2_TARGET"
echo "============================================================"
