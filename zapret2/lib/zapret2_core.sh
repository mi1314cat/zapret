#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - zapret2_core.sh
# 核心参数构建器 + nfqws2 启动器（zapret2d）
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/strategy_parser.sh"
source "$SCRIPT_DIR/node_loader.sh"

ZAPRET2_DIR="/root/catmi/Zapret2"
ZAPRET2_CFG="$ZAPRET2_DIR/config"
PROFILE_DIR="$ZAPRET2_CFG/nodes"
NFQWS_BIN="$ZAPRET2_DIR/nfqws2"
QUEUE_NUM=200

LOG_FILE="/var/log/zapret2/nfqws2.log"

ensure_dir "/var/log/zapret2"

# ============================================================
# 加载基础配置
# ============================================================
load_base_config() {
    source "$ZAPRET2_CFG/pkt.conf"
    source "$ZAPRET2_CFG/ports.conf"
    MODE=$(cat "$ZAPRET2_CFG/mode.conf" 2>/dev/null || echo "local")
}

# ============================================================
# 构建 nfqws2 参数数组
# ============================================================
build_nfqws_args() {
    local -n out="$1"
    out=()

    # 基础参数
    out+=("--queue-num=$QUEUE_NUM")
    out+=("--queue-bypass")
    out+=("--tcp-pkt-in=$TCP_PKT_IN")
    out+=("--tcp-pkt-out=$TCP_PKT_OUT")
    out+=("--udp-pkt-in=$UDP_PKT_IN")
    out+=("--udp-pkt-out=$UDP_PKT_OUT")

    # 策略参数（每行一个完整片段）
    while IFS= read -r token; do
        out+=("$token")
    done < <(parse_strategy_file "$ZAPRET2_CFG/strategy.conf")

    # 节点系统：生成 master 列表
    local master_host="$ZAPRET2_CFG/master_hostlist.txt"
    local master_ip="$ZAPRET2_CFG/master_iplist.txt"

    node_loader_main "$PROFILE_DIR" "$master_host" "$master_ip"

    [[ -f "$master_host" ]] && out+=("--hostlist=$master_host")
    [[ -f "$master_ip" ]] && out+=("--ipset=$master_ip")
}

# ============================================================
# zapret2d：守护进程（替代 run_nfqws2.sh）
# ============================================================
zapret2d() {
    require_root
    acquire_lock

    log_info "Zapret2 守护进程启动..."

    load_base_config

    # 构建参数
    local args=()
    build_nfqws_args args

    # 日志重定向
    exec > >(tee -a "$LOG_FILE") 2>&1

    echo "========== $(date) - zapret2d 启动 =========="

    # 清理旧进程
    if pgrep -x nfqws2 >/dev/null 2>&1; then
        log_warn "检测到旧 nfqws2 进程，正在终止..."
        killall -9 nfqws2 2>/dev/null || true
        sleep 1
    fi

    # 健康检查：队列占用检测
    if ss -u -a | grep -q "nfqueue"; then
        log_fatal "NFQUEUE 已被其他进程占用"
    fi

    # 最终执行命令
    log_info "执行命令：$NFQWS_BIN ${args[*]}"

    # systemd Watchdog 支持
    if [[ -n "${WATCHDOG_USEC:-}" ]]; then
        log_info "启用 systemd Watchdog"
        while true; do
            "$NFQWS_BIN" "${args[@]}" &
            pid=$!

            # 每 2 秒发送一次 watchdog 心跳
            while kill -0 "$pid" 2>/dev/null; do
                sleep 2
                systemd-notify WATCHDOG=1 || true
            done

            log_warn "nfqws2 崩溃，正在重启..."
            sleep 1
        done
    else
        # 无 watchdog
        exec "$NFQWS_BIN" "${args[@]}"
    fi
}

# ============================================================
# 对外接口
# ============================================================
zapret2_core_main() {
    zapret2d
}
