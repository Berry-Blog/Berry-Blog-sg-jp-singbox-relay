# sing-box 新加坡多落地机中转管理（SG / JP / US / 更多）

为新加坡 GoMami 入口与日本 BIGLOBE、美国 PAV 等任意多个落地机设计的 Alpine/OpenRC 管理脚本。初始保留 SG Direct 与 SG → JP 两条线路，可额外添加多台 VLESS Reality 或 Shadowsocks 落地机。每条线路由不同客户端 UUID 独立路由，自动导出所有 VLESS 链接和 Clash Meta/Mihomo 配置。

## 原有双节点工作方式（保留不变）

两个客户端节点共用新加坡同一个 Reality 监听地址和端口，通过不同的 VLESS UUID 用户名路由：

- **节点 A：新加坡直出**。VLESS 用户名为 `sg-direct`，流量由新加坡机器直接出站。
- **节点 B：新加坡 → 日本 BIGLOBE**。VLESS 用户名为 `sg-via-jp`，流量继续使用现有日本 Reality（或后续配置的 SS）出站。

路由使用 sing-box 的 VLESS 用户 `name` 与 route `auth_user` 匹配。新增节点不会重新生成或替换现有日本中转节点的 UUID、Reality 私钥、公钥和 Short ID。

## 一键安装

仅支持 Alpine Linux x86_64 + OpenRC：

```sh
apk add --no-cache bash curl && bash -c "$(curl -fsSL https://raw.githubusercontent.com/Berry-Blog/Berry-Blog-sg-jp-singbox-relay/main/install.sh)"
```

安装器检测到旧 sing-box 文件时会询问是否清理。清理为可选项；不会删除 SSH、系统网络配置或历史备份。首次配置时服务器 IP/域名由管理员输入，端口可直接回车采用默认值，也可以输入自定义端口。

## 已部署机器升级

如果机器已经安装旧版管理脚本，不要重新安装核心，也不要重新运行安装器。

1. SSH 登录新加坡服务器。
2. 输入 `sb`。
3. 在旧版菜单中选择“更新 sb 管理脚本”（旧菜单编号 27）。
4. 脚本从本 Public 仓库下载新版、先执行 `bash -n` 检查，再自动重新载入中文菜单。
5. 在新版菜单选择“应用/修复全部节点路由配置”（编号 9）；新版菜单中的管理脚本更新功能仍为编号 30。

更新管理脚本本身不会立即改变正在运行的 sing-box 配置。旧版双节点不需要重装。新增落地机通过菜单 33 保存并触发配置校验、重启与备份；如果需要按当前参数重新生成配置，选择菜单 9。对新增落地机的变更失败会回滚参数和配置。

也可以在服务器上执行 `sb update` 更新管理脚本。

## 中文菜单功能

- 查看双节点状态与参数
- 明文显示新加坡、日本两侧 UUID、Reality Private/Public Key、Short ID
- 生成全部独立 VLESS Reality 一键导入链接（2 条原线路 + N 条新增线路）
- 生成 Clash Meta / Mihomo YAML 配置文件
- 启用本机 Clash 订阅文件服务并生成 HTTPS 订阅地址；落地机变更后订阅文件自动更新
- 修改新加坡/日本 IP、端口、UUID、Public Key、Short ID、SNI
- 单独重新生成新加坡直出 UUID
- 轮换新加坡 Reality 密钥
- Reality / Shadowsocks 日本出站切换
- 配置校验、服务启停、日志、备份恢复、核心更新和卸载

## 导出文件

菜单 3 和菜单 4 是两个不同的导出方式，不是重复功能：

- **菜单 3：VLESS 分享链接**。生成两个独立的 VLESS URI，文件 `/etc/sing-box/export/vless.txt` 只包含两条 URI，方便逐条复制或批量导入。
- **菜单 4：本地 Clash 配置文件**。生成包含两个节点及手动选择策略组的 YAML，保存到 `/etc/sing-box/export/clash.yaml`。通过 SCP 下载后，在 Clash Meta / Mihomo 中从文件导入。
- **菜单 5：远程订阅服务**。不是再次生成本地 YAML，而是启动本机静态文件服务，让 Clash 客户端可以通过 HTTPS 订阅地址自动更新 YAML。

## Clash 远程订阅地址

菜单 5 可以启用一个轻量本机静态文件服务：

- Alpine 的 HTTP applet 由 `busybox-extras` 包提供，实际执行文件为 `/bin/busybox-extras`；不能用基础 `/bin/busybox --list` 判断扩展 applet 是否存在。
- 默认仅监听 `127.0.0.1:18080`，不直接开放公网端口
- 生成随机长令牌路径，订阅文件不放在公开仓库
- 要获得可用的远程订阅 URL，需自行将 HTTPS 域名、Cloudflare Tunnel 或 HTTPS 反向代理转发到脚本显示的本机上游地址
- 订阅 URL 包含随机访问令牌，等同于节点凭据；不要公开分享
- 脚本不会擅自增加商家公网端口映射，也不会自动替用户创建 DNS、证书或 Cloudflare Tunnel

如果尚未配置 HTTPS 反向代理，可先使用本地 Clash YAML 文件导入，不要把含节点凭据的 YAML 放在公开 GitHub 仓库或通过明文 HTTP 公开传输。

## 多落地机管理（2026-11-12）

新版 `sb` 在原菜单末尾新增以下功能，不改动其他菜单编号：

- **33：添加落地机**。填写 ID（例如 `us-pav`）、显示名称、落地协议 `reality` 或 `ss`、公网地址、映射端口及对应的远端认证参数。脚本自动生成一条独立的 **新加坡客户端 UUID**。
- **34：查看落地机**。显示新增线路的 ID、协议、目的地址和客户端 UUID。
- **35：修改落地机**。可以修改名称、落地 IP/端口和远端密钥，按需重新生成该线路客户端 UUID。
- **36：删除落地机**。仅移除选中的新增路由、配置和客户端链接，不删除原日本 BIGLOBE 或新加坡直出。
- **3：查看全部 VLESS 链接**。输出 `SG-Direct`、`SG-via-JP` 和 `SG-via-<id>`，每行一个 URI；文件 `/etc/sing-box/export/vless.txt`。
- **4：导出完整 Clash YAML**。将全部客户端节点添加到同一选择策略组；文件 `/etc/sing-box/export/clash.yaml`。
- **30：更新管理脚本**。从本仓库 `main` 下载，进行 Bash 语法检查，并载入新菜单；也可执行 `sb update`。

例如新增美国 PAV 后，客户端仍连接 **新加坡 GoMami 的原 Reality 入口 IP/端口和公钥**，但使用新生成的 `SG-via-us-pav` UUID。新加坡 sing-box 根据用户名转发至美国 PAV；原 `SG-via-JP` UUID 和路线保持不变。

**注意：菜单 33 只配置新加坡中转端，不会远程登录或安装美国 PAV 落地机。** 新落地机必须预先运行对应 VLESS Reality 或 Shadowsocks 入站，并允许新加坡连接其公网 TCP 端口（如果是 NAT VPS，填写商家映射后的公网端口）。`Reality UUID/Public Key/Short ID/SNI` 必须与远端实际配置一致。未配置美国 PAV 时，不应认为新增客户端已经可以连通。

新增和修改会自动备份当前配置、运行 `sing-box check`，再重启主服务；如果配置校验或重启失败会回滚。GitHub Actions 使用随机测试凭据验证多路由 JSON、两种落地协议、多条链接、YAML 格式及增加/修改/删除后的配置一致性。这些离线检查不等于实际跨境连通性测试。

## 安全说明

- 公开仓库只保存通用脚本，不保存真实服务器 IP、UUID、Reality 密钥、Short ID 或订阅令牌。
- 本地参数文件 `/etc/sing-box/relay.json` 权限为 root-only（600）。
- 用户明确要求凭据在 SSH 终端明文显示；菜单 2 会展示完整参数。请不要在公开录屏、截图或聊天中暴露这些内容。
- 当前节点端口映射为 TCP；Clash 配置按 TCP Reality 生成，不宣称已启用 UDP。
- 修改端口后，需要在商家面板同步修改端口映射。
- 修改日本落地 UUID/Public Key/Short ID 后，必须与日本 BIGLOBE 实际入站配置一致。此脚本只管理新加坡机器，不会远程修改日本服务器。

## 本地文件

- `/etc/sing-box/relay.json`：本地参数及认证凭据（600），新增落地机保存在 `extra_exits[]` 中
- `/etc/sing-box/config.json`：sing-box 运行配置（600）
- `/etc/sing-box/export/vless.txt`：两个 VLESS 分享链接（600）
- `/etc/sing-box/export/clash.yaml`：Clash Meta/Mihomo 配置（600）
- `/root/sb-relay-backups/`：修改前自动备份
- `/usr/local/bin/sb`：中文管理命令

## 参考

管理菜单和节点导出体验参考 [yonggekkk/sing-box-yg](https://github.com/yonggekkk/sing-box-yg)；双节点路由和参数管理为本项目按 SG-JP 架构定制。
