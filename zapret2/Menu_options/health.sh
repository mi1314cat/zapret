#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 健康检查（最终优化版）
# CPU / NFQUEUE / PID / 服务 / 防火墙 / 端口
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
BIN="$BASE/bin"
LIB="$BASE/lib"
MENU="$BASE/Menu_options"

source "$MENU/colors.sh"
source "$LIB/utils.sh"

LOCK_FILE="/run/zapret2_health.lock"
SERVICE="zapret2"
PIDFILE="/run/zapret2d.pid"

# ============================================================
# CPU 占用检查
# ============================================================
check_cpu() {
    echo -e "${CYAN}▶ CPU 占用${RESET}"

    ps -eo pid,comm,%cpu --sort=-%cpu | grep -E "zapret2d|nfqws2" || {
        warn "未找到 zapret2d 或 nfqws2 进程"
        return
    }

    ps -eo pid,comm,%cpu --sort=-%cpu | head -n 10
    echo ""
}

# ============================================================
# NFQUEUE 状态检查
# ============================================================
check_nfq() {
    echo -e "${CYAN}▶ NFQUEUE 队列状态${RESET}"

    if command -v nfqtop >/dev/null 2>&1; then
        nfqtop -1 2>/dev/null | head -n 10
    else
        warn "未安装 nfqtop，无法查看 NFQUEUE 状态"
    fi

    echo ""
}

# ============================================================
# PID 状态检查
# ============================================================
check_pid() {
    echo -e "${CYAN}▶ PID 状态${RESET}"

    if [[ ! -f "$PIDFILE" ]]; then
        warn "PID 文件不存在"
        return
    fi

    pid=$(cat "$PIDFILE")

    if [[ ! -d "/proc/$pid" ]]; then
        warn "检测到僵尸 PID：$pid"
        echo -e "${YELLOW}可运行 pidfix 修复${RESET}"
    else
        ok "PID 正常：$pid"
    fi

    echo ""
}

# ============================================================
# systemd 服务状态
# ============================================================
check_service() {
    echo -e "${CYAN}▶ 服务状态（systemd）${RESET}"

    systemctl is-active --quiet "$SERVICE" && ok "服务运行中" || err "服务未运行"
    systemctl status "$SERVICE" --no-pager | head -n 10

    echo ""
}

# ============================================================
# nftables 状态检查
# ============================================================
check_firewall() {
    echo -e "${CYAN}▶ 防火墙状态（nftables）${RESET}"

    if nft list table inet zapret2 >/dev/null 2>&1; then
        ok "zapret2 表已加载"
        nft list table inet zapret2 | head -n 20
    else
        err "zapret2 表未加载"
    fi

    echo ""
}

# ============================================================
# 端口监听检查
# ============================================================
check_ports() {
    echo -e "${CYAN}▶ 端口监听${RESET}"

    ports=$(grep -E '^port[0-9]=' "$CFG/ports.conf" 2>/dev/null | cut -d= -f2)

    if [[ -z "$ports" ]]; then
        warn "未配置端口"
        return
    fi

    for p in $ports; do
        if ss -lnt | grep -q ":$p "; then
            ok "端口 $p 正在监听"
        else
            err "端口 $p 未监听"
        fi
    done

    echo ""
}

# ============================================================
# 主菜单
# ============================================================
health_menu() {
    with_lock "$LOCK_FILE" _health_impl
}

_health_impl() {
    clear
    title "Zapret2 健康检查"

    check_cpu
    check_nfq
    check_pid
    check_service
    check_firewall
    check_ports

    echo -e "${CYAN}1) 修复僵尸 PID（调用 pidfix）${RESET}"
    echo -e "${CYAN}0) 返回${RESET}"
    echo ""

    read -rp "选择：" choice

    case "$choice" in
        1) bash "$MENU/pidfix.sh" ;;
        0) return ;;
    esac
}

health_menu
