#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - healthcheck
# 健康检查：队列占用、卡死检测、资源监控
# ============================================================

set -euo pipefail

BASE_DIR="/root/catmi/Zapret2"
LIB_DIR="$BASE_DIR/lib"

source "$LIB_DIR/utils.sh"

NFQWS_BIN="$BASE_DIR/nfqws2"
QUEUE_NUM=200

# ============================================================
# 检查 nfqws2 是否在运行
# ============================================================
check_process() {
    if ! pgrep -x nfqws2 >/dev/null 2>&1; then
        log_error "nfqws2 未运行"
        return 1
    fi
    return 0
}

# ============================================================
# 检查 NFQUEUE 是否被占用
# ============================================================
check_nfqueue() {
    if ss -u -a | grep -q "nfqueue"; then
        # 检查是否为 nfqws2 自己占用
        local pid
        pid=$(pgrep -x nfqws2 || true)

        if [[ -z "$pid" ]]; then
            log_error "NFQUEUE 被未知进程占用"
            return 1
        fi

        # 如果 nfqws2 在运行，则视为正常
        return 0
    fi

    # 如果 nfqws2 在运行但队列未占用 → 异常
    if pgrep -x nfqws2 >/dev/null 2>&1; then
        log_error "nfqws2 运行中但未占用 NFQUEUE"
        return 1
    fi

    return 0
}

# ============================================================
# 检查 CPU 占用（卡死检测）
# ============================================================
check_cpu() {
    local pid
    pid=$(pgrep -x nfqws2 || true)

    [[ -z "$pid" ]] && return 0

    local cpu
    cpu=$(ps -p "$pid" -o %cpu= | awk '{print int($1)}')

    # 如果 CPU 长时间为 0 → 可能卡死
    if (( cpu == 0 )); then
        log_warn "nfqws2 CPU 占用为 0，可能卡死"
        return 1
    fi

    return 0
}

# ============================================================
# 检查内存泄漏
# ============================================================
check_memory() {
    local pid
    pid=$(pgrep -x nfqws2 || true)

    [[ -z "$pid" ]] && return 0

    local mem
    mem=$(ps -p "$pid" -o rss= | awk '{print int($1)}')

    # 超过 200MB 视为异常
    if (( mem > 200000 )); then
        log_warn "nfqws2 内存占用异常：${mem}KB"
        return 1
    fi

    return 0
}

# ============================================================
# 综合健康检查
# ============================================================
run_healthcheck() {
    local status=0

    check_process   || status=1
    check_nfqueue   || status=1
    check_cpu       || status=1
    check_memory    || status=1

    if (( status == 0 )); then
        log_info "健康检查通过"
    else
        log_error "健康检查失败"
    fi

    return "$status"
}

# ============================================================
# 主入口
# ============================================================
run_healthcheck
