#!/usr/bin/env python3
"""Zabbix の API を呼ぶ小さな道具。標準ライブラリだけで動く。

SSM のポート転送（127.0.0.1:18080）が張られている前提で使う。

  bash scripts/dev/zabbix-forward.sh python3 scripts/dev/zabbix_api.py status
  bash scripts/dev/zabbix-forward.sh python3 scripts/dev/zabbix_api.py problems

管理者のパスワードは、SSM Parameter Store から AWS CLI で読む（画面には出さない）。
"""

import json
import os
import subprocess
import sys
import time
import urllib.request

URL = os.environ.get("ZABBIX_API_URL", "http://127.0.0.1:18080/api_jsonrpc.php")
PARAM = os.environ.get("ZABBIX_ADMIN_PARAM", "/iac-monitoring/dev/zabbix/admin-password")
REGION = os.environ.get("AWS_REGION", "ap-northeast-1")
HOST_GROUP = "aws-iac-monitoring"

SEVERITY = ["Not classified", "Information", "Warning", "Average", "High", "Disaster"]


class Zabbix:
    def __init__(self):
        self.token = None
        self._id = 0

    def call(self, method, params):
        self._id += 1
        body = json.dumps({"jsonrpc": "2.0", "method": method, "params": params, "id": self._id}).encode()
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        req = urllib.request.Request(URL, data=body, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as res:
            data = json.loads(res.read().decode())
        if "error" in data:
            raise RuntimeError("%s: %s" % (method, data["error"].get("data", data["error"])))
        return data["result"]

    def login(self):
        password = subprocess.run(
            ["aws", "ssm", "get-parameter", "--region", REGION, "--name", PARAM,
             "--with-decryption", "--query", "Parameter.Value", "--output", "text"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        self.token = self.call("user.login", {"username": "Admin", "password": password})
        return self

    def logout(self):
        if self.token:
            try:
                self.call("user.logout", [])
            finally:
                self.token = None

    def group_id(self):
        groups = self.call("hostgroup.get", {"filter": {"name": [HOST_GROUP]}, "output": ["groupid"]})
        return groups[0]["groupid"]

    def problems(self):
        """今発生している障害を、発生した順に返す。"""
        rows = self.call("problem.get", {
            "groupids": [self.group_id()],
            "output": ["eventid", "name", "severity", "clock"],
            "sortfield": ["eventid"],
        })
        return [{"eventid": r["eventid"], "name": r["name"],
                 "severity": SEVERITY[int(r["severity"])], "clock": int(r["clock"])} for r in rows]


def ts(epoch):
    return time.strftime("%H:%M:%S", time.localtime(epoch))


def cmd_status(z):
    hosts = z.call("host.get", {
        "groupids": [z.group_id()],
        "output": ["hostid", "host"],
        "selectInterfaces": ["ip", "available", "error"],
        "selectParentTemplates": ["name"],
    })
    available = {"0": "不明", "1": "利用可能", "2": "利用不可"}
    ok = True
    for h in sorted(hosts, key=lambda x: x["host"]):
        iface = h["interfaces"][0]
        state = available.get(str(iface["available"]), "?")
        ok = ok and str(iface["available"]) == "1"
        print("%s : エージェント %s" % (h["host"], state))
        print("    テンプレート: " + ", ".join(sorted(t["name"] for t in h["parentTemplates"])))
        items = z.call("item.get", {
            "hostids": [h["hostid"]],
            "output": ["name", "key_", "lastvalue", "lastclock", "state"],
            "search": {"key_": "systemd.unit.info"},
        }) + z.call("item.get", {
            "hostids": [h["hostid"]],
            "output": ["name", "key_", "lastvalue", "lastclock", "state"],
            "filter": {"key_": ["system.cpu.util[,idle,avg1]"]},
        })
        for it in sorted(items, key=lambda x: x["name"]):
            got = int(it["lastclock"]) > 0
            ok = ok and got and it["state"] == "0"
            value = it["lastvalue"] if got else "(まだ値なし)"
            print("    %-28s = %-10s %s" % (it["name"], value, ts(int(it["lastclock"])) if got else ""))
        web = z.call("httptest.get", {"hostids": [h["hostid"]], "output": ["name"]})
        for w in web:
            fail = z.call("item.get", {
                "hostids": [h["hostid"]], "webitems": True,
                "output": ["key_", "lastvalue", "lastclock"],
                "search": {"key_": "web.test."},
            })
            for it in sorted(fail, key=lambda x: x["key_"]):
                if it["key_"].startswith(("web.test.fail", "web.test.rspcode")):
                    got = int(it["lastclock"]) > 0
                    ok = ok and got
                    print("    %-28s = %-10s %s" % (it["key_"][:28], it["lastvalue"] if got else "(まだ値なし)",
                                                    ts(int(it["lastclock"])) if got else ""))
    problems = z.problems()
    print("発生中の障害: %d 件" % len(problems))
    for p in problems:
        print("    %s  [%s] %s" % (ts(p["clock"]), p["severity"], p["name"]))
    return 0 if ok else 1


def cmd_problems(z):
    print(json.dumps(z.problems(), ensure_ascii=False))
    return 0


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    z = Zabbix().login()
    try:
        if command == "status":
            return cmd_status(z)
        if command == "problems":
            return cmd_problems(z)
        print("使い方: zabbix_api.py [status|problems]", file=sys.stderr)
        return 2
    finally:
        z.logout()


if __name__ == "__main__":
    sys.exit(main())
