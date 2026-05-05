#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - firewall_iptables.sh
# iptables 热交换（无重复挂载 + 无链污染）
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
# 检查 hook 是否已存在（避免重复挂载）
# ============================================================
hook_exists() {
    local cmd="$1"
    local hook="$2"
    local chain="$3"

    $cmd -t mangle -C "$hook" -j "$chain" >/dev/null 2>&1
}

# ============================================================
# 删除旧链（如果存在）
# ============================================================
delete_chain_if_exists() {
    local cmd="$1"
    local chain="$2"

    if $cmd -t mangle -L "$chain" >/dev/null 2>&1; then
        $cmd -t mangle -F "$chain" 2>/dev/null || true
        $cmd -t mangle -X "$chain" 2>/dev/null || true
    fi
}

# ============================================================
# 创建热交换链（NEW → swap → delete old）
# ============================================================
swap_chain() {
    local cmd="$1"
    local chain="$2"
    local hook="$3"

    local new="${chain}_NEW"

    # 清理旧 NEW 链
    delete_chain_if_exists "$cmd" "$new"

    # 创建 NEW 链
    $cmd -t mangle -N "$new"

    # DNS 豁免
    $cmd -t mangle -A "$new" -p udp --dport 53 -j RETURN
    $cmd -t mangle -A "$new" -p tcp --dport 53 -j RETURN

    # SAFE 列表豁免
    local is_v6=0
    [[ "$cmd" =~ ip6 ]] && is_v6=1

    if (( is_v6 == 0 )); then
        for net in "${SAFE_V4[@]}"; do
            $cmd -t mangle -A "$new" -d "$net" -j RETURN
        done

        [[ -n "${TCP4_PORTS:-}" ]] && \
            $cmd -t mangle -A "$new" -p tcp -m multiport --dports "$TCP4_PORTS" -j NFQUEUE --queue-num "$QUEUE_NUM" --queue-bypass

        [[ -n "${UDP4_PORTS:-}" ]] && \
            $cmd -t mangle -A "$new" -p udp -m multiport --dports "$UDP4_PORTS" -j NFQUEUE --queue-num "$QUEUE_NUM" --queue-bypass

    else
        for net in "${SAFE_V6[@]}"; do
            $cmd -t mangle -A "$new" -d "$net" -j RETURN
        done

        [[ -n "${TCP6_PORTS:-}" ]] && \
            $cmd -t mangle -A "$new" -p tcp -m multiport --dports "$TCP6_PORTS" -j NFQUEUE --queue-num "$QUEUE_NUM" --queue-bypass

        [[ -n "${UDP6_PORTS:-}" ]] && \
            $cmd -t mangle -A "$new" -p udp -m multiport --dports "$UDP6_PORTS" -j NFQUEUE --queue-num "$QUEUE_NUM" --queue-bypass
    fi

    # 插入 NEW 链（避免重复）
    if ! hook_exists "$cmd" "$hook" "$chain"; then
        $cmd -t mangle -I "$hook" -j "$new"
    fi

    # 删除旧链
    delete_chain_if_exists "$cmd" "$chain"

    # NEW → chain
    $cmd -t mangle -E "$new" "$chain"
}

# ============================================================
# 应用 iptables 规则（Local / Gateway）
# ============================================================
apply_iptables_rules() {
    local mode="$1"

    load_ports
    build_safe_lists

    local ipt4="iptables"
    local ipt6="ip6tables"

    # OUTPUT（Local）
    swap_chain "$ipt4" "ZAPRET2_OUT" "OUTPUT"
    swap_chain "$ipt6" "ZAPRET2_OUT" "OUTPUT"

    if [[ "$mode" == "gateway" ]]; then
        swap_chain "$ipt4" "ZAPRET2_PRE" "PREROUTING"
        swap_chain "$ipt6" "ZAPRET2_PRE" "PREROUTING"

        swap_chain "$ipt4" "ZAPRET2_FWD" "FORWARD"
        swap_chain "$ipt6" "ZAPRET2_FWD" "FORWARD"
    fi

    log_info "iptables 规则加载完成"
}

# ============================================================
# 清理 iptables 规则
# ============================================================
clear_iptables_rules() {
    local cmds=(iptables iptables-legacy ip6tables ip6tables-legacy)

    for cmd in "${cmds[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || continue

        for chain in ZAPRET2_OUT ZAPRET2_PRE ZAPRET2_FWD; do
            $cmd -t mangle -D OUTPUT -j "$chain" 2>/dev/null || true
            $cmd -t mangle -D PREROUTING -j "$chain" 2>/dev/null || true
            $cmd -t mangle -D FORWARD -j "$chain" 2>/dev/null || true

            delete_chain_if_exists "$cmd" "$chain"
        done
    done

    log_info "iptables 规则已清理"
}
