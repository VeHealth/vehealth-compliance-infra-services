# ==============================================================================
# Compliance Services Compute Module
# ==============================================================================
# Lambda functions for driver document management:
# - document_upload: Handle document uploads to S3
# - document_review: Review and approve/reject documents
# - document_expiry: Check for expiring documents
# ==============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.tags, { Module = "compute" })
  lambda_environment = {
    ENVIRONMENT        = var.environment
    LOG_LEVEL          = var.log_level
    RDS_PROXY_ENDPOINT = var.rds_proxy_endpoint
    DOCUMENTS_BUCKET   = var.documents_bucket_name
  }
}

# ------------------------------------------------------------------------------
# IAM Role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "compliance_lambda_role" {
  name = "${local.name_prefix}-compliance-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "lambda_logging" {
  name = "${local.name_prefix}-compliance-lambda-logging"
  role = aws_iam_role.compliance_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_vpc" {
  name = "${local.name_prefix}-compliance-lambda-vpc"
  role = aws_iam_role.compliance_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_secrets" {
  count = var.rds_security_group != null ? 1 : 0
  name  = "${local.name_prefix}-compliance-lambda-secrets"
  role  = aws_iam_role.compliance_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:*:*:secret:vehealth/${var.environment}/rds-*"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_s3" {
  name = "${local.name_prefix}-compliance-lambda-s3"
  role = aws_iam_role.compliance_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.documents_bucket_name}",
        "arn:aws:s3:::${var.documents_bucket_name}/*"
      ]
    }]
  })
}

# ------------------------------------------------------------------------------
# Security Group
# ------------------------------------------------------------------------------

resource "aws_security_group" "compliance_lambda_sg" {
  name        = "${local.name_prefix}-compliance-lambda-sg"
  description = "Security group for compliance Lambda functions"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-compliance-lambda-sg" })
}

# ------------------------------------------------------------------------------
# Lambda Functions
# ------------------------------------------------------------------------------

resource "aws_lambda_function" "document_upload" {
  function_name    = "${local.name_prefix}-document-upload"
  role             = aws_iam_role.compliance_lambda_role.arn
  handler          = "index.handler"
  runtime          = var.lambda_runtime
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout
  filename         = "${path.module}/lambda/functions/placeholder.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/functions/placeholder.zip")

  dynamic "vpc_config" {
    for_each = var.private_subnet_ids != null && length(var.private_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.private_subnet_ids
      security_group_ids = compact([aws_security_group.compliance_lambda_sg.id, var.rds_security_group])
    }
  }

  environment { variables = local.lambda_environment }
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-document-upload", Function = "document-upload" })
}

resource "aws_lambda_function" "document_review" {
  function_name    = "${local.name_prefix}-document-review"
  role             = aws_iam_role.compliance_lambda_role.arn
  handler          = "index.handler"
  runtime          = var.lambda_runtime
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout
  filename         = "${path.module}/lambda/functions/placeholder.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/functions/placeholder.zip")

  dynamic "vpc_config" {
    for_each = var.private_subnet_ids != null && length(var.private_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.private_subnet_ids
      security_group_ids = compact([aws_security_group.compliance_lambda_sg.id, var.rds_security_group])
    }
  }

  environment { variables = local.lambda_environment }
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-document-review", Function = "document-review" })
}

resource "aws_lambda_function" "document_expiry" {
  function_name    = "${local.name_prefix}-document-expiry"
  role             = aws_iam_role.compliance_lambda_role.arn
  handler          = "index.handler"
  runtime          = var.lambda_runtime
  memory_size      = var.lambda_memory_size
  timeout          = 60
  filename         = "${path.module}/lambda/functions/placeholder.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/functions/placeholder.zip")

  dynamic "vpc_config" {
    for_each = var.private_subnet_ids != null && length(var.private_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.private_subnet_ids
      security_group_ids = compact([aws_security_group.compliance_lambda_sg.id, var.rds_security_group])
    }
  }

  environment { variables = local.lambda_environment }
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-document-expiry", Function = "document-expiry" })
}

# ------------------------------------------------------------------------------
# CloudWatch Log Groups
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "document_upload" {
  name              = "/aws/lambda/${aws_lambda_function.document_upload.function_name}"
  retention_in_days = var.environment == "prod" ? 90 : 30
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "document_review" {
  name              = "/aws/lambda/${aws_lambda_function.document_review.function_name}"
  retention_in_days = var.environment == "prod" ? 90 : 30
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "document_expiry" {
  name              = "/aws/lambda/${aws_lambda_function.document_expiry.function_name}"
  retention_in_days = var.environment == "prod" ? 90 : 30
  tags              = local.common_tags
}
