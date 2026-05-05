#!/usr/bin/env bash
BASE="/root/catmi/Zapret2"
BIN="$BASE/bin"
MENU="$BASE/Menu_options"
source "$MENU/colors.sh"

title "防火墙管理"

echo "1) 加载防火墙"
echo "2) 清理防火墙"
echo "0) 返回"
read -rp "选择：" f

case "$f" in
    1) bash "$BIN/firewallctl" apply; ok "已加载防火墙" ;;
    2) bash "$BIN/firewallctl" clear; ok "已清理防火墙" ;;
    0) exit 0 ;;
    *) err "无效选择" ;;
esac

read -rp "按回车继续..."
