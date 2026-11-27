#!/usr/bin/env python3
"""スクリーンショットを撮るための、閲覧だけできる一時的な Zabbix ユーザーを作る・消す。

管理者のパスワードを画面に入力せずに済ませるための道具。
ユーザーは aws-iac-monitoring グループのホストを「読み取り」だけできる。

  bash scripts/dev/zabbix-forward.sh python3 scripts/dev/zabbix_viewer.py create <パスワードを書き出すファイル>
  bash scripts/dev/zabbix-forward.sh python3 scripts/dev/zabbix_viewer.py delete

パスワードはランダムに作り、指定したファイルにだけ書く（画面には出さない）。
"""

import os
import secrets
import string
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from zabbix_api import Zabbix  # noqa: E402

USER = "evidence-viewer"
GROUP = "Evidence viewers (temporary)"


def delete(z):
    users = z.call("user.get", {"filter": {"username": [USER]}, "output": ["userid"]})
    if users:
        z.call("user.delete", [u["userid"] for u in users])
    groups = z.call("usergroup.get", {"filter": {"name": [GROUP]}, "output": ["usrgrpid"]})
    if groups:
        z.call("usergroup.delete", [g["usrgrpid"] for g in groups])
    print("一時ユーザー: 削除しました" if users or groups else "一時ユーザー: もともとありません")


def create(z, path):
    delete(z)
    group = z.call("usergroup.create", {
        "name": GROUP,
        # 2 = 読み取りのみ
        "hostgroup_rights": [{"id": z.group_id(), "permission": 2}],
    })
    role = z.call("role.get", {"filter": {"name": ["User role"]}, "output": ["roleid"]})[0]["roleid"]
    alphabet = string.ascii_letters + string.digits
    password = "".join(secrets.choice(alphabet) for _ in range(24))
    z.call("user.create", {
        "username": USER, "passwd": password, "roleid": role,
        "usrgrps": [{"usrgrpid": group["usrgrpids"][0]}],
        "lang": "ja_JP", "theme": "blue-theme",
    })
    with open(path, "w", encoding="utf-8") as f:
        f.write(password + "\n")
    os.chmod(path, 0o600)
    print("一時ユーザー %s を作りました（読み取りのみ）" % USER)


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    z = Zabbix().login()
    try:
        if command == "create" and len(sys.argv) > 2:
            create(z, sys.argv[2])
        elif command == "delete":
            delete(z)
        else:
            print("使い方: zabbix_viewer.py create <ファイル> | delete", file=sys.stderr)
            return 2
    finally:
        z.logout()
    return 0


if __name__ == "__main__":
    sys.exit(main())
