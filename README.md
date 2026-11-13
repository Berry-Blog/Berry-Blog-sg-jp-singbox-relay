# sing-box 狗妈多线路统一管理（SG / JP / Global / US / 更多）

适用于 Alpine Linux x86_64 + OpenRC 的 sing-box 多落地机中转管理。狗妈作为统一 VLESS Reality 客户端入口，支持狗妈直出、日本 BIGLOBE、global、美国 PAV 及任意新增 Reality / Shadowsocks 出站线路。

## 一键安装

```sh
apk add --no-cache bash curl && bash -c "$(curl -fsSL https://raw.githubusercontent.com/Berry-Blog/Berry-Blog-sg-jp-singbox-relay/main/install.sh)"
```

仅首次部署时使用安装器。已经运行 sing-box 的机器升级管理脚本，不要重新运行安装器，也不要重新安装核心。

## 已部署机器更新管理面板

SSH 登录狗妈，执行：

```sh
sb update
```

也可以进入 `sb` 菜单，选择“更新 sb 管理脚本”。更新管理脚本不会重装 sing-box，也不会自动修改正在运行的节点配置。首次使用新版管理面板时，会把旧版 `relay.json` 自动迁移为 schema v4，保留现有 UUID、Reality 密钥、Short ID、端口、线路认证参数及订阅设置。

## 新版菜单

1. 线路总览：显示每条线路 ID、名称、协议、服务器地址、端口和默认出站。
2. 显示线路认证参数。
3. 导出所有 VLESS Reality 分享链接。
4. 导出 Clash Meta / Mihomo YAML。
5. 启用 Clash 远程订阅服务。
6. 查看当前订阅链接。
7. 更新订阅令牌。
8. 关闭订阅服务。
9. 应用/修复全部线路配置。
10. 统一线路管理：添加、修改、删除、设置默认出站。
11. 狗妈入口设置：入口名称、公网 IP/域名、公网映射端口、内部监听地址/端口、入口 Reality SNI。
12. sing-box 配置检查。
13. 服务启动、停止、重启。
14. 服务状态及监听端口。
15. 最近日志。
16. 手动备份。
17. 恢复历史备份。
18. 更新 sb 管理脚本。
19. 更新 sing-box 核心。
20. 卸载。

## 统一线路管理

所有线路在同一管理界面中操作：

- **狗妈直出（direct）**：可修改线路名称、狗妈入口 IP/域名、映射端口及直出客户端 UUID。
- **日本 BIGLOBE（jp）**：可修改名称、落地服务器 IP/域名、端口、Reality / SS 协议及对应认证参数。
- **其他落地线路**：可添加、修改、删除 global、美国 PAV 及其他线路。每条线路可修改名称、服务器 IP/域名、服务器端口、协议、落地 UUID、Reality Public Key、Short ID、SNI，或 SS 加密方式和密码。
- **默认出站**：可将任意已启用线路设置为默认出站。
- 删除内置直出或日本线路后，可以从“添加线路”菜单重新启用；其他线路可以直接删除和重新添加。

新增线路时会生成独立的狗妈入口客户端 UUID。修改线路时默认保留现有客户端 UUID；落地 UUID、Reality 公钥、Short ID、SNI、SS 密码等均按输入值更新。脚本只管理狗妈端的出站和路由，不会远程修改落地机本身。

## 狗妈入口设置

入口参数与落地线路参数分开管理。可修改入口名称、公网 IP/域名、公网映射端口、内部监听地址、内部监听端口及入口 Reality SNI。修改公网映射端口或内部监听端口后，需要同步调整服务商端口映射。修改入口 Reality SNI 后，客户端及外部中转的 SNI 也需要同步。

入口 Reality UUID 用户、Private Key、Public Key、Short ID 不会因为修改线路名称、IP、端口或切换家宽而自动重新生成。

## 配置与导出

- 本地参数：`/etc/sing-box/relay.json`
- sing-box 运行配置：`/etc/sing-box/config.json`
- VLESS 分享链接：`/etc/sing-box/export/vless.txt`
- Clash YAML：`/etc/sing-box/export/clash.yaml`
- 历史备份：`/root/sb-relay-backups/`
- 管理脚本：`/usr/local/bin/sb`

线路变更后会重新生成 VLESS 链接、Clash YAML 和已启用的订阅文件。所有客户端仍连接狗妈统一 Reality 入口，由不同 UUID 用户路由到不同出站线路。

## 订阅

订阅服务仅监听本机回环地址，外部访问需要用户自行配置 HTTPS 域名、Cloudflare Tunnel 或反向代理。订阅文件包含节点凭据，不要公开分享。

## 运行环境与说明

- Alpine Linux x86_64 + OpenRC。
- 当前入口与导出的客户端节点为 VLESS Reality / TCP。
- 额外落地支持 VLESS Reality 和 Shadowsocks 出站。
- Shadowsocks 落地必须预先在远端部署匹配的 SS 入站，并确保狗妈能访问其公网映射端口。
- Reality 落地 UUID、Public Key、Short ID、SNI 必须与远端入站保持一致。
- 脚本不会自动修改云服务商防火墙或端口映射。
- GitHub Actions 运行配置与多线路增删改回归测试；测试不代表真实跨境网络连通性。
