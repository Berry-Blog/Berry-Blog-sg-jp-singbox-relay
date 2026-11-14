# sing-box 狗妈多线路统一管理（SG / JP / Global / US / 更多）

适用于 Alpine Linux x86_64 + OpenRC 的 sing-box 多落地机中转管理。狗妈作为统一 VLESS Reality 客户端入口，支持狗妈直出、日本 BIGLOBE、Global Home 多家宽，以及任意新增 Reality / Shadowsocks 出站线路。

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

也可以进入 `sb` 菜单，选择“更新 sb 管理脚本”。更新只替换管理脚本和 Global 线路辅助模块，不重装 sing-box，也不改现有线路。首次使用新版面板时，会把旧版 `relay.json` 自动迁移为 schema v5，保留已有 UUID、Reality 密钥、Short ID、端口、线路认证参数及订阅设置。

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
21. Global 多家宽管理（JSON 导入、手动录入、增删改、客户端链接及分段状态检查）。

## Global 家宽导入

在 Global SSH 中执行 `gl`，选择“导出狗妈中转 JSON”。在 Windows PowerShell 5.1 中执行：

```powershell
New-Item -ItemType Directory -Force -Path 'D:\gpt项目\2global'
scp -P 40022 root@209.33.166.81:/etc/global-home-nodes/exports/dogma-relay.json 'D:\gpt项目\2global\dogma-relay.json'
scp -P 40022 'D:\gpt项目\2global\dogma-relay.json' root@178.94.15.19:/root/global-relay.json
```

登录狗妈执行 `chmod 600 /root/global-relay.json`，然后运行 `sb` → `21）Global 多家宽管理` → `1）从 JSON 文件导入 Global 家宽`。导入候选会显示 `1、2、3…` 序号、线路名称和 ID；输入一个或多个序号（逗号分隔）选择，输入 `ALL` 选择所有正常候选。异常、重复及未选择的线路不会被导入。导入前仍会显示新增、更新、重复和异常预览；默认采用增量导入，不会因文件缺少某条线路而自动删除现有线路。也可以在 `sb` → `21` → `2` 手动添加：第一次粘贴完整 Global VLESS Reality 链接或逐字段录入；后续线路只需选择同一个 profile 并输入新的 Global UUID。

Global profile 和各线路保存在 `/etc/sing-box/relay.json` 的独立字段中。Global UUID 只用于狗妈到 Global 的 VLESS 出站；狗妈客户端 UUID 单独生成。狗妈连接 Global 公网 VLESS Reality 地址，不使用 Global 内部 SOCKS5 地址。

## 统一线路管理

所有线路在同一管理界面中操作。线路列表会为每条线路显示序号和名称；修改、删除、设置默认出站时可输入该列表中的序号。显示 VLESS 链接时也会在链接前标出对应序号和线路名称，便于核对；保存到 `/etc/sing-box/export/vless.txt` 的文件仍保持一条链接一行，方便客户端导入：

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
- Global JSON 协议：[`docs/global-home-dogma-relay.schema.json`](docs/global-home-dogma-relay.schema.json)
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
- GitHub Actions 运行配置、Global JSON 校验、版本迁移和多线路增删改回归测试；测试不代表真实跨境网络连通性。
