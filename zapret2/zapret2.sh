#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 主菜单入口（专业 CLI）
# ============================================================

set -euo pipefail

BASE_DIR="/root/catmi/Zapret2"
BIN_DIR="$BASE_DIR/bin"
CFG_DIR="$BASE_DIR/config"
LIB_DIR="$BASE_DIR/lib"
SERVICE="zapret2.service"

source "$LIB_DIR/utils.sh"

FIREWALLCTL="$BIN_DIR/firewallctl"
HEALTHCHECK="$BIN_DIR/healthcheck"
ZAPRET2D="$BIN_DIR/zapret2d"

# ============================================================
# 基础操作
# ============================================================

cmd_install() {
    log_info "开始安装 Zapret2 v7.0..."

    systemctl stop "$SERVICE" 2>/dev/null || true

    bash "$LIB_DIR/smart_build.sh"

    log_info "安装完成，请执行：systemctl enable --now zapret2"
}

cmd_start() {
    log_info "启动 Zapret2..."
    systemctl start "$SERVICE"
}

cmd_stop() {
    log_info "停止 Zapret2..."
    systemctl stop "$SERVICE"
}

cmd_restart() {
    log_info "重启 Zapret2..."
    systemctl restart "$SERVICE"
}

cmd_status() {
    systemctl status "$SERVICE" --no-pager
}

cmd_logs() {
    journalctl -u "$SERVICE" -f
}

cmd_firewall_apply() {
    "$FIREWALLCTL" apply
}

cmd_firewall_clear() {
    "$FIREWALLCTL" clear
}

cmd_health() {
    "$HEALTHCHECK"
}

# ============================================================
# 模式切换（Local / Gateway）
# ============================================================

cmd_mode() {
    local mode="${1:-}"

    if [[ -z "$mode" ]]; then
        echo "当前模式：$(cat "$CFG_DIR/mode.conf")"
        return 0
    fi

    if [[ "$mode" != "local" && "$mode" != "gateway" ]]; then
        log_fatal "模式必须为 local 或 gateway"
    fi

    echo "$mode" > "$CFG_DIR/mode.conf"
    log_info "已切换模式为：$mode"
    systemctl restart "$SERVICE"
}

# ============================================================
# 策略管理
# ============================================================

cmd_strategy_edit() {
    nano "$CFG_DIR/strategy.conf"
    systemctl restart "$SERVICE"
}

cmd_strategy_show() {
    cat "$CFG_DIR/strategy.conf"
}

# ============================================================
# 端口管理
# ============================================================

cmd_ports_edit() {
    nano "$CFG_DIR/ports.conf"
    systemctl restart "$SERVICE"
}

cmd_ports_show() {
    cat "$CFG_DIR/ports.conf"
}

# ============================================================
# 节点管理
# ============================================================

cmd_nodes_list() {
    echo "节点列表："
    ls -1 "$CFG_DIR/nodes"
}

cmd_nodes_edit() {
    local node="$1"
    [[ -z "$node" ]] && log_fatal "必须指定节点名称"

    local dir="$CFG_DIR/nodes/$node"
    ensure_dir "$dir"

    echo "编辑节点：$node"
    echo "1) hostlist.txt"
    echo "2) iplist.txt"
    read -p "选择文件：" sel

    case "$sel" in
        1) nano "$dir/hostlist.txt" ;;
        2) nano "$dir/iplist.txt" ;;
        *) log_fatal "无效选择" ;;
    esac

    systemctl restart "$SERVICE"
}

# ============================================================
# 一键修复
# ============================================================

cmd_fix() {
    log_info "执行一键修复..."

    systemctl stop "$SERVICE" || true
    "$FIREWALLCTL" clear || true

    bash "$LIB_DIR/smart_build.sh"

    systemctl restart "$SERVICE"
    log_info "修复完成"
}

# ============================================================
# 帮助
# ============================================================

show_help() {
    cat <<EOF
Zapret2 v7.0 - 专业 CLI

用法：
  zapret2.sh install              安装 / 编译 nfqws2
  zapret2.sh start                启动服务
  zapret2.sh stop                 停止服务
  zapret2.sh restart              重启服务
  zapret2.sh status               查看状态
  zapret2.sh logs                 查看日志

  zapret2.sh mode [local|gateway] 查看/切换模式

  zapret2.sh strategy edit        编辑策略
  zapret2.sh strategy show        查看策略

  zapret2.sh ports edit           编辑端口
  zapret2.sh ports show           查看端口

  zapret2.sh nodes list           列出节点
  zapret2.sh nodes edit <name>    编辑节点

  zapret2.sh firewall apply       加载防火墙
  zapret2.sh firewall clear       清理防火墙

  zapret2.sh health               健康检查
  zapret2.sh fix                  一键修复
EOF
}

# ============================================================
# 主入口
# ============================================================

cmd="${1:-}"

case "$cmd" in
    install) cmd_install ;;
    start) cmd_start ;;
    stop) cmd_stop ;;
    restart) cmd_restart ;;
    status) cmd_status ;;
    logs) cmd_logs ;;
    mode) shift; cmd_mode "$@" ;;
    strategy)
        case "${2:-}" in
            edit) cmd_strategy_edit ;;
            show) cmd_strategy_show ;;
            *) show_help ;;
        esac
        ;;
    ports)
        case "${2:-}" in
            edit) cmd_ports_edit ;;
            show) cmd_ports_show ;;
            *) show_help ;;
        esac
        ;;
    nodes)
        case "${2:-}" in
            list) cmd_nodes_list ;;
            edit) shift 2; cmd_nodes_edit "$@" ;;
            *) show_help ;;
        esac
        ;;
    firewall)
        case "${2:-}" in
            apply) cmd_firewall_apply ;;
            clear) cmd_firewall_clear ;;
            *) show_help ;;
        esac
        ;;
    health) cmd_health ;;
    fix) cmd_fix ;;
    *) show_help ;;
esac
