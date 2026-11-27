output "instance_ids" {
  description = "役割名 → インスタンス ID"
  value       = { for k, v in aws_instance.this : k => v.id }
}

output "private_ips" {
  description = "役割名 → プライベート IP"
  value       = { for k, v in aws_instance.this : k => v.private_ip }
}

output "public_ips" {
  description = "役割名 → パブリック IP"
  value       = { for k, v in aws_instance.this : k => v.public_ip }
}

output "iam_role_names" {
  description = "役割名 → IAM ロール名（あとから権限を足すときに使う）"
  value       = { for k, v in aws_iam_role.instance : k => v.name }
}

output "ansible_ssm_bucket_name" {
  description = "Ansible の SSM 接続が使う転送用バケットの名前"
  value       = aws_s3_bucket.ansible_ssm.bucket
}
