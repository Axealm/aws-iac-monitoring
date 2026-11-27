output "vpc_id" {
  description = "VPC の ID"
  value       = aws_vpc.this.id
}

output "public_subnet_id" {
  description = "public サブネットの ID"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "private サブネットの ID"
  value       = aws_subnet.private.id
}

output "monitor_security_group_id" {
  description = "monitor 用セキュリティグループの ID"
  value       = aws_security_group.monitor.id
}

output "web_security_group_id" {
  description = "web 用セキュリティグループの ID"
  value       = aws_security_group.web.id
}
