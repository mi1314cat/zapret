#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - zapret2d
# 主守护进程（防火墙加载 + 参数构建 + nfqws2 运行 + 自愈）
# ============================================================

set -euo pipefail

BASE_DIR="/root/catmi/Zapret2"
LIB_DIR="$BASE_DIR/lib"
BIN_DIR="$BASE_DIR/bin"
CFG_DIR="$BASE_DIR/config"

source "$LIB_DIR/utils.sh"
source "$LIB_DIR/zapret2_core.sh"

FIREWALLCTL="$BIN_DIR/firewallctl"
HEALTHCHECK="$BIN_DIR/healthcheck"

LOG_FILE="/var/log/zapret2/zapret2d.log"
ensure_dir "/var/log/zapret2"

# ============================================================
# 加载防火墙
# ============================================================
load_firewall() {
    log_info "加载防火墙规则..."
    "$FIREWALLCTL" apply
}

# ============================================================
# 清理防火墙
# ============================================================
clear_firewall() {
    log_info "清理防火墙规则..."
    "$FIREWALLCTL" clear
}

# ============================================================
# 健康检查循环
# ============================================================
health_loop() {
    while true; do
        sleep 5

        if ! "$HEALTHCHECK" >/dev/null 2>&1; then
            log_warn "健康检查失败，正在重启 nfqws2..."
            killall -9 nfqws2 2>/dev/null || true
            sleep 1
            zapret2_core_main &
        fi

        # systemd Watchdog 心跳
        if [[ -n "${WATCHDOG_USEC:-}" ]]; then
            systemd-notify WATCHDOG=1 || true
        fi
    done
}

# ============================================================
# 主入口
# ============================================================
main() {
    require_root
    acquire_lock

    exec > >(tee -a "$LOG_FILE") 2>&1

    echo "========== $(date) - zapret2d 启动 =========="

    # 加载防火墙
    load_firewall

    # 启动核心（nfqws2）
    zapret2_core_main &

    # 健康检查循环
    health_loop
}

main
