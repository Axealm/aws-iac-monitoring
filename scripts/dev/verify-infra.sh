#!/usr/bin/env bash
# dev 環境を apply したあとの動作確認。読み取りと、SSM 経由の無害なコマンドの実行だけを行う。
# 表示では 12桁のアカウント ID と IP アドレスを伏せる。
#
#   bash scripts/dev/verify-infra.sh
set -uo pipefail

export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
export TF_IN_AUTOMATION=1
cd "$(dirname "$0")/../.."

mask() { sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g; s/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/<IP>/g'; }
tf() { terraform -chdir=terraform/envs/dev "$@"; }

monitor_id="$(tf output -json instance_ids | python3 -c 'import json,sys; print(json.load(sys.stdin)["monitor"])')"
web_id="$(tf output -json instance_ids | python3 -c 'import json,sys; print(json.load(sys.stdin)["web"])')"
monitor_ip="$(tf output -json public_ips | python3 -c 'import json,sys; print(json.load(sys.stdin)["monitor"])')"
web_ip="$(tf output -json public_ips | python3 -c 'import json,sys; print(json.load(sys.stdin)["web"])')"
failed=0

echo "===== 1. Systems Manager への登録 ====="
# 起動直後は登録まで1〜2分かかるので、最大5分待つ
for i in $(seq 1 30); do
  online="$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=${monitor_id},${web_id}" \
    --query 'length(InstanceInformationList[?PingStatus==`Online`])' --output text 2>/dev/null)"
  [ "$online" = "2" ] && break
  sleep 10
done
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=${monitor_id},${web_id}" \
  --query 'InstanceInformationList[].[InstanceId,PingStatus,PlatformName,PlatformVersion,AgentVersion]' --output text | mask
[ "$online" = "2" ] && echo "結果: 2台とも Online" || { echo "結果: Online が ${online:-0} 台"; failed=1; }

echo "===== 2. SSM 経由でコマンドを実行 ====="
for pair in "monitor:${monitor_id}" "web:${web_id}"; do
  role="${pair%%:*}"; id="${pair##*:}"
  cid="$(aws ssm send-command --instance-ids "$id" --document-name AWS-RunShellScript \
    --parameters 'commands=["hostname","cat /etc/system-release","nproc","free -m | sed -n 2p","systemctl is-active sshd chronyd amazon-ssm-agent"]' \
    --query Command.CommandId --output text 2>&1)" || { echo "[$role] 送信に失敗: $cid" | mask; failed=1; continue; }
  status=Pending
  for i in $(seq 1 20); do
    status="$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$id" --query Status --output text 2>/dev/null)"
    case "$status" in Success|Failed|TimedOut|Cancelled) break ;; esac
    sleep 3
  done
  echo "[$role] 状態: $status"
  aws ssm get-command-invocation --command-id "$cid" --instance-id "$id" --query StandardOutputContent --output text | mask | sed 's/^/    /'
  [ "$status" = "Success" ] || failed=1
done

echo "===== 3. セキュリティグループの受信ルール ====="
for name in monitor web; do
  sg="$(aws ec2 describe-security-groups --filters "Name=group-name,Values=aws-iac-monitoring-dev-${name}" --query 'SecurityGroups[0].GroupId' --output text)"
  echo "[$name] 受信:"
  aws ec2 describe-security-group-rules --filters "Name=group-id,Values=${sg}" \
    --query 'SecurityGroupRules[?IsEgress==`false`].[IpProtocol,FromPort,ToPort,CidrIpv4,ReferencedGroupInfo.GroupId]' --output text | mask | sed 's/^/    /'
  n22="$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=${sg}" \
    --query 'length(SecurityGroupRules[?IsEgress==`false` && FromPort<=`22` && ToPort>=`22`])' --output text)"
  echo "    22番を含む受信ルール: ${n22} 件"
  [ "$n22" = "0" ] || failed=1
done

echo "===== 4. 外からの接続（この PC から） ====="
probe() { # $1=ラベル $2=IP $3=ポート
  if timeout 5 bash -c "exec 3<>/dev/tcp/$2/$3" 2>/tmp/probe.err; then
    echo "$1 : 接続できた"
  elif grep -q -i 'refused' /tmp/probe.err; then
    echo "$1 : 拒否された（通信は届いたが、待ち受けているプログラムがない）"
  else
    echo "$1 : 応答なし（セキュリティグループで遮断）"
  fi
}
probe "monitor の 22番" "$monitor_ip" 22
probe "web の 22番    " "$web_ip" 22
probe "monitor の 80番" "$monitor_ip" 80
probe "web の 80番    " "$web_ip" 80

echo "===== 5. state とロック ====="
bucket="$(sed -n 's/^bucket *= *"\(.*\)"/\1/p' terraform/envs/dev/backend.hcl)"
aws s3 ls "s3://${bucket}/envs/dev/" | awk '{print "    " $3 " bytes  " $4}'
# use_lockfile が効いていれば、plan の実行中だけ S3 にロックファイル（.tflock）ができる。
# plan を裏で動かし、その間にロックファイルが現れることと、終わると消えることを確かめる。
tf plan -input=false -no-color > /tmp/lock-first.txt 2>&1 &
first=$!
seen=no
for i in $(seq 1 60); do
  if aws s3api head-object --bucket "$bucket" --key envs/dev/terraform.tfstate.tflock > /dev/null 2>&1; then
    seen=yes
    break
  fi
  kill -0 "$first" 2>/dev/null || break
  sleep 0.5
done
wait "$first"
grep -E 'No changes|Plan:' /tmp/lock-first.txt | sed 's/^/    plan の結果: /'
if [ "$seen" = yes ]; then
  echo "    plan の実行中: ロックファイルあり（期待どおり）"
else
  echo "    plan の実行中: ロックファイルを確認できなかった"
  failed=1
fi
if aws s3api head-object --bucket "$bucket" --key envs/dev/terraform.tfstate.tflock > /dev/null 2>&1; then
  echo "    plan の終了後: ロックファイルが残っている"
  failed=1
else
  echo "    plan の終了後: ロックファイルなし（期待どおり）"
fi

echo
[ "$failed" -eq 0 ] && echo "確認結果: 問題なし" || echo "確認結果: 失敗した項目あり"
exit "$failed"
