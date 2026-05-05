#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - firewall_nft.sh
# nft 原子加载（严格事务 + 无裸奔窗口）
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ZAPRET2_CFG="/root/catmi/Zapret2/config"
QUEUE_NUM=200

# ============================================================
# 读取端口配置
# ============================================================
load_ports() {
    source "$ZAPRET2_CFG/ports.conf"
}

# ============================================================
# 获取本机 IP（并去重）
# ============================================================
get_local_ips() {
    local tmp="/tmp/zapret2_local_ip.tmp"
    > "$tmp"

    ip -4 addr show scope global | awk '/inet / {split($2,a,"/"); print a[1]}' >> "$tmp"
    ip -6 addr show scope global | awk '/inet6 / {split($2,a,"/"); print a[1]}' >> "$tmp"

    sort -u "$tmp"
}

# ============================================================
# 构建 SAFE 列表（保留网段 + 本机 IP）
# ============================================================
build_safe_lists() {
    SAFE_V4=(
        "127.0.0.0/8"
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
    )

    SAFE_V6=(
        "::1/128"
        "fe80::/10"
        "fc00::/7"
    )

    while IFS= read -r ip; do
        [[ "$ip" =~ : ]] && SAFE_V6+=("$ip") || SAFE_V4+=("$ip")
    done < <(get_local_ips)

    SAFE_V4=($(printf '%s\n' "${SAFE_V4[@]}" | sort -u))
    SAFE_V6=($(printf '%s\n' "${SAFE_V6[@]}" | sort -u))
}

# ============================================================
# 生成 nft 事务文件
# ============================================================
generate_nft_file() {
    local nft_file="$1"
    local mode="$2"

    load_ports
    build_safe_lists

    {
        echo "delete table inet zapret2"
        echo "table inet zapret2 {"

        # -------------------------------
        # OUTPUT 链（Local 模式必需）
        # -------------------------------
        echo "  chain zapret2_output {"
        echo "    type filter hook output priority -150;"
        echo "    udp dport 53 return"
        echo "    tcp dport 53 return"

        for net in "${SAFE_V4[@]}"; do echo "    ip daddr $net return"; done
        for net in "${SAFE_V6[@]}"; do echo "    ip6 daddr $net return"; done

        [[ -n "${TCP4_PORTS:-}" ]] && echo "    meta l4proto tcp tcp dport { $TCP4_PORTS } queue num $QUEUE_NUM bypass"
        [[ -n "${UDP4_PORTS:-}" ]] && echo "    meta l4proto udp udp dport { $UDP4_PORTS } queue num $QUEUE_NUM bypass"
        [[ -n "${TCP6_PORTS:-}" ]] && echo "    meta l4proto tcp tcp dport { $TCP6_PORTS } queue num $QUEUE_NUM bypass"
        [[ -n "${UDP6_PORTS:-}" ]] && echo "    meta l4proto udp udp dport { $UDP6_PORTS } queue num $QUEUE_NUM bypass"

        echo "  }"

        # -------------------------------
        # Gateway 模式：PREROUTING + FORWARD
        # -------------------------------
        if [[ "$mode" == "gateway" ]]; then
            for chain in zapret2_prerouting zapret2_forward; do
                hook="prerouting"
                [[ "$chain" == "zapret2_forward" ]] && hook="forward"

                echo "  chain $chain {"
                echo "    type filter hook $hook priority -150;"
                echo "    udp dport 53 return"
                echo "    tcp dport 53 return"

                for net in "${SAFE_V4[@]}"; do echo "    ip daddr $net return"; done
                for net in "${SAFE_V6[@]}"; do echo "    ip6 daddr $net return"; done

                [[ -n "${TCP4_PORTS:-}" ]] && echo "    meta l4proto tcp tcp dport { $TCP4_PORTS } queue num $QUEUE_NUM bypass"
                [[ -n "${UDP4_PORTS:-}" ]] && echo "    meta l4proto udp udp dport { $UDP4_PORTS } queue num $QUEUE_NUM bypass"
                [[ -n "${TCP6_PORTS:-}" ]] && echo "    meta l4proto tcp tcp dport { $TCP6_PORTS } queue num $QUEUE_NUM bypass"
                [[ -n "${UDP6_PORTS:-}" ]] && echo "    meta l4proto udp udp dport { $UDP6_PORTS } queue num $QUEUE_NUM bypass"

                echo "  }"
            done
        fi

        echo "}"
    } > "$nft_file"
}

# ============================================================
# 应用 nft 规则（原子加载）
# ============================================================
apply_nft_rules() {
    local mode="$1"
    local nft_file="/tmp/zapret2_atomic.nft"

    generate_nft_file "$nft_file" "$mode"

    log_info "加载 nft 原子规则..."
    if ! nft -f "$nft_file" 2>/dev/null; then
        log_fatal "nft 规则加载失败，请检查配置"
    fi

    log_info "nft 规则加载完成"
}

# ============================================================
# 清理 nft 规则
# ============================================================
clear_nft_rules() {
    nft delete table inet zapret2 2>/dev/null || true
    log_info "nft 规则已清理"
}
