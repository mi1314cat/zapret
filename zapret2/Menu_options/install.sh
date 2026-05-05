#!/usr/bin/env bash
BASE="/root/catmi/Zapret2"
MENU="$BASE/Menu_options"
source "$MENU/colors.sh"

title "一键安装 Zapret2"

bash "$BASE/zapret2.sh" install || true
systemctl enable --now zapret2 || true

ok "安装完成！Zapret2 已启动"
read -rp "按回车继续..."
