#!/usr/bin/env bash
# 障害注入テストを1つ実行する。SSM のポート転送を張り、その間に run_test.py を動かす。
#
#   bash scripts/fault-injection/run.sh nginx-stop
#   bash scripts/fault-injection/run.sh chronyd-stop
#   bash scripts/fault-injection/run.sh omikuji-stop
#   bash scripts/fault-injection/run.sh cpu-load
#
# 対象は web サーバーだけ。注入したあとは、必ず復旧まで実行する。
# 結果は docs/evidence/<シナリオ名>.json に保存される。
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
bash "$here/../dev/zabbix-forward.sh" python3 "$here/run_test.py" "$@"
