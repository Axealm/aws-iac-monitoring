#!/usr/bin/env bash
# SSM 経由で、指定した役割のインスタンスでシェルのコマンドを実行し、結果を表示する。
# 調査や確認のための道具。コマンドは標準入力から渡す。
#
#   echo 'systemctl is-active nginx' | bash scripts/dev/ssm-run.sh web
#   bash scripts/dev/ssm-run.sh monitor < some-commands.sh
set -uo pipefail

role="${1:?使い方: ssm-run.sh <monitor|web> （コマンドは標準入力から）}"
cd "$(dirname "$0")/../.."

id="$(terraform -chdir=terraform/envs/dev output -json instance_ids | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$role")"
params="$(python3 -c 'import json,sys; print(json.dumps({"commands": [sys.stdin.read()]}))')"

cid="$(aws ssm send-command --instance-ids "$id" --document-name AWS-RunShellScript \
  --parameters "$params" --query Command.CommandId --output text)" || exit 1

status=Pending
for i in $(seq 1 100); do
  status="$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$id" --query Status --output text 2>/dev/null)"
  case "$status" in Success|Failed|TimedOut|Cancelled) break ;; esac
  sleep 3
done

aws ssm get-command-invocation --command-id "$cid" --instance-id "$id" --query StandardOutputContent --output text
err="$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$id" --query StandardErrorContent --output text)"
[ -n "$err" ] && [ "$err" != "None" ] && { echo "--- stderr ---"; echo "$err"; }
echo "[ssm-run] $role: $status"
[ "$status" = "Success" ]
