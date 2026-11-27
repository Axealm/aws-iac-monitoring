output "state_bucket_name" {
  description = "state 用バケットの名前。envs/dev/backend.hcl の bucket に書く"
  value       = aws_s3_bucket.tfstate.bucket
}

output "budget_name" {
  description = "作成した予算の名前"
  value       = aws_budgets_budget.monthly.name
}
