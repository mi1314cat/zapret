#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - ip_validator.sh
# IPv4 / IPv6 / CIDR 合法性校验器（生产级）
# ============================================================

set -euo pipefail

# 引入 utils
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ============================================================
# IPv4 校验
# ============================================================
is_ipv4() {
    local ip="$1"

    # 基础格式：A.B.C.D
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    IFS='.' read -r a b c d <<< "$ip"

    # 每段必须 0–255
    ((a >= 0 && a <= 255)) || return 1
    ((b >= 0 && b <= 255)) || return 1
    ((c >= 0 && c <= 255)) || return 1
    ((d >= 0 && d <= 255)) || return 1

    return 0
}

# ============================================================
# IPv6 校验（支持压缩格式）
# ============================================================
is_ipv6() {
    local ip="$1"

    # 使用内核工具校验（最可靠）
    if printf "%s\n" "$ip" | grep -qiE '^[0-9a-f:]+$'; then
        if ip -6 route add blackhole "$ip" 2>/dev/null; then
            ip -6 route del blackhole "$ip" 2>/dev/null
            return 0
        fi
    fi

    return 1
}

# ============================================================
# CIDR 校验（IPv4 / IPv6）
# ============================================================
is_cidr() {
    local cidr="$1"

    # IPv4 CIDR
    if [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]{1,2})$ ]]; then
        local mask="${cidr#*/}"
        ((mask >= 0 && mask <= 32)) || return 1
        local ip="${cidr%/*}"
        is_ipv4 "$ip" || return 1
        return 0
    fi

    # IPv6 CIDR
    if [[ "$cidr" =~ ^[0-9a-fA-F:]+/[0-9]{1,3}$ ]]; then
        local mask="${cidr#*/}"
        ((mask >= 0 && mask <= 128)) || return 1
        local ip="${cidr%/*}"
        is_ipv6 "$ip" || return 1
        return 0
    fi

    return 1
}

# ============================================================
# 自动判断 IPv4 / IPv6 / CIDR
# ============================================================
is_valid_ip_or_cidr() {
    local x="$1"

    is_ipv4 "$x" && return 0
    is_ipv6 "$x" && return 0
    is_cidr "$x" && return 0

    return 1
}

# ============================================================
# 清洗一行 IP（非法则返回空）
# ============================================================
clean_ip_line() {
    local line="$1"
    line="${line//[[:space:]]/}"   # 去空白

    if is_valid_ip_or_cidr "$line"; then
        printf "%s\n" "$line"
    fi
}

# ============================================================
# 批量清洗（输入文件 → 输出文件）
# ============================================================
clean_ip_file() {
    local infile="$1"
    local outfile="$2"

    ensure_file "$infile"
    ensure_dir "$(dirname "$outfile")"

    > "$outfile"

    while IFS= read -r line || [[ -n "$line" ]]; do
        cleaned=$(clean_ip_line "$line" || true)
        [[ -n "$cleaned" ]] && echo "$cleaned" >> "$outfile"
    done < "$infile"

    # 去重
    sort -u -o "$outfile" "$outfile"
}
