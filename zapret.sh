#!/usr/bin/env bash
# ============================================================
# Zapret2 Panel 
# 修复与优化：
# - [安全] 移除 eval 解析策略，使用安全数组分割避免注入风险
# - [过滤] 增强节点列表正则，精准适配 IPv6 CIDR 且过滤尾随空格
# - [防护] 强化参数构建引擎，阻断空参数(--hostlist=)引发的进程崩溃
# - [网络] 引入原子化防火墙挂载机制 (nft 事务 / iptables 热交换)，消除裸奔窗口
# - [依赖] 补全 libnfnetlink-dev 依赖，解决部分极简系统的编译报错
# ============================================================

ZAPRET2_DIR="/root/catmi/Zapret2"
ZAPRET2_CFG="$ZAPRET2_DIR/config"
PROFILE_DIR="$ZAPRET2_CFG/profiles"
SERVICE="nfqws2"

REPO_URL="https://github.com/bol-van/zapret"
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

check_deps() {
  local missing=()
  for c in git make gcc iptables ip awk sed grep killall curl; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if ((${#missing[@]})); then
    warn "缺少基础依赖，尝试自动安装..."
    apt-get update -y || true
    # 新增 libnfnetlink-dev，配合 libmnl-dev 彻底解决头文件缺失问题
    apt-get install -y git make gcc zlib1g-dev libcap-dev libnetfilter-queue-dev libmnl-dev libnfnetlink-dev iptables nftables iproute2 psmisc curl || {
      err "依赖安装失败，请检查系统源配置。"
      exit 1
    }
  fi
}

detect_firewall_backend() {
  if command -v nft >/dev/null 2>&1; then
    echo "nft"
  elif command -v iptables >/dev/null 2>&1; then
    if iptables --version 2>&1 | grep -q "nf_tables"; then
      if command -v iptables-legacy >/dev/null 2>&1; then
        echo "iptables-legacy"
      else
        echo "iptables"
      fi
    else
      echo "iptables"
    fi
  else
    echo "none"
  fi
}

install_zapret2() {
  msg "${GREEN}开始安装 Zapret2 ...${RESET}"
  check_deps

  systemctl stop "$SERVICE" 2>/dev/null || true
  
  rm -rf "$ZAPRET2_DIR"
  git clone "$REPO_URL" "$ZAPRET2_DIR"
  cd "$ZAPRET2_DIR" || { err "无法进入目录 $ZAPRET2_DIR"; exit 1; }

  msg "${BLUE}正在编译 nfqws ...${RESET}"
  # 清理旧产物确保不被干扰
  make clean >/dev/null 2>&1
  if ! make; then
    err "编译失败！请检查上方 gcc/ld 的报错日志。"
    exit 1
  fi

  # 寻找并验证编译产物
  local raw_bin=""
  if [[ -x "nfqws/nfqws" ]]; then raw_bin="nfqws/nfqws"
  elif [[ -x "nfqws" ]]; then raw_bin="nfqws"
  elif ls binaries/my/nfqws >/dev/null 2>&1; then raw_bin="binaries/my/nfqws"
  fi

  if [[ -n "$raw_bin" ]] && verify_binary "$raw_bin"; then
    cp -f "$raw_bin" "$ZAPRET2_DIR/nfqws2"
    chmod +x "$ZAPRET2_DIR/nfqws2"
    ok "二进制文件校验通过，已成功部署。"
  else
    err "编译生成的二进制文件损坏或不兼容当前系统架构！"
    err "请检查是否在非标准系统（如极其精简的 Alpine 或 架构不匹配的容器）中运行。"
    exit 1
  fi

  mkdir -p "$ZAPRET2_CFG" "$PROFILE_DIR"
  
  # 初始化基础配置
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
  [[ -f "$ZAPRET2_CFG/strategy.conf" ]] || echo "--lua-desync=fake:blob=fake_default_tls:fooling=md5sig" > "$ZAPRET2_CFG/strategy.conf"
  echo "local" > "$ZAPRET2_CFG/mode.conf"

  generate_run_script
  generate_firewall_scripts
  generate_systemd_service

  systemctl daemon-reload
  systemctl enable "$SERVICE"
  systemctl restart "$SERVICE"
  
  sleep 2
  if ! systemctl is-active "$SERVICE" >/dev/null 2>&1; then
    err "服务启动失败！正在输出最近日志..."
    journalctl -u "$SERVICE" --no-pager -n 20
    exit 1
  fi

  ok "Zapret2 v5.4 安装完成且验证成功！"
}

generate_run_script() {
  cat > "$ZAPRET2_DIR/run_nfqws2.sh" <<'SCRIPT'
#!/usr/bin/env bash
ZAPRET2_DIR="/root/catmi/Zapret2"
ZAPRET2_CFG="$ZAPRET2_DIR/config"
PROFILE_DIR="$ZAPRET2_CFG/profiles"
QUEUE_NUM=200

logfile="/var/log/nfqws2.log"
exec > >(tee -a "$logfile") 2>&1
echo "========== $(date) - nfqws2 启动 =========="

if pgrep -x nfqws2 >/dev/null 2>&1; then
    echo "发现残留 nfqws2 进程，发送 SIGKILL..."
    killall -9 nfqws2 2>/dev/null
    sleep 1
fi

source "$ZAPRET2_CFG/pkt.conf"

args=(
  "--queue-num=$QUEUE_NUM"
  "--queue-bypass"
  "--tcp-pkt-in=$TCP_PKT_IN"
  "--tcp-pkt-out=$TCP_PKT_OUT"
  "--udp-pkt-in=$UDP_PKT_IN"
  "--udp-pkt-out=$UDP_PKT_OUT"
)

# [安全升级] 使用 xargs 安全解析包含空格的参数，杜绝 eval 注入
if [[ -f "$ZAPRET2_CFG/strategy.conf" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    while read -r -d '' arg; do
      [[ -n "$arg" ]] && args+=("$arg")
    done < <(echo "$line" | xargs printf '%s\0' 2>/dev/null)
  done < "$ZAPRET2_CFG/strategy.conf"
fi

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

# [增强清洗] 强化空格处理和异常字符清洗
sed -e 's/^[[:space:]]*//; s/[[:space:]]*$//; s|^https*://||i; s|/.*||; s|:[0-9]*||' "$TMP_HOST" | awk 'NF' | sort -u > "$MASTER_HOST"
grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?|([0-9a-fA-F:]+(:[0-9a-fA-F]+){1,7})(/[0-9]{1,3})?' "$TMP_IP" | awk 'NF' | sort -u > "$MASTER_IP"

if [[ ! -s "$MASTER_HOST" ]]; then rm -f "$MASTER_HOST"; fi
if [[ ! -s "$MASTER_IP" ]]; then rm -f "$MASTER_IP"; fi

if [[ -f "$MASTER_HOST" ]]; then args+=("--hostlist=$MASTER_HOST"); fi
if [[ -f "$MASTER_IP" ]]; then args+=("--ipset=$MASTER_IP"); fi

# [参数安全] 拦截空参数，防止 --hostlist= 进入执行链导致崩溃
valid_args=()
for arg in "${args[@]}"; do
  [[ "$arg" =~ ^--(hostlist|ipset)=?$ ]] && continue
  valid_args+=("$arg")
done
args=("${valid_args[@]}")

echo "执行: $ZAPRET2_DIR/nfqws2 ${args[*]}"

if ! "$ZAPRET2_DIR/nfqws2" --help >/dev/null 2>&1; then
  echo "[ERR] nfqws2 二进制文件不可用或已损坏！"
  exit 1
fi

exec "$ZAPRET2_DIR/nfqws2" "${args[@]}"
SCRIPT
  chmod +x "$ZAPRET2_DIR/run_nfqws2.sh"
}

generate_firewall_scripts() {
  cat > "$ZAPRET2_DIR/apply_rules.sh" <<'SCRIPT'
#!/usr/bin/env bash
ZAPRET2_DIR="/root/catmi/Zapret2"
ZAPRET2_CFG="$ZAPRET2_DIR/config"
QUEUE_NUM=200

source "$ZAPRET2_CFG/ports.conf"
MODE=$(cat "$ZAPRET2_CFG/mode.conf" 2>/dev/null || echo "local")

LOCAL_V4=$(ip -4 addr show scope global | awk '/inet / {split($2, a, "/"); print a[1]}')
LOCAL_V6=$(ip -6 addr show scope global | awk '/inet6 / {split($2, a, "/"); print a[1]}')

SAFE_V4=( 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 )
SAFE_V6=( ::1/128 fe80::/10 fc00::/7 )

while IFS= read -r ip; do [[ -n "$ip" ]] && SAFE_V4+=("$ip"); done <<< "$LOCAL_V4"
while IFS= read -r ip; do [[ -n "$ip" ]] && SAFE_V6+=("$ip"); done <<< "$LOCAL_V6"

backend=$(cat "$ZAPRET2_CFG/backend" 2>/dev/null || echo "auto")
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
    echo "无可用的防火墙！"
    exit 1
  fi
fi

# ==================== 原子化加载 (nftables) ====================
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
  for net in "${SAFE_V4[@]}"; do [[ -n "$net" ]] && echo "    ip daddr $net return" >> "$NFT_FILE"; done
  for net in "${SAFE_V6[@]}"; do [[ -n "$net" ]] && echo "    ip6 daddr $net return" >> "$NFT_FILE"; done

  [[ -n "$TCP4_PORTS" ]] && echo "    meta l4proto tcp tcp dport { $TCP4_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
  [[ -n "$UDP4_PORTS" ]] && echo "    meta l4proto udp udp dport { $UDP4_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
  [[ -n "$TCP6_PORTS" ]] && echo "    meta l4proto tcp tcp dport { $TCP6_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
  [[ -n "$UDP6_PORTS" ]] && echo "    meta l4proto udp udp dport { $UDP6_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
  
  echo "  }" >> "$NFT_FILE"

  if [[ "$MODE" == "gateway" ]]; then
    cat >> "$NFT_FILE" <<EOF
  chain zapret2_prerouting {
    type filter hook prerouting priority -150;
    udp dport 53 return
    tcp dport 53 return
EOF
    for net in "${SAFE_V4[@]}"; do [[ -n "$net" ]] && echo "    ip daddr $net return" >> "$NFT_FILE"; done
    for net in "${SAFE_V6[@]}"; do [[ -n "$net" ]] && echo "    ip6 daddr $net return" >> "$NFT_FILE"; done
    [[ -n "$TCP4_PORTS" ]] && echo "    meta l4proto tcp tcp dport { $TCP4_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
    [[ -n "$UDP4_PORTS" ]] && echo "    meta l4proto udp udp dport { $UDP4_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
    [[ -n "$TCP6_PORTS" ]] && echo "    meta l4proto tcp tcp dport { $TCP6_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
    [[ -n "$UDP6_PORTS" ]] && echo "    meta l4proto udp udp dport { $UDP6_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
    echo "  }" >> "$NFT_FILE"

    cat >> "$NFT_FILE" <<EOF
  chain zapret2_forward {
    type filter hook forward priority -150;
    udp dport 53 return
    tcp dport 53 return
EOF
    for net in "${SAFE_V4[@]}"; do [[ -n "$net" ]] && echo "    ip daddr $net return" >> "$NFT_FILE"; done
    for net in "${SAFE_V6[@]}"; do [[ -n "$net" ]] && echo "    ip6 daddr $net return" >> "$NFT_FILE"; done
    [[ -n "$TCP4_PORTS" ]] && echo "    meta l4proto tcp tcp dport { $TCP4_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
    [[ -n "$UDP4_PORTS" ]] && echo "    meta l4proto udp udp dport { $UDP4_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
    [[ -n "$TCP6_PORTS" ]] && echo "    meta l4proto tcp tcp dport { $TCP6_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
    [[ -n "$UDP6_PORTS" ]] && echo "    meta l4proto udp udp dport { $UDP6_PORTS } queue num $QUEUE_NUM bypass" >> "$NFT_FILE"
    echo "  }" >> "$NFT_FILE"
  fi
  
  echo "}" >> "$NFT_FILE"
  nft -f "$NFT_FILE"
  exit 0
fi

# ==================== 原子化加载 (iptables 热交换) ====================
if [[ "$backend" == "iptables" || "$backend" == "iptables-legacy" ]]; then
  ipt4="iptables"; ipt6="ip6tables"
  if [[ "$backend" == "iptables-legacy" ]]; then ipt4="iptables-legacy"; ipt6="ip6tables-legacy"; fi
  QUEUE="--queue-num $QUEUE_NUM --queue-bypass"

  # 定义热交换函数，彻底消除重载时的裸奔空窗期
  swap_chain() {
    local cmd=$1
    local chain=$2
    local hook=$3
    local new_chain="${chain}_NEW"

    $cmd -t mangle -N $new_chain 2>/dev/null || $cmd -t mangle -F $new_chain
    $cmd -t mangle -A $new_chain -p udp --dport 53 -j RETURN
    $cmd -t mangle -A $new_chain -p tcp --dport 53 -j RETURN

    local is_v6=0
    [[ "$cmd" =~ "ip6" ]] && is_v6=1
    
    if [[ $is_v6 -eq 0 ]]; then
      for net in "${SAFE_V4[@]}"; do [[ -n "$net" ]] && $cmd -t mangle -A $new_chain -d $net -j RETURN; done
      [[ -n "$TCP4_PORTS" ]] && $cmd -t mangle -A $new_chain -p tcp -m multiport --dports $TCP4_PORTS -j NFQUEUE $QUEUE
      [[ -n "$UDP4_PORTS" ]] && $cmd -t mangle -A $new_chain -p udp -m multiport --dports $UDP4_PORTS -j NFQUEUE $QUEUE
    else
      for net in "${SAFE_V6[@]}"; do [[ -n "$net" ]] && $cmd -t mangle -A $new_chain -d $net -j RETURN; done
      [[ -n "$TCP6_PORTS" ]] && $cmd -t mangle -A $new_chain -p tcp -m multiport --dports $TCP6_PORTS -j NFQUEUE $QUEUE
      [[ -n "$UDP6_PORTS" ]] && $cmd -t mangle -A $new_chain -p udp -m multiport --dports $UDP6_PORTS -j NFQUEUE $QUEUE
    fi

    $cmd -t mangle -I $hook -j $new_chain
    $cmd -t mangle -D $hook -j $chain 2>/dev/null || true
    $cmd -t mangle -F $chain 2>/dev/null || true
    $cmd -t mangle -X $chain 2>/dev/null || true
    $cmd -t mangle -E $new_chain $chain
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

  cat > "$ZAPRET2_DIR/clear_rules.sh" <<'CLEARSCRIPT'
#!/usr/bin/env bash
if command -v nft >/dev/null 2>&1; then nft delete table inet zapret2 2>/dev/null; fi
for cmd in iptables iptables-legacy ip6tables ip6tables-legacy; do
  if command -v $cmd >/dev/null 2>&1; then
    $cmd -t mangle -D OUTPUT -j ZAPRET2_OUT 2>/dev/null || true
    $cmd -t mangle -D PREROUTING -j ZAPRET2_PRE 2>/dev/null || true
    $cmd -t mangle -D FORWARD -j ZAPRET2_FWD 2>/dev/null || true
    for chain in ZAPRET2_OUT ZAPRET2_PRE ZAPRET2_FWD; do
      $cmd -t mangle -F $chain 2>/dev/null || true
      $cmd -t mangle -X $chain 2>/dev/null || true
    done
  fi
done
CLEARSCRIPT
  chmod +x "$ZAPRET2_DIR/clear_rules.sh"

  detect_firewall_backend > "$ZAPRET2_CFG/backend"
}

generate_systemd_service() {
  cat > /etc/systemd/system/"$SERVICE".service <<EOF
[Unit]
Description=Zapret2 nfqws2 DPI Bypass Service
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
ExecStart=$ZAPRET2_DIR/run_nfqws2.sh
ExecStartPre=$ZAPRET2_DIR/apply_rules.sh
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

menu_strategy() {
  [[ -d "$ZAPRET2_CFG" ]] || { err "请先安装 Zapret2！"; return; }
  while true; do
    clear
    echo -e "${GREEN}--- 全局 DPI 策略 ---${RESET}"
    [[ -f "$ZAPRET2_CFG/strategy.conf" ]] && cat "$ZAPRET2_CFG/strategy.conf"
    echo
    echo "1) Minimal (最小干扰)"
    echo "2) Stable (推荐：稳定绕过)"
    echo "3) Aggressive (激进：应对强力阻断)"
    echo "4) 自定义输入 (修复安全注入，支持安全展开)"
    echo "0) 返回"
    read -rp "选择：" opt
    case "$opt" in
      1) echo "--lua-desync=fake:blob=fake_default_tls" > "$ZAPRET2_CFG/strategy.conf" ;;
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
        warn "注意：不要重复添加互斥参数！"
        read -rp "请输入自定义策略（单行或多行皆可支持）：" custom_strat
        [[ -n "$custom_strat" ]] && echo "$custom_strat" > "$ZAPRET2_CFG/strategy.conf"
        ;;
      0) break ;;
    esac
    if [[ "$opt" != "0" ]]; then
      ok "策略已更新"
      systemctl restart "$SERVICE" 2>/dev/null
      pause
    fi
  done
}

menu_node() {
  [[ -d "$PROFILE_DIR" ]] || { err "请先安装 Zapret2！"; return; }
  while true; do
    clear
    echo -e "${GREEN}--- 节点名单管理（动态合并入全局策略） ---${RESET}"
    echo "1) 添加节点白名单"
    echo "2) 查看已有节点"
    echo "3) 删除节点"
    echo "0) 返回"
    read -rp "选择：" opt
    case "$opt" in
      1)
        read -rp "节点名称（如 argo/tuic）：" name
        [[ -z "$name" ]] && continue
        mkdir -p "$PROFILE_DIR/$name"
        echo "1) 域名节点（如 my.domain.com）"
        echo "2) IP 节点（如 1.2.3.4 或 2606:4700::）"
        read -rp "选择类型：" t
        if [[ "$t" == "1" ]]; then
          read -rp "输入域名 (可带混杂符号，底层会自动清洗)：" val
          echo "$val" > "$PROFILE_DIR/$name/hostlist.txt"
        elif [[ "$t" == "2" ]]; then
          read -rp "输入IP：" val
          echo "$val" > "$PROFILE_DIR/$name/iplist.txt"
        fi
        ok "节点添加完成"
        systemctl restart "$SERVICE" 2>/dev/null
        ;;
      2) ls "$PROFILE_DIR" 2>/dev/null || echo "无" ;;
      3)
        read -rp "要删除的节点名称：" name
        rm -rf "$PROFILE_DIR/$name"
        ok "节点已删除"
        systemctl restart "$SERVICE" 2>/dev/null
        ;;
      0) break ;;
    esac
    pause
  done
}

run_blockcheck2() {
  [[ -d "$ZAPRET2_DIR" ]] || { err "未安装！"; return; }
  warn "将暂停规则以运行 Blockcheck (Ctrl+C 也会自动恢复规则)..."
  "$ZAPRET2_DIR/clear_rules.sh" 2>/dev/null

  trap '"$ZAPRET2_DIR/apply_rules.sh" 2>/dev/null; msg "\n${BLUE}[OK] 防火墙规则已安全恢复！${RESET}"' EXIT HUP INT TERM

  if [[ -f "$ZAPRET2_DIR/blockcheck2.sh" ]]; then
    (cd "$ZAPRET2_DIR" && ./blockcheck2.sh)
  elif [[ -f "$ZAPRET2_DIR/blockcheck.sh" ]]; then
    (cd "$ZAPRET2_DIR" && ./blockcheck.sh)
  fi

  trap - EXIT HUP INT TERM
  "$ZAPRET2_DIR/apply_rules.sh" 2>/dev/null
  ok "探测结束，规则已恢复"
}

uninstall_zapret2() {
  systemctl stop "$SERVICE" 2>/dev/null
  systemctl disable "$SERVICE" 2>/dev/null
  rm -f /etc/systemd/system/"$SERVICE".service
  systemctl daemon-reload
  [[ -f "$ZAPRET2_DIR/clear_rules.sh" ]] && "$ZAPRET2_DIR/clear_rules.sh" 2>/dev/null
  rm -rf "$ZAPRET2_DIR"
  ok "Zapret2 已彻底清空！"
}

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
  read -rp "TCP4_PORTS (默认保持不变直接回车): " input_tcp4
  read -rp "UDP4_PORTS (默认保持不变直接回车): " input_udp4
  read -rp "TCP6_PORTS (默认保持不变直接回车): " input_tcp6
  read -rp "UDP6_PORTS (默认保持不变直接回车): " input_udp6

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
  systemctl restart "$SERVICE" 2>/dev/null
}

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
  read -rp "TCP_PKT_OUT (不变直接回车): " in_t_out
  read -rp "TCP_PKT_IN (不变直接回车): " in_t_in
  read -rp "UDP_PKT_OUT (不变直接回车): " in_u_out
  read -rp "UDP_PKT_IN (不变直接回车): " in_u_in

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
  systemctl restart "$SERVICE" 2>/dev/null
}

menu_main() {
  while true; do
    clear
    local status
    status=$(systemctl is-active "$SERVICE" 2>/dev/null || echo "未安装")
    [[ "$status" == "active" ]] && status="${GREEN}运行中${RESET}"
    [[ "$status" == "inactive" ]] && status="${YELLOW}已停止/报错${RESET}"

    echo -e "${GREEN}===== Zapret2 Panel v5.3 (Zero Downtime) =====${RESET}"
    echo -e "服务状态：${BLUE}$status${RESET}"
    echo
    echo "1) 安装 Zapret2"
    echo "2) 启停/重启服务"
    echo "3) 查看实时日志"
    echo "4) 配置监听端口（IPv4/IPv6）"
    echo "5) 配置包处理数量（前 N 个包）"
    echo "6) 节点域名/IP管理"
    echo "7) 配置全局策略"
    echo "8) 切换 Local / Gateway 模式"
    echo "9) 运行 Blockcheck"
    echo "10) 卸载"
    echo "0) 退出"
    read -rp "选择：" opt
    case "$opt" in
      1) install_zapret2; pause ;;
      2)
        systemctl restart "$SERVICE" 2>/dev/null
        ok "服务已重启并原子重载规则"
        pause ;;
      3) journalctl -u "$SERVICE" -f -n 50 ;;
      4) menu_ports ;;
      5) menu_pkt ;;
      6) menu_node ;;
      7) menu_strategy ;;
      8)
        [[ -d "$ZAPRET2_CFG" ]] || { err "请先安装！"; pause; continue; }
        MODE=$(cat "$ZAPRET2_CFG/mode.conf" 2>/dev/null || echo "local")
        [[ "$MODE" == "local" ]] && echo "gateway" > "$ZAPRET2_CFG/mode.conf" || echo "local" > "$ZAPRET2_CFG/mode.conf"
        ok "模式已切换为：$(cat "$ZAPRET2_CFG/mode.conf")"
        systemctl restart "$SERVICE" 2>/dev/null
        pause ;;
      9) run_blockcheck2; pause ;;
      10) uninstall_zapret2; pause ;;
      0) clear; exit 0 ;;
    esac
  done
}

main() {
  require_root
  mkdir -p "$ZAPRET2_CFG" "$PROFILE_DIR"
  menu_main
}

main
