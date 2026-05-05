#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - 核心参数构建器 + nfqws2 启动器
# 只负责：读取配置 → 生成参数 → 启动 nfqws2
# 不负责：锁、防火墙、守护、健康循环
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
BIN="$BASE/bin"
CFG="$BASE/config"

NFQWS_BIN="$BIN/nfqws2"

# ============================================================
# 读取模式 / 配置
# ============================================================
get_mode() {
    if [[ -f "$CFG/mode.conf" ]]; then
        cat "$CFG/mode.conf"
    else
        echo "local"
    fi
}

# 这里可以根据你的实际配置结构调整
build_nfqws_args() {
    local mode
    mode="$(get_mode)"

    # 基础参数
    local args=()

    # 示例：根据模式切换不同参数
    case "$mode" in
        local)
            args+=(
                "--queue-num" "100"
                "--bind-addr" "127.0.0.1"
            )
            ;;
        gateway)
            args+=(
                "--queue-num" "100"
                "--bind-addr" "0.0.0.0"
            )
            ;;
        *)
            echo "[WARN] 未知模式：$mode，使用 local"
            args+=(
                "--queue-num" "100"
                "--bind-addr" "127.0.0.1"
            )
            ;;
    esac

    # TODO: 如果你有更多配置（节点、策略等），可以在这里继续拼接 args

    printf '%s\n' "${args[@]}"
}

# ============================================================
# 启动 nfqws2（单次）
# ============================================================
zapret2_core_start_nfqws2() {
    local args
    mapfile -t args < <(build_nfqws_args)

    echo "[INFO] 启动 nfqws2..."
    exec "$NFQWS_BIN" "${args[@]}"
}

# ============================================================
# 兼容旧入口：zapret2_core_main
# zapret2d 里用的是：zapret2_core_main &
# ============================================================
zapret2_core_main() {
    zapret2_core_start_nfqws2
}
