#!/usr/bin/env bash
# 自动把节点 + 本地地址加入白名单

#!/usr/bin/env bash

# 1. 先处理静默模式
SILENT=0
[[ "${1:-}" == "--silent" ]] && SILENT=1

# 2. 再加载路径、颜色等
BASE="/root/catmi/Zapret2"
CFG="$BASE/config"
MENU="$BASE/Menu_options"
source "$MENU/colors.sh"

WL_FILE="$CFG/whitelist.txt"
NODES_DIR="$CFG/nodes"

# 3. 再输出标题（如果不是静默模式）
[[ $SILENT -eq 0 ]] && title "自动生成白名单（节点 + 本地地址）"


WL_FILE="$CFG/whitelist.txt"
NODES_DIR="$CFG/nodes"

title "自动生成白名单（节点 + 本地地址）"

echo "" > "$WL_FILE"

# -----------------------------
# 1. 本地保留网段
# -----------------------------
LOCAL_NETS=(
    "127.0.0.0/8"
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
)

for net in "${LOCAL_NETS[@]}"; do
    echo "$net" >> "$WL_FILE"
done

# -----------------------------
# 2. 本机 IP
# -----------------------------
ip -4 addr show scope global | awk '/inet /{split($2,a,"/");print a[1]}' >> "$WL_FILE"
ip -6 addr show scope global | awk '/inet6 /{split($2,a,"/");print a[1]}' >> "$WL_FILE"

# -----------------------------
# 3. 节点 IP/域名
# -----------------------------
for f in "$NODES_DIR"/*.node; do
    [[ -f "$f" ]] || continue
    host=$(grep '^host=' "$f" | cut -d= -f2)
    echo "$host" >> "$WL_FILE"
done

# 去重
sort -u "$WL_FILE" -o "$WL_FILE"

ok "白名单已自动生成："
echo ""
cat "$WL_FILE"
echo ""

read -rp "按回车继续..."
