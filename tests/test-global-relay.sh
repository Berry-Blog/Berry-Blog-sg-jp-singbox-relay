#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$ROOT/tests/fixtures/global-home-dogma-relay-v1.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export SB_LIB_ONLY=1
source "$ROOT/sb"
CONFIG_DIR="$TMP/sing-box"
DATA_FILE="$CONFIG_DIR/relay.json"
CONFIG_FILE="$CONFIG_DIR/config.json"
EXPORT_DIR="$CONFIG_DIR/export"
URI_FILE="$EXPORT_DIR/vless.txt"
CLASH_FILE="$EXPORT_DIR/clash.yaml"
BACKUP_ROOT="$TMP/backups"
SUB_ROOT="$TMP/subscription"
BIN="$(command -v sing-box)"
mkdir -p "$CONFIG_DIR" "$EXPORT_DIR"

# A v4-like existing data file stands in for the currently deployed dogma data.
jq -n '
  {schema_version:4,mode:"reality",public_host:"178.94.15.19",public_port:30010,
   listen_address:"127.0.0.1",listen_port:10010,entrance_name:"狗妈",
   inbound_uuid:"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",direct_uuid:"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
   inbound_private_key:"Bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
   inbound_public_key:"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",inbound_short_id:"fedcba9876543210",
   inbound_sni:"addons.mozilla.org",inbound_handshake:"addons.mozilla.org",
   direct_name:"狗妈直出",direct_enabled:true,jp_name:"日本 BIGLOBE（原线路）",jp_enabled:true,
   jp_host:"old-jp.example",jp_port:30001,jp_uuid:"cccccccc-cccc-4ccc-8ccc-cccccccccccc",
   jp_public_key:"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",jp_short_id:"0011223344556677",jp_sni:"addons.mozilla.org",
   default_exit:"jp",extra_exits:[
    {id:"us-pav",name:"美国 Pavlov（原线路）",protocol:"reality",host:"old-us.example",port:30002,
     client_uuid:"dddddddd-dddd-4ddd-8ddd-dddddddddddd",uuid:"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
     public_key:"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",short_id:"8899aabbccddeeff",sni:"addons.mozilla.org"},
    {id:"global",name:"Global（原线路）",protocol:"reality",host:"old-global.example",port:30003,
     client_uuid:"ffffffff-ffff-4fff-8fff-ffffffffffff",uuid:"99999999-9999-4999-8999-999999999999",
     public_key:"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",short_id:"0123456789abcdef",sni:"addons.mozilla.org"}
   ]}' > "$DATA_FILE"
chmod 600 "$DATA_FILE"
migrate_legacy_data
test "$(jq -r '.schema_version' "$DATA_FILE")" = 5
test "$(jq -r '.inbound_uuid' "$DATA_FILE")" = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
test "$(jq -r '.extra_exits|length' "$DATA_FILE")" = 2

global_relay apply "$FIXTURE" "$DATA_FILE" incremental >/dev/null
test "$(jq -r '.global_profiles|length' "$DATA_FILE")" = 1
test "$(jq -r '.global_exits|length' "$DATA_FILE")" = 3
test "$(jq -r '.extra_exits|length' "$DATA_FILE")" = 2
test "$(jq -r '.default_exit' "$DATA_FILE")" = jp

render_config > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"
"$BIN" check -c "$CONFIG_FILE"
config_check >/dev/null
# Sing-box accepts this configuration structurally, but the relay manager must
# also reject a Global client whose auth_user no longer routes to its outbound.
cp "$CONFIG_FILE" "$TMP/config.valid.json"
jq '(.route.rules[] | select(.outbound=="to-extra-global-biglobe")).auth_user=["wrong-client"]' "$CONFIG_FILE" > "$TMP/config.invalid-route.json"
mv -f "$TMP/config.invalid-route.json" "$CONFIG_FILE"
if config_check >/dev/null 2>&1; then
  echo 'config_check accepted a broken Global user-to-outbound route.' >&2
  exit 1
fi
mv -f "$TMP/config.valid.json" "$CONFIG_FILE"
jq -e '
  (.inbounds[0].users|length)==7 and
  ([.inbounds[0].users[]|select(.name=="sg-direct" and .uuid=="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")]|length)==1 and
  ([.inbounds[0].users[]|select(.name=="sg-via-jp" and .uuid=="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")]|length)==1 and
  ([.inbounds[0].users[]|select(.name=="sg-via-us-pav" and .uuid=="dddddddd-dddd-4ddd-8ddd-dddddddddddd")]|length)==1 and
  ([.inbounds[0].users[]|select(.name=="sg-via-global" and .uuid=="ffffffff-ffff-4fff-8fff-ffffffffffff")]|length)==1 and
  ([.outbounds[]|select(.tag=="to-extra-global-biglobe" and .type=="vless" and .server=="209.33.166.81" and .server_port==40045 and .uuid=="11111111-1111-4111-8111-111111111111")]|length)==1 and
  ([.route.rules[]|select(.auth_user==["sg-via-global-biglobe"] and .outbound=="to-extra-global-biglobe")]|length)==1 and
  ([.route.rules[]|select(.auth_user==["sg-via-global-pavlov"] and .outbound=="to-extra-global-pavlov")]|length)==1 and
  ([.route.rules[]|select(.auth_user==["sg-via-global-starhub"] and .outbound=="to-extra-global-starhub")]|length)==1 and
  ([.outbounds[]|select((.server // "")=="10.88.0.1")]|length)==0
' "$CONFIG_FILE" >/dev/null

write_exports
test "$(wc -l < "$URI_FILE" | tr -d '[:space:]')" = 7
grep -Fq '178.94.15.19:30010' "$URI_FILE"
grep -Fq '%E6%97%A5%E6%9C%AC%20BIGLOBE' "$URI_FILE"
! grep -Fq '11111111-1111-4111-8111-111111111111@' "$URI_FILE"
grep -Fq 'sg-via-global-biglobe' "$CLASH_FILE"

old_client="$(jq -r '.global_exits[]|select(.id=="global-biglobe")|.client_uuid' "$DATA_FILE")"
printf '%s' '12121212-1212-4121-8121-121212121212' | global_relay edit-exit "$DATA_FILE" global-biglobe global-biglobe-jp '日本 BIGLOBE（重命名）'
test "$(jq -r '.global_exits[]|select(.id=="global-biglobe-jp")|.client_uuid' "$DATA_FILE")" = "$old_client"
global_relay remove-exit "$DATA_FILE" global-pavlov >/dev/null
render_config > "$CONFIG_FILE"
"$BIN" check -c "$CONFIG_FILE"
test "$(jq -r '.global_exits|length' "$DATA_FILE")" = 2
test "$(jq -r '.extra_exits|length' "$DATA_FILE")" = 2
! jq -e '.outbounds[]|select(.tag=="to-extra-global-pavlov")' "$CONFIG_FILE" >/dev/null
jq -e '.outbounds[]|select(.tag=="to-extra-global-starhub" and .server=="209.33.166.81" and .server_port==40045)' "$CONFIG_FILE" >/dev/null

echo "Global JSON preview/apply, v4→v5 migration, UUID separation, seven-user config, routes, links, Clash and isolated edit/delete checks passed."

