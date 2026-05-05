#!/usr/bin/env bash
BASE="/root/catmi/Zapret2"
MENU="$BASE/Menu_options"
source "$MENU/colors.sh"

title "运行 Blockcheck"

bash "$BASE/bin/blockcheck"

ok "Blockcheck 已完成"
read -rp "按回车继续..."
