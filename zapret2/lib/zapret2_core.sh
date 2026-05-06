#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 核心调度逻辑（只负责 nfqws2）
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
BIN="$BASE/bin"
LIB="$BASE/lib"
CFG="$BASE/config"

source "$LIB/utils.sh"
source "$LIB/ip_validator.sh"
source "$LIB/node_loader.sh"
source "$LIB/strategy_parser.sh"

NFQWS2_BIN="$BIN/nfqws2"

# ============================================================
# 构建 nfqws2 参数
# ============================================================
zapret2_core_build_args() {
    local qnum qsize port1 port2

    # 读取端口
    port1=$(grep -oP 'port1=\K\d+' "$CFG/ports.conf")
    port2=$(grep -oP 'port2=\K\d+' "$CFG/ports.conf")

    # 读取 NFQUEUE 参数
    qnum=$(grep -oP 'qnum=\K\d+' "$CFG/qnum.conf")
    qsize=$(grep -oP 'qsize=\K\d+' "$CFG/qnum.conf")

    NFQWS2_ARGS=(
        --qnum "$qnum"
        --qsize "$qsize"
        --port "$port1"
        --port "$port2"
    )

    # 节点参数
    node_args=$(load_node_args)
    if [[ -n "$node_args" ]]; then
        NFQWS2_ARGS+=($node_args)
    fi

    # 策略参数
    strategy_args=$(parse_strategy)
    if [[ -n "$strategy_args" ]]; then
        NFQWS2_ARGS+=($strategy_args)
    fi
}

# ============================================================
# 启动 nfqws2
# ============================================================
zapret2_core_main() {
    require_root

    if [[ ! -x "$NFQWS2_BIN" ]]; then
        err "未找到 nfqws2：$NFQWS2_BIN"
        return 1
    fi

    zapret2_core_build_args

    info "[CORE] 启动 nfqws2：$NFQWS2_BIN ${NFQWS2_ARGS[*]}"
    "$NFQWS2_BIN" "${NFQWS2_ARGS[@]}" &
}
