# Ansible の SSM 接続プラグイン（amazon.aws.aws_ssm）がファイル転送に使う S3 バケット。
# 一時ファイルの置き場なので、1日で自動削除し、destroy で中身ごと消せるようにする。

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "ansible_ssm" {
  #checkov:skip=CKV_AWS_21:一時ファイルの置き場で、1日で消す。前の版を残す必要がない
  bucket        = "${var.name}-ansible-ssm-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id

  rule {
    id     = "expire-transfer-files"
    status = "Enabled"

    filter {}

    expiration {
      days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "ansible_ssm_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.ansible_ssm.arn,
      "${aws_s3_bucket.ansible_ssm.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id
  policy = data.aws_iam_policy_document.ansible_ssm_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.ansible_ssm]
}
