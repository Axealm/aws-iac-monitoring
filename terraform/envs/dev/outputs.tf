output "instance_ids" {
  description = "役割名 → インスタンス ID"
  value       = module.compute.instance_ids
}

output "private_ips" {
  description = "役割名 → プライベート IP"
  value       = module.compute.private_ips
}

output "public_ips" {
  description = "役割名 → パブリック IP"
  value       = module.compute.public_ips
}

output "ansible_ssm_bucket_name" {
  description = "Ansible の SSM 接続が使う転送用バケットの名前"
  value       = module.compute.ansible_ssm_bucket_name
}

output "ssm_start_session_commands" {
  description = "各インスタンスに SSM Session Manager で接続するコマンド"
  value = {
    for role, id in module.compute.instance_ids :
    role => "aws ssm start-session --region ${var.region} --target ${id}"
  }
}

output "omikuji_url" {
  description = "おみくじ API の URL（allowed_http_cidrs に入れた IP からだけ開ける）"
  value       = "http://${module.compute.public_ips["web"]}/omikuji"
}
