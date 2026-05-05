#!/usr/bin/env bash
# ============================================================
# Zapret2 v7.0 - node_loader.sh
# 节点系统：hostlist/iplist 合并 + 清洗 + 去重（生产级）
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/ip_validator.sh"

# ============================================================
# 清洗域名（去协议、路径、端口）
# ============================================================
clean_domain() {
    local d="$1"

    # 去空白
    d="$(echo "$d" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

    # 去协议
    d="${d#http://}"
    d="${d#https://}"

    # 去路径
    d="${d%%/*}"

    # 去端口
    d="${d%%:*}"

    # 必须包含至少一个点（避免 localhost / test）
    [[ "$d" =~ \. ]] || return 1

    printf "%s\n" "$d"
}

# ============================================================
# 批量清洗域名文件
# ============================================================
clean_domain_file() {
    local infile="$1"
    local outfile="$2"

    ensure_file "$infile"
    ensure_dir "$(dirname "$outfile")"

    > "$outfile"

    while IFS= read -r line || [[ -n "$line" ]]; do
        cleaned=$(clean_domain "$line" || true)
        [[ -n "$cleaned" ]] && echo "$cleaned" >> "$outfile"
    done < "$infile"

    sort -u -o "$outfile" "$outfile"
}

# ============================================================
# 加载所有节点（hostlist/iplist）
# ============================================================
load_nodes() {
    local profile_dir="$1"
    local tmp_host="$2"
    local tmp_ip="$3"

    > "$tmp_host"
    > "$tmp_ip"

    ensure_dir "$profile_dir"

    for p in "$profile_dir"/*; do
        [[ -d "$p" ]] || continue

        # 域名节点
        if [[ -f "$p/hostlist.txt" ]]; then
            cat "$p/hostlist.txt" >> "$tmp_host"
        fi

        # IP 节点
        if [[ -f "$p/iplist.txt" ]]; then
            cat "$p/iplist.txt" >> "$tmp_ip"
        fi
    done
}

# ============================================================
# 生成最终 master_hostlist.txt / master_iplist.txt
# ============================================================
generate_master_lists() {
    local profile_dir="$1"
    local out_host="$2"
    local out_ip="$3"

    local tmp_host="/tmp/zapret2_host.tmp"
    local tmp_ip="/tmp/zapret2_ip.tmp"

    load_nodes "$profile_dir" "$tmp_host" "$tmp_ip"

    # 清洗域名
    clean_domain_file "$tmp_host" "$out_host"

    # 清洗 IP
    clean_ip_file "$tmp_ip" "$out_ip"

    # 如果为空则删除
    [[ -s "$out_host" ]] || rm -f "$out_host"
    [[ -s "$out_ip" ]] || rm -f "$out_ip"
}

# ============================================================
# 对外接口：生成 master 列表
# ============================================================
node_loader_main() {
    local profile_dir="$1"
    local out_host="$2"
    local out_ip="$3"

    log_info "正在合并节点列表..."
    generate_master_lists "$profile_dir" "$out_host" "$out_ip"
    log_info "节点列表生成完成"
}
