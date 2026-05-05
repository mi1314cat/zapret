#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - NFQUEUE 包处理数量管理（qnum/qsize）
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
QCONF="$CFG/qnum.conf"

source "$BASE/Menu_options/colors.sh"
source "$BASE/lib/utils.sh"

touch "$QCONF"

qnum_menu() {
    clear
    title "NFQUEUE 包处理数量管理"

    cur_qnum=$(grep '^qnum=' "$QCONF" | cut -d= -f2)
    cur_qsize=$(grep '^qsize=' "$QCONF" | cut -d= -f2)

    echo -e "${CYAN}当前配置：${RESET}"
    echo "qnum  = ${GREEN}${cur_qnum:-100}${RESET}"
    echo "qsize = ${GREEN}${cur_qsize:-4096}${RESET}"
    echo ""

    read -rp "请输入新的 qnum（队列号）：" qn
    read -rp "请输入新的 qsize（队列大小）：" qs

    [[ "$qn" =~ ^[0-9]+$ ]] || { err "qnum 必须是数字"; return; }
    [[ "$qs" =~ ^[0-9]+$ ]] || { err "qsize 必须是数字"; return; }

    echo "qnum=$qn" > "$QCONF"
    echo "qsize=$qs" >> "$QCONF"

    ok "NFQUEUE 配置已更新：qnum=$qn / qsize=$qs"

    log_info "重启 zapret2 使配置生效..."
    systemctl restart zapret2
}

qnum_menu
