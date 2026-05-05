#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 主菜单（最终整合版）
# 默认参数自动合理配置，小白安装即用
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
LIB="$BASE/lib"
MENU="$BASE/Menu_options"
LOG="$BASE/logs"

mkdir -p "$CFG" "$LOG"

source "$MENU/colors.sh"
source "$LIB/utils.sh"

SERVICE="zapret2"
PIDFILE="/run/zapret2d.pid"

# -----------------------------
# 默认配置
# -----------------------------
default_mode="local"
default_port1="51610"
default_port2="26095"
default_qnum="100"
default_qsize="4096"

# -----------------------------
# 状态检测
# -----------------------------
get_service_status() {
    if systemctl is-active --quiet "$SERVICE"; then
        echo -e "${GREEN}运行中${RESET}"
    else
        echo -e "${RED}未运行${RESET}"
    fi
}

get_mode() {
    [[ -f "$CFG/mode.conf" ]] && cat "$CFG/mode.conf" || echo "$default_mode"
}

get_ports() {
    if [[ -f "$CFG/ports.conf" ]]; then
        p1=$(grep '^port1=' "$CFG/ports.conf" | cut -d= -f2)
        p2=$(grep '^port2=' "$CFG/ports.conf" | cut -d= -f2)
        echo "${p1:-$default_port1}/${p2:-$default_port2}"
    else
        echo "$default_port1/$default_port2"
    fi
}

get_qconf() {
    if [[ -f "$CFG/qnum.conf" ]]; then
        qn=$(grep '^qnum=' "$CFG/qnum.conf" | cut -d= -f2)
        qs=$(grep '^qsize=' "$CFG/qnum.conf" | cut -d= -f2)
        echo "qnum=${qn:-$default_qnum} qsize=${qs:-$default_qsize}"
    else
        echo "qnum=$default_qnum qsize=$default_qsize"
    fi
}

# -----------------------------
# 一键安装（自动默认配置）
# -----------------------------
install_zapret2() {
    clear
    title "一键安装 Zapret2（自动配置默认值）"

    # 目录
    mkdir -p "$CFG/nodes" "$CFG/strategy.d" "$LOG"

    # mode.conf
    echo "$default_mode" > "$CFG/mode.conf"

    # ports.conf
    {
        echo "port1=$default_port1"
        echo "port2=$default_port2"
    } > "$CFG/ports.conf"

    # qnum.conf
    {
        echo "qnum=$default_qnum"
        echo "qsize=$default_qsize"
    } > "$CFG/qnum.conf"

    # 基础文件
    : > "$CFG/whitelist.txt"
    : > "$CFG/blacklist.txt"
    : > "$CFG/hostlist.txt"
    : > "$CFG/iplist.txt"

    ok "基础配置文件已生成"

    # 自动生成白名单 + hostlist/iplist
    bash "$MENU/autowhitelist.sh" --silent || true
    bash "$MENU/hostlist.sh" --silent || true

    ok "白名单与 hostlist/iplist 已自动生成"

    # systemd 服务（如果不存在则创建简单模板）
    if [[ ! -f "/etc/systemd/system/$SERVICE.service" ]]; then
        cat >/etc/systemd/system/$SERVICE.service <<EOF
[Unit]
Description=Zapret2 DPI Service
After=network.target

[Service]
Type=simple
ExecStart=$BASE/zapret2d
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi

    # 防火墙
    "$BASE/bin/firewallctl" apply || warn "防火墙应用失败，请稍后检查"

    # 启动服务
    systemctl enable --now "$SERVICE" || err "无法启动服务，请检查 zapret2d"

    echo ""
    ok "Zapret2 已成功安装并启动！"
    echo "当前模式：$(get_mode)"
    echo "端口：$(get_ports)"
    echo "NFQUEUE：$(get_qconf)"
    echo ""
    read -rp "按回车返回主菜单..."
}

# -----------------------------
# 运行状态
# -----------------------------
show_status() {
    clear
    title "运行状态"

    echo -e "服务状态：$(get_service_status)"
    echo -e "当前模式：${GREEN}$(get_mode)${RESET}"
    echo -e "端口：${CYAN}$(get_ports)${RESET}"
    echo -e "NFQUEUE：${YELLOW}$(get_qconf)${RESET}"

    echo ""
    systemctl status "$SERVICE" --no-pager | head -n 15 || true
    echo ""
    read -rp "按回车返回主菜单..."
}

# -----------------------------
# 启动/停止/重启
# -----------------------------
start_zapret2() {
    systemctl start "$SERVICE" && ok "已启动 Zapret2" || err "启动失败"
    sleep 1
}

stop_zapret2() {
    systemctl stop "$SERVICE" && ok "已停止 Zapret2" || err "停止失败"
    sleep 1
}

restart_zapret2() {
    systemctl restart "$SERVICE" && ok "已重启 Zapret2" || err "重启失败"
    sleep 1
}

# -----------------------------
# 实时日志
# -----------------------------
tail_logs() {
    clear
    title "实时日志（Ctrl+C 退出）"
    journalctl -fu "$SERVICE"
}

# -----------------------------
# 切换模式
# -----------------------------
switch_mode() {
    clear
    title "切换模式（Local / Gateway）"

    cur=$(get_mode)
    echo "当前模式：$cur"
    echo ""
    echo "1) local（本机模式）"
    echo "2) gateway（网关模式）"
    echo ""

    read -rp "选择：" c
    case "$c" in
        1) echo "local" > "$CFG/mode.conf" ;;
        2) echo "gateway" > "$CFG/mode.conf" ;;
        *) warn "无效选择"; sleep 1; return ;;
    esac

    ok "模式已切换为：$(get_mode)"
    "$BASE/bin/firewallctl" apply || warn "防火墙应用失败"
    sleep 1
}

# -----------------------------
# 一键修复
# -----------------------------
onekey_fix() {
    clear
    title "一键修复"

    bash "$MENU/pidfix.sh"
    "$BASE/bin/firewallctl" clear || true
    "$BASE/bin/firewallctl" apply || true

    ok "一键修复流程已完成"
    sleep 1
}

# -----------------------------
# 主菜单
# -----------------------------
main_menu() {
    while true; do
        clear
        title "Zapret2 v7.0 控制面板"

        echo -e "服务状态：$(get_service_status)  模式：${GREEN}$(get_mode)${RESET}  端口：${CYAN}$(get_ports)${RESET}  NFQUEUE：${YELLOW}$(get_qconf)${RESET}"
        echo "------------------------------------------------------"
        echo " 1) 一键安装（自动配置默认值）"
        echo " 2) 查看运行状态"
        echo " 3) 启动 Zapret2"
        echo " 4) 停止 Zapret2"
        echo " 5) 重启 Zapret2"
        echo " 6) 实时日志"
        echo " 7) 切换模式（Local/Gateway）"
        echo " 8) 健康检查"
        echo " 9) 一键修复（PID + 防火墙）"
        echo ""
        echo "10) 节点管理"
        echo "11) 策略管理"
        echo "12) 白名单管理"
        echo "13) 黑名单管理"
        echo ""
        echo "14) 端口管理（port.sh）"
        echo "15) NFQUEUE 包处理数量（qnum.sh）"
        echo "16) 防火墙管理（firewallctl）"
        echo ""
        echo "17) 自动生成白名单"
        echo "18) 生成 hostlist/iplist"
        echo "19) 运行 Blockcheck"
        echo ""
        echo "20) 卸载 Zapret2"
        echo ""
        echo " 0) 退出"
        echo ""

        read -rp "选择：" choice

        case "$choice" in
            1) install_zapret2 ;;
            2) show_status ;;
            3) start_zapret2 ;;
            4) stop_zapret2 ;;
            5) restart_zapret2 ;;
            6) tail_logs ;;
            7) switch_mode ;;
            8) bash "$MENU/health.sh" ;;
            9) onekey_fix ;;
            10) bash "$MENU/nodes.sh" ;;
            11) bash "$MENU/strategy.sh" ;;
            12) bash "$MENU/whitelist.sh" ;;
            13) bash "$MENU/blacklist.sh" ;;
            14) bash "$MENU/port.sh" ;;
            15) bash "$MENU/qnum.sh" ;;
            16) "$BASE/bin/firewallctl" status; echo ""; read -rp "按回车返回..." ;;
            17) bash "$MENU/autowhitelist.sh" ;;
            18) bash "$MENU/hostlist.sh" ;;
            19) bash "$MENU/blockcheck.sh" ;;
            20) bash "$MENU/uninstall.sh" ;;
            0) clear; exit 0 ;;
            *) warn "无效选择"; sleep 1 ;;
        esac
    done
}

main_menu
