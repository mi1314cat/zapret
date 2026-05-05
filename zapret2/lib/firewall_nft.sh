#!/usr/bin/env bash
set -euo pipefail

TABLE_NAME="zapret2"
QUEUE_NUM=200
CFG="/root/catmi/Zapret2/config"

WL_FILE="$CFG/whitelist.txt"
BL_FILE="$CFG/blacklist.txt"

load_ports() {
    source "$CFG/ports.conf"
}

cleanup_table() {
    nft delete table inet "$TABLE_NAME" 2>/dev/null || true
}

create_table() {
    nft add table inet "$TABLE_NAME"

    nft add chain inet "$TABLE_NAME" zapret2_out
    nft add chain inet "$TABLE_NAME" zapret2_pre
    nft add chain inet "$TABLE_NAME" zapret2_fwd

    # 基础豁免：本机、DNS 等
    nft add rule inet "$TABLE_NAME" zapret2_out meta skuid 0 return
    nft add rule inet "$TABLE_NAME" zapret2_out iifname "lo" return
    nft add rule inet "$TABLE_NAME" zapret2_out tcp dport 53 return
    nft add rule inet "$TABLE_NAME" zapret2_out udp dport 53 return
}

add_whitelist_rules() {
    local chain="$1"

    [[ -f "$WL_FILE" ]] || return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # 白名单：Zapret2 不处理
        nft add rule inet "$TABLE_NAME" "$chain" ip daddr "$line" return 2>/dev/null || true
        nft add rule inet "$TABLE_NAME" "$chain" ip6 daddr "$line" return 2>/dev/null || true
    done < "$WL_FILE"
}

add_blacklist_rules() {
    local chain="$1"

    [[ -f "$BL_FILE" ]] || return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # 黑名单：强制进入 NFQUEUE
        nft add rule inet "$TABLE_NAME" "$chain" ip daddr "$line" queue num "$QUEUE_NUM" bypass 2>/dev/null || true
        nft add rule inet "$TABLE_NAME" "$chain" ip6 daddr "$line" queue num "$QUEUE_NUM" bypass 2>/dev/null || true
    done < "$BL_FILE"
}

add_nfqueue_rules() {
    local chain="$1"

    [[ -n "${TCP4_PORTS:-}" ]] && nft add rule inet "$TABLE_NAME" "$chain" tcp dport { $TCP4_PORTS } queue num "$QUEUE_NUM" bypass
    [[ -n "${UDP4_PORTS:-}" ]] && nft add rule inet "$TABLE_NAME" "$chain" udp dport { $UDP4_PORTS } queue num "$QUEUE_NUM" bypass
    [[ -n "${TCP6_PORTS:-}" ]] && nft add rule inet "$TABLE_NAME" "$chain" tcp dport { $TCP6_PORTS } queue num "$QUEUE_NUM" bypass
    [[ -n "${UDP6_PORTS:-}" ]] && nft add rule inet "$TABLE_NAME" "$chain" udp dport { $UDP6_PORTS } queue num "$QUEUE_NUM" bypass
}

apply_nft_rules() {
    local mode="$1"

    load_ports
    cleanup_table
    create_table

    # 出站链：先白名单 → 黑名单 → 默认 NFQUEUE
    add_whitelist_rules "zapret2_out"
    add_blacklist_rules "zapret2_out"
    add_nfqueue_rules "zapret2_out"

    if [[ "$mode" == "gateway" ]]; then
        # 网关模式：PREROUTING/FORWARD 也加
        add_whitelist_rules "zapret2_pre"
        add_blacklist_rules "zapret2_pre"
        add_nfqueue_rules "zapret2_pre"

        add_whitelist_rules "zapret2_fwd"
        add_blacklist_rules "zapret2_fwd"
        add_nfqueue_rules "zapret2_fwd"
    fi

    echo "[INFO] nftables 规则加载完成"
}

clear_nft_rules() {
    cleanup_table
}
