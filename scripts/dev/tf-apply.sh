#!/usr/bin/env bash
# tf-plan.sh が保存した plan（tfplan）を、そのまま apply する。
# plan を見て承認した内容だけが作られる。表示では 12桁のアカウント ID を伏せる。
#
#   bash scripts/dev/tf-apply.sh terraform/bootstrap
#   bash scripts/dev/tf-apply.sh terraform/envs/dev
set -uo pipefail

dir="${1:?使い方: tf-apply.sh <Terraform のフォルダ>}"
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
export TF_IN_AUTOMATION=1

cd "$(dirname "$0")/../../$dir" || exit 1

if [ ! -f tfplan ]; then
  echo "tfplan がありません。先に tf-plan.sh を実行してください。"
  exit 1
fi

terraform apply -input=false -no-color tfplan 2>&1 | sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g'
rc="${PIPESTATUS[0]}"

# 同じ plan を二度使えないように消す
[ "$rc" -eq 0 ] && rm -f tfplan
exit "$rc"
