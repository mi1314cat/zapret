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
source "$LIB/config.sh"
source "$LIB/qnum.sh"
source "$LIB/strategy.sh"
source "$LIB/nodes.sh"

NFQWS2_BIN="$BIN/nfqws2"

zapret2_core_build_args() {
    local mode ports qnum qsize node_args extra_args

    mode=$(get_mode)              # 来自 config.sh / mode.conf
    read_ports ports              # 来自 config.sh / ports.conf
    read_qnum qnum qsize          # 来自 qnum.sh / qnum.conf
    node_args=$(build_node_args)  # 来自 nodes.sh
    extra_args=$(build_strategy_args "$mode")  # 来自 strategy.sh

    # 这里你可以按你自己的 nfqws2 参数风格调整
    NFQWS2_ARGS=(
        --qnum "$qnum"
        --qsize "$qsize"
        --port "$ports"
    )

    if [[ -n "$node_args" ]]; then
        NFQWS2_ARGS+=($node_args)
    fi
    if [[ -n "$extra_args" ]]; then
        NFQWS2_ARGS+=($extra_args)
    fi
}

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
