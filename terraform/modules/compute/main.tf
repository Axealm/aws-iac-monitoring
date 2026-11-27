# EC2 インスタンス。SSH の鍵は作らず、SSM Session Manager で接続する。

# 最新の Amazon Linux 2023 の AMI ID を、AWS が公開している SSM パラメータから取る
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "this" {
  #checkov:skip=CKV_AWS_88:NAT Gateway を使わない方針のため、SSM 接続とパッケージ取得にパブリック IP が要る。受信は SG で絞っている
  #checkov:skip=CKV_AWS_126:詳細モニタリング（1分間隔）は費用が増える。細かい監視は Zabbix が受け持つ
  for_each = var.instances

  ami                         = data.aws_ssm_parameter.al2023_ami.insecure_value
  instance_type               = each.value.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = each.value.security_group_ids
  iam_instance_profile        = aws_iam_instance_profile.instance[each.key].name
  associate_public_ip_address = true
  ebs_optimized               = true
  monitoring                  = false

  # key_name は指定しない（SSH を使わない）

  # メタデータは IMDSv2 を必須にする
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # T3 の既定（unlimited）は、負荷をかけ続けると追加料金が出る。
  # 障害注入で CPU 負荷をかけるので、standard にして上限を付ける。
  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = each.value.root_volume_gb
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.name}-${each.key}-root"
      Role = each.key
    }
  }

  tags = {
    Name = "${var.name}-${each.key}"
    Role = each.key
  }

  lifecycle {
    # 新しい AMI が公開されるたびにインスタンスが作り直されるのを防ぐ
    ignore_changes = [ami]
  }
}
