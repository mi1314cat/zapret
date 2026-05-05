#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - smart_build.sh
# 智能编译系统（ABI 检查 + 依赖检查 + fallback）
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ZAPRET2_DIR="/root/catmi/Zapret2"
NFQWS_BIN="$ZAPRET2_DIR/nfqws2"

# ============================================================
# 检查依赖
# ============================================================
check_build_deps() {
    log_info "检查编译依赖..."

    local deps=(
        git make gcc
        libmnl-dev libnfnetlink-dev libnetfilter-queue-dev
        zlib1g-dev libcap-dev
    )

    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y "${deps[@]}" >/dev/null 2>&1 || true
}

# ============================================================
# ABI 检查（确保二进制架构正确）
# ============================================================
check_abi() {
    local bin="$1"
    local arch
    arch=$(uname -m)

    local info
    info=$(file -b "$bin" || true)

    case "$arch" in
        aarch64)
            [[ "$info" =~ "ARM" ]] || return 1
            ;;
        armv7l|armv7)
            [[ "$info" =~ "ARM" ]] || return 1
            ;;
        x86_64)
            [[ "$info" =~ "x86-64" ]] || return 1
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

# ============================================================
# ldd 检查（依赖缺失检测）
# ============================================================
check_ldd() {
    local bin="$1"

    if ldd "$bin" 2>/dev/null | grep -q "not found"; then
        return 1
    fi

    return 0
}

# ============================================================
# 自检（--help / --version）
# ============================================================
self_test() {
    local bin="$1"

    "$bin" --help >/dev/null 2>&1 || return 1
    "$bin" --version >/dev/null 2>&1 || return 1

    return 0
}

# ============================================================
# 二进制完整性检查
# ============================================================
verify_binary() {
    local bin="$1"

    [[ -x "$bin" ]] || return 1
    [[ -s "$bin" ]] || return 1

    check_abi "$bin" || return 1
    check_ldd "$bin" || return 1
    self_test "$bin" || return 1

    return 0
}

# ============================================================
# 清理旧源码
# ============================================================
prepare_source() {
    rm -rf "$ZAPRET2_DIR"
    git clone --depth=1 https://github.com/bol-van/zapret "$ZAPRET2_DIR"
}

# ============================================================
# 智能编译（快速 → 补依赖 → 全量）
# ============================================================
smart_build_nfqws() {
    log_info "开始智能编译 nfqws..."

    prepare_source
    cd "$ZAPRET2_DIR"

    # -------------------------------
    # ① 快速编译
    # -------------------------------
    log_warn "尝试快速编译..."
    if make -C nfq >/dev/null 2>&1; then
        cp nfq/nfqws "$NFQWS_BIN" 2>/dev/null || true
        if verify_binary "$NFQWS_BIN"; then
            log_info "快速编译成功"
            return 0
        fi
    fi

    # -------------------------------
    # ② 自动补依赖后重试
    # -------------------------------
    log_warn "快速编译失败 → 自动补依赖..."
    check_build_deps

    if make -C nfq >/dev/null 2>&1; then
        cp nfq/nfqws "$NFQWS_BIN" 2>/dev/null || true
        if verify_binary "$NFQWS_BIN"; then
            log_info "补依赖后编译成功"
            return 0
        fi
    fi

    # -------------------------------
    # ③ 全量编译 fallback
    # -------------------------------
    log_warn "快速编译仍失败 → 执行全量编译..."

    if make >/dev/null 2>&1; then
        # 多路径 fallback
        if [[ -x nfqws ]]; then
            cp nfqws "$NFQWS_BIN"
        elif [[ -x binaries/my/nfqws ]]; then
            cp binaries/my/nfqws "$NFQWS_BIN"
        elif ls binaries/*/nfqws >/dev/null 2>&1; then
            cp "$(ls binaries/*/nfqws | head -n 1)" "$NFQWS_BIN"
        fi

        if verify_binary "$NFQWS_BIN"; then
            log_info "全量编译成功"
            return 0
        fi
    fi

    log_fatal "智能编译失败：无法构建 nfqws"
}
