#!/usr/bin/env bash
BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
MENU="$BASE/Menu_options"
source "$MENU/colors.sh"

SERVICE="zapret2"

case "$1" in
    start)
        systemctl start "$SERVICE"
        ok "Zapret2 已启动"
        ;;
    stop)
        systemctl stop "$SERVICE"
        ok "Zapret2 已停止"
        ;;
    restart)
        systemctl restart "$SERVICE"
        ok "Zapret2 已重启"
        ;;
    logs)
        title "实时日志（Ctrl+C 退出）"
        journalctl -fu "$SERVICE"
        ;;
    mode)
        title "切换模式"
        echo "当前模式：$(cat "$CFG/mode.conf")"
        echo "1) local"
        echo "2) gateway"
        read -rp "选择：" m
        case "$m" in
            1) echo "local" > "$CFG/mode.conf" ;;
            2) echo "gateway" > "$CFG/mode.conf" ;;
            *) err "无效选择"; exit 1 ;;
        esac
        ok "模式已切换为：$(cat "$CFG/mode.conf")"
        systemctl restart "$SERVICE"
        ;;
    *)
        err "未知参数"
        ;;
esac

read -rp "按回车继续..."
