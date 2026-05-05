#!/usr/bin/env bash
BASE="/root/catmi/Zapret2"
MENU="$BASE/Menu_options"
source "$MENU/colors.sh"

PIDFILE="/run/zapret2.pid"
SERVICE="zapret2"

title "修复 zapret2d 僵尸 PID"

if [[ -f "$PIDFILE" ]]; then
    pid=$(cat "$PIDFILE")
    if [[ ! -d "/proc/$pid" ]]; then
        warn "检测到僵尸 PID：$pid"
        rm -f "$PIDFILE"
        ok "已删除僵尸 PID 文件"
    else
        info "PID 文件正常，无需修复"
    fi
else
    info "没有 PID 文件"
fi

systemctl reset-failed "$SERVICE"
systemctl restart "$SERVICE"

ok "zapret2d 已重启"
read -rp "按回车继续..."
