#!/usr/bin/env bash
# dev 環境の、Git に入れない設定ファイルを作る。bootstrap の apply のあとに実行する。
#
#   bash scripts/dev/setup-dev-config.sh
#
# - terraform/envs/dev/backend.hcl      state 用バケットの名前（bootstrap の出力から取る）
# - terraform/envs/dev/terraform.tfvars 80 番を許可する IP（今のグローバル IP を /32 で書く）
# すでにあるファイルは上書きしない。
set -euo pipefail

cd "$(dirname "$0")/../.."

bucket="$(terraform -chdir=terraform/bootstrap output -raw state_bucket_name)"

if [ ! -f terraform/envs/dev/backend.hcl ]; then
  printf 'bucket = "%s"\n' "$bucket" > terraform/envs/dev/backend.hcl
  echo "backend.hcl を作りました。"
else
  echo "backend.hcl はすでにあります（変更なし）。"
fi

if [ ! -f terraform/envs/dev/terraform.tfvars ]; then
  # 今のグローバル IP を AWS の確認用サービスで調べる
  ip="$(curl -4 -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]')"
  if ! printf '%s' "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    echo "グローバル IP を取得できませんでした。terraform.tfvars を手で作ってください。"
    exit 1
  fi
  printf '# このファイルは .gitignore で除外している。\nallowed_http_cidrs = ["%s/32"]\n' "$ip" > terraform/envs/dev/terraform.tfvars
  echo "terraform.tfvars を作りました（今のグローバル IP を /32 で許可）。"
else
  echo "terraform.tfvars はすでにあります（変更なし）。"
fi
