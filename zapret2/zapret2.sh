#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 主菜单（完整版 1–21）
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
BIN="$BASE/bin"
LIB="$BASE/lib"
CFG="$BASE/config"
MENU="$BASE/Menu_options"

source "$LIB/utils.sh"

SERVICE="zapret2"

run_menu_script() {
    local script="$1"
    if [[ -x "$MENU/$script" ]]; then
        bash "$MENU/$script"
    else
        log_warn "菜单脚本不存在或不可执行：$MENU/$script"
        read -rp "按回车返回..."
    fi
}

one_key_install() {
    if [[ -x "$BASE/bootstrap.sh" ]]; then
        bash "$BASE/bootstrap.sh"
    else
        log_warn "未找到 bootstrap.sh，一键安装不可用"
        read -rp "按回车返回..."
    fi
}

view_status() {
    systemctl status "$SERVICE" --no-pager
    echo ""
    read -rp "按回车返回..."
}

start_zapret2() {
    log_info "启动 Zapret2..."
    systemctl start "$SERVICE"
    view_status
}

stop_zapret2() {
    log_warn "停止 Zapret2..."
    systemctl stop "$SERVICE"
    view_status
}

restart_zapret2() {
    log_info "重启 Zapret2..."
    systemctl restart "$SERVICE"
    view_status
}

tail_logs() {
    journalctl -u "$SERVICE" -f --no-pager
}

toggle_mode() {
    local mode_file="$CFG/mode.conf"
    local cur="local"

    [[ -f "$mode_file" ]] && cur="$(cat "$mode_file")"

    if [[ "$cur" == "local" ]]; then
        echo "gateway" > "$mode_file"
        log_info "已切换为 Gateway 模式"
    else
        echo "local" > "$mode_file"
        log_info "已切换为 Local 模式"
    fi

    echo "当前模式：$(cat "$mode_file")"
    read -rp "按回车返回..."
}

firewall_menu() {
    clear
    echo -e "${CYAN}=== 防火墙管理 ===${RESET}"
    echo "1) 加载规则"
    echo "2) 清理规则"
    echo "3) 查看规则"
    echo "0) 返回"
    read -rp "选择: " opt

    case "$opt" in
        1) bash "$BIN/firewallctl" apply ;;
        2) bash "$BIN/firewallctl" clear ;;
        3) bash "$BIN/firewallctl" status ;;
    esac

    echo ""
    read -rp "按回车返回..."
}

health_check_menu() {
    if [[ -x "$MENU/health.sh" ]]; then
        bash "$MENU/health.sh"
    else
        bash "$BIN/healthcheck"
        echo ""
        read -rp "按回车返回..."
    fi
}

main_menu() {
    while true; do
        clear
        echo -e "${GREEN}=========================================${RESET}"
        echo -e "${CYAN}        Zapret2 v7.0 控制面板${RESET}"
        echo -e "${GREEN}=========================================${RESET}"
        echo ""
        echo -e "${CYAN}1)${RESET} 一键安装"
        echo -e "${CYAN}2)${RESET} 查看运行状态"
        echo -e "${CYAN}3)${RESET} 启动 Zapret2"
        echo -e "${CYAN}4)${RESET} 停止 Zapret2"
        echo -e "${CYAN}5)${RESET} 重启 Zapret2"
        echo -e "${CYAN}6)${RESET} 实时日志"
        echo -e "${CYAN}7)${RESET} 切换模式（Local/Gateway）"
        echo -e "${CYAN}8)${RESET} 策略管理（自动编号）"
        echo -e "${CYAN}9)${RESET} 修改端口"
        echo -e "${CYAN}10)${RESET} 节点管理（自动编号）"
        echo -e "${CYAN}11)${RESET} 防火墙管理"
        echo -e "${CYAN}12)${RESET} 健康检查（CPU/NFQUEUE/PID）"
        echo -e "${CYAN}13)${RESET} 一键修复（原 fix）"
        echo -e "${CYAN}14)${RESET} 生成 hostlist/iplist"
        echo -e "${CYAN}15)${RESET} 运行 Blockcheck"
        echo -e "${CYAN}16)${RESET} 配置包处理数量（qnum/qsize）"
        echo -e "${CYAN}17)${RESET} 修复僵尸 PID 并重启 zapret2d"
        echo -e "${CYAN}18)${RESET} 白名单管理（Zapret2 不处理）"
        echo -e "${CYAN}19)${RESET} 黑名单管理（强制进入 Zapret2）"
        echo -e "${CYAN}20)${RESET} 卸载 Zapret2（删除所有文件）"
        echo -e "${CYAN}21)${RESET} 自动生成白名单（节点 + 本地地址）"
        echo ""
        echo -e "${CYAN}0)${RESET} 退出"
        echo ""
        read -rp "选择: " opt

        case "$opt" in
            1) one_key_install ;;
            2) view_status ;;
            3) start_zapret2 ;;
            4) stop_zapret2 ;;
            5) restart_zapret2 ;;
            6) tail_logs ;;
            7) toggle_mode ;;
            8) run_menu_script "strategy.sh" ;;
            9) run_menu_script "port.sh" ;;
            10) run_menu_script "nodes.sh" ;;
            11) firewall_menu ;;
            12) health_check_menu ;;
            13) run_menu_script "fix.sh" ;;
            14) run_menu_script "hostlist.sh" ;;
            15) run_menu_script "blockcheck.sh" ;;
            16) run_menu_script "qnum.sh" ;;
            17) run_menu_script "pidfix.sh" ;;
            18) run_menu_script "whitelist.sh" ;;
            19) run_menu_script "blacklist.sh" ;;
            20) run_menu_script "uninstall.sh" ;;
            21) run_menu_script "autowhitelist.sh" ;;
            0) exit 0 ;;
            *) log_warn "无效选择" ; sleep 1 ;;
        esac
    done
}

main_menu
