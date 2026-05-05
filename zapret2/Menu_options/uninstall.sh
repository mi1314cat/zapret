#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 完整卸载（最终优化版）
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
BIN="$BASE/bin"
LIB="$BASE/lib"
MENU="$BASE/Menu_options"

source "$MENU/colors.sh"
source "$LIB/utils.sh"

LOCK_FILE="/run/zapret2_uninstall.lock"
SERVICE="zapret2"
PIDFILE="/run/zapret2d.pid"

# ============================================================
# 卸载核心逻辑
# ============================================================
uninstall_core() {
    clear
    title "卸载 Zapret2（完全删除所有文件）"

    echo -e "${RED}警告：此操作将删除 Zapret2 的所有文件、配置、日志、服务！${RESET}"
    echo -e "${YELLOW}包括：${RESET}"
    echo " - systemd 服务"
    echo " - bin/ lib/ config/ logs/ Menu_options/"
    echo " - firewallctl 创建的 nftables 表"
    echo " - PID 文件"
    echo " - 临时文件"
    echo ""
    read -rp "确认卸载？(yes/no): " ans

    [[ "$ans" != "yes" ]] && warn "已取消卸载" && sleep 1 && return

    # -----------------------------
    # 1. 停止服务
    # -----------------------------
    info "停止 zapret2 服务..."
    systemctl stop "$SERVICE" 2>/dev/null || true
    systemctl disable "$SERVICE" 2>/dev/null || true

    # -----------------------------
    # 2. 删除 systemd 服务
    # -----------------------------
    info "删除 systemd 服务..."
    rm -f "/etc/systemd/system/$SERVICE.service"
    systemctl daemon-reload

    # -----------------------------
    # 3. 删除 PID 文件
    # -----------------------------
    info "删除 PID 文件..."
    rm -f "$PIDFILE"

    # -----------------------------
    # 4. 清理 nftables 表
    # -----------------------------
    info "清理 nftables 表..."
    nft delete table inet zapret2 2>/dev/null || true

    # -----------------------------
    # 5. 删除 Zapret2 目录
    # -----------------------------
    info "删除 Zapret2 文件..."
    rm -rf "$BASE"

    # -----------------------------
    # 6. 删除临时文件
    # -----------------------------
    info "清理临时文件..."
    rm -f /run/zapret2_* 2>/dev/null || true

    # -----------------------------
    # 7. 完成
    # -----------------------------
    ok "Zapret2 已完全卸载！"

    echo ""
    read -rp "按回车返回..."
}

# ============================================================
# 主入口（带锁）
# ============================================================
with_lock "$LOCK_FILE" uninstall_core
