# ==============================================================================
# Compliance Storage Module - S3 for Driver Documents
# ==============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.tags, { Module = "storage" })
}

# ------------------------------------------------------------------------------
# S3 Bucket for Driver Documents
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "driver_documents" {
  bucket = "${local.name_prefix}-driver-documents"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-driver-documents" })
}

resource "aws_s3_bucket_versioning" "driver_documents" {
  bucket = aws_s3_bucket.driver_documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "driver_documents" {
  bucket = aws_s3_bucket.driver_documents.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "driver_documents" {
  bucket = aws_s3_bucket.driver_documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "driver_documents" {
  bucket = aws_s3_bucket.driver_documents.id

  rule {
    id     = "expire-rejected-documents"
    status = "Enabled"

    filter {
      prefix = "rejected/"
    }

    expiration {
      days = 30
    }
  }

  rule {
    id     = "move-to-glacier"
    status = var.environment == "prod" ? "Enabled" : "Disabled"

    filter {
      prefix = "approved/"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }
}
