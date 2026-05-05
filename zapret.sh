#!/usr/bin/env bash
# ============================================================
# Zapret2 Panel v6.0 (Enhanced, Smart Build, aarch64)
# ============================================================

set -euo pipefail

ZAPRET2_DIR="/root/catmi/Zapret2"
ZAPRET2_CFG="$ZAPRET2_DIR/config"
PROFILE_DIR="$ZAPRET2_CFG/profiles"
SERVICE="nfqws2"
QUEUE_NUM=200

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; RESET="\e[0m"
msg(){ echo -e "$1"; }
ok(){ msg "${GREEN}[OK]${RESET} $1"; }
warn(){ msg "${YELLOW}[WARN]${RESET} $1"; }
err(){ msg "${RED}[ERR]${RESET} $1"; }
pause(){ read -rp "按回车继续..." _; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "请使用 root 账号运行此脚本！"
    exit 1
  fi
}

# -------------------------------
# 架构检测
# -------------------------------
detect_arch() {
  case "$(uname -m)" in
    aarch64) echo "aarch64" ;;
    armv7l|armv7) echo "armv7l" ;;
    x86_64|amd64) echo "x86_64" ;;
    *) err "未知架构：$(uname -m)"; exit 1 ;;
  esac
}

# -------------------------------
# 依赖检测（含 dev 包）
# -------------------------------
check_deps() {
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y \
    git make gcc curl \
    iptables nftables iproute2 psmisc ca-certificates \
    zlib1g-dev libcap-dev libmnl-dev libnfnetlink-dev libnetfilter-queue-dev \
    >/dev/null 2>&1 || true
}

# -------------------------------
# 二进制验证（架构 + 自检）
# -------------------------------
verify_binary() {
  local bin="$1"
  [[ -x "$bin" ]] || return 1
  local arch=$(detect_arch)
  local info=$(file -b "$bin" || true)

  case "$arch" in
    aarch64) [[ "$info" =~ "ARM" ]] || return 1 ;;
    armv7l)  [[ "$info" =~ "ARM" ]] || return 1 ;;
    x86_64)  [[ "$info" =~ "x86-64" ]] || return 1 ;;
  esac

  "$bin" --help >/dev/null 2>&1 || return 1
  return 0
}

# -------------------------------
# 源码准备
# -------------------------------
prepare_source() {
  rm -rf "$ZAPRET2_DIR"
  git clone --depth=1 https://github.com/bol-van/zapret "$ZAPRET2_DIR"
}

# -------------------------------
# make 成功检测（不能只看退出码）
# -------------------------------
check_make_success() {
  [[ -s "$1" ]]
}

# ============================================================
# 智能编译（Smart Build）
# ============================================================
smart_build_nfqws() {
  msg "${BLUE}开始智能编译 nfqws ...${RESET}"

  prepare_source
  cd "$ZAPRET2_DIR"

  # ① 快速编译
  warn "尝试快速编译 nfqws ..."
  if make -C nfq >/dev/null 2>&1 && check_make_success "nfq/nfqws"; then
    cp nfq/nfqws nfqws2
    verify_binary nfqws2 && ok "快速编译成功！" && return 0
  fi

  # ② 自动补依赖后编译
  warn "快速编译失败 → 自动补依赖后重试 ..."
  check_deps
  if make -C nfq >/dev/null 2>&1 && check_make_success "nfq/nfqws"; then
    cp nfq/nfqws nfqws2
    verify_binary nfqws2 && ok "补依赖后编译成功！" && return 0
  fi

  # ③ 全量编译 fallback
  warn "快速编译仍失败 → 执行全量编译 ..."
  if make >/dev/null 2>&1; then
    if [[ -x nfqws ]]; then cp nfqws nfqws2
    elif [[ -x binaries/my/nfqws ]]; then cp binaries/my/nfqws nfqws2
    elif ls binaries/*/nfqws >/dev/null 2>&1; then cp $(ls binaries/*/nfqws | head -n 1) nfqws2
    fi

    verify_binary nfqws2 && ok "全量编译成功！" && return 0
  fi

  err "智能编译失败：无法构建 nfqws。"
  exit 1
}
# ============================================================
# 生成 run_nfqws2.sh（核心运行引擎）
# ============================================================
generate_run_script() {
  cat > "$ZAPRET2_DIR/run_nfqws2.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

ZAPRET2_DIR="/root/catmi/Zapret2"
ZAPRET2_CFG="$ZAPRET2_DIR/config"
PROFILE_DIR="$ZAPRET2_CFG/profiles"
QUEUE_NUM=200

logfile="/var/log/nfqws2.log"
mkdir -p "$(dirname "$logfile")"
exec > >(tee -a "$logfile") 2>&1
echo "========== $(date) - nfqws2 启动 =========="

# 清理残留进程
if pgrep -x nfqws2 >/dev/null 2>&1; then
  killall -9 nfqws2 2>/dev/null || true
  sleep 1
fi

# 加载 pkt.conf
source "$ZAPRET2_CFG/pkt.conf"

# -------------------------------
# 基础参数
# -------------------------------
args=(
  "--queue-num=$QUEUE_NUM"
  "--queue-bypass"
  "--tcp-pkt-in=$TCP_PKT_IN"
  "--tcp-pkt-out=$TCP_PKT_OUT"
  "--udp-pkt-in=$UDP_PKT_IN"
  "--udp-pkt-out=$UDP_PKT_OUT"
)

# -------------------------------
# 解析策略文件（安全解析）
# -------------------------------
if [[ -f "$ZAPRET2_CFG/strategy.conf" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    read -r -a tokens <<<"$line"
    for t in "${tokens[@]}"; do
      [[ -n "$t" ]] && args+=("$t")
    done
  done < "$ZAPRET2_CFG/strategy.conf"
fi

# -------------------------------
# 节点系统：合并 hostlist/iplist
# -------------------------------
MASTER_HOST="$ZAPRET2_CFG/master_hostlist.txt"
MASTER_IP="$ZAPRET2_CFG/master_iplist.txt"
TMP_HOST="/tmp/zapret_host.tmp"
TMP_IP="/tmp/zapret_ip.tmp"
> "$TMP_HOST"
> "$TMP_IP"

if [[ -d "$PROFILE_DIR" ]]; then
  for p in "$PROFILE_DIR"/*; do
    [[ -d "$p" ]] || continue
    [[ -f "$p/hostlist.txt" ]] && cat "$p/hostlist.txt" >> "$TMP_HOST"
    [[ -f "$p/iplist.txt" ]] && cat "$p/iplist.txt" >> "$TMP_IP"
  done
fi

# 清洗域名
sed -e 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    -e 's|^https*://||i' \
    -e 's|/.*||' \
    -e 's|:[0-9]*||' "$TMP_HOST" \
  | awk 'NF' | sort -u > "$MASTER_HOST"

# 清洗 IP
grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?|([0-9a-fA-F:]+(:[0-9a-fA-F]+){1,7})(/[0-9]{1,3})?' \
  "$TMP_IP" | awk 'NF' | sort -u > "$MASTER_IP"

[[ -s "$MASTER_HOST" ]] || rm -f "$MASTER_HOST"
[[ -s "$MASTER_IP" ]] || rm -f "$MASTER_IP"

[[ -f "$MASTER_HOST" ]] && args+=("--hostlist=$MASTER_HOST")
[[ -f "$MASTER_IP" ]] && args+=("--ipset=$MASTER_IP")

echo "执行: $ZAPRET2_DIR/nfqws2 ${args[*]}"

if ! "$ZAPRET2_DIR/nfqws2" --help >/dev/null 2>&1; then
  echo "[ERR] nfqws2 二进制文件不可用或已损坏！"
  exit 1
fi

exec "$ZAPRET2_DIR/nfqws2" "${args[@]}"
SCRIPT

  chmod +x "$ZAPRET2_DIR/run_nfqws2.sh"
}

# ============================================================
# 生成 apply_rules.sh（原子化防火墙挂载）
# ============================================================
generate_firewall_scripts() {
  cat > "$ZAPRET2_DIR/apply_rules.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

ZAPRET2_DIR="/root/catmi/Zapret2"
ZAPRET2_CFG="$ZAPRET2_DIR/config"
QUEUE_NUM=200

source "$ZAPRET2_CFG/ports.conf"
MODE=$(cat "$ZAPRET2_CFG/mode.conf" 2>/dev/null || echo "local")

LOCAL_V4=$(ip -4 addr show scope global | awk '/inet / {split($2,a,"/"); print a[1]}')
LOCAL_V6=$(ip -6 addr show scope global | awk '/inet6 / {split($2,a,"/"); print a[1]}')

SAFE_V4=(127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16)
SAFE_V6=(::1/128 fe80::/10 fc00::/7)

while IFS= read -r ip; do [[ -n "$ip" ]] && SAFE_V4+=("$ip"); done <<< "$LOCAL_V4"
while IFS= read -r ip; do [[ -n "$ip" ]] && SAFE_V6+=("$ip"); done <<< "$LOCAL_V6"

backend="auto"
[[ -f "$ZAPRET2_CFG/backend" ]] && backend=$(cat "$ZAPRET2_CFG/backend")

if [[ "$backend" == "auto" ]]; then
  if command -v nft >/dev/null 2>&1; then
    backend="nft"
  elif command -v iptables >/dev/null 2>&1; then
    if iptables --version 2>&1 | grep -q "nf_tables"; then
      if command -v iptables-legacy >/dev/null 2>&1; then
        backend="iptables-legacy"
      else
        backend="iptables"
      fi
    else
      backend="iptables"
    fi
  else
    echo "[ERR] 无可用防火墙后端！"
    exit 1
  fi
fi

# ============================================================
# nftables 原子化加载
# ============================================================
if [[ "$backend" == "nft" ]]; then
  NFT_FILE="/tmp/zapret2_atomic.nft"

  cat > "$NFT_FILE" <<EOF
table inet zapret2
delete table inet zapret2
table inet zapret2 {
  chain zapret2_output {
    type filter hook output priority -150;
    udp dport 53 return
    tcp dport 53 return
EOF

  for net in "${SAFE_V4[@]}"; do echo "    ip daddr $net return" >> "$NFT_FILE"; done
  for net in "${SAFE_V6[@]}"; do echo "    ip6 daddr $net return" >> "$NFT_FILE"; done

  [[ -n "$TCP4_PORTS" ]] && echo "    meta l4proto tcp tcp dport { $TCP4_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
  [[ -n "$UDP4_PORTS" ]] && echo "    meta l4proto udp udp dport { $UDP4_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
  [[ -n "$TCP6_PORTS" ]] && echo "    meta l4proto tcp tcp dport { $TCP6_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
  [[ -n "$UDP6_PORTS" ]] && echo "    meta l4proto udp udp dport { $UDP6_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"

  echo "  }" >> "$NFT_FILE"

  if [[ "$MODE" == "gateway" ]]; then
    for chain in zapret2_prerouting zapret2_forward; do
      hook="prerouting"
      [[ "$chain" == "zapret2_forward" ]] && hook="forward"

      cat >> "$NFT_FILE" <<EOF
  chain $chain {
    type filter hook $hook priority -150;
    udp dport 53 return
    tcp dport 53 return
EOF

      for net in "${SAFE_V4[@]}"; do echo "    ip daddr $net return" >> "$NFT_FILE"; done
      for net in "${SAFE_V6[@]}"; do echo "    ip6 daddr $net return" >> "$NFT_FILE"; done

      [[ -n "$TCP4_PORTS" ]] && echo "    meta l4proto tcp tcp dport { $TCP4_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
      [[ -n "$UDP4_PORTS" ]] && echo "    meta l4proto udp udp dport { $UDP4_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
      [[ -n "$TCP6_PORTS" ]] && echo "    meta l4proto tcp tcp dport { $TCP6_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
      [[ -n "$UDP6_PORTS" ]] && echo "    meta l4proto udp udp dport { $UDP6_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"

      echo "  }" >> "$NFT_FILE"
    done
  fi

  echo "}" >> "$NFT_FILE"

  nft -f "$NFT_FILE"
  exit 0
fi

# ============================================================
# iptables / legacy 热交换链
# ============================================================
if [[ "$backend" == "iptables" || "$backend" == "iptables-legacy" ]]; then
  ipt4="iptables"; ipt6="ip6tables"
  [[ "$backend" == "iptables-legacy" ]] && ipt4="iptables-legacy" && ipt6="ip6tables-legacy"

  QUEUE="--queue-num $QUEUE_NUM --queue-bypass"

  swap_chain() {
    local cmd=$1 chain=$2 hook=$3
    local new="${chain}_NEW"

    $cmd -t mangle -N "$new" 2>/dev/null || $cmd -t mangle -F "$new"

    $cmd -t mangle -A "$new" -p udp --dport 53 -j RETURN
    $cmd -t mangle -A "$new" -p tcp --dport 53 -j RETURN

    local is_v6=0
    [[ "$cmd" =~ ip6 ]] && is_v6=1

    if [[ $is_v6 -eq 0 ]]; then
      for net in "${SAFE_V4[@]}"; do $cmd -t mangle -A "$new" -d "$net" -j RETURN; done
      [[ -n "$TCP4_PORTS" ]] && $cmd -t mangle -A "$new" -p tcp -m multiport --dports "$TCP4_PORTS" -j NFQUEUE $QUEUE
      [[ -n "$UDP4_PORTS" ]] && $cmd -t mangle -A "$new" -p udp -m multiport --dports "$UDP4_PORTS" -j NFQUEUE $QUEUE
    else
      for net in "${SAFE_V6[@]}"; do $cmd -t mangle -A "$new" -d "$net" -j RETURN; done
      [[ -n "$TCP6_PORTS" ]] && $cmd -t mangle -A "$new" -p tcp -m multiport --dports "$TCP6_PORTS" -j NFQUEUE $QUEUE
      [[ -n "$UDP6_PORTS" ]] && $cmd -t mangle -A "$new" -p udp -m multiport --dports "$UDP6_PORTS" -j NFQUEUE $QUEUE
    fi

    $cmd -t mangle -I "$hook" -j "$new"
    $cmd -t mangle -D "$hook" -j "$chain" 2>/dev/null || true
    $cmd -t mangle -F "$chain" 2>/dev/null || true
    $cmd -t mangle -X "$chain" 2>/dev/null || true
    $cmd -t mangle -E "$new" "$chain"
  }

  swap_chain "$ipt4" "ZAPRET2_OUT" "OUTPUT"
  swap_chain "$ipt6" "ZAPRET2_OUT" "OUTPUT"

  if [[ "$MODE" == "gateway" ]]; then
    swap_chain "$ipt4" "ZAPRET2_PRE" "PREROUTING"
    swap_chain "$ipt6" "ZAPRET2_PRE" "PREROUTING"
    swap_chain "$ipt4" "ZAPRET2_FWD" "FORWARD"
    swap_chain "$ipt6" "ZAPRET2_FWD" "FORWARD"
  fi

  exit 0
fi
SCRIPT

  chmod +x "$ZAPRET2_DIR/apply_rules.sh"
}

# ============================================================
# 生成 clear_rules.sh（焦土清理）
# ============================================================
generate_clear_script() {
  cat > "$ZAPRET2_DIR/clear_rules.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] 清理 Zapret2 防火墙规则..."

if command -v nft >/dev/null 2>&1; then
  nft delete table inet zapret2 2>/dev/null || true
fi

for cmd in iptables iptables-legacy ip6tables ip6tables-legacy; do
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" -t mangle -D OUTPUT -j ZAPRET2_OUT 2>/dev/null || true
    "$cmd" -t mangle -D PREROUTING -j ZAPRET2_PRE 2>/dev/null || true
    "$cmd" -t mangle -D FORWARD -j ZAPRET2_FWD 2>/dev/null || true

    for chain in ZAPRET2_OUT ZAPRET2_PRE ZAPRET2_FWD; do
      "$cmd" -t mangle -F "$chain" 2>/dev/null || true
      "$cmd" -t mangle -X "$chain" 2>/dev/null || true
    done
  fi
done

echo "[INFO] 清理完成"
SCRIPT

  chmod +x "$ZAPRET2_DIR/clear_rules.sh"
}

# ============================================================
# 生成 systemd 服务文件
# ============================================================
generate_systemd_service() {
  cat > /etc/systemd/system/"$SERVICE".service <<EOF
[Unit]
Description=Zapret2 nfqws2 DPI Bypass Service (v6.0)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
ExecStartPre=$ZAPRET2_DIR/apply_rules.sh
ExecStart=$ZAPRET2_DIR/run_nfqws2.sh
ExecStopPost=$ZAPRET2_DIR/clear_rules.sh

NoNewPrivileges=yes
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_KILL
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_KILL

Restart=on-failure
RestartSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}
# ============================================================
# 安装 Zapret2（完整流程）
# ============================================================
install_zapret2() {
  msg "${GREEN}开始安装 Zapret2 v6.0 ...${RESET}"

  check_deps
  smart_build_nfqws
  init_config
  generate_run_script
  generate_firewall_scripts
  generate_clear_script
  generate_systemd_service

  systemctl daemon-reload
  systemctl enable "$SERVICE" >/dev/null 2>&1 || true
  systemctl restart "$SERVICE" || true

  ok "Zapret2 v6.0 安装完成！"
}

# ============================================================
# 卸载 Zapret2
# ============================================================
uninstall_zapret2() {
  systemctl stop "$SERVICE" 2>/dev/null || true
  systemctl disable "$SERVICE" 2>/dev/null || true
  rm -f /etc/systemd/system/"$SERVICE".service
  systemctl daemon-reload

  [[ -f "$ZAPRET2_DIR/clear_rules.sh" ]] && "$ZAPRET2_DIR/clear_rules.sh" 2>/dev/null || true
  rm -rf "$ZAPRET2_DIR"

  ok "Zapret2 v6.0 已彻底卸载。"
}

# ============================================================
# 初始化配置目录
# ============================================================
init_config() {
  mkdir -p "$ZAPRET2_CFG" "$PROFILE_DIR"

  [[ -f "$ZAPRET2_CFG/ports.conf" ]] || cat > "$ZAPRET2_CFG/ports.conf" <<EOF
TCP4_PORTS="443,8443,7844"
UDP4_PORTS="443,8443,7844"
TCP6_PORTS="443,8443,7844"
UDP6_PORTS="443,8443,7844"
EOF

  [[ -f "$ZAPRET2_CFG/pkt.conf" ]] || cat > "$ZAPRET2_CFG/pkt.conf" <<EOF
TCP_PKT_OUT="9"
TCP_PKT_IN="3"
UDP_PKT_OUT="0"
UDP_PKT_IN="0"
EOF

  [[ -f "$ZAPRET2_CFG/strategy.conf" ]] || cat > "$ZAPRET2_CFG/strategy.conf" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
EOF

  [[ -f "$ZAPRET2_CFG/mode.conf" ]] || echo "local" > "$ZAPRET2_CFG/mode.conf"
}

# ============================================================
# 菜单：端口配置
# ============================================================
menu_ports() {
  [[ -f "$ZAPRET2_CFG/ports.conf" ]] || { err "请先安装 Zapret2！"; return; }
  source "$ZAPRET2_CFG/ports.conf"
  clear
  echo -e "${GREEN}当前端口配置：${RESET}"
  echo "TCP4_PORTS=\"$TCP4_PORTS\""
  echo "UDP4_PORTS=\"$UDP4_PORTS\""
  echo "TCP6_PORTS=\"$TCP6_PORTS\""
  echo "UDP6_PORTS=\"$UDP6_PORTS\""
  echo
  read -rp "TCP4_PORTS (回车保持不变): " input_tcp4
  read -rp "UDP4_PORTS (回车保持不变): " input_udp4
  read -rp "TCP6_PORTS (回车保持不变): " input_tcp6
  read -rp "UDP6_PORTS (回车保持不变): " input_udp6

  TCP4_PORTS=${input_tcp4:-$TCP4_PORTS}
  UDP4_PORTS=${input_udp4:-$UDP4_PORTS}
  TCP6_PORTS=${input_tcp6:-$TCP6_PORTS}
  UDP6_PORTS=${input_udp6:-$UDP6_PORTS}

  cat > "$ZAPRET2_CFG/ports.conf" <<EOF
TCP4_PORTS="$TCP4_PORTS"
UDP4_PORTS="$UDP4_PORTS"
TCP6_PORTS="$TCP6_PORTS"
UDP6_PORTS="$UDP6_PORTS"
EOF

  ok "端口已更新"
  systemctl restart "$SERVICE" 2>/dev/null || true
}

# ============================================================
# 菜单：包处理数量
# ============================================================
menu_pkt() {
  [[ -f "$ZAPRET2_CFG/pkt.conf" ]] || { err "请先安装 Zapret2！"; return; }
  source "$ZAPRET2_CFG/pkt.conf"
  clear
  echo -e "${GREEN}当前包处理配置：${RESET}"
  echo "TCP_PKT_OUT=\"$TCP_PKT_OUT\""
  echo "TCP_PKT_IN=\"$TCP_PKT_IN\""
  echo "UDP_PKT_OUT=\"$UDP_PKT_OUT\""
  echo "UDP_PKT_IN=\"$UDP_PKT_IN\""
  echo
  read -rp "TCP_PKT_OUT (回车保持不变): " in_t_out
  read -rp "TCP_PKT_IN (回车保持不变): " in_t_in
  read -rp "UDP_PKT_OUT (回车保持不变): " in_u_out
  read -rp "UDP_PKT_IN (回车保持不变): " in_u_in

  TCP_PKT_OUT=${in_t_out:-$TCP_PKT_OUT}
  TCP_PKT_IN=${in_t_in:-$TCP_PKT_IN}
  UDP_PKT_OUT=${in_u_out:-$UDP_PKT_OUT}
  UDP_PKT_IN=${in_u_in:-$UDP_PKT_IN}

  cat > "$ZAPRET2_CFG/pkt.conf" <<EOF
TCP_PKT_OUT="$TCP_PKT_OUT"
TCP_PKT_IN="$TCP_PKT_IN"
UDP_PKT_OUT="$UDP_PKT_OUT"
UDP_PKT_IN="$UDP_PKT_IN"
EOF

  ok "包处理配置已更新"
  systemctl restart "$SERVICE" 2>/dev/null || true
}

# ============================================================
# 菜单：策略管理
# ============================================================
menu_strategy() {
  [[ -d "$ZAPRET2_CFG" ]] || { err "请先安装 Zapret2！"; return; }
  while true; do
    clear
    echo -e "${GREEN}--- 全局 DPI 策略 ---${RESET}"
    [[ -f "$ZAPRET2_CFG/strategy.conf" ]] && cat "$ZAPRET2_CFG/strategy.conf"
    echo
    echo "1) Minimal（最小干扰）"
    echo "2) Stable（推荐）"
    echo "3) Aggressive（激进）"
    echo "4) 自定义策略（多行）"
    echo "0) 返回"
    read -rp "选择：" opt

    case "$opt" in
      1)
        echo "--lua-desync=fake:blob=fake_default_tls" > "$ZAPRET2_CFG/strategy.conf"
        ;;
      2)
        cat > "$ZAPRET2_CFG/strategy.conf" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
EOF
        ;;
      3)
        cat > "$ZAPRET2_CFG/strategy.conf" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
--lua-desync=multidisorder:pos=1
EOF
        ;;
      4)
        warn "请输入自定义策略（Ctrl+D 结束）："
        tmp=$(mktemp)
        cat > "$tmp"
        [[ -s "$tmp" ]] && mv "$tmp" "$ZAPRET2_CFG/strategy.conf"
        ;;
      0) break ;;
    esac

    if [[ "$opt" != "0" ]]; then
      ok "策略已更新"
      systemctl restart "$SERVICE" 2>/dev/null || true
      pause
    fi
  done
}

# ============================================================
# 菜单：节点管理
# ============================================================
menu_node() {
  [[ -d "$PROFILE_DIR" ]] || { err "请先安装 Zapret2！"; return; }
  while true; do
    clear
    echo -e "${GREEN}--- 节点管理（Argo / TUIC / HY2） ---${RESET}"
    echo "1) 添加节点"
    echo "2) 查看节点"
    echo "3) 删除节点"
    echo "0) 返回"
    read -rp "选择：" opt

    case "$opt" in
      1)
        read -rp "节点名称：" name
        [[ -z "$name" ]] && continue
        mkdir -p "$PROFILE_DIR/$name"

        echo "1) 域名节点"
        echo "2) IP 节点"
        read -rp "选择类型：" t

        if [[ "$t" == "1" ]]; then
          read -rp "输入域名：" val
          echo "$val" > "$PROFILE_DIR/$name/hostlist.txt"
        else
          read -rp "输入 IP 或 CIDR：" val
          echo "$val" > "$PROFILE_DIR/$name/iplist.txt"
        fi

        ok "节点添加完成"
        systemctl restart "$SERVICE" 2>/dev/null || true
        ;;
      2)
        ls "$PROFILE_DIR" 2>/dev/null || echo "无节点"
        ;;
      3)
        read -rp "要删除的节点：" name
        rm -rf "$PROFILE_DIR/$name"
        ok "节点已删除"
        systemctl restart "$SERVICE" 2>/dev/null || true
        ;;
      0) break ;;
    esac

    pause
  done
}

# ============================================================
# Blockcheck
# ============================================================
run_blockcheck2() {
  [[ -d "$ZAPRET2_DIR" ]] || { err "未安装 Zapret2！"; return; }

  warn "暂停规则以运行 Blockcheck ..."
  "$ZAPRET2_DIR/clear_rules.sh" 2>/dev/null || true

  trap '"$ZAPRET2_DIR/apply_rules.sh" 2>/dev/null; echo \"[OK] 规则已恢复\"' EXIT HUP INT TERM

  if [[ -f "$ZAPRET2_DIR/blockcheck2.sh" ]]; then
    (cd "$ZAPRET2_DIR" && ./blockcheck2.sh)
  elif [[ -f "$ZAPRET2_DIR/blockcheck.sh" ]]; then
    (cd "$ZAPRET2_DIR" && ./blockcheck.sh)
  else
    warn "未找到 blockcheck 脚本"
  fi

  trap - EXIT HUP INT TERM
  "$ZAPRET2_DIR/apply_rules.sh" 2>/dev/null || true
  ok "探测结束，规则已恢复"
}

# ============================================================
# 主菜单
# ============================================================
menu_main() {
  while true; do
    clear
    local raw status
    raw=$(systemctl is-active "$SERVICE" 2>/dev/null || echo "unknown")

    case "$raw" in
      active) status="${GREEN}运行中${RESET}" ;;
      activating) status="${YELLOW}启动中${RESET}" ;;
      failed) status="${RED}启动失败${RESET}" ;;
      inactive) status="${YELLOW}已停止${RESET}" ;;
      *) status="未安装/未知" ;;
    esac

    echo -e "${GREEN}===== Zapret2 Panel v6.0 (Enhanced) =====${RESET}"
    echo -e "服务状态：${BLUE}$status${RESET}"
    echo
    echo "1) 安装 / 重新安装 Zapret2"
    echo "2) 启停 / 重启服务"
    echo "3) 查看实时日志"
    echo "4) 配置监听端口"
    echo "5) 配置包处理数量"
    echo "6) 节点管理"
    echo "7) 策略管理"
    echo "8) 切换 Local / Gateway 模式"
    echo "9) 运行 Blockcheck"
    echo "10) 卸载 Zapret2"
    echo "0) 退出"
    read -rp "选择：" opt

    case "$opt" in
      1) install_zapret2; pause ;;
      2)
        systemctl restart "$SERVICE" 2>/dev/null || true
        ok "服务已重启"
        pause ;;
      3) journalctl -u "$SERVICE" -f -n 50 ;;
      4) menu_ports ;;
      5) menu_pkt ;;
      6) menu_node ;;
      7) menu_strategy ;;
      8)
        MODE=$(cat "$ZAPRET2_CFG/mode.conf" 2>/dev/null || echo "local")
        [[ "$MODE" == "local" ]] && echo "gateway" > "$ZAPRET2_CFG/mode.conf" || echo "local" > "$ZAPRET2_CFG/mode.conf"
        ok "模式切换为：$(cat "$ZAPRET2_CFG/mode.conf")"
        systemctl restart "$SERVICE" 2>/dev/null || true
        pause ;;
      9) run_blockcheck2 ;;
      10) uninstall_zapret2; pause ;;
      0) clear; exit 0 ;;
    esac
  done
}

# ============================================================
# main()
# ============================================================
main() {
  require_root
  mkdir -p "$ZAPRET2_CFG" "$PROFILE_DIR"
  menu_main
}

main
