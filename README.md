
---

# 📘 Zapret2 Panel v3（生产级）  
一个可在生产环境长期运行的 **DPI 绕过管理面板**，支持 IPv4/IPv6、iptables/nftables、多队列、节点独立策略、自动规则加载等。

---

## ✨ 功能特性

- **IPv4 + IPv6 全支持**
- **iptables / ip6tables / nftables 自动识别**
- **local / gateway 模式切换**
- **多队列 queue-balance（多核分摊）**
- **全局 DPI 策略（Minimal / Stable / Aggressive）**
- **节点独立策略（Profile）**
- **动态参数加载（无需重写 systemd）**
- **NFQUEUE 规则随服务自动加载/卸载**
- **systemd 安全沙箱**
- **blockcheck2 环境隔离**
- **小白友好菜单**
- **卸载干净，不留规则**

适用于：

- VPS  
- 家庭旁路由  
- 网关透明代理  
- Cloudflare Argo  
- VLESS / Trojan / Hysteria / Reality  
- gost / sing-box / mihomo  
- 任何需要 DPI 绕过的代理流量  

---

# 🚀 安装

```bash
chmod +x zapret2_panel.sh
./zapret2_panel.sh
```

首次运行选择：

```
1) 安装 Zapret2（自动）
```

脚本会自动：

- 安装依赖  
- 下载并编译 Zapret2  
- 初始化配置  
- 创建 systemd 服务  
- 自动加载 NFQUEUE 规则  
- 启动服务  

---

# 🧩 使用指南

运行：

```bash
./zapret2_panel.sh
```

你会看到主菜单：

```
1) 安装 Zapret2（自动）
2) 启动 Zapret2
3) 停止 Zapret2
4) 重启 Zapret2
5) 查看实时日志
6) 配置 NFQUEUE 端口（IPv4/IPv6）
7) 配置包处理数量
8) 配置全局 DPI 策略
9) 节点 DPI 绕过管理（Profile）
10) 切换模式（local / gateway）
11) 运行 blockcheck2（隔离环境）
12) 卸载 Zapret2（干净删除）
0) 退出
```

---

# 🔧 模式说明（local / gateway）

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| **local** | 只处理本机出站流量（OUTPUT） | VPS、普通服务器 |
| **gateway** | 处理经过服务器的所有流量（PREROUTING + FORWARD） | 旁路由、网关、透明代理 |

切换方式：

```
10) 切换模式（local / gateway）
```

---

# 🔥 NFQUEUE 端口配置（IPv4/IPv6）

进入：

```
6) 配置 NFQUEUE 端口（IPv4/IPv6）
```

你可以设置：

```
TCP4_PORTS="443,8443"
UDP4_PORTS="443"
TCP6_PORTS="443"
UDP6_PORTS=""
```

修改后会自动应用规则。

---

# 🧠 全局 DPI 策略

进入：

```
8) 配置全局 DPI 策略
```

提供三种预设：

- Minimal（最稳）
- Stable（推荐）
- Aggressive（最强）

也可以自定义：

```
--lua-desync=fake:blob=fake_default_tls:fooling=md5sig
--lua-desync=multisplit:pos=2
```

---

# 🧩 节点独立 DPI 策略（Profile）

进入：

```
9) 节点 DPI 绕过管理（Profile）
```

你可以：

- 启用某个节点的 DPI 绕过  
- 查看节点策略  
- 删除节点策略  

每个节点会生成独立目录：

```
/root/catmi/Zapret2/config/profiles/<节点名>/
  ├── strategy.conf
  └── hostlist.txt
```

Zapret2 会自动加载所有 profile。

---

# 📡 实时日志

```
5) 查看实时日志
```

用于调试 DPI 绕过是否生效。

---

# 🧪 blockcheck2（隔离环境）

```
11) 运行 blockcheck2（隔离环境）
```

脚本会：

- 暂时清理 NFQUEUE 规则  
- 运行 blockcheck2  
- 自动恢复规则  

不会污染现有防火墙。

---

# 🧹 卸载（干净删除）

```
12) 卸载 Zapret2（干净删除）
```

会删除：

- systemd 服务  
- 所有 NFQUEUE 规则  
- Zapret2 目录  
- 配置文件  

不会影响其他服务。

---

# 🟦 示例：如何让 mihomo（sing-box）里的 VLESS 节点走 DPI 绕过？

假设你 VPS 上运行 mihomo，其中一个 VLESS 节点的域名是：

```
argo
```

你想让它走 Zapret2 DPI 绕过，只需要两步。

---

## ✔ 第一步：进入节点管理菜单

运行：

```bash
./zapret2_panel.sh
```

选择：

```
9) 节点 DPI 绕过管理（Profile）
```

---

## ✔ 第二步：启用节点 DPI 绕过

选择：

```
1) 启用节点 DPI 绕过
```

脚本会问：

```
节点名称：
```

你可以随便写，例如：

```
mihomo-argo
```

然后：

```
节点域名（如 cf.example.com）：
```

你填：

```
argo
```

再选择策略：

```
1) Minimal
2) Stable
3) Aggressive
```

推荐：

```
2) Stable
```

脚本会自动生成：

```
/root/catmi/Zapret2/config/profiles/mihomo-argo/strategy.conf
/root/catmi/Zapret2/config/profiles/mihomo-argo/hostlist.txt
```

并自动重启 Zapret2。

---

# 🎉 完成！

你的 mihomo VLESS 节点 **argo** 已经成功启用 DPI 绕过。

无需修改 mihomo 配置  
无需修改 iptables  
无需修改路由表  

Zapret2 会自动：

- 捕获所有访问 argo 的流量  
- 注入 DPI 绕过策略  
- 多队列分摊  
- IPv4/IPv6 全支持  
- nft/iptables 自动适配  

---

# ❓ FAQ

### Q1：我需要修改 mihomo/sing-box 配置吗？  
**不需要。**  
Zapret2 在 NFQUEUE 层处理，不影响代理配置。

---

### Q2：Cloudflare Argo / VLESS / Trojan / Hysteria 都能用吗？  
**能。**  
只要是基于域名的流量，都能通过 hostlist 匹配。

---

### Q3：IPv6 会不会漏掉？  
不会。  
v3 已经完整支持 IPv6 NFQUEUE。

---

### Q4：我用的是 nftables，会不会冲突？  
不会。  
Zapret2 使用独立表：

```
table inet zapret2
```

不会影响系统原有规则。

---

### Q5：我用的是 iptables，会不会影响现有规则？  
不会。  
Zapret2 只添加带有 `ZAPRET2` 注释的规则，卸载时会自动清理。

---

### Q6：gateway 模式会不会影响路由器？  
不会。  
脚本自动跳过：

- 内网流量  
- SSH  
- DNS  
- 已建立连接（可选）  

---

# 🧩 高级用法（可选）

- 自定义策略（Lua）  
- 多节点多策略  
- 旁路由透明代理  
- Cloudflare Argo 最佳策略  
- Reality 最佳策略  
- 多队列优化（200–203）  
- 自定义 NFQUEUE 范围  

