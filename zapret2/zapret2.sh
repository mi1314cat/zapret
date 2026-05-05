#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 小白引导式菜单（模块化终极版）
# 所有复杂功能均拆分到 Menu_options/*.sh
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
MENU="$BASE/Menu_options"

# 加载颜色模块
source "$MENU/colors.sh"

SERVICE="zapret2"
CFG="$BASE/config"

pause() {
    echo ""
    read -rp "按回车继续..."
}

# ================================
# 主菜单
# ================================
main_menu() {
    while true; do
        clear
        title "Zapret2 v7.0 小白引导菜单（模块化版）"

        # 服务状态
        if systemctl is-active --quiet "$SERVICE"; then
            status="${GREEN}运行中${RESET}"
        else
            status="${RED}未运行${RESET}"
        fi

        echo -e "服务状态：$status"
        echo -e "当前模式：${YELLOW}$(cat "$CFG/mode.conf")${RESET}"
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

        echo -e "${CYAN}0)${RESET} 退出"
        echo ""

        read -rp "请输入数字：" choice

        case "$choice" in
            1) bash "$MENU/install.sh" ;;
            2) systemctl status "$SERVICE"; pause ;;
            3) bash "$MENU/service.sh" start ;;
            4) bash "$MENU/service.sh" stop ;;
            5) bash "$MENU/service.sh" restart ;;
            6) bash "$MENU/service.sh" logs ;;
            7) bash "$MENU/service.sh" mode ;;
            8) bash "$MENU/strategy.sh" ;;
            9) nano "$CFG/ports.conf"; pause ;;
            10) bash "$MENU/nodes.sh" ;;
            11) bash "$MENU/firewall.sh" ;;
            12) bash "$MENU/health.sh" ;;
            13) bash "$BASE/zapret2.sh" fix; pause ;;
            14) bash "$MENU/hostlist.sh" ;;
            15) bash "$MENU/blockcheck.sh" ;;
            16) bash "$MENU/packet.sh" ;;
            17) bash "$MENU/pidfix.sh" ;;
            18) bash "$MENU/whitelist.sh" ;;
            19) bash "$MENU/blacklist.sh" ;;
            20) bash "$MENU/delete.sh" ;;
            21) bash "$MENU/auto_whitelist.sh" ;;

            0) exit 0 ;;
            *)
                err "无效选择"
                pause
                ;;
        esac
    done
}

main_menu
