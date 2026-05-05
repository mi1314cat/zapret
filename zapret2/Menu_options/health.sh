#!/usr/bin/env bash
BASE="/root/catmi/Zapret2"
MENU="$BASE/Menu_options"
source "$MENU/colors.sh"

PIDFILE="/run/zapret2.pid"
SERVICE="zapret2"

title "Zapret2 健康检查"

# 僵尸 PID 检查
if [[ -f "$PIDFILE" ]]; then
    pid=$(cat "$PIDFILE")
    if [[ ! -d "/proc/$pid" ]]; then
        warn "僵尸 PID：$pid"
        rm -f "$PIDFILE"
        ok "已删除僵尸 PID 文件"
    fi
fi

# 获取 PID
pid=$(pgrep -x zapret2d || true)
if [[ -z "$pid" ]]; then
    warn "zapret2d 未运行，尝试重启..."
    systemctl restart "$SERVICE"
    ok "已重启 zapret2d"
    read -rp "按回车继续..."
    exit 0
fi

# CPU 卡死检测
cpu=$(ps -p "$pid" -o %cpu= | awk '{print int($1)}')
if [[ "$cpu" -eq 0 ]]; then
    warn "CPU=0，疑似卡死"
    systemctl restart "$SERVICE"
    ok "已重启 zapret2d"
else
    ok "CPU 正常：$cpu%"
fi

# NFQUEUE 检查
if iptables -t mangle -S | grep -q NFQUEUE; then
    if [[ -f /proc/net/netfilter/nfnetlink_queue ]]; then
        lines=$(wc -l < /proc/net/netfilter/nfnetlink_queue)
        ok "NFQUEUE 队列存在：$lines 行"
    else
        warn "NFQUEUE 队列不存在"
    fi
else
    warn "未检测到 NFQUEUE 规则"
fi

read -rp "按回车继续..."
