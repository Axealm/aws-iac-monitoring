#!/usr/bin/env bash
# dev 環境を消して、消えたことと、残っているものを確認する。
# state 用のバケットと予算（bootstrap）は消さない。
#
#   bash scripts/dev/tf-destroy.sh
set -uo pipefail

cd "$(dirname "$0")/../.."
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
export TF_IN_AUTOMATION=1
mask() { sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g'; }

echo "== terraform destroy（envs/dev） =="
terraform -chdir=terraform/envs/dev destroy -auto-approve -input=false -no-color 2>&1 \
  | grep -E 'Destroy complete|Error' -A3 | mask
rc="${PIPESTATUS[0]}"
[ "$rc" -eq 0 ] || exit "$rc"

echo "== 消えたことの確認 =="
echo "state に残っているリソース: $(terraform -chdir=terraform/envs/dev state list 2>/dev/null | wc -l) 件"
echo "起動中・停止中の EC2（このプロジェクトのタグ）: $(aws ec2 describe-instances \
  --filters Name=tag:Project,Values=aws-iac-monitoring Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'length(Reservations[].Instances[])' --output text) 台"
echo "VPC（このプロジェクトのタグ）: $(aws ec2 describe-vpcs --filters Name=tag:Project,Values=aws-iac-monitoring \
  --query 'length(Vpcs)' --output text) 個"
echo "CloudWatch アラーム: $(aws cloudwatch describe-alarms --alarm-name-prefix aws-iac-monitoring-dev \
  --query 'length(MetricAlarms)' --output text) 個"
echo "SNS トピック: $(aws sns list-topics --query 'length(Topics[?contains(TopicArn, `aws-iac-monitoring-dev`)])' --output text) 個"

echo "== 残しているもの（費用はほぼ 0） =="
aws s3api list-buckets --query 'Buckets[?contains(Name, `aws-iac-monitoring`)].Name' --output text | tr '\t' '\n' | mask | sed 's/^/S3 バケット: /'
aws budgets describe-budgets --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --query 'Budgets[].BudgetName' --output text | sed 's/^/予算: /'
aws ssm describe-parameters --query 'Parameters[].Name' --output text | tr '\t' '\n' | sed 's/^/SSM パラメータ: /'
