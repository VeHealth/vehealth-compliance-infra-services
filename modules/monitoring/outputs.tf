# ==============================================================================
# CloudWatch Monitoring Module - Outputs
# ==============================================================================

output "sns_topic_arn" {
  description = "ARN of SNS topic for alarms"
  value       = aws_sns_topic.document_alarms.arn
}

output "dashboard_name" {
  description = "Name of CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.driver_documents.dashboard_name
}

output "dashboard_url" {
  description = "URL to CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.driver_documents.dashboard_name}"
}

output "lambda_error_alarms" {
  description = "Map of Lambda error alarm names"
  value = {
    for k, v in aws_cloudwatch_metric_alarm.lambda_errors : k => v.alarm_name
  }
}

output "lambda_duration_alarms" {
  description = "Map of Lambda duration alarm names"
  value = {
    for k, v in aws_cloudwatch_metric_alarm.lambda_duration : k => v.alarm_name
  }
}

output "lambda_throttle_alarms" {
  description = "Map of Lambda throttle alarm names"
  value = {
    for k, v in aws_cloudwatch_metric_alarm.lambda_throttles : k => v.alarm_name
  }
}

output "api_error_alarms" {
  description = "API Gateway error alarm names"
  value = {
    "4xx" = aws_cloudwatch_metric_alarm.api_4xx_errors.alarm_name
    "5xx" = aws_cloudwatch_metric_alarm.api_5xx_errors.alarm_name
  }
}

output "api_latency_alarm" {
  description = "API Gateway latency alarm name"
  value       = aws_cloudwatch_metric_alarm.api_latency.alarm_name
}
