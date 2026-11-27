output "sns_topic_arn" {
  description = "アラートの通知先の SNS トピックの ARN"
  value       = aws_sns_topic.alerts.arn
}

output "alarm_names" {
  description = "作成した CloudWatch アラームの名前"
  value = concat(
    [for a in aws_cloudwatch_metric_alarm.status_check : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.cpu_high : a.alarm_name],
  )
}
