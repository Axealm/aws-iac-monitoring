#!/usr/bin/env bash
# 通知の経路を確かめる。SNS の購読の状態を表示し、監視サーバーからテスト通知を1通送る。
# Zabbix が使うのと同じスクリプト・同じユーザー（zabbix）・同じ IAM ロールで送る。
#
#   bash scripts/dev/sns-test.sh
set -uo pipefail

cd "$(dirname "$0")/../.."
mask() { sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g'; }

topic="$(terraform -chdir=terraform/envs/dev output -raw sns_topic_arn)"
echo "== 購読の状態 =="
aws sns list-subscriptions-by-topic --topic-arn "$topic" \
  --query 'Subscriptions[].[Protocol,SubscriptionArn]' --output text | mask
if aws sns list-subscriptions-by-topic --topic-arn "$topic" --query 'Subscriptions[].SubscriptionArn' --output text \
  | grep -q PendingConfirmation; then
  echo "購読がまだ確認されていません。確認メールのリンクを押してください。"
  exit 1
fi

echo "== 監視サーバーからテスト通知を送る =="
bash scripts/dev/ssm-run.sh monitor <<'EOF' | mask
runuser -u zabbix -- /usr/lib/zabbix/alertscripts/sns-publish.sh \
  "[Zabbix] TEST: notification path check" \
  "This is a test message sent from the Zabbix server through its instance role."
EOF
