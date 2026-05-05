#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 端口管理（最终优化版）
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
PORT_FILE="$CFG/ports.conf"

source "$BASE/Menu_options/colors.sh"
source "$BASE/lib/utils.sh"

touch "$PORT_FILE"

edit_port() {
    clear
    title "端口管理"

    cur1=$(grep '^port1=' "$PORT_FILE" | cut -d= -f2)
    cur2=$(grep '^port2=' "$PORT_FILE" | cut -d= -f2)

    echo -e "${CYAN}当前端口：${RESET}"
    echo "port1 = ${GREEN}${cur1:-未设置}${RESET}"
    echo "port2 = ${GREEN}${cur2:-未设置}${RESET}"
    echo ""

    read -rp "请输入新的 port1：" p1
    read -rp "请输入新的 port2：" p2

    [[ "$p1" =~ ^[0-9]+$ ]] || { err "port1 必须是数字"; return; }
    [[ "$p2" =~ ^[0-9]+$ ]] || { err "port2 必须是数字"; return; }

    echo "port1=$p1" > "$PORT_FILE"
    echo "port2=$p2" >> "$PORT_FILE"

    ok "端口已更新：$p1 / $p2"

    log_info "重启 zapret2 使端口生效..."
    systemctl restart zapret2
}

edit_port
