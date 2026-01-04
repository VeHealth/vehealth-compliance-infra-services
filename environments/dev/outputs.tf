# ==============================================================================
# Environment Outputs
# ==============================================================================

output "compliance_lambda_arns" {
  description = "ARNs of compliance Lambda functions"
  value       = module.compliance_services.lambda_arns
}

output "documents_bucket_name" {
  description = "S3 bucket for driver documents"
  value       = module.storage.documents_bucket_name
}

output "documents_bucket_arn" {
  description = "S3 bucket ARN for driver documents"
  value       = module.storage.documents_bucket_arn
}

# ==============================================================================
# Monitoring Outputs
# ==============================================================================

output "monitoring_dashboard_name" {
  description = "CloudWatch dashboard name for driver documents"
  value       = module.monitoring.dashboard_name
}

output "monitoring_dashboard_url" {
  description = "URL to CloudWatch dashboard"
  value       = module.monitoring.dashboard_url
}

output "monitoring_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  value       = module.monitoring.sns_topic_arn
}

output "monitoring_lambda_error_alarms" {
  description = "Lambda error alarm names"
  value       = module.monitoring.lambda_error_alarms
}

output "monitoring_api_error_alarms" {
  description = "API Gateway error alarm names"
  value       = module.monitoring.api_error_alarms
}
