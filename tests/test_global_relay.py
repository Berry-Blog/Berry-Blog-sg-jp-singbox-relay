import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from global_relay import (  # noqa: E402
    add_manual_exit,
    apply_import,
    parse_vless_uri,
    plan_import,
    remove_global_exit,
    remove_global_profile,
    validate_document,
)


U1 = "11111111-1111-4111-8111-111111111111"
U2 = "22222222-2222-4222-8222-222222222222"
U3 = "33333333-3333-4333-8333-333333333333"
CLIENT = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
PUB = "A" * 43


def doc():
    return {
        "schema_version": 1,
        "kind": "global-home-dogma-relay",
        "generated_at": "2026-11-14T00:00:00Z",
        "profile": {"profile_id": "global-home-main", "name": "Global Home",
                    "server": "209.33.166.81", "public_port": 40045, "network": "tcp",
                    "security": "reality", "sni": "www.apple.com", "fingerprint": "chrome",
                    "flow": "xtls-rprx-vision", "public_key": PUB, "short_id": "0123456789abcdef"},
        "exits": [
            {"id": "global-biglobe", "name": "日本 BIGLOBE", "uuid": U1, "email": "biglobe@home",
             "outbound_tag": "big-out", "socks5": {"server": "10.88.0.1", "port": 5002},
             "expected_exit_ip": "61.193.51.9", "enabled": True, "route_valid": True},
            {"id": "global-pavlov", "name": "美国 Pavlov", "uuid": U2, "email": "pavlov@home",
             "outbound_tag": "pav-out", "socks5": {"server": "10.88.0.1", "port": 5005},
             "expected_exit_ip": "96.63.208.157", "enabled": True, "route_valid": True},
            {"id": "global-starhub", "name": "新加坡 StarHub", "uuid": U3, "email": "starhub@home",
             "outbound_tag": "star-out", "socks5": {"server": "10.88.0.1", "port": 5009},
             "expected_exit_ip": "202.156.27.233", "enabled": True, "route_valid": True},
        ],
    }


def current_data():
    return {"schema_version": 4, "direct_uuid": CLIENT, "inbound_uuid": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            "inbound_private_key": "DOGMA_PRIVATE", "inbound_public_key": PUB,
            "inbound_short_id": "fedcba9876543210", "default_exit": "jp",
            "extra_exits": [{"id": "us-pav", "name": "美国 PAV（原线路）", "protocol": "reality",
                             "client_uuid": "cccccccc-cccc-4ccc-8ccc-cccccccccccc", "uuid": "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
                             "host": "old.example", "port": 443, "public_key": PUB, "short_id": "1122334455667788",
                             "sni": "addons.mozilla.org"}],
            "global_profiles": [], "global_exits": []}


class GlobalRelayTests(unittest.TestCase):
    def test_shared_fixture_and_schema_match_the_checked_in_protocol(self):
        root = Path(__file__).resolve().parents[1]
        doc_path = root / "tests" / "fixtures" / "global-home-dogma-relay-v1.json"
        schema_path = root / "docs" / "global-home-dogma-relay.schema.json"
        imported = validate_document(json.loads(doc_path.read_text(encoding="utf-8")))
        self.assertEqual(imported["profile"], doc()["profile"])
        self.assertEqual(imported["exits"], doc()["exits"])
        self.assertEqual(imported["anomalies"], [])
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        self.assertEqual(schema["properties"]["kind"]["const"], "global-home-dogma-relay")
        self.assertEqual(schema["properties"]["profile"]["properties"]["public_port"]["maximum"], 65535)

    def test_schema_validation_accepts_fixture_and_rejects_secret_or_invalid_routes(self):
        self.assertEqual(validate_document(doc())["profile"]["public_port"], 40045)
        bad = doc()
        bad["profile"]["private_key"] = "must-not-be-accepted"
        with self.assertRaises(ValueError):
            validate_document(bad)
        bad = doc()
        bad["exits"][0]["route_valid"] = False
        plan = plan_import(bad, current_data(), mode="incremental")
        self.assertNotIn("global-biglobe", plan["add"])
        self.assertTrue(any(row["id"] == "global-biglobe" for row in plan["anomalies"]))

    def test_incremental_import_adds_only_new_lines_and_never_deletes_existing_lines(self):
        current = current_data()
        current["global_profiles"] = [doc()["profile"]]
        current["global_exits"] = [{"id": "global-older", "name": "保留线路", "profile_id": "global-home-main",
                                     "global_uuid": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
                                     "client_uuid": "ffffffff-ffff-4fff-8fff-ffffffffffff", "enabled": True}]
        result = apply_import(doc(), current, mode="incremental")
        self.assertEqual({e["id"] for e in result["global_exits"]},
                         {"global-older", "global-biglobe", "global-pavlov", "global-starhub"})
        self.assertEqual(result["extra_exits"], current["extra_exits"])
        client_ids = [e["client_uuid"] for e in result["global_exits"]]
        self.assertEqual(len(client_ids), len(set(client_ids)))
        self.assertNotIn(U1, client_ids)

    def test_update_mode_keeps_client_uuid_and_incremental_mode_skips_changed_existing_line(self):
        current = current_data()
        current["global_profiles"] = [doc()["profile"]]
        current["global_exits"] = [{"id": "global-biglobe", "name": "旧名称", "profile_id": "global-home-main",
                                     "global_uuid": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
                                     "client_uuid": "ffffffff-ffff-4fff-8fff-ffffffffffff", "enabled": True}]
        plan = plan_import(doc(), current, mode="incremental")
        self.assertIn("global-biglobe", plan["duplicates"])
        self.assertNotIn("global-biglobe", plan["update"])
        updated = apply_import(doc(), current, mode="update")
        entry = next(e for e in updated["global_exits"] if e["id"] == "global-biglobe")
        self.assertEqual(entry["client_uuid"], "ffffffff-ffff-4fff-8fff-ffffffffffff")
        self.assertEqual(entry["global_uuid"], U1)
        self.assertEqual(entry["name"], "日本 BIGLOBE")

    def test_conflicting_public_profile_needs_explicit_confirmation(self):
        current = current_data()
        current["global_profiles"] = [dict(doc()["profile"], sni="other.example")]
        with self.assertRaisesRegex(ValueError, "公共参数冲突"):
            apply_import(doc(), current, mode="incremental")
        updated = apply_import(doc(), current, mode="incremental", allow_profile_update=True)
        self.assertEqual(updated["global_profiles"][0]["sni"], "www.apple.com")

    def test_manual_link_parser_and_added_exit_keep_uuids_separate(self):
        link = (f"vless://{U1}@209.33.166.81:40045?encryption=none&flow=xtls-rprx-vision"
                f"&security=reality&sni=www.apple.com&fp=chrome&pbk={PUB}&sid=0123456789abcdef&type=tcp#BIGLOBE")
        parsed = parse_vless_uri(link)
        self.assertEqual(parsed["global_uuid"], U1)
        self.assertEqual(parsed["profile"]["server"], "209.33.166.81")
        self.assertEqual(parsed["profile"]["public_port"], 40045)
        current = current_data()
        result = add_manual_exit(current, parsed["profile"], "global-biglobe", "日本 BIGLOBE", U1)
        entry = result["global_exits"][0]
        self.assertNotEqual(entry["global_uuid"], entry["client_uuid"])
        self.assertNotIn(entry["client_uuid"], (CLIENT, current["inbound_uuid"]))
        self.assertEqual(result["schema_version"], 5)

    def test_removing_profile_with_attached_exit_is_forbidden(self):
        current = current_data()
        current["global_profiles"] = [doc()["profile"]]
        current["global_exits"] = [{"id": "global-biglobe", "profile_id": "global-home-main",
                                     "global_uuid": U1, "client_uuid": "ffffffff-ffff-4fff-8fff-ffffffffffff",
                                     "name": "日本 BIGLOBE", "enabled": True}]
        with self.assertRaisesRegex(ValueError, "仍有关联线路"):
            remove_global_profile(current, "global-home-main")
        reduced = remove_global_exit(current, "global-biglobe")
        self.assertEqual(reduced["global_exits"], [])
        self.assertEqual(remove_global_profile(reduced, "global-home-main")["global_profiles"], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
