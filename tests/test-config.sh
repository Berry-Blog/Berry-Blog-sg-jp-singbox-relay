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
