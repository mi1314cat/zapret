#!/usr/bin/env bash
# ============================================================
# Zapret2 Panel v5（终极生产版：处理极端网络与双栈环境）
# 修复与优化：
# - 焦土级防火墙清理 (双杀 iptables/nftables 残留)
# - 完整支持 IPv6 流量捕获 (ip6tables/nft6)
# - 遍历全网卡 IP 豁免 + 端口级 DNS (53) 豁免，绝对防劫持
# - Host/IP 列表正则清洗 (防畸形导致崩溃)
# - Systemd 防重启风暴 + 进程/队列强杀释放
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
  for c in git make gcc iptables ip awk sed grep killall; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done

  if ((${#missing[@]})); then
    warn "缺少基础依赖，尝试自动安装..."
    apt-get update -y || true
    apt-get install -y git make gcc zlib1g-dev libcap-dev libnetfilter-queue-dev iptables ip6tables nftables iproute2 psmisc curl || {
      err "依赖安装失败，请检查系统源"; exit 1;
    }
  fi
}

install_zapret2() {
  msg "${GREEN}开始安装 Zapret2 ...${RESET}"
  check_deps
  
  trap 'err "安装中断或出错，正在执行回滚清理..."; uninstall_zapret2 >/dev/null 2>&1; exit 1' ERR
  set -e

  systemctl stop "$SERVICE" 2>/dev/null || true
  rm -rf "$ZAPRET2_DIR"
  
  git clone "$REPO_URL" "$ZAPRET2_DIR"
  cd "$ZAPRET2_DIR"
  make
  
  if [[ -x "nfqws" ]]; then
    cp nfqws nfqws2
  elif [[ -x "binaries/my/nfqws" ]]; then
    cp binaries/my/nfqws nfqws2
  elif ls binaries/*/nfqws >/dev/null 2>&1; then
    cp $(ls binaries/*/nfqws | head -n 1) nfqws2
  else
    err "未找到编译好的 nfqws 程序！"
    exit 1
  fi

  set +e
  trap - ERR

  mkdir -p "$ZAPRET2_CFG" "$PROFILE_DIR"

  cat > "$ZAPRET2_CFG/ports.conf" <<EOF
TCP4_PORTS="443,8443,7844"
UDP4_PORTS="443,8443,7844"
TCP6_PORTS="443,8443,7844"
UDP6_PORTS="443,8443,7844"
EOF

  cat > "$ZAPRET2_CFG/pkt.conf" <<EOF
TCP_PKT_OUT="9"
TCP_PKT_IN="3"
UDP_PKT_OUT="0"
UDP_PKT_IN="0"
EOF

  cat > "$ZAPRET2_CFG/strategy.conf" <<EOF
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
EOF

  echo "local" > "$ZAPRET2_CFG/mode.conf"

  generate_run_script
  generate_firewall_scripts
  generate_systemd_service

  systemctl daemon-reload
  systemctl enable "$SERVICE"
  systemctl restart "$SERVICE"

  ok "Zapret2 安装与配置完成！核心路径：$ZAPRET2_DIR"
}

generate_run_script() {
  cat > "$ZAPRET2_DIR/run_nfqws2.sh" <<EOF
#!/usr/bin/env bash
ZAPRET2_DIR="$ZAPRET2_DIR"
ZAPRET2_CFG="\$ZAPRET2_DIR/config"
PROFILE_DIR="\$ZAPRET2_CFG/profiles"
QUEUE_NUM=$QUEUE_NUM

# 强制释放僵尸进程与队列占用
killall -9 nfqws2 2>/dev/null
sleep 0.5

source "\$ZAPRET2_CFG/pkt.conf"

args=(
  "--queue-num=\$QUEUE_NUM"
  "--queue-bypass"
  "--tcp-pkt-in=\$TCP_PKT_IN"
  "--tcp-pkt-out=\$TCP_PKT_OUT"
  "--udp-pkt-in=\$UDP_PKT_IN"
  "--udp-pkt-out=\$UDP_PKT_OUT"
)

# 读取全局策略
if [[ -f "\$ZAPRET2_CFG/strategy.conf" ]]; then
  while read -r line; do
    [[ -z "\$line" || "\$line" =~ ^# ]] && continue
    for token in \$line; do
      args+=("\$token")
    done
  done < "\$ZAPRET2_CFG/strategy.conf"
fi

# 动态合并配置并执行严格的数据清洗
MASTER_HOST="\$ZAPRET2_CFG/master_hostlist.txt"
MASTER_IP="\$ZAPRET2_CFG/master_iplist.txt"
TMP_HOST="/tmp/zapret_host.tmp"
TMP_IP="/tmp/zapret_ip.tmp"
> "\$TMP_HOST"
> "\$TMP_IP"

if [[ -d "\$PROFILE_DIR" ]]; then
  for p in "\$PROFILE_DIR"/*; do
    [[ -d "\$p" ]] || continue
    [[ -f "\$p/hostlist.txt" ]] && cat "\$p/hostlist.txt" >> "\$TMP_HOST"
    [[ -f "\$p/iplist.txt" ]] && cat "\$p/iplist.txt" >> "\$TMP_IP"
  done
fi

# 清洗域名: 剔除协议头、斜杠路径、端口号、空白行
sed -e 's|^https*://||i' -e 's|/.*||' -e 's|:[0-9]*||' "\$TMP_HOST" | awk 'NF' | sort -u > "\$MASTER_HOST"

# 清洗 IP: 仅保留合法的 IPv4/IPv6 字符段，剔除杂质
grep -oE '[0-9a-fA-F.:/]+' "\$TMP_IP" | awk 'NF' | sort -u > "\$MASTER_IP"

[[ -s "\$MASTER_HOST" ]] && args+=("--hostlist=\$MASTER_HOST")
[[ -s "\$MASTER_IP" ]] && args+=("--ipset=\$MASTER_IP")

exec "\$ZAPRET2_DIR/nfqws2" "\${args[@]}"
EOF
  chmod +x "$ZAPRET2_DIR/run_nfqws2.sh"
}

generate_firewall_scripts() {
  cat > "$ZAPRET2_DIR/apply_rules.sh" <<EOF
#!/usr/bin/env bash
ZAPRET2_DIR="$ZAPRET2_DIR"
ZAPRET2_CFG="\$ZAPRET2_DIR/config"
QUEUE_NUM=$QUEUE_NUM

# 应用前调用焦土清理
"\$ZAPRET2_DIR/clear_rules.sh" 2>/dev/null

backend="none"
if command -v nft >/dev/null 2>&1; then
  backend="nft"
elif command -v iptables >/dev/null 2>&1; then
  backend="iptables"
fi

source "\$ZAPRET2_CFG/ports.conf"
MODE=\$(cat "\$ZAPRET2_CFG/mode.conf" 2>/dev/null || echo "local")

# 绝对安全的本机IP获取: 遍历所有网卡的 global IP
LOCAL_V4=\$(ip -4 addr show scope global | awk '/inet / {split(\$2, a, "/"); print a[1]}')
LOCAL_V6=\$(ip -6 addr show scope global | awk '/inet6 / {split(\$2, a, "/"); print a[1]}')

SAFE_V4="127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 \$LOCAL_V4"
SAFE_V6="::1/128 fe80::/10 fc00::/7 \$LOCAL_V6"

if [[ "\$backend" == "nft" ]]; then
  nft add table inet zapret2
  nft add chain inet zapret2 output "{ type filter hook output priority -150; }"
  if [[ "\$MODE" == "gateway" ]]; then
    nft add chain inet zapret2 prerouting "{ type filter hook prerouting priority -150; }"
    nft add chain inet zapret2 forward "{ type filter hook forward priority -150; }"
  fi

  # 端口级 DNS 防劫持 (双协议)
  nft add rule inet zapret2 output udp dport 53 return
  nft add rule inet zapret2 output tcp dport 53 return
  [[ "\$MODE" == "gateway" ]] && {
    nft add rule inet zapret2 prerouting udp dport 53 return
    nft add rule inet zapret2 prerouting tcp dport 53 return
    nft add rule inet zapret2 forward udp dport 53 return
    nft add rule inet zapret2 forward tcp dport 53 return
  }

  for net in \$SAFE_V4; do
    [[ -n "\$net" ]] && nft add rule inet zapret2 output ip daddr \$net return 2>/dev/null
    [[ "\$MODE" == "gateway" && -n "\$net" ]] && {
      nft add rule inet zapret2 prerouting ip daddr \$net return 2>/dev/null
      nft add rule inet zapret2 forward ip daddr \$net return 2>/dev/null
    }
  done

  for net in \$SAFE_V6; do
    [[ -n "\$net" ]] && nft add rule inet zapret2 output ip6 daddr \$net return 2>/dev/null
    [[ "\$MODE" == "gateway" && -n "\$net" ]] && {
      nft add rule inet zapret2 prerouting ip6 daddr \$net return 2>/dev/null
      nft add rule inet zapret2 forward ip6 daddr \$net return 2>/dev/null
    }
  done

  # 完整双栈捕获
  if [[ -n "\$TCP4_PORTS" ]]; then
    nft add rule inet zapret2 output ip protocol tcp tcp dport { \$TCP4_PORTS } queue num \$QUEUE_NUM bypass
    [[ "\$MODE" == "gateway" ]] && {
      nft add rule inet zapret2 prerouting ip protocol tcp tcp dport { \$TCP4_PORTS } queue num \$QUEUE_NUM bypass
      nft add rule inet zapret2 forward ip protocol tcp tcp dport { \$TCP4_PORTS } queue num \$QUEUE_NUM bypass
    }
  fi
  if [[ -n "\$UDP4_PORTS" ]]; then
    nft add rule inet zapret2 output ip protocol udp udp dport { \$UDP4_PORTS } queue num \$QUEUE_NUM bypass
    [[ "\$MODE" == "gateway" ]] && {
      nft add rule inet zapret2 prerouting ip protocol udp udp dport { \$UDP4_PORTS } queue num \$QUEUE_NUM bypass
      nft add rule inet zapret2 forward ip protocol udp udp dport { \$UDP4_PORTS } queue num \$QUEUE_NUM bypass
    }
  fi
  if [[ -n "\$TCP6_PORTS" ]]; then
    nft add rule inet zapret2 output ip6 protocol tcp tcp dport { \$TCP6_PORTS } queue num \$QUEUE_NUM bypass
    [[ "\$MODE" == "gateway" ]] && {
      nft add rule inet zapret2 prerouting ip6 protocol tcp tcp dport { \$TCP6_PORTS } queue num \$QUEUE_NUM bypass
      nft add rule inet zapret2 forward ip6 protocol tcp tcp dport { \$TCP6_PORTS } queue num \$QUEUE_NUM bypass
    }
  fi
  if [[ -n "\$UDP6_PORTS" ]]; then
    nft add rule inet zapret2 output ip6 protocol udp udp dport { \$UDP6_PORTS } queue num \$QUEUE_NUM bypass
    [[ "\$MODE" == "gateway" ]] && {
      nft add rule inet zapret2 prerouting ip6 protocol udp udp dport { \$UDP6_PORTS } queue num \$QUEUE_NUM bypass
      nft add rule inet zapret2 forward ip6 protocol udp udp dport { \$UDP6_PORTS } queue num \$QUEUE_NUM bypass
    }
  fi
  exit 0
fi

if [[ "\$backend" == "iptables" ]]; then
  # 初始化独立链
  for table in iptables ip6tables; do
    \$table -t mangle -N ZAPRET2_OUT
    [[ "\$MODE" == "gateway" ]] && \$table -t mangle -N ZAPRET2_PRE && \$table -t mangle -N ZAPRET2_FWD
    
    # DNS 防劫持
    \$table -t mangle -A ZAPRET2_OUT -p udp --dport 53 -j RETURN
    \$table -t mangle -A ZAPRET2_OUT -p tcp --dport 53 -j RETURN
    [[ "\$MODE" == "gateway" ]] && {
      \$table -t mangle -A ZAPRET2_PRE -p udp --dport 53 -j RETURN
      \$table -t mangle -A ZAPRET2_PRE -p tcp --dport 53 -j RETURN
      \$table -t mangle -A ZAPRET2_FWD -p udp --dport 53 -j RETURN
      \$table -t mangle -A ZAPRET2_FWD -p tcp --dport 53 -j RETURN
    }
  done

  # 写入本机 IP 直连
  for net in \$SAFE_V4; do
    [[ -z "\$net" ]] && continue
    iptables -t mangle -A ZAPRET2_OUT -d \$net -j RETURN
    [[ "\$MODE" == "gateway" ]] && iptables -t mangle -A ZAPRET2_PRE -d \$net -j RETURN && iptables -t mangle -A ZAPRET2_FWD -d \$net -j RETURN
  done
  for net in \$SAFE_V6; do
    [[ -z "\$net" ]] && continue
    ip6tables -t mangle -A ZAPRET2_OUT -d \$net -j RETURN
    [[ "\$MODE" == "gateway" ]] && ip6tables -t mangle -A ZAPRET2_PRE -d \$net -j RETURN && ip6tables -t mangle -A ZAPRET2_FWD -d \$net -j RETURN
  done

  QUEUE="--queue-num \$QUEUE_NUM --queue-bypass"

  # IPv4 捕获
  [[ -n "\$TCP4_PORTS" ]] && {
    iptables -t mangle -A ZAPRET2_OUT -p tcp -m multiport --dports \$TCP4_PORTS -j NFQUEUE \$QUEUE
    [[ "\$MODE" == "gateway" ]] && iptables -t mangle -A ZAPRET2_PRE -p tcp -m multiport --dports \$TCP4_PORTS -j NFQUEUE \$QUEUE && iptables -t mangle -A ZAPRET2_FWD -p tcp -m multiport --dports \$TCP4_PORTS -j NFQUEUE \$QUEUE
  }
  [[ -n "\$UDP4_PORTS" ]] && {
    iptables -t mangle -A ZAPRET2_OUT -p udp -m multiport --dports \$UDP4_PORTS -j NFQUEUE \$QUEUE
    [[ "\$MODE" == "gateway" ]] && iptables -t mangle -A ZAPRET2_PRE -p udp -m multiport --dports \$UDP4_PORTS -j NFQUEUE \$QUEUE && iptables -t mangle -A ZAPRET2_FWD -p udp -m multiport --dports \$UDP4_PORTS -j NFQUEUE \$QUEUE
  }
  # IPv6 捕获
  [[ -n "\$TCP6_PORTS" ]] && {
    ip6tables -t mangle -A ZAPRET2_OUT -p tcp -m multiport --dports \$TCP6_PORTS -j NFQUEUE \$QUEUE
    [[ "\$MODE" == "gateway" ]] && ip6tables -t mangle -A ZAPRET2_PRE -p tcp -m multiport --dports \$TCP6_PORTS -j NFQUEUE \$QUEUE && ip6tables -t mangle -A ZAPRET2_FWD -p tcp -m multiport --dports \$TCP6_PORTS -j NFQUEUE \$QUEUE
  }
  [[ -n "\$UDP6_PORTS" ]] && {
    ip6tables -t mangle -A ZAPRET2_OUT -p udp -m multiport --dports \$UDP6_PORTS -j NFQUEUE \$QUEUE
    [[ "\$MODE" == "gateway" ]] && ip6tables -t mangle -A ZAPRET2_PRE -p udp -m multiport --dports \$UDP6_PORTS -j NFQUEUE \$QUEUE && ip6tables -t mangle -A ZAPRET2_FWD -p udp -m multiport --dports \$UDP6_PORTS -j NFQUEUE \$QUEUE
  }

  # 挂载入口
  for table in iptables ip6tables; do
    \$table -t mangle -I OUTPUT -j ZAPRET2_OUT
    [[ "\$MODE" == "gateway" ]] && \$table -t mangle -I PREROUTING -j ZAPRET2_PRE && \$table -t mangle -I FORWARD -j ZAPRET2_FWD
  done
  exit 0
fi
EOF
  chmod +x "$ZAPRET2_DIR/apply_rules.sh"

  cat > "$ZAPRET2_DIR/clear_rules.sh" <<'EOF'
#!/usr/bin/env bash
# 焦土清理策略：无论底层是啥，全部执行一遍清理，防 iptables-nft 混合污染
if command -v nft >/dev/null 2>&1; then
  nft delete table inet zapret2 2>/dev/null
fi
if command -v iptables >/dev/null 2>&1; then
  for table in iptables ip6tables; do
    $table -t mangle -D OUTPUT -j ZAPRET2_OUT 2>/dev/null
    $table -t mangle -D PREROUTING -j ZAPRET2_PRE 2>/dev/null
    $table -t mangle -D FORWARD -j ZAPRET2_FWD 2>/dev/null
    for chain in ZAPRET2_OUT ZAPRET2_PRE ZAPRET2_FWD; do
      $table -t mangle -F $chain 2>/dev/null
      $table -t mangle -X $chain 2>/dev/null
    done
  done
fi
exit 0
EOF
  chmod +x "$ZAPRET2_DIR/clear_rules.sh"
}

generate_systemd_service() {
  cat > /etc/systemd/system/"$SERVICE".service <<EOF
[Unit]
Description=Zapret2 nfqws2 DPI Bypass Service
After=network.target
# 防重启风暴: 30秒内最多重启5次，否则挂起
StartLimitIntervalSec=30
StartLimitBurst=5

[Service]
Type=simple
ExecStart=$ZAPRET2_DIR/run_nfqws2.sh
ExecStartPre=$ZAPRET2_DIR/apply_rules.sh
ExecStopPost=$ZAPRET2_DIR/clear_rules.sh

NoNewPrivileges=yes
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_KILL
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_KILL

Restart=on-failure
RestartSec=3
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
    echo "4) 自定义输入 (注意：错误参数组合会导致启动静默失败)"
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
        warn "注意：不要重复添加 --lua-desync 等互斥参数！"
        read -rp "请输入自定义策略（单行）：" custom_strat
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
    
    echo -e "${GREEN}===== Zapret2 Panel v5 (Production) =====${RESET}"
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
        ok "服务已重启并重载规则"
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
