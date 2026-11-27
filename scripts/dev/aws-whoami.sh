#!/usr/bin/env bash
# AWS の認証が通っているかを確認する。12桁のアカウント ID は伏せて表示する。
#
#   bash scripts/dev/aws-whoami.sh
set -uo pipefail

mask() { sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g'; }

echo "== 認証 (sts get-caller-identity) =="
if ! out="$(aws sts get-caller-identity --output json 2>&1)"; then
  echo "認証できていません:"
  echo "$out" | mask
  exit 1
fi
echo "$out" | mask

echo "== CLI の設定 =="
aws configure list 2>&1 | mask

echo "== アカウントのプラン (freetier get-account-plan-state) =="
# 無料プランか有料プランか、クレジットの残りを確認する。使えない場合は理由だけ表示する。
aws freetier get-account-plan-state --region us-east-1 --output json 2>&1 | mask
