#!/usr/bin/env bash
set -Eeuo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

IN_KEYS="$(sing-box generate reality-keypair)"
IN_PRIVATE="$(printf '%s\n' "$IN_KEYS" | awk -F': ' '/^PrivateKey:/ {print $2}')"
IN_PUBLIC="$(printf '%s\n' "$IN_KEYS" | awk -F': ' '/^PublicKey:/ {print $2}')"
JP_KEYS="$(sing-box generate reality-keypair)"
JP_PUBLIC="$(printf '%s\n' "$JP_KEYS" | awk -F': ' '/^PublicKey:/ {print $2}')"

DIRECT_UUID="$(sing-box generate uuid)"
JP_USER_UUID="$(sing-box generate uuid)"
JP_OUT_UUID="$(sing-box generate uuid)"
IN_SHORT="$(sing-box generate rand 8 --hex)"
JP_SHORT="$(sing-box generate rand 8 --hex)"

jq -n \
  --arg in_private "$IN_PRIVATE" \
  --arg in_short "$IN_SHORT" \
  --arg in_public "$IN_PUBLIC" \
  --arg direct_uuid "$DIRECT_UUID" \
  --arg jp_user_uuid "$JP_USER_UUID" \
  --arg jp_out_uuid "$JP_OUT_UUID" \
  --arg jp_public "$JP_PUBLIC" \
  --arg jp_short "$JP_SHORT" '
  {
    log:{level:"warn",timestamp:true},
    inbounds:[{
      type:"vless",
      tag:"sg-reality-in",
      listen:"0.0.0.0",
      listen_port:10010,
      users:[
        {name:"sg-direct",uuid:$direct_uuid,flow:"xtls-rprx-vision"},
        {name:"sg-via-jp",uuid:$jp_user_uuid,flow:"xtls-rprx-vision"}
      ],
      tls:{
        enabled:true,
        server_name:"addons.mozilla.org",
        reality:{
          enabled:true,
          handshake:{server:"addons.mozilla.org",server_port:443},
          private_key:$in_private,
          short_id:[$in_short]
        }
      }
    }],
    outbounds:[
      {type:"direct",tag:"sg-direct-out"},
      {
        type:"vless",
        tag:"to-jp-reality",
        server:"example.com",
        server_port:30001,
        uuid:$jp_out_uuid,
        flow:"xtls-rprx-vision",
        network:"tcp",
        tls:{
          enabled:true,
          server_name:"addons.mozilla.org",
          utls:{enabled:true,fingerprint:"chrome"},
          reality:{enabled:true,public_key:$jp_public,short_id:$jp_short}
        }
      }
    ],
    route:{
      rules:[
        {
          inbound:["sg-reality-in"],
          auth_user:["sg-direct"],
          action:"route",
          outbound:"sg-direct-out"
        }
      ],
      final:"to-jp-reality"
    }
  }' > "$TMP/config.json"

sing-box check -c "$TMP/config.json"
echo "双 VLESS 用户、auth_user 路由及 Reality 出站配置校验通过。"


echo "开始验证多落地机动态渲染、独立路由与客户端导出（仅使用随机测试密钥）。"

export SB_LIB_ONLY=1
source ./sb
CONFIG_DIR="$TMP/sg"
DATA_FILE="$CONFIG_DIR/relay.json"
CONFIG_FILE="$CONFIG_DIR/config.json"
EXPORT_DIR="$CONFIG_DIR/export"
URI_FILE="$EXPORT_DIR/vless.txt"
CLASH_FILE="$EXPORT_DIR/clash.yaml"
BACKUP_ROOT="$TMP/backups"
SUB_ROOT="$TMP/subscription"
BIN="$(command -v sing-box)"
mkdir -p "$CONFIG_DIR" "$EXPORT_DIR"

US_CLIENT="$("$BIN" generate uuid)"
US_LANDING="$("$BIN" generate uuid)"
SS_CLIENT="$("$BIN" generate uuid)"

jq -n \
  --arg in_uuid "$JP_USER_UUID" --arg direct_uuid "$DIRECT_UUID" \
  --arg in_private "$IN_PRIVATE" --arg in_public "$IN_PUBLIC" --arg in_short "$IN_SHORT" \
  --arg jp_out_uuid "$JP_OUT_UUID" --arg jp_public "$JP_PUBLIC" --arg jp_short "$JP_SHORT" \
  --arg us_client "$US_CLIENT" --arg us_landing "$US_LANDING" \
  --arg ss_client "$SS_CLIENT" '
  {
    schema_version:3, mode:"reality",
    public_host:"127.0.0.1",public_port:30010,
    listen_address:"127.0.0.1",listen_port:10010,
    inbound_uuid:$in_uuid,direct_uuid:$direct_uuid,
    inbound_private_key:$in_private,inbound_public_key:$in_public,
    inbound_short_id:$in_short,inbound_sni:"addons.mozilla.org",
    inbound_handshake:"addons.mozilla.org",
    jp_host:"example.com",jp_port:30001,jp_uuid:$jp_out_uuid,
    jp_public_key:$jp_public,jp_short_id:$jp_short,jp_sni:"addons.mozilla.org",
    jp_ss_port:30003,jp_ss_method:"2022-blake3-aes-128-gcm",jp_ss_password:"",
    extra_exits:[
      {
        id:"us-pav",name:"美国 PAV",protocol:"reality",host:"example.com",port:443,
        client_uuid:$us_client,uuid:$us_landing,public_key:$jp_public,
        short_id:$jp_short,sni:"addons.mozilla.org"
      },
      {
        id:"us-ss",name:"美国 SS 备用",protocol:"ss",host:"example.com",port:8388,
        client_uuid:$ss_client,method:"aes-128-gcm",password:"test-password-not-production"
      }
    ]
  }' > "$DATA_FILE"
chmod 600 "$DATA_FILE"

render_config > "$CONFIG_FILE"
"$BIN" check -c "$CONFIG_FILE"
jq -e '
  (.inbounds[0].users | length)==4 and
  (.outbounds | length)==4 and
  .route.final=="to-jp-reality" and
  ([.route.rules[] | select(.auth_user==["sg-direct"] and .outbound=="sg-direct-out")] | length)==1 and
  ([.route.rules[] | select(.auth_user==["sg-via-us-pav"] and .outbound=="to-extra-us-pav")] | length)==1 and
  ([.route.rules[] | select(.auth_user==["sg-via-us-ss"] and .outbound=="to-extra-us-ss")] | length)==1 and
  ([.outbounds[] | select(.tag=="to-extra-us-pav" and .type=="vless")] | length)==1 and
  ([.outbounds[] | select(.tag=="to-extra-us-ss" and .type=="shadowsocks")] | length)==1
' "$CONFIG_FILE" >/dev/null

write_exports
test "$(wc -l < "$URI_FILE" | tr -d '[:space:]')" = "4"
test "$(grep -c '^vless://' "$URI_FILE")" = "4"
grep -Fq '#%E7%8B%97%E5%A6%88%E7%9B%B4%E5%87%BA' "$URI_FILE"
grep -Fq '#%E6%97%A5%E6%9C%AC%20BIGLOBE' "$URI_FILE"
grep -Fq '#SG-via-us-pav-%E7%BE%8E%E5%9B%BD%20PAV' "$URI_FILE"
grep -Fq '#SG-via-us-ss-%E7%BE%8E%E5%9B%BD%20SS%20%E5%A4%87%E7%94%A8' "$URI_FILE"

# 测试生成 YAML 能被 Python YAML 解析器解析，且四个代理均在策略组中。
/usr/bin/python3 - "$CLASH_FILE" <<'PY'
import sys
import yaml
with open(sys.argv[1], encoding="utf-8") as fp:
    conf = yaml.safe_load(fp)
assert len(conf["proxies"]) == 4, conf["proxies"]
names = [p["name"] for p in conf["proxies"]]
assert len(set(names)) == 4, names
group = conf["proxy-groups"][0]["proxies"]
for name in names:
    assert name in group, (name, group)
assert all(p["type"] == "vless" for p in conf["proxies"])
PY

# 测试增删改存储与重新渲染，确认与原日本线路相互隔离。
snapshot_jp="$(jq -c '[.inbound_uuid,.jp_uuid,.jp_public_key,.jp_short_id,.jp_host,.jp_port]' "$DATA_FILE")"
save_extra_change remove "us-pav" '{}'
test "$(jq -r '(.extra_exits // []) | length' "$DATA_FILE")" = "1"
render_config > "$CONFIG_FILE"
"$BIN" check -c "$CONFIG_FILE"
write_exports
test "$(wc -l < "$URI_FILE" | tr -d '[:space:]')" = "3"
! grep -Fq '#SG-via-us-pav-' "$URI_FILE"

entry="$(jq -c '.extra_exits[0] | .name="修改后的备用出口"' "$DATA_FILE")"
save_extra_change edit "us-ss" "$entry"
jq -e '.extra_exits[0].name=="修改后的备用出口"' "$DATA_FILE" >/dev/null

entry="$(jq -cn --arg u "$US_CLIENT" --arg v "$US_LANDING" --arg p "$JP_PUBLIC" --arg sid "$JP_SHORT" \
  '{id:"us-pav",name:"美国 PAV",protocol:"reality",host:"example.com",port:443,client_uuid:$u,uuid:$v,public_key:$p,short_id:$sid,sni:"addons.mozilla.org"}')"
save_extra_change add "us-pav" "$entry"
render_config > "$CONFIG_FILE"
"$BIN" check -c "$CONFIG_FILE"
write_exports
test "$(wc -l < "$URI_FILE" | tr -d '[:space:]')" = "4"
test "$(jq -c '[.inbound_uuid,.jp_uuid,.jp_public_key,.jp_short_id,.jp_host,.jp_port]' "$DATA_FILE")" = "$snapshot_jp"
echo "多落地机动态配置、节点路由、VLESS 链接、Clash YAML 及增删改回归测试通过。"


# 模拟实际菜单 33/35/36 的交互操作；不运行任何真实 system service。
rc-service(){ return 0; }
printf '%s\n' \
  'us-pav2' '美国PAV第二条' 'reality' 'example.com' '443' \
  "$US_LANDING" "$JP_PUBLIC" "$JP_SHORT" 'addons.mozilla.org' |
  add_extra_exit > "$TMP/menu-add.out"
test "$(jq -r '(.extra_exits // []) | length' "$DATA_FILE")" = "3"
test "$(wc -l < "$URI_FILE" | tr -d '[:space:]')" = "5"
jq -e '.extra_exits[] | select(.id=="us-pav2" and .name=="美国PAV第二条")' "$DATA_FILE" >/dev/null

printf '%s\n' \
  'us-pav2' '美国PAV已修改' 'reality' 'example.com' '443' 'N' \
  "$US_LANDING" "$JP_PUBLIC" "$JP_SHORT" 'addons.mozilla.org' |
  edit_extra_exit > "$TMP/menu-edit.out"
jq -e '.extra_exits[] | select(.id=="us-pav2" and .name=="美国PAV已修改")' "$DATA_FILE" >/dev/null

printf '%s\n' 'us-pav2' 'YES' |
  remove_extra_exit > "$TMP/menu-remove.out"
test "$(jq -r '(.extra_exits // []) | length' "$DATA_FILE")" = "2"
test "$(wc -l < "$URI_FILE" | tr -d '[:space:]')" = "4"
! grep -Fq '#SG-via-us-pav2-' "$URI_FILE"
test "$(jq -c '[.inbound_uuid,.jp_uuid,.jp_public_key,.jp_short_id,.jp_host,.jp_port]' "$DATA_FILE")" = "$snapshot_jp"
echo "菜单 33/35/36 实际交互增删改测试通过。"
