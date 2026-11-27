# 通知の出口（SNS）と、AWS の外側から見る監視（CloudWatch アラーム）。
#
# 役割分担:
# - Zabbix      … OS の中を見る（サービス、プロセス、メモリ、HTTP の応答）。細かく早い。
# - CloudWatch  … OS の外から見る（EC2 のステータスチェック、CPU）。
#                 Zabbix サーバー自身が止まっても検知できる。
# どちらの通知も、同じ SNS トピックからメールで届く。

data "aws_caller_identity" "current" {}

# --- 通知の出口 ---

resource "aws_sns_topic" "alerts" {
  #checkov:skip=CKV_AWS_26:AWS 管理の鍵（alias/aws/sns）で暗号化すると CloudWatch アラームから送れない。専用の KMS キーは月1ドルかかるので、検証用では暗号化しない。通知の本文に秘密情報は入れない
  name = "${var.name}-alerts"
}

# CloudWatch アラームからの送信だけを許可する（このアカウントのアラームに限る）。
# 同じアカウントの IAM ロール（monitor）は、下の IAM ポリシーで許可する。
data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid       = "AllowCloudWatchAlarms"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

# メールの購読。apply のあとに届く確認メールのリンクを押すまで、通知は届かない。
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# --- Zabbix から SNS へ送るための権限 ---

data "aws_iam_policy_document" "zabbix_publish" {
  statement {
    sid       = "PublishAlertsOnly"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "zabbix_publish" {
  name   = "${var.name}-zabbix-sns-publish"
  role   = var.zabbix_publisher_role_name
  policy = data.aws_iam_policy_document.zabbix_publish.json
}

# --- CloudWatch アラーム ---

# ハードウェアや OS が応答しなくなったとき。Zabbix からは「エージェントに届かない」としか
# 見えない障害を、AWS の側から確かめられる。
resource "aws_cloudwatch_metric_alarm" "status_check" {
  for_each = var.instance_ids

  alarm_name          = "${var.name}-${each.key}-status-check-failed"
  alarm_description   = "EC2 status check failed on ${each.key}. The instance or its host is not responding."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# CPU 使用率。基本モニタリング（5分間隔）の値を使うので、Zabbix より検知は遅い。
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = var.instance_ids

  alarm_name          = "${var.name}-${each.key}-cpu-high"
  alarm_description   = "CPU utilization on ${each.key} is at or above ${var.cpu_threshold_percent}% (5-minute average)."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.cpu_threshold_percent

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
