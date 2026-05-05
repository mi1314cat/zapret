#!/usr/bin/env bash
BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
MENU="$BASE/Menu_options"
source "$MENU/colors.sh"

title "配置包处理数量"

read -rp "NFQUEUE 队列号（默认 200）：" qnum
read -rp "队列大小（默认 4096）：" qsize

echo "QNUM=${qnum:-200}" > "$CFG/pkt.conf"
echo "QSIZE=${qsize:-4096}" >> "$CFG/pkt.conf"

ok "包处理数量已更新"
read -rp "按回车继续..."
