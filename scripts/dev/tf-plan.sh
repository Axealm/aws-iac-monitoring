#!/usr/bin/env bash
# terraform plan を実行して、結果をファイル（tfplan）に保存する。何も作らない。
# 表示するときは、12桁のアカウント ID を伏せる。
#
#   bash scripts/dev/tf-plan.sh terraform/bootstrap
#   bash scripts/dev/tf-plan.sh terraform/envs/dev
set -uo pipefail

dir="${1:?使い方: tf-plan.sh <Terraform のフォルダ>}"
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
export TF_IN_AUTOMATION=1
mkdir -p "$TF_PLUGIN_CACHE_DIR"

cd "$(dirname "$0")/../../$dir" || exit 1

init_args=(-input=false -no-color)
[ -f backend.hcl ] && init_args+=(-backend-config=backend.hcl)
if ! terraform init "${init_args[@]}" > /tmp/tf-init.log 2>&1; then
  sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g' /tmp/tf-init.log | tail -20
  exit 1
fi

terraform plan -input=false -no-color -out=tfplan 2>&1 | sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g'
exit "${PIPESTATUS[0]}"
