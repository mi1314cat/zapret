#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - firewallctl
# 统一防火墙控制器（自动选择 nft / iptables）
# ============================================================

set -euo pipefail

BASE_DIR="/root/catmi/Zapret2"
CFG_DIR="$BASE_DIR/config"
LIB_DIR="$BASE_DIR/lib"

source "$LIB_DIR/utils.sh"

NFT_MOD="$LIB_DIR/firewall_nft.sh"
IPT_MOD="$LIB_DIR/firewall_iptables.sh"

# ============================================================
# 自动检测防火墙后端
# ============================================================
detect_backend() {
    # 用户强制指定
    if [[ -f "$CFG_DIR/backend.conf" ]]; then
        backend=$(cat "$CFG_DIR/backend.conf")
        echo "$backend"
        return 0
    fi

    # 优先 nft
    if command -v nft >/dev/null 2>&1; then
        echo "nft"
        return 0
    fi

    # 再尝试 iptables
    if command -v iptables >/dev/null 2>&1; then
        # 检查是否为 nft backend
        if iptables --version 2>&1 | grep -q "nf_tables"; then
            # 如果有 legacy，则优先 legacy
            if command -v iptables-legacy >/dev/null 2>&1; then
                echo "iptables-legacy"
            else
                echo "iptables"
            fi
        else
            echo "iptables"
        fi
        return 0
    fi

    log_fatal "未找到可用的防火墙后端（nft / iptables）"
}

# ============================================================
# 应用规则
# ============================================================
apply_rules() {
    local mode
    mode=$(cat "$CFG_DIR/mode.conf" 2>/dev/null || echo "local")

    local backend
    backend=$(detect_backend)

    log_info "使用防火墙后端：$backend"

    case "$backend" in
        nft)
            source "$NFT_MOD"
            apply_nft_rules "$mode"
            ;;
        iptables|iptables-legacy)
            source "$IPT_MOD"
            apply_iptables_rules "$mode"
            ;;
        *)
            log_fatal "未知防火墙后端：$backend"
            ;;
    esac
}

# ============================================================
# 清理规则
# ============================================================
clear_rules() {
    local backend
    backend=$(detect_backend)

    log_info "清理防火墙规则（后端：$backend）"

    case "$backend" in
        nft)
            source "$NFT_MOD"
            clear_nft_rules
            ;;
        iptables|iptables-legacy)
            source "$IPT_MOD"
            clear_iptables_rules
            ;;
        *)
            log_fatal "未知防火墙后端：$backend"
            ;;
    esac
}

# ============================================================
# 显示当前后端
# ============================================================
show_backend() {
    detect_backend
}

# ============================================================
# 主入口
# ============================================================
cmd="${1:-}"

case "$cmd" in
    apply)
        apply_rules
        ;;
    clear)
        clear_rules
        ;;
    backend)
        show_backend
        ;;
    *)
        echo "用法：firewallctl {apply|clear|backend}"
        exit 1
        ;;
esac
