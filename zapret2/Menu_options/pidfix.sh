#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 修复 zapret2d 僵尸 PID（最终优化版）
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
MENU="$BASE/Menu_options"
CFG="$BASE/config"
LIB="$BASE/lib"

source "$MENU/colors.sh"
source "$LIB/utils.sh"

PIDFILE="/run/zapret2d.pid"
SERVICE="zapret2"
LOCK_FILE="/run/zapret2_pidfix.lock"

pidfix_menu() {
    with_lock "$LOCK_FILE" _pidfix_impl
}

_pidfix_impl() {
    clear
    title "修复 zapret2d 僵尸 PID"

    # ============================================================
    # 1. 检查 PID 文件是否存在
    # ============================================================
    if [[ ! -f "$PIDFILE" ]]; then
        info "没有 PID 文件，无需修复"
        echo ""
        read -rp "按回车返回..."
        return
    fi

    pid=$(cat "$PIDFILE" 2>/dev/null || true)

    if [[ -z "$pid" ]]; then
        warn "PID 文件为空，已删除"
        rm -f "$PIDFILE"
    else
        # ============================================================
        # 2. 检查进程是否存在
        # ============================================================
        if [[ ! -d "/proc/$pid" ]]; then
            warn "检测到僵尸 PID：$pid"
            rm -f "$PIDFILE"
            ok "已删除僵尸 PID 文件"
        else
            info "PID 文件正常：进程 $pid 正在运行"
            echo ""
            read -rp "按回车返回..."
            return
        fi
    fi

    # ============================================================
    # 3. 清理 systemd 状态
    # ============================================================
    info "重置 systemd 状态..."
    systemctl reset-failed "$SERVICE"

    # ============================================================
    # 4. 重启服务
    # ============================================================
    info "正在重启 zapret2..."
    systemctl restart "$SERVICE"

    ok "zapret2d 已成功重启"

    echo ""
    read -rp "按回车返回..."
}

pidfix_menu
