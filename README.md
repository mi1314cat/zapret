

---

# ⭐ **Zapret2 v7.0 **

> **说明：**  


---
# 🧩 如何安装面板？

```
bash <(curl -Ls https://github.com/mi1314cat/zapret/raw/refs/heads/main/zapret.sh)
```

markdown
# Zapret2 v7.0
高性能、可视化、模块化的 DPI 绕过工具集。  
支持 Local / Gateway 模式，支持自动防火墙、自动白名单、自动 hostlist/iplist、节点管理、策略管理等功能。

Zapret2 v7.0 旨在让 **小白也能轻松使用，高级用户也能深度定制**。

---

# ✨ 功能亮点

### 🟢 一键安装（自动配置所有默认值）
- 自动生成所有配置文件  
- 自动生成白名单（本地网段 + 本机 IP + 节点 IP）  
- 自动生成 hostlist/iplist  
- 自动加载 nftables 防火墙  
- 自动启动 zapret2d 服务  
- 小白无需任何额外操作即可使用

### 🟢 完整的可视化菜单（zapret2.sh）
- 节点管理（自动编号）
- 策略管理（自动编号）
- 白名单 / 黑名单管理
- 端口管理
- NFQUEUE 性能管理（qnum/qsize）
- 防火墙管理
- 健康检查（CPU / NFQUEUE / PID / 服务 / 防火墙）
- 一键修复（PID + 防火墙）
- Blockcheck
- 自动生成白名单
- 自动生成 hostlist/iplist
- 卸载 Zapret2

### 🟢 高性能 DPI 绕过
- 基于 nfqws2 + NFQUEUE  
- 自动设置队列大小  
- 自动加载 nftables 规则  
- 支持 IPv4 + IPv6  

### 🟢 完整的自保护机制
- 自动排除本机 IP  
- 自动排除回环地址  
- 防止 zapret2d 自杀  
- 防止错误规则导致断网  

---

# 📁 目录结构


Zapret2/
├── zapret2.sh                # 主菜单（控制面板）
├── zapret2d                  # 主程序（nfqws2 封装）
├── bin/
│   └── firewallctl           # 防火墙控制器（nftables）
├── config/
│   ├── mode.conf             # local/gateway
│   ├── ports.conf            # 端口配置
│   ├── qnum.conf             # NFQUEUE 配置
│   ├── whitelist.txt         # 白名单
│   ├── blacklist.txt         # 黑名单
│   ├── hostlist.txt          # 域名列表
│   ├── iplist.txt            # IP 列表
│   ├── nodes/                # 节点配置
│   └── strategy.d/           # 策略规则
├── logs/
│   └── blockcheck.log
├── lib/
│   ├── utils.sh              # 日志/锁/校验工具
├── Menu_options/
│   ├── colors.sh
│   ├── nodes.sh
│   ├── strategy.sh
│   ├── whitelist.sh
│   ├── blacklist.sh
│   ├── port.sh
│   ├── qnum.sh
│   ├── health.sh
│   ├── pidfix.sh
│   ├── autowhitelist.sh
│   ├── hostlist.sh
│   ├── blockcheck.sh
│   └── uninstall.sh






Zapret2 会自动完成：

- 生成所有配置文件  
- 自动生成白名单  
- 自动生成 hostlist/iplist  
- 自动加载防火墙  
- 自动启动 zapret2d  

安装完成后即可使用。

---

# ⚙ 默认配置说明（小白友好）

Zapret2 v7.0 在安装时会自动生成以下默认值：

| 配置项 | 默认值 | 说明 |
|-------|--------|------|
| 模式 | `local` | 本机模式，最安全 |
| 端口 | `51610 / 26095` | 高位端口，避免冲突 |
| qnum | `100` | NFQUEUE 队列号 |
| qsize | `4096` | NFQUEUE 队列大小 |
| 白名单 | 自动生成 | 本地网段 + 本机 IP + 节点 IP |
| hostlist/iplist | 自动生成 | 从节点/策略提取 |

这些默认值经过大量测试，适合绝大多数用户。

---

# 🧭 主菜单功能说明

以下是 zapret2.sh 的所有功能：

## 🟦 系统管理
| 选项 | 功能 |
|------|------|
| 1 | 一键安装（自动配置默认值） |
| 2 | 查看运行状态 |
| 3 | 启动 Zapret2 |
| 4 | 停止 Zapret2 |
| 5 | 重启 Zapret2 |
| 6 | 实时日志 |
| 7 | 切换模式（Local/Gateway） |
| 8 | 健康检查 |
| 9 | 一键修复（PID + 防火墙） |

## 🟩 配置管理
| 选项 | 功能 |
|------|------|
| 10 | 节点管理（自动编号） |
| 11 | 策略管理（自动编号） |
| 12 | 白名单管理 |
| 13 | 黑名单管理 |

## 🟧 高级配置
| 选项 | 功能 |
|------|------|
| 14 | 端口管理（port.sh） |
| 15 | NFQUEUE 包处理数量（qnum.sh） |
| 16 | 防火墙管理（firewallctl） |

## 🟨 工具类
| 选项 | 功能 |
|------|------|
| 17 | 自动生成白名单 |
| 18 | 生成 hostlist/iplist |
| 19 | 运行 Blockcheck |

## 🟥 危险操作
| 选项 | 功能 |
|------|------|
| 20 | 卸载 Zapret2 |

## 🟦 退出
| 选项 | 功能 |
|------|------|
| 0 | 退出 |

---

# 🧪 高级用法

### 重新加载防火墙
```bash
./bin/firewallctl apply
```

### 静默生成白名单
```bash
./Menu_options/autowhitelist.sh --silent
```

### 静默生成 hostlist/iplist
```bash
./Menu_options/hostlist.sh --silent
```

---

# ❓ 常见问题（FAQ）

### Q1：安装后无法上网？
可能是 nftables 规则冲突：

```bash
./bin/firewallctl clear
./bin/firewallctl apply
```

### Q2：CPU 占用高？
运行健康检查：

```bash
8) 健康检查
```

查看 nfqws2 是否异常。

### Q3：如何添加节点？
进入：

```
10) 节点管理
```

支持自动编号、自动保存。

### Q4：如何修改端口？
进入：

```
14) 端口管理
```

修改后会自动重启服务。

---

# ⚠ 注意事项

- **Local 模式最安全**，建议默认使用  
- Gateway 模式需要正确的路由配置  
- 不要手动修改 nftables，否则可能导致断网  
- 所有配置修改后建议执行：  
  ```
  firewallctl apply
  ```

---

# ❤️ 致谢

Zapret2 v7.0 由社区共同维护，欢迎提交 PR 与 Issue。

```

