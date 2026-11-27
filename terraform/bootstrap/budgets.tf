# 月額の予算と通知。
# 予算はアカウント全体の費用が対象（このプロジェクト以外の費用も含む）。
# 通知だけで、課金を止める機能ではない。集計には数時間の遅れがある。

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # 無料プランでは、利用額がクレジットで相殺されて請求額が 0 になる。
  # そのままでは通知が一度も飛ばないので、相殺する前の利用額で判定する。
  # （クレジットを使い切ると無料プランのアカウントは閉じるため、減り具合を知る意味がある）
  cost_types {
    include_credit = false
    include_refund = false
  }

  # 実績が予算の 50%・80%・100% を超えたら通知する
  dynamic "notification" {
    for_each = [50, 80, 100]

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_email]
    }
  }

  # 月末の予測が予算を超えそうなときも通知する
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}
