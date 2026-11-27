#!/usr/bin/env bash
# 手元での検査をまとめて実行する。AWS には接続しない。
#
#   bash scripts/dev/check.sh            すべて実行
#   bash scripts/dev/check.sh checkov    1つだけ実行（gitleaks / fmt / validate / tflint / checkov）
#
# 1つでも失敗すると、終了コード 1 で終わる。
set -uo pipefail

export PATH="$HOME/.local/bin:$PATH"
# プロバイダーを作業フォルダごとにダウンロードし直さないよう、共有のキャッシュを使う
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
export TF_IN_AUTOMATION=1
mkdir -p "$TF_PLUGIN_CACHE_DIR"

cd "$(dirname "$0")/../.." || exit 1

only="${1:-all}"
failed=0

run() { [ "$only" = all ] || [ "$only" = "$1" ]; }

if run gitleaks; then
  echo "===== gitleaks ====="
  # .terraform/（プロバイダーの本体）は対象にしないよう、Git が管理するファイルだけを調べる
  if ! git ls-files -co --exclude-standard -z | xargs -0 -I{} gitleaks dir "{}" --no-banner --redact --log-level warn; then
    failed=1
  fi
  echo "gitleaks: 完了"
fi

if run fmt; then
  echo "===== terraform fmt ====="
  terraform fmt -check -recursive -diff terraform || failed=1
fi

if run validate; then
  for d in terraform/bootstrap terraform/envs/dev; do
    echo "===== terraform validate: $d ====="
    (
      cd "$d" || exit 1
      if ! terraform init -backend=false -input=false -no-color > /tmp/tf-init.log 2>&1; then
        tail -20 /tmp/tf-init.log
        exit 1
      fi
      terraform validate -no-color
    ) || failed=1
  done
fi

if run tflint; then
  echo "===== tflint ====="
  tflint --init --config "$PWD/.tflint.hcl" > /dev/null
  tflint --recursive --config "$PWD/.tflint.hcl" --no-color || failed=1
  echo "tflint: 完了"
fi

if run checkov; then
  echo "===== checkov ====="
  checkov --config-file .checkov.yaml || failed=1
fi

if [ "$failed" -ne 0 ]; then
  echo "検査に失敗したものがあります。"
  exit 1
fi
echo "すべての検査が通りました。"
