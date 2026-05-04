

---

# 🟩 **Zapret2 Panel v5.1 — GitHub Release 文案（专业版）**

## 🚀 Zapret2 Panel v5.1（Production Hardened Release）

v5.1 是 Zapret2 Panel 的“生产稳定版”，专为复杂网络环境、双栈 IPv4/IPv6、iptables-nft 混合系统、运营商强 DPI 干扰等场景设计。本版本在 v5 的基础上进行了深度修复与强化，确保在长期运行、极端网络、透明网关、旁路由等环境中保持稳定可靠。

---

## 🔧 **本次更新重点（v5 → v5.1）**

### **1. 完整修复策略参数切割问题**
- 旧版本使用 `for token in $line` 会导致带空格/引号的策略被拆分  
- v5.1 改为 **整行作为一个参数**  
- 彻底避免 nfqws2 因策略格式导致的静默崩溃

### **2. 修正 nftables 规则语法**
- 移除冗余的 `ip protocol tcp tcp dport` 写法  
- 改为标准 `meta l4proto tcp tcp dport { ... }`  
- 兼容旧版/严格模式 nft

### **3. table/chain 存在性检查**
- 避免重复创建导致的报错  
- 支持多次 reload / restart  
- 更适合 systemd 长期运行

### **4. 多 IP 遍历增强**
- 遍历所有网卡的 global IPv4/IPv6  
- 自动过滤空元素  
- 自动加入安全白名单  
- 适配多网卡、多 IP、IPv6 SLAAC、PD 环境

### **5. 自动检测 iptables-legacy / iptables-nft**
- 避免 nft 与 iptables-nft 混合污染  
- 自动选择最安全的后端  
- 兼容 OpenVZ / LXC / 老内核

### **6. nfqws2 强杀逻辑优化**
- 增加冷却期  
- 避免队列占用残留  
- 防止“服务在跑但不生效”

### **7. IPv6 CIDR 清洗增强**
- 更严格的 IPv6 正则  
- 支持 IPv6/CIDR 节点  
- 防止畸形输入导致崩溃

### **8. 更详细的日志与错误捕获**
- `/var/log/nfqws2.log`  
- 启动参数完整打印  
- 方便调试与问题定位

---

## 🧩 **核心能力（继承自 v5）**

- 焦土级防火墙清理（iptables/ip6tables/nftables 全清）  
- 完整 IPv6 捕获（OUTPUT / PREROUTING / FORWARD）  
- DNS 劫持防护（53 TCP/UDP 直通）  
- Host/IP 列表自动清洗与合并  
- systemd 防重启风暴  
- 自动适配 local/gateway 模式  
- 支持 Argo / TUIC / HY2 / VLESS / Trojan / WS / H2  
- 适配透明代理、旁路由、VPS 全场景  

---

## 📦 **适用场景**

- 运营商强 DPI 干扰  
- Cloudflare Argo 被重置/限速  
- TUIC/HY2 纯 IP 节点被阻断  
- IPv6 环境下的透明代理  
- iptables-nft 混合系统  
- 多网卡、多 IP、双栈环境  
- 家庭旁路由 / 网关模式  

---

## 🏁 **总结**

v5.1 是 Zapret2 Panel 迄今为止最稳定、最兼容、最安全的版本。  
适合长期运行在生产环境中，尤其是复杂网络与强 DPI 干扰场景。

---

# 🟦 **Zapret2 Panel v5.1 — GitHub Release 文案（小白版）**

## 🚀 Zapret2 Panel v5.1（更稳、更强、更省心）

这是 Zapret2 Panel 的最新稳定版，专门为 **普通 VPS 用户、家庭旁路由、透明代理** 打造。  
你不需要懂防火墙、不需要懂 nftables、不需要懂 DPI，只需要运行脚本即可。

---

## 🌟 **这次更新有什么变化？**

### ✔ 不会再因为策略写错导致服务启动失败  
策略现在是“整行读取”，不会被拆坏。

### ✔ 防火墙规则更稳了  
修复了 nft 规则语法问题，兼容更多系统。

### ✔ 自动检测系统环境  
自动判断你是 iptables、iptables-nft 还是 nft，不会冲突。

### ✔ 自动清理旧规则  
每次启动都会清理旧规则，避免“服务在跑但不生效”。

### ✔ 自动识别你的 IPv4/IPv6  
所有本机 IP 自动加入白名单，不会误伤。

### ✔ 日志更清晰  
如果出问题，你可以在 `/var/log/nfqws2.log` 看到详细信息。

---



