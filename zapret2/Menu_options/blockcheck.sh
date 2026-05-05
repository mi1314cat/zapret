#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - Blockcheck（最终优化版）
# 隔离环境运行 / 自动恢复 / 静默模式 / 并发锁
# ============================================================

set -euo pipefail

BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
BIN="$BASE/bin"
LOG="$BASE/logs/blockcheck.log"

source "$BASE/Menu_options/colors.sh"
source "$BASE/lib/utils.sh"

LOCK_FILE="/run/zapret2_blockcheck.lock"

BLOCKCHECK_BIN="$BIN/blockcheck2"

mkdir -p "$BASE/logs"

# ============================================================
# 静默模式
# ============================================================
SILENT=0
[[ "${1:-}" == "--silent" ]] && SILENT=1

# ============================================================
# 运行 Blockcheck（隔离环境）
# ============================================================
run_blockcheck() {
    [[ $SILENT -eq 0 ]] && title "运行 Blockcheck（隔离环境）"

    # -----------------------------
    # 1. 检查 blockcheck2 是否存在
    # -----------------------------
    if [[ ! -x "$BLOCKCHECK_BIN" ]]; then
        err "未找到 blockcheck2，可执行文件不存在"
        return
    fi

    # -----------------------------
    # 2. 备份系统状态（防止 Blockcheck 修改系统）
    # -----------------------------
    tmp_fw=$(mktemp)
    tmp_route=$(mktemp)

    nft list ruleset > "$tmp_fw" 2>/dev/null || true
    ip route show > "$tmp_route" 2>/dev/null || true

    info "已备份当前防火墙与路由状态"

    # -----------------------------
    # 3. 运行 Blockcheck（隔离）
    # -----------------------------
    info "开始运行 Blockcheck..."

    {
        echo "===== Blockcheck $(date '+%Y-%m-%d %H:%M:%S') ====="
        "$BLOCKCHECK_BIN"
        echo ""
    } | tee "$LOG"

    ok "Blockcheck 已完成，结果已保存到：$LOG"

    # -----------------------------
    # 4. 自动恢复系统状态
    # -----------------------------
    info "恢复防火墙与路由状态..."

    nft -f "$tmp_fw" 2>/dev/null || warn "恢复 nftables 失败"
    ip route flush table main 2>/dev/null || true
    while IFS= read -r r; do
        ip route add $r 2>/dev/null || true
    done < "$tmp_route"

    rm -f "$tmp_fw" "$tmp_route"

    ok "系统已恢复到运行 Blockcheck 前的状态"

    # -----------------------------
    # 5. 完成提示
    # -----------------------------
    if [[ $SILENT -eq 0 ]]; then
        echo ""
        read -rp "按回车返回..."
    fi
}

# ============================================================
# 主入口（带锁）
# ============================================================
with_lock "$LOCK_FILE" run_blockcheck
