# EC2 に付ける IAM ロール。
# SSM Session Manager で接続するための最小限の権限（AmazonSSMManagedInstanceCore）だけを付ける。
# ロールを役割ごとに分けているのは、あとで monitor にだけ通知用の権限を足すため。

data "aws_partition" "current" {}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  for_each = var.instances

  name               = "${var.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  for_each = var.instances

  role       = aws_iam_role.instance[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  for_each = var.instances

  name = "${var.name}-${each.key}"
  role = aws_iam_role.instance[each.key].name
}
