#!/usr/bin/env bash
# 障害注入テストを続けて実行する。引数がなければ、短時間で終わる3種類を実行する。
#
#   bash scripts/fault-injection/run-all.sh                      nginx-stop chronyd-stop omikuji-stop
#   bash scripts/fault-injection/run-all.sh cpu-load             指定したものだけ
#
# テストの間は少し待つ（前のテストの復旧の通知が落ち着くのを待つため）。
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
[ "$#" -gt 0 ] || set -- nginx-stop chronyd-stop omikuji-stop

failed=0
for scenario in "$@"; do
  echo "########## $scenario"
  bash "$here/run.sh" "$scenario" 2>&1 | sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g'
  rc="${PIPESTATUS[0]}"
  echo "exit=$rc"
  [ "$rc" -eq 0 ] || failed=1
  sleep 45
done
exit "$failed"
