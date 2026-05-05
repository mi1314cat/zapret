#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 小白引导式菜单（终极版）
# - 一键安装 / 启动 / 停止 / 重启 / 实时日志
# - 节点管理（自动编号）
# - 自动生成 hostlist/iplist
# - Blockcheck
# - 配置包处理数量
# - 防火墙管理
# - 健康检查（CPU=0 / NFQUEUE / 僵尸 PID）
# - 僵尸 PID 修复
# ============================================================

set -euo pipefail

# ================================
# 彩色定义
# ================================
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
WHITE="\e[97m"
BOLD="\e[1m"
RESET="\e[0m"

ok()    { echo -e "${GREEN}[✔]${RESET} $1"; }
err()   { echo -e "${RED}[✘]${RESET} $1"; }
warn()  { echo -e "${YELLOW}[!]${RESET} $1"; }
info()  { echo -e "${CYAN}[i]${RESET} $1"; }

title() {
    echo -e "${MAGENTA}${BOLD}"
    echo "╔══════════════════════════════════════════════╗"
    printf "║ %-42s ║\n" "$1"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

BASE="/root/catmi/Zapret2"
BIN="$BASE/bin"
CFG="$BASE/config"
PIDFILE="/run/zapret2.pid"
SERVICE="zapret2"

pause() {
    echo ""
    read -rp "按回车继续..."
}

# ================================
# 一键安装
# ================================
onekey_install() {
    title "一键安装"

    bash "$BASE/zapret2.sh" install || true
    systemctl enable --now "$SERVICE" || true

    ok "安装完成！Zapret2 已启动"
    pause
}

# ================================
# 启动 / 停止 / 重启 / 日志
# ================================
start_service() {
    systemctl start "$SERVICE"
    ok "Zapret2 已启动"
    pause
}

stop_service() {
    systemctl stop "$SERVICE"
    ok "Zapret2 已停止"
    pause
}

restart_service() {
    systemctl restart "$SERVICE"
    ok "Zapret2 已重启"
    pause
}

show_logs() {
    title "实时日志（Ctrl+C 退出）"
    journalctl -fu "$SERVICE"
}

# ================================
# 切换模式
# ================================
switch_mode() {
    title "切换模式"

    echo "当前模式：$(cat "$CFG/mode.conf")"
    echo ""
    echo "1) local"
    echo "2) gateway"
    read -rp "选择：" n

    case "$n" in
        1) echo "local" > "$CFG/mode.conf" ;;
        2) echo "gateway" > "$CFG/mode.conf" ;;
        *) err "无效选择"; pause; return ;;
    esac

    ok "模式已切换为：$(cat "$CFG/mode.conf")"
    bash "$BIN/firewallctl" apply || true
    systemctl restart "$SERVICE" || true
    pause
}

# ================================
# 节点管理（自动编号）
# ================================
node_menu() {
    while true; do
        clear
        title "节点管理"

        echo -e "${CYAN}编号 | 地址 | 端口${RESET}"
        echo "----------------------------------------"

        idx=1
        for f in "$CFG/nodes"/*.node; do
            [[ -f "$f" ]] || continue
            host=$(grep '^host=' "$f" | cut -d= -f2)
            port=$(grep '^port=' "$f" | cut -d= -f2)

            printf "${GREEN}%02d${RESET}) %-25s ${YELLOW}%s${RESET}\n" \
                "$idx" "$host" "$port"

            idx=$((idx + 1))
        done

        echo "----------------------------------------"
        echo ""
        echo "1) 添加节点"
        echo "2) 删除节点"
        echo "0) 返回"
        echo ""

        read -rp "选择：" choice

        case "$choice" in
            1)
                read -rp "请输入节点地址（IP 或域名）：" host
                read -rp "请输入端口：" port

                num=$(ls "$CFG/nodes"/*.node 2>/dev/null | wc -l)
                num=$((num + 1))
                file="$CFG/nodes/$(printf "%02d" "$num").node"

                cat > "$file" <<EOF
host=$host
port=$port
EOF

                ok "节点已添加：$host:$port"
                sleep 1
                ;;

            2)
                read -rp "请输入要删除的编号：" del
                file="$CFG/nodes/$(printf "%02d" "$del").node"

                if [[ -f "$file" ]]; then
                    rm -f "$file"
                    ok "已删除节点编号 $del"
                else
                    err "节点编号不存在"
                fi
                sleep 1
                ;;

            0) return ;;
            *) err "无效选择"; sleep 1 ;;
        esac
    done
}

# ================================
# 自动生成 hostlist/iplist
# ================================
generate_hostlist() {
    title "生成 hostlist/iplist"

    > "$CFG/hostlist.txt"
    > "$CFG/iplist.txt"

    for f in "$CFG/nodes"/*.node; do
        [[ -f "$f" ]] || continue
        host=$(grep '^host=' "$f" | cut -d= -f2)

        if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$host" >> "$CFG/iplist.txt"
        else
            echo "$host" >> "$CFG/hostlist.txt"
        fi
    done

    ok "hostlist/iplist 已生成"
    pause
}

# ================================
# Blockcheck
# ================================
run_blockcheck() {
    title "运行 Blockcheck"
    bash "$BASE/bin/blockcheck"
    pause
}

# ================================
# 配置包处理数量
# ================================
set_packet_config() {
    title "配置包处理数量"

    read -rp "NFQUEUE 队列号（默认 200）：" qnum
    read -rp "队列大小（默认 4096）：" qsize

    echo "QNUM=${qnum:-200}" > "$CFG/pkt.conf"
    echo "QSIZE=${qsize:-4096}" >> "$CFG/pkt.conf"

    ok "包处理数量已更新"
    pause
}

# ================================
# 防火墙管理
# ================================
firewall_menu() {
    title "防火墙管理"

    echo "1) 加载防火墙"
    echo "2) 清理防火墙"
    echo "0) 返回"
    read -rp "选择：" f

    case "$f" in
        1) bash "$BIN/firewallctl" apply; pause ;;
        2) bash "$BIN/firewallctl" clear; pause ;;
        0) return ;;
        *) err "无效选择"; pause ;;
    esac
}

# ================================
# 僵尸 PID 修复
# ================================
fix_zombie_pid() {
    title "修复 zapret2d 僵尸 PID"

    if [[ -f "$PIDFILE" ]]; then
        pid=$(cat "$PIDFILE")
        if [[ -n "$pid" && ! -d "/proc/$pid" ]]; then
            warn "检测到僵尸 PID 文件：$PIDFILE (PID=$pid 不存在)"
            rm -f "$PIDFILE"
            ok "已删除僵尸 PID 文件"
        else
            info "PID 文件存在且进程正常，无需修复"
        fi
    else
        info "没有 PID 文件，无需修复"
    fi

    systemctl reset-failed "$SERVICE" || true
    bash "$BIN/firewallctl" clear || true
    systemctl restart "$SERVICE" || true

    ok "zapret2d 已重新启动"
    pause
}

# ================================
# 健康检查（CPU=0 / NFQUEUE / 僵尸 PID）
# ================================
get_zapret_pid() {
    if [[ -f "$PIDFILE" ]]; then
        cat "$PIDFILE"
    else
        pgrep -x zapret2d || true
    fi
}

check_zombie_only() {
    if [[ -f "$PIDFILE" ]]; then
        pid=$(cat "$PIDFILE")
        if [[ -n "$pid" && ! -d "/proc/$pid" ]]; then
            warn "检测到僵尸 PID 文件：$PIDFILE (PID=$pid 不存在)"
            rm -f "$PIDFILE"
            ok "已删除僵尸 PID 文件"
        fi
    fi
}

check_cpu_stall() {
    local pid="$1"
    local samples=3
    local sleep_sec=2
    local zero_count=0

    [[ -z "$pid" ]] && return 1

    for _ in $(seq 1 "$samples"); do
        cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print int($1)}' || echo 0)
        if [[ "$cpu" -le 0 ]]; then
            zero_count=$((zero_count + 1))
        fi
        sleep "$sleep_sec"
    done

    if [[ "$zero_count" -ge "$samples" ]]; then
        warn "检测到 zapret2d CPU 长期为 0，疑似卡死 (PID=$pid)"
        return 1
    fi

    ok "zapret2d CPU 正常 (PID=$pid)"
    return 0
}

check_nfqueue() {
    if command -v iptables >/dev/null 2>&1; then
        if iptables -t mangle -S 2>/dev/null | grep -q "NFQUEUE"; then
            if [[ -f /proc/net/netfilter/nfnetlink_queue ]]; then
                qlines=$(wc -l < /proc/net/netfilter/nfnetlink_queue || echo 0)
                if [[ "$qlines" -eq 0 ]]; then
                    warn "NFQUEUE 规则存在，但队列为空，可能未正常工作"
                else
                    ok "NFQUEUE 队列存在 ($qlines 行)"
                fi
            else
                warn "未找到 /proc/net/netfilter/nfnetlink_queue，无法检测队列"
            fi
        else
            warn "未检测到 NFQUEUE 规则（可能未加载防火墙）"
        fi
    fi
}

restart_zapret2_health() {
    warn "准备清理防火墙并重启 zapret2d..."

    if [[ -x "$BIN/firewallctl" ]]; then
        "$BIN/firewallctl" clear || true
    fi

    systemctl reset-failed "$SERVICE" || true
    systemctl restart "$SERVICE"

    ok "zapret2d 已重启"
}

health_check() {
    title "Zapret2 健康检查"

    check_zombie_only

    pid=$(get_zapret_pid || true)

    if [[ -z "$pid" ]]; then
        warn "未找到 zapret2d 进程，尝试重启..."
        restart_zapret2_health
        pause
        return
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        warn "zapret2d PID=$pid 不存在，尝试重启..."
        restart_zapret2_health
        pause
        return
    fi

    if ! check_cpu_stall "$pid"; then
        restart_zapret2_health
        pause
        return
    fi

    check_nfqueue

    ok "健康检查完成，无需操作"
    pause
}

# ================================
# 主菜单
# ================================
main_menu() {
    while true; do
        clear
        title "Zapret2 v7.0 小白引导菜单"

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
        echo -e "${CYAN}7)${RESET} 切换模式"
        echo -e "${CYAN}8)${RESET} 修改策略"
        echo -e "${CYAN}9)${RESET} 修改端口"
        echo -e "${CYAN}10)${RESET} 节点管理"
        echo -e "${CYAN}11)${RESET} 防火墙管理"
        echo -e "${CYAN}12)${RESET} 健康检查（CPU/NFQUEUE/PID）"
        echo -e "${CYAN}13)${RESET} 一键修复（原有 fix）"
        echo -e "${CYAN}14)${RESET} 生成 hostlist/iplist"
        echo -e "${CYAN}15)${RESET} 运行 Blockcheck"
        echo -e "${CYAN}16)${RESET} 配置包处理数量"
        echo -e "${CYAN}17)${RESET} 修复僵尸 PID 并重启 zapret2d"
        echo -e "${CYAN}0)${RESET} 退出"
        echo ""

        read -rp "请输入数字：" choice

        case "$choice" in
            1) onekey_install ;;
            2) systemctl status "$SERVICE"; pause ;;
            3) start_service ;;
            4) stop_service ;;
            5) restart_service ;;
            6) show_logs ;;
            7) switch_mode ;;
            8) nano "$CFG/strategy.conf"; pause ;;
            9) nano "$CFG/ports.conf"; pause ;;
            10) node_menu ;;
            11) firewall_menu ;;
            12) health_check ;;
            13) bash "$BASE/zapret2.sh" fix; pause ;;
            14) generate_hostlist ;;
            15) run_blockcheck ;;
            16) set_packet_config ;;
            17) fix_zombie_pid ;;
            0) exit 0 ;;
            *) err "无效选择"; pause ;;
        esac
    done
}

main_menu
