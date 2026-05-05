#!/usr/bin/env bash
set -euo pipefail

TABLE_NAME="zapret2"
QUEUE_NUM=200
CFG="/root/catmi/Zapret2/config"

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

    nft add rule inet "$TABLE_NAME" zapret2_out meta skuid 0 return
    nft add rule inet "$TABLE_NAME" zapret2_out iifname "lo" return
    nft add rule inet "$TABLE_NAME" zapret2_out tcp dport 53 return
    nft add rule inet "$TABLE_NAME" zapret2_out udp dport 53 return
}

add_nfqueue_rules() {
    local chain="$1"

    [[ -n "${TCP4_PORTS:-}" ]] && nft add rule inet "$TABLE_NAME" "$chain" tcp dport { $TCP4_PORTS } queue num "$QUEUE_NUM" bypass
    [[ -n "${UDP4_PORTS:-}" ]] && nft add rule inet "$TABLE_NAME" "$chain" udp dport { $UDP4_PORTS } queue num "$QUEUE_NUM" bypass
}

apply_nft_rules() {
    local mode="$1"

    load_ports
    cleanup_table
    create_table

    add_nfqueue_rules "zapret2_out"

    if [[ "$mode" == "gateway" ]]; then
        add_nfqueue_rules "zapret2_pre"
        add_nfqueue_rules "zapret2_fwd"
    fi

    echo "[INFO] nftables 规则加载完成"
}

clear_nft_rules() {
    cleanup_table
}
