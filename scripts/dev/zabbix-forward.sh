#!/usr/bin/env bash
# SSM のポート転送を張って、その間だけ指定したコマンドを実行する。
# 監視サーバーの中でしか待ち受けていない Zabbix（127.0.0.1:8080）に、手元の 127.0.0.1:18080 から届く。
# コマンドが終わると、ポート転送を閉じる。
#
#   bash scripts/dev/zabbix-forward.sh curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18080/
set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
local_port="${ZABBIX_LOCAL_PORT:-18080}"

monitor_id="$(terraform -chdir="$root/terraform/envs/dev" output -json instance_ids \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["monitor"])')"

aws ssm start-session --target "$monitor_id" --document-name AWS-StartPortForwardingSession \
  --parameters "portNumber=8080,localPortNumber=${local_port}" > /tmp/zabbix-forward.log 2>&1 &
pf=$!

cleanup() {
  kill "$pf" 2>/dev/null
  pkill -f "session-manager-plugin.*${monitor_id}" 2>/dev/null
}
trap cleanup EXIT

# 転送が使えるようになるまで待つ
ready=no
for i in $(seq 1 20); do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' -m 3 "http://127.0.0.1:${local_port}/" || true)" = 200 ]; then
    ready=yes
    break
  fi
  sleep 2
done
if [ "$ready" != yes ]; then
  echo "ポート転送を張れませんでした。" >&2
  sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g' /tmp/zabbix-forward.log >&2
  exit 1
fi

"$@"
