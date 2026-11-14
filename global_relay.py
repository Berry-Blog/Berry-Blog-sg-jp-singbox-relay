#!/usr/bin/env python3
"""Validated Global Home relay import and manual-entry data operations."""
from __future__ import annotations

import argparse
import copy
import datetime as dt
import ipaddress
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import uuid as uuidlib
from urllib.parse import parse_qs, urlsplit


SCHEMA_VERSION = 1
KIND = "global-home-dogma-relay"
DATA_SCHEMA_VERSION = 5
PROFILE_FIELDS = ("profile_id", "name", "server", "public_port", "network", "security",
                  "sni", "fingerprint", "flow", "public_key", "short_id")
_ID_RE = re.compile(r"^[a-z][a-z0-9-]{1,31}$")
_UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
_PUB_RE = re.compile(r"^[A-Za-z0-9_-]{43}$")
_SHORT_RE = re.compile(r"^(?:[0-9a-fA-F]{2}){1,8}$")
_TAG_RE = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")


def _host(value, label):
    if not isinstance(value, str) or not value or len(value) > 253 or any(c.isspace() for c in value) or "/" in value:
        raise ValueError(f"{label}格式无效")
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        if not re.fullmatch(r"(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", value) or ".." in value:
            raise ValueError(f"{label}格式无效") from None
        if any(not part or len(part) > 63 or part.startswith("-") or part.endswith("-") for part in value.split(".")):
            raise ValueError(f"{label}格式无效")
        return value.lower()


def _port(value, label):
    if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= 65535:
        raise ValueError(f"{label}无效")
    return value


def _profile(profile):
    if not isinstance(profile, dict):
        raise ValueError("Global公共参数结构无效")
    if any(any(part in str(key).lower() for part in ("private", "password", "secret", "client_uuid")) for key in profile):
        raise ValueError("Global公共参数不得包含Private Key、密码或狗妈客户端UUID")
    pid = profile.get("profile_id")
    if not isinstance(pid, str) or not _ID_RE.fullmatch(pid):
        raise ValueError("profile_id格式无效")
    name = profile.get("name")
    if not isinstance(name, str) or not name.strip() or len(name) > 120 or any(ord(c) < 32 for c in name):
        raise ValueError("Global配置名称无效")
    normalized = dict(profile)
    normalized["profile_id"] = pid
    normalized["name"] = name.strip()
    normalized["server"] = _host(profile.get("server"), "Global公网IP/域名")
    normalized["public_port"] = _port(profile.get("public_port"), "Global公网映射端口")
    if profile.get("network") != "tcp" or profile.get("security") != "reality":
        raise ValueError("当前只支持TCP Reality配置")
    normalized["network"] = "tcp"
    normalized["security"] = "reality"
    normalized["sni"] = _host(profile.get("sni"), "Global Reality SNI")
    if profile.get("fingerprint") != "chrome":
        raise ValueError("Global Reality Fingerprint必须是chrome")
    if profile.get("flow") != "xtls-rprx-vision":
        raise ValueError("Global Reality Flow必须是xtls-rprx-vision")
    if not isinstance(profile.get("public_key"), str) or not _PUB_RE.fullmatch(profile["public_key"]):
        raise ValueError("Global Reality Public Key格式无效")
    normalized["public_key"] = profile["public_key"]
    if not isinstance(profile.get("short_id"), str) or not _SHORT_RE.fullmatch(profile["short_id"]):
        raise ValueError("Global Reality Short ID格式无效")
    normalized["short_id"] = profile["short_id"].lower()
    allowed = set(PROFILE_FIELDS)
    if set(normalized) - allowed:
        raise ValueError("Global公共参数包含不支持的字段")
    return {key: normalized[key] for key in PROFILE_FIELDS}


def validate_document(document):
    if not isinstance(document, dict):
        raise ValueError("JSON顶层必须是对象")
    if document.get("schema_version") != SCHEMA_VERSION or isinstance(document.get("schema_version"), bool):
        raise ValueError("不支持的schema_version")
    if document.get("kind") != KIND:
        raise ValueError("JSON kind不正确")
    generated = document.get("generated_at")
    if not isinstance(generated, str):
        raise ValueError("generated_at缺失")
    try:
        dt.datetime.fromisoformat(generated.replace("Z", "+00:00"))
    except ValueError:
        raise ValueError("generated_at必须是ISO8601时间") from None
    profile = _profile(document.get("profile"))
    exits = document.get("exits")
    if not isinstance(exits, list) or len(exits) > 500:
        raise ValueError("exits必须是最多500条线路的数组")
    result = dict(document)
    result["profile"] = profile
    result["exits"] = copy.deepcopy(exits)
    _reject_secrets(result)
    return result


def _reject_secrets(value, parent=""):
    if isinstance(value, dict):
        for key, child in value.items():
            name = str(key).lower()
            if any(part in name for part in ("private_key", "password", "secret", "dogma_client_uuid", "client_uuid")):
                raise ValueError("JSON不得包含Private Key、密码或狗妈客户端UUID")
            _reject_secrets(child, name)
    elif isinstance(value, list):
        for child in value:
            _reject_secrets(child, parent)


def _exit_problem(row):
    if not isinstance(row, dict):
        return "线路不是对象"
    line_id = row.get("id")
    if not isinstance(line_id, str) or not _ID_RE.fullmatch(line_id):
        return "线路ID格式无效"
    name = row.get("name")
    if not isinstance(name, str) or not name.strip() or len(name) > 180 or any(ord(c) < 32 for c in name):
        return "线路名称无效"
    if not isinstance(row.get("uuid"), str) or not _UUID_RE.fullmatch(row["uuid"]):
        return "Global UUID格式无效"
    if not isinstance(row.get("email"), str) or len(row["email"]) > 254 or any(ord(c) < 32 for c in row["email"]):
        return "Xray email无效"
    if not isinstance(row.get("outbound_tag"), str) or not _TAG_RE.fullmatch(row["outbound_tag"]):
        return "Xray outboundTag无效"
    socks = row.get("socks5")
    if not isinstance(socks, dict):
        return "Global出口映射缺少SOCKS状态"
    try:
        _host(socks.get("server"), "Global内部SOCKS地址")
        _port(socks.get("port"), "Global内部SOCKS端口")
    except ValueError as exc:
        return str(exc)
    if not isinstance(row.get("enabled"), bool) or not isinstance(row.get("route_valid"), bool):
        return "线路缺少enabled或route_valid状态"
    if not row["enabled"]:
        return "Global线路未启用"
    if not row["route_valid"]:
        return "Global UUID到SOCKS5路由无效"
    expected = row.get("expected_exit_ip")
    if expected is not None:
        try:
            ipaddress.ip_address(expected)
        except (ValueError, TypeError):
            return "预期出口IP格式无效"
    return None


def _current(value):
    if not isinstance(value, dict):
        raise ValueError("本地relay.json格式无效")
    state = copy.deepcopy(value)
    state.setdefault("global_profiles", [])
    state.setdefault("global_exits", [])
    if not isinstance(state["global_profiles"], list) or not isinstance(state["global_exits"], list):
        raise ValueError("本地Global profile或线路数据格式无效")
    return state


def _profile_equal(left, right):
    return all(left.get(field) == right.get(field) for field in PROFILE_FIELDS)


def plan_import(document, current_data, mode="incremental"):
    if mode not in ("add", "update", "incremental"):
        raise ValueError("导入模式无效")
    doc = validate_document(document)
    state = _current(current_data)
    profile = doc["profile"]
    profiles = [item for item in state["global_profiles"] if isinstance(item, dict) and item.get("profile_id") == profile["profile_id"]]
    profile_conflict = bool(profiles and not _profile_equal(profiles[0], profile))
    if len(profiles) > 1:
        profile_conflict = True

    additions, updates, duplicates, anomalies = [], [], [], []
    seen_ids, seen_uuids = set(), set()
    current_exits = state["global_exits"]
    current_by_id = {item.get("id"): item for item in current_exits if isinstance(item, dict)}
    current_global_uuids = {item.get("global_uuid"): item.get("id") for item in current_exits if isinstance(item, dict)}
    local_clients = _local_client_uuids(state)
    legacy_ids = _legacy_line_ids(state)
    for row in doc["exits"]:
        reason = _exit_problem(row)
        line_id = row.get("id") if isinstance(row, dict) and isinstance(row.get("id"), str) else "unknown"
        if not reason and line_id in {"direct", "jp"}:
            reason = "线路ID与保留内置ID冲突"
        if not reason and line_id in legacy_ids and line_id not in current_by_id:
            reason = "线路ID与现有非Global线路冲突"
        if reason:
            anomalies.append({"id": line_id, "name": row.get("name", line_id) if isinstance(row, dict) else line_id, "reason": reason})
            continue
        uid = row["uuid"].lower()
        if line_id in seen_ids:
            anomalies.append({"id": line_id, "name": row["name"], "reason": "JSON内线路ID重复"})
            continue
        if uid in seen_uuids:
            anomalies.append({"id": line_id, "name": row["name"], "reason": "JSON内Global UUID重复"})
            continue
        seen_ids.add(line_id)
        seen_uuids.add(uid)
        existing = current_by_id.get(line_id)
        existing_uuid_owner = current_global_uuids.get(uid)
        if uid in local_clients:
            anomalies.append({"id": line_id, "name": row["name"], "reason": "Global UUID与本地客户端UUID冲突"})
            continue
        if uid in _remote_uuids(state, exclude_global_id=line_id if existing else None):
            anomalies.append({"id": line_id, "name": row["name"], "reason": "Global UUID与现有非Global/其他远端VLESS UUID冲突"})
            continue
        if existing_uuid_owner is not None and existing_uuid_owner != line_id:
            anomalies.append({"id": line_id, "name": row["name"], "reason": "Global UUID已被其他线路使用"})
            continue
        if existing:
            if existing.get("profile_id") != profile["profile_id"]:
                anomalies.append({"id": line_id, "name": row["name"], "reason": "线路ID已关联其他Global profile"})
            elif mode == "update" and (existing.get("global_uuid", "").lower() != uid or existing.get("name") != row["name"]):
                updates.append(row)
            else:
                duplicates.append(line_id)
        else:
            additions.append(row)
    return {"profile_id": profile["profile_id"], "profile_conflict": profile_conflict,
            "add": [row["id"] for row in additions], "update": [row["id"] for row in updates],
            "duplicates": duplicates, "anomalies": anomalies,
            "_additions": additions, "_updates": updates, "_profile": profile}


def _local_client_uuids(state):
    result = set()
    for key in ("direct_uuid", "inbound_uuid"):
        value = state.get(key)
        if isinstance(value, str):
            result.add(value.lower())
    for collection in ("extra_exits", "global_exits"):
        for item in state.get(collection, []) if isinstance(state.get(collection), list) else []:
            value = item.get("client_uuid") if isinstance(item, dict) else None
            if isinstance(value, str):
                result.add(value.lower())
    return result


def _legacy_line_ids(state):
    result = {"direct", "jp"}
    for item in state.get("extra_exits", []) if isinstance(state.get("extra_exits"), list) else []:
        if isinstance(item, dict) and isinstance(item.get("id"), str):
            result.add(item["id"])
    return result


def _remote_uuids(state, exclude_global_id=None):
    result = set()
    for key in ("jp_uuid",):
        value = state.get(key)
        if isinstance(value, str) and value:
            result.add(value.lower())
    for item in state.get("extra_exits", []) if isinstance(state.get("extra_exits"), list) else []:
        if isinstance(item, dict):
            for key in ("uuid", "global_uuid"):
                value = item.get(key)
                if isinstance(value, str) and value:
                    result.add(value.lower())
    for item in state.get("global_exits", []) if isinstance(state.get("global_exits"), list) else []:
        if isinstance(item, dict) and item.get("id") != exclude_global_id:
            value = item.get("global_uuid")
            if isinstance(value, str) and value:
                result.add(value.lower())
    return result


def _new_client_uuid(state, forbidden):
    global_uuids = _remote_uuids(state)
    used = _local_client_uuids(state) | global_uuids | {str(value).lower() for value in forbidden}
    for _ in range(16):
        value = str(uuidlib.uuid4())
        if value.lower() not in used:
            return value
    raise RuntimeError("无法生成唯一的狗妈客户端UUID")


def _stored_exit(row, profile, client_uuid=None, previous=None):
    result = {"id": row["id"], "name": row["name"], "profile_id": profile["profile_id"],
              "global_uuid": row["uuid"].lower(),
              "client_uuid": (previous or {}).get("client_uuid") or client_uuid,
              "enabled": (previous or {}).get("enabled", True),
              "expected_exit_ip": row.get("expected_exit_ip")}
    if row.get("email") and row.get("outbound_tag") and row.get("route_valid") is True:
        result.update({"source": "global-json", "verification": "global-export-validated",
                       "source_email": row["email"], "source_outbound_tag": row["outbound_tag"]})
    else:
        result.update({"source": "manual", "verification": "unverified"})
    return result


def apply_import(document, current_data, mode="incremental", allow_profile_update=False):
    doc = validate_document(document)
    state = _current(current_data)
    plan = plan_import(doc, state, mode)
    if plan["profile_conflict"] and not allow_profile_update:
        raise ValueError("Global公共参数冲突；必须在预览后明确确认更新此profile")
    if plan["profile_conflict"]:
        state["global_profiles"] = [p for p in state["global_profiles"] if not (isinstance(p, dict) and p.get("profile_id") == doc["profile"]["profile_id"])]

    rows_to_add = plan["_additions"]
    rows_to_update = plan["_updates"]
    if rows_to_add or rows_to_update or plan["profile_conflict"]:
        if not any(isinstance(p, dict) and p.get("profile_id") == doc["profile"]["profile_id"] for p in state["global_profiles"]):
            state["global_profiles"].append(doc["profile"])
        else:
            state["global_profiles"] = [doc["profile"] if isinstance(p, dict) and p.get("profile_id") == doc["profile"]["profile_id"] else p for p in state["global_profiles"]]
    current_by_id = {item.get("id"): item for item in state["global_exits"] if isinstance(item, dict)}
    forbidden = [row["uuid"] for row in rows_to_add + rows_to_update]
    for row in rows_to_add:
        state["global_exits"].append(_stored_exit(row, doc["profile"], _new_client_uuid(state, forbidden)))
    for row in rows_to_update:
        previous = current_by_id[row["id"]]
        replacement = _stored_exit(row, doc["profile"], previous=previous)
        state["global_exits"] = [replacement if isinstance(item, dict) and item.get("id") == row["id"] else item for item in state["global_exits"]]
    if rows_to_add or rows_to_update or plan["profile_conflict"]:
        state["schema_version"] = DATA_SCHEMA_VERSION
    return state


def add_manual_exit(current_data, profile, line_id, name, global_uuid):
    state = _current(current_data)
    profile = _profile(profile)
    if not isinstance(line_id, str) or not _ID_RE.fullmatch(line_id):
        raise ValueError("线路ID格式无效")
    if not isinstance(name, str) or not name.strip() or len(name) > 180 or any(ord(c) < 32 for c in name):
        raise ValueError("线路名称无效")
    if not isinstance(global_uuid, str) or not _UUID_RE.fullmatch(global_uuid):
        raise ValueError("Global UUID格式无效")
    if line_id in {"direct", "jp"}:
        raise ValueError("线路ID与保留内置ID冲突")
    if line_id in _legacy_line_ids(state) or any(item.get("id") == line_id for item in state["global_exits"] if isinstance(item, dict)):
        raise ValueError("线路ID已存在或与原有线路冲突")
    if global_uuid.lower() in _remote_uuids(state):
        raise ValueError("Global UUID与现有远端VLESS UUID冲突")
    if global_uuid.lower() in _local_client_uuids(state):
        raise ValueError("Global UUID与本地客户端UUID冲突")
    existing_profile = next((p for p in state["global_profiles"] if isinstance(p, dict) and p.get("profile_id") == profile["profile_id"]), None)
    if existing_profile and not _profile_equal(existing_profile, profile):
        raise ValueError("Global公共参数冲突；请通过profile修改菜单明确更新")
    if not existing_profile:
        state["global_profiles"].append(profile)
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    row = {"id": line_id, "name": name.strip(), "uuid": global_uuid.lower(), "enabled": True}
    state["global_exits"].append(_stored_exit(row, profile, _new_client_uuid(state, [global_uuid]), previous={"created_at": now}))
    state["schema_version"] = DATA_SCHEMA_VERSION
    return state


def edit_global_exit(current_data, old_id, new_id, name, global_uuid):
    state = _current(current_data)
    target = next((e for e in state["global_exits"] if isinstance(e, dict) and e.get("id") == old_id), None)
    if not target:
        raise ValueError("未找到Global线路")
    if not isinstance(new_id, str) or not _ID_RE.fullmatch(new_id):
        raise ValueError("线路ID格式无效")
    if not isinstance(name, str) or not name.strip() or len(name) > 180 or any(ord(c) < 32 for c in name):
        raise ValueError("线路名称无效")
    if not isinstance(global_uuid, str) or not _UUID_RE.fullmatch(global_uuid):
        raise ValueError("Global UUID格式无效")
    if new_id in {"direct", "jp"}:
        raise ValueError("线路ID与保留内置ID冲突")
    if new_id in _legacy_line_ids(state) or any(e.get("id") == new_id and e is not target for e in state["global_exits"] if isinstance(e, dict)):
        raise ValueError("线路ID已存在或与原有线路冲突")
    if global_uuid.lower() in _remote_uuids(state, exclude_global_id=old_id):
        raise ValueError("Global UUID与现有远端VLESS UUID冲突")
    if global_uuid.lower() in _local_client_uuids(state):
        raise ValueError("Global UUID与本地客户端UUID冲突")
    target["id"], target["name"], target["global_uuid"] = new_id, name.strip(), global_uuid.lower()
    if state.get("default_exit") == old_id:
        state["default_exit"] = new_id
    state["schema_version"] = DATA_SCHEMA_VERSION
    return state


def remove_global_exit(current_data, line_id):
    state = _current(current_data)
    before = len(state["global_exits"])
    state["global_exits"] = [item for item in state["global_exits"] if not (isinstance(item, dict) and item.get("id") == line_id)]
    if len(state["global_exits"]) == before:
        raise ValueError("未找到Global线路")
    if state.get("default_exit") == line_id:
        state["default_exit"] = "jp" if state.get("jp_enabled", True) else "direct"
    state["schema_version"] = DATA_SCHEMA_VERSION
    return state


def remove_global_profile(current_data, profile_id):
    state = _current(current_data)
    if any(isinstance(e, dict) and e.get("profile_id") == profile_id for e in state["global_exits"]):
        raise ValueError("Global profile仍有关联线路")
    found = any(isinstance(p, dict) and p.get("profile_id") == profile_id for p in state["global_profiles"])
    if not found:
        raise ValueError("未找到Global profile")
    state["global_profiles"] = [p for p in state["global_profiles"] if not (isinstance(p, dict) and p.get("profile_id") == profile_id)]
    state["schema_version"] = DATA_SCHEMA_VERSION
    return state


def update_global_profile(current_data, profile):
    state = _current(current_data)
    profile = _profile(profile)
    if not any(isinstance(p, dict) and p.get("profile_id") == profile["profile_id"] for p in state["global_profiles"]):
        raise ValueError("未找到Global profile")
    state["global_profiles"] = [profile if isinstance(p, dict) and p.get("profile_id") == profile["profile_id"] else p for p in state["global_profiles"]]
    state["schema_version"] = DATA_SCHEMA_VERSION
    return state


def parse_vless_uri(uri):
    if not isinstance(uri, str) or len(uri) > 16384:
        raise ValueError("VLESS链接无效")
    try:
        parsed = urlsplit(uri.strip())
        if parsed.scheme != "vless" or not parsed.hostname or parsed.port is None:
            raise ValueError
        global_uuid = parsed.username
        query = parse_qs(parsed.query, keep_blank_values=True, strict_parsing=False)
    except (ValueError, TypeError):
        raise ValueError("VLESS链接格式无效") from None
    if not isinstance(global_uuid, str) or not _UUID_RE.fullmatch(global_uuid):
        raise ValueError("VLESS链接中的Global UUID无效")
    def one(key):
        values = query.get(key, [])
        if len(values) != 1:
            raise ValueError("VLESS链接缺少唯一参数：" + key)
        return values[0]
    if one("encryption") != "none" or one("security") != "reality" or one("type") != "tcp":
        raise ValueError("VLESS链接必须是TCP Reality")
    profile = _profile({"profile_id": "global-home-main", "name": "Global Home", "server": parsed.hostname,
                        "public_port": parsed.port, "network": "tcp", "security": "reality",
                        "sni": one("sni"), "fingerprint": one("fp"), "flow": one("flow"),
                        "public_key": one("pbk"), "short_id": one("sid")})
    return {"profile": profile, "global_uuid": global_uuid.lower()}


def _write_state(path, state):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix="." + path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            os.fchmod(stream.fileno(), 0o600)
            json.dump(state, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
        path.chmod(0o600)
    except BaseException:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise


def _load(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        raise ValueError("JSON文件不存在或格式无效") from None


def _print_json(value):
    print(json.dumps(value, ensure_ascii=False, indent=2))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="command", required=True)
    subs.add_parser("parse-link")
    p = subs.add_parser("plan"); p.add_argument("document"); p.add_argument("state"); p.add_argument("mode", choices=("add", "update", "incremental"))
    p = subs.add_parser("apply"); p.add_argument("document"); p.add_argument("state"); p.add_argument("mode", choices=("add", "update", "incremental")); p.add_argument("--allow-profile-update", action="store_true")
    p = subs.add_parser("add-manual"); p.add_argument("state"); p.add_argument("profile"); p.add_argument("line_id"); p.add_argument("name")
    p = subs.add_parser("edit-exit"); p.add_argument("state"); p.add_argument("old_id"); p.add_argument("new_id"); p.add_argument("name")
    p = subs.add_parser("remove-exit"); p.add_argument("state"); p.add_argument("line_id")
    p = subs.add_parser("remove-profile"); p.add_argument("state"); p.add_argument("profile_id")
    p = subs.add_parser("update-profile"); p.add_argument("state"); p.add_argument("profile")
    args = parser.parse_args(argv)
    try:
        if args.command == "parse-link":
            _print_json(parse_vless_uri(sys.stdin.read()))
            return 0
        if args.command == "plan":
            _print_json(plan_import(_load(args.document), _load(args.state), args.mode))
            return 0
        state_path = Path(args.state)
        state = _load(state_path)
        if args.command == "apply":
            state = apply_import(_load(args.document), state, args.mode, args.allow_profile_update)
        elif args.command == "add-manual":
            state = add_manual_exit(state, _load(args.profile), args.line_id, args.name, sys.stdin.read().strip())
        elif args.command == "edit-exit":
            state = edit_global_exit(state, args.old_id, args.new_id, args.name, sys.stdin.read().strip())
        elif args.command == "remove-exit":
            state = remove_global_exit(state, args.line_id)
        elif args.command == "remove-profile":
            state = remove_global_profile(state, args.profile_id)
        elif args.command == "update-profile":
            state = update_global_profile(state, _load(args.profile))
        _write_state(state_path, state)
        _print_json({"schema_version": state.get("schema_version"), "global_exit_count": len(state.get("global_exits", []))})
        return 0
    except (ValueError, OSError, RuntimeError) as exc:
        print("Global线路操作失败：" + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
