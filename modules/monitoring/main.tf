# ==============================================================================
# CloudWatch Monitoring Module - Driver Documents
# ==============================================================================
# Creates CloudWatch alarms and dashboards for document Lambda functions
#
# Alarms:
# - Lambda errors (4xx, 5xx)
# - Lambda duration/timeout warnings
# - Lambda throttles
# - API Gateway error rates
# - API Gateway latency
#
# Dashboard:
# - Lambda metrics (invocations, errors, duration)
# - API Gateway metrics (requests, latency, errors)
# - S3 metrics (uploads, storage)
# ==============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ==============================================================================
# LOCAL VARIABLES
# ==============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Lambda function names
  lambda_functions = {
    document_upload = "${local.name_prefix}-document-upload"
    document_review = "${local.name_prefix}-document-review"
    document_expiry = "${local.name_prefix}-document-expiry"
  }

  # SNS topic for alarms
  alarm_topic_name = "${local.name_prefix}-document-alarms"

  # Common alarm tags
  alarm_tags = merge(
    var.tags,
    {
      Module      = "monitoring"
      Service     = "driver-documents"
      Environment = var.environment
    }
  )
}

# ==============================================================================
# SNS TOPIC FOR ALARMS
# ==============================================================================

resource "aws_sns_topic" "document_alarms" {
  name         = local.alarm_topic_name
  display_name = "Driver Document System Alarms"

  tags = local.alarm_tags
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count = var.alarm_email != null ? 1 : 0

  topic_arn = aws_sns_topic.document_alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ==============================================================================
# LAMBDA ERROR ALARMS
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.lambda_functions

  alarm_name          = "${each.value}-errors"
  alarm_description   = "Alert when ${each.key} Lambda function errors exceed threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = var.lambda_error_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = [aws_sns_topic.document_alarms.arn]
  ok_actions    = [aws_sns_topic.document_alarms.arn]

  tags = merge(
    local.alarm_tags,
    {
      Name         = "${each.value}-errors"
      AlarmType    = "lambda-errors"
      FunctionName = each.value
    }
  )
}

# ==============================================================================
# LAMBDA DURATION ALARMS
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = local.lambda_functions

  alarm_name          = "${each.value}-duration"
  alarm_description   = "Alert when ${each.key} Lambda function duration approaches timeout"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300 # 5 minutes
  statistic           = "Average"
  threshold           = var.lambda_duration_threshold # milliseconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = [aws_sns_topic.document_alarms.arn]
  ok_actions    = [aws_sns_topic.document_alarms.arn]

  tags = merge(
    local.alarm_tags,
    {
      Name         = "${each.value}-duration"
      AlarmType    = "lambda-duration"
      FunctionName = each.value
    }
  )
}

# ==============================================================================
# LAMBDA THROTTLE ALARMS
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = local.lambda_functions

  alarm_name          = "${each.value}-throttles"
  alarm_description   = "Alert when ${each.key} Lambda function is throttled"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60 # 1 minute
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = [aws_sns_topic.document_alarms.arn]
  ok_actions    = [aws_sns_topic.document_alarms.arn]

  tags = merge(
    local.alarm_tags,
    {
      Name         = "${each.value}-throttles"
      AlarmType    = "lambda-throttles"
      FunctionName = each.value
    }
  )
}

# ==============================================================================
# API GATEWAY ERROR RATE ALARMS
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "api_4xx_errors" {
  alarm_name          = "${local.name_prefix}-api-4xx-errors"
  alarm_description   = "Alert when API Gateway 4xx error rate is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = var.api_4xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = var.api_gateway_id
  }

  alarm_actions = [aws_sns_topic.document_alarms.arn]
  ok_actions    = [aws_sns_topic.document_alarms.arn]

  tags = merge(
    local.alarm_tags,
    {
      Name      = "${local.name_prefix}-api-4xx-errors"
      AlarmType = "api-4xx-errors"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "api_5xx_errors" {
  alarm_name          = "${local.name_prefix}-api-5xx-errors"
  alarm_description   = "Alert when API Gateway 5xx error rate is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = var.api_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = var.api_gateway_id
  }

  alarm_actions = [aws_sns_topic.document_alarms.arn]
  ok_actions    = [aws_sns_topic.document_alarms.arn]

  tags = merge(
    local.alarm_tags,
    {
      Name      = "${local.name_prefix}-api-5xx-errors"
      AlarmType = "api-5xx-errors"
    }
  )
}

# ==============================================================================
# API GATEWAY LATENCY ALARM
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "${local.name_prefix}-api-latency"
  alarm_description   = "Alert when API Gateway latency is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "IntegrationLatency"
  namespace           = "AWS/ApiGateway"
  period              = 300 # 5 minutes
  statistic           = "Average"
  threshold           = var.api_latency_threshold # milliseconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = var.api_gateway_id
  }

  alarm_actions = [aws_sns_topic.document_alarms.arn]
  ok_actions    = [aws_sns_topic.document_alarms.arn]

  tags = merge(
    local.alarm_tags,
    {
      Name      = "${local.name_prefix}-api-latency"
      AlarmType = "api-latency"
    }
  )
}

# ==============================================================================
# CLOUDWATCH DASHBOARD
# ==============================================================================

resource "aws_cloudwatch_dashboard" "driver_documents" {
  dashboard_name = "${local.name_prefix}-driver-documents"

  dashboard_body = jsonencode({
    widgets = [
      # Lambda Invocations
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations"],
          ]
          period     = 300
          stat       = "Sum"
          region     = var.aws_region
          title      = "Lambda Invocations"
          dimensions = {
            FunctionName = local.lambda_functions.document_upload
          }
          yAxis = {
            left = {
              min = 0
            }
          }
        }
        width  = 12
        height = 6
        x      = 0
        y      = 0
      },

      # Lambda Errors
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Errors"],
          ]
          period     = 300
          stat       = "Sum"
          region     = var.aws_region
          title      = "Lambda Errors"
          dimensions = {
            FunctionName = local.lambda_functions.document_upload
          }
          yAxis = {
            left = {
              min = 0
            }
          }
        }
        width  = 12
        height = 6
        x      = 12
        y      = 0
      },

      # Lambda Duration
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration"],
          ]
          period     = 300
          stat       = "Average"
          region     = var.aws_region
          title      = "Lambda Duration (ms)"
          dimensions = {
            FunctionName = local.lambda_functions.document_upload
          }
          yAxis = {
            left = {
              min = 0
            }
          }
        }
        width  = 12
        height = 6
        x      = 0
        y      = 6
      },

      # Lambda Throttles
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Throttles"],
          ]
          period     = 300
          stat       = "Sum"
          region     = var.aws_region
          title      = "Lambda Throttles"
          dimensions = {
            FunctionName = local.lambda_functions.document_upload
          }
          yAxis = {
            left = {
              min = 0
            }
          }
        }
        width  = 12
        height = 6
        x      = 12
        y      = 6
      },

      # API Gateway Requests
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count"]
          ]
          period     = 300
          stat       = "Sum"
          region     = var.aws_region
          title      = "API Gateway Requests"
          dimensions = {
            ApiId = var.api_gateway_id
          }
          yAxis = {
            left = {
              min = 0
            }
          }
        }
        width  = 12
        height = 6
        x      = 0
        y      = 12
      },

      # API Gateway Errors
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApiGateway", "4XXError"],
            ["AWS/ApiGateway", "5XXError"]
          ]
          period     = 300
          stat       = "Sum"
          region     = var.aws_region
          title      = "API Gateway Errors"
          dimensions = {
            ApiId = var.api_gateway_id
          }
          yAxis = {
            left = {
              min = 0
            }
          }
        }
        width  = 12
        height = 6
        x      = 12
        y      = 12
      },

      # API Gateway Latency
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApiGateway", "IntegrationLatency"],
            ["AWS/ApiGateway", "Latency"]
          ]
          period     = 300
          stat       = "Average"
          region     = var.aws_region
          title      = "API Gateway Latency (ms)"
          dimensions = {
            ApiId = var.api_gateway_id
          }
          yAxis = {
            left = {
              min = 0
            }
          }
        }
        width  = 24
        height = 6
        x      = 0
        y      = 18
      }
    ]
  })
}
