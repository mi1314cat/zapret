#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - firewall_nft.sh (Optimized)
# nftables 规则管理（无链污染 + 防止 zapret2d 自杀）
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ZAPRET2_CFG="/root/catmi/Zapret2/config"
QUEUE_NUM=200
TABLE_NAME="zapret2"

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
build_safe_sets() {
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
# 清理旧表
# ============================================================
cleanup_table() {
    nft list table inet "$TABLE_NAME" >/dev/null 2>&1 || return 0
    nft flush table inet "$TABLE_NAME" || true
    nft delete table inet "$TABLE_NAME" || true
}

# ============================================================
# 创建表和基础结构
# ============================================================
create_table() {
    nft add table inet "$TABLE_NAME"

    nft add chain inet "$TABLE_NAME" zapret2_out { type filter hook output priority mangle; policy accept; }
    nft add chain inet "$TABLE_NAME" zapret2_pre { type filter hook prerouting priority mangle; policy accept; }
    nft add chain inet "$TABLE_NAME" zapret2_fwd { type filter hook forward priority mangle; policy accept; }

    nft add set inet "$TABLE_NAME" safe_v4 { type ipv4_addr; flags interval; }
    nft add set inet "$TABLE_NAME" safe_v6 { type ipv6_addr; flags interval; }
}

# ============================================================
# 填充 SAFE 集合
# ============================================================
populate_safe_sets() {
    local v4_list v6_list

    if ((${#SAFE_V4[@]})); then
        v4_list=$(printf '%s,' "${SAFE_V4[@]}")
        v4_list="${v4_list%,}"
        nft add element inet "$TABLE_NAME" safe_v4 { $v4_list }
    fi

    if ((${#SAFE_V6[@]})); then
        v6_list=$(printf '%s,' "${SAFE_V6[@]}")
        v6_list="${v6_list%,}"
        nft add element inet "$TABLE_NAME" safe_v6 { $v6_list }
    fi
}

# ============================================================
# 构建通用排除规则（防止 zapret2d 自杀）
# ============================================================
add_common_excludes() {
    local chain="$1"

    # 排除 zapret2d 自身流量（UID 0）
    nft add rule inet "$TABLE_NAME" "$chain" meta skuid 0 return

    # 排除 loopback
    nft add rule inet "$TABLE_NAME" "$chain" iifname "lo" return
    nft add rule inet "$TABLE_NAME" "$chain" oifname "lo" return

    # 排除 SSH
    nft add rule inet "$TABLE_NAME" "$chain" tcp sport 22 return
    nft add rule inet "$TABLE_NAME" "$chain" tcp dport 22 return

    # 排除 SAFE 列表
    nft add rule inet "$TABLE_NAME" "$chain" ip daddr @safe_v4 return
    nft add rule inet "$TABLE_NAME" "$chain" ip6 daddr @safe_v6 return

    # DNS 豁免
    nft add rule inet "$TABLE_NAME" "$chain" udp dport 53 return
    nft add rule inet "$TABLE_NAME" "$chain" tcp dport 53 return
}

# ============================================================
# 为链添加 NFQUEUE 规则
# ============================================================
add_nfqueue_rules() {
    local chain="$1"

    if [[ -n "${TCP4_PORTS:-}" ]]; then
        nft add rule inet "$TABLE_NAME" "$chain" ip protocol tcp tcp dport { $TCP4_PORTS } queue num "$QUEUE_NUM" bypass
    fi

    if [[ -n "${UDP4_PORTS:-}" ]]; then
        nft add rule inet "$TABLE_NAME" "$chain" ip protocol udp udp dport { $UDP4_PORTS } queue num "$QUEUE_NUM" bypass
    fi

    if [[ -n "${TCP6_PORTS:-}" ]]; then
        nft add rule inet "$TABLE_NAME" "$chain" ip6 nexthdr tcp tcp dport { $TCP6_PORTS } queue num "$QUEUE_NUM" bypass
    fi

    if [[ -n "${UDP6_PORTS:-}" ]]; then
        nft add rule inet "$TABLE_NAME" "$chain" ip6 nexthdr udp udp dport { $UDP6_PORTS } queue num "$QUEUE_NUM" bypass
    fi
}

# ============================================================
# 应用 nftables 规则（Local / Gateway）
# ============================================================
apply_nft_rules() {
    local mode="$1"

    load_ports
    build_safe_sets

    cleanup_table
    create_table
    populate_safe_sets

    # OUTPUT（Local）
    add_common_excludes "zapret2_out"
    add_nfqueue_rules "zapret2_out"

    if [[ "$mode" == "gateway" ]]; then
        add_common_excludes "zapret2_pre"
        add_nfqueue_rules "zapret2_pre"

        add_common_excludes "zapret2_fwd"
        add_nfqueue_rules "zapret2_fwd"
    fi

    log_info "nftables 规则加载完成"
}

# ============================================================
# 清理 nftables 规则
# ============================================================
clear_nft_rules() {
    cleanup_table
    log_info "nftables 规则已清理"
}
