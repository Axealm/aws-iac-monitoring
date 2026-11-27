#!/usr/bin/env bash
# 費用の見積もりに使う単価を、AWS の Price List API から取る（オンデマンド、米ドル）。
# あわせて、このアカウントで無料利用枠の対象になるインスタンスタイプを表示する。
#
#   bash scripts/dev/price-check.sh [リージョン]     既定は ap-northeast-1
set -uo pipefail

REGION="${1:-ap-northeast-1}"

# Price List API は us-east-1 で呼ぶ。返ってきた JSON から単価と説明だけを表示する。
price() {
  local svc="$1"
  shift
  aws pricing get-products --region us-east-1 --service-code "$svc" --filters "$@" --max-results 5 --output json \
    | python3 -c '
import json, sys
data = json.load(sys.stdin)
if not data.get("PriceList"):
    print("  (該当なし)")
    sys.exit()
for raw in data["PriceList"]:
    product = json.loads(raw)
    for term in product["terms"].get("OnDemand", {}).values():
        for dim in term["priceDimensions"].values():
            print("  %s USD / %s  -- %s" % (dim["pricePerUnit"].get("USD"), dim["unit"], dim["description"]))
'
}

f() { echo "Type=TERM_MATCH,Field=$1,Value=$2"; }

for t in t3.small t3.micro; do
  echo "== EC2 ${t}（Linux、${REGION}） =="
  price AmazonEC2 "$(f instanceType "$t")" "$(f regionCode "$REGION")" "$(f operatingSystem Linux)" \
    "$(f tenancy Shared)" "$(f preInstalledSw NA)" "$(f capacitystatus Used)"
done

echo "== EBS gp3（1GB・1か月あたり、${REGION}） =="
price AmazonEC2 "$(f regionCode "$REGION")" "$(f productFamily Storage)" "$(f volumeApiName gp3)"

echo "== パブリック IPv4 アドレス（${REGION}） =="
price AmazonVPC "$(f regionCode "$REGION")" "$(f group VPCPublicIPv4Address)"

echo "== 無料利用枠の対象になるインスタンスタイプ（${REGION}） =="
aws ec2 describe-instance-types --region "$REGION" \
  --filters Name=free-tier-eligible,Values=true \
  --query 'InstanceTypes[].InstanceType' --output text | tr '\t' '\n' | sort | tr '\n' ' '
echo
