#!/usr/bin/env bash
# Zabbix の監視設定（ホスト、テンプレート、通知）をコードから登録する。
# SSM のポート転送を張り、その間に ansible/zabbix-config.yml を実行する。
#
#   bash scripts/dev/zabbix-config.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
bash "$here/zabbix-forward.sh" bash "$here/ansible.sh" ansible-playbook zabbix-config.yml "$@"
