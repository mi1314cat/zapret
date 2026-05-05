

---

# 🚀 Zapret2 v7.0



本项目特点：

- ✔ 小白友好菜单  
- ✔ 所有功能模块化  
- ✔ 自动生成白名单  
- ✔ 自动生成 hostlist/iplist  
- ✔ 自动管理策略  
- ✔ 自动管理节点  
- ✔ 自动修复  
- ✔ 自动检测 nft / iptables  
- ✔ 完整 systemd 服务  
- ✔ 完整 firewallctl（支持白名单/黑名单）  

---
# 🧩 如何安装面板？

```
bash <(curl -Ls https://github.com/mi1314cat/zapret/raw/refs/heads/main/zapret.sh)
```
---
# 📦 目录结构

```
zapret2/
 ├── zapret2.sh                # 主菜单
 ├── Menu_options/             # 所有功能模块
 │     ├── install.sh
 │     ├── service.sh
 │     ├── nodes.sh
 │     ├── strategy.sh
 │     ├── firewall.sh
 │     ├── blockcheck.sh
 │     ├── health.sh
 │     ├── pidfix.sh
 │     ├── hostlist.sh
 │     ├── packet.sh
 │     ├── whitelist.sh
 │     ├── blacklist.sh
 │     ├── auto_whitelist.sh
 │     ├── delete.sh
 ├── config/                   # 配置文件
 │     ├── ports.conf
 │     ├── pkt.conf
 │     ├── mode.conf
 │     ├── whitelist.txt
 │     ├── blacklist.txt
 │     ├── nodes/
 │     ├── strategy.d/
 ├── bin/
 │     ├── firewallctl
 │     ├── nfqws2
 ├── lib/
 │     ├── firewall_nft.sh
 │     ├── firewall_iptables.sh
 │     ├── utils.sh
```




---

# 🧭 主菜单功能说明

下面是主菜单每一个选项的详细说明。

---

## **1) 一键安装**

自动完成：

- 安装依赖  
- 编译 nfqws2  
- 安装 systemd 服务  
- 加载防火墙  
- 启动 zapret2d  

适合第一次使用。

---

## **2) 查看运行状态**

查看 systemd 服务状态：

- 是否运行  
- 是否报错  
- 是否重启失败  

---

## **3) 启动 Zapret2**

手动启动 zapret2d 服务。

---

## **4) 停止 Zapret2**

停止 zapret2d 服务。

---

## **5) 重启 Zapret2**

重启 zapret2d 服务（修改配置后需要）。

---

## **6) 实时日志**

实时查看 zapret2d 输出日志（Ctrl+C 退出）。

---

## **7) 切换模式（Local / Gateway）**

- **Local 模式**：只处理本机流量（适合 VPS）  
- **Gateway 模式**：处理经过网关的所有流量（适合旁路网关 / 软路由）

切换后自动重启服务。

---

## **8) 策略管理（自动编号）**

管理策略文件：

- 新增策略  
- 删除策略  
- 编辑策略  
- 自动编号  
- 存放于 `config/strategy.d/`

策略用于控制 DPI 绕过行为，例如：

- TLS 混淆  
- HTTP 伪装  
- SNI 替换  
- UA 伪装  

---

## **9) 修改端口**

编辑 `config/ports.conf`：

- TCP4_PORTS  
- UDP4_PORTS  
- TCP6_PORTS  
- UDP6_PORTS  

用于指定哪些端口需要进入 NFQUEUE。

---

## **10) 节点管理（自动编号）**

管理节点文件：

- 新增节点  
- 删除节点  
- 编辑节点  
- 自动编号  
- 存放于 `config/nodes/*.node`

每个节点包含：

```
host=xxx.com
port=443
type=argo/tuic/hy2
```

---

## **11) 防火墙管理**

提供：

- 加载防火墙规则  
- 清理防火墙规则  

使用 firewallctl 自动选择 nft / iptables。

---

## **12) 健康检查（CPU/NFQUEUE/PID）**

自动检测：

- zapret2d 是否卡死（CPU=0）  
- NFQUEUE 是否存在  
- PID 是否僵尸  
- 自动修复  

---

## **13) 一键修复（原 fix）**

执行 zapret2 内置修复流程：

- 清理防火墙  
- 重启服务  
- 重建配置  

---

## **14) 生成 hostlist/iplist**

从节点中提取：

- 域名 → hostlist.txt  
- IP → iplist.txt  

用于策略或外部工具。

---

## **15) 运行 Blockcheck**

运行官方 blockcheck 测试：

- 检测运营商 DPI 行为  
- 自动识别最佳策略  

---

## **16) 配置包处理数量（qnum/qsize）**

编辑 `config/pkt.conf`：

- QNUM：NFQUEUE 队列号  
- QSIZE：队列大小  

用于优化性能。

---

## **17) 修复僵尸 PID 并重启 zapret2d**

自动检测：

- PID 文件是否存在  
- PID 是否已死  
- 自动删除  
- 自动重启服务  

---

## **18) 白名单管理（Zapret2 不处理）**

白名单中的域名/IP：

- 不进入 NFQUEUE  
- 不被 DPI 处理  
- 不被 zapret2 修改  

适合：

- 银行  
- 支付  
- 本地局域网  
- 自己的服务器  

功能：

- 查看白名单  
- 添加白名单  
- 删除白名单  

---

## **19) 黑名单管理（强制进入 Zapret2）**

黑名单中的域名/IP：

- 强制进入 NFQUEUE  
- 强制 DPI 绕过  
- 强制使用策略  

适合：

- 被墙网站  
- 游戏服务器  
- 特定 CDN  

功能：

- 查看黑名单  
- 添加黑名单  
- 删除黑名单  

---

## **20) 卸载 Zapret2（删除所有文件）**

彻底删除：

- 所有配置  
- 所有模块  
- 所有日志  
- 所有 systemd 服务  
- 所有防火墙规则  
- 整个 Zapret2 目录  

不可恢复。

---

## **21) 自动生成白名单（本地地址）**

自动加入：

- 本地网段（10.x / 172.x / 192.168.x）  
- 本机 IP（IPv4/IPv6）  

不会自动加入节点（你手动控制）。

---

# 🛠️ 一键启动

```
bash zapret2.sh
```

---

# ❤️ 适合人群

- 小白用户  
- 家庭宽带  
- 旁路网关  
- 软路由  
- VPS  
- 想要简单使用 DPI 绕过的人  

---

# 📌 注意事项

- 修改配置后记得重启服务  
- 切换模式后会自动重启  
- 防火墙规则由 firewallctl 自动管理  
- 白名单/黑名单会影响流量是否进入 NFQUEUE  

---


