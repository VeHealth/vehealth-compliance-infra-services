output "lambda_arns" {
  value = {
    document_upload = aws_lambda_function.document_upload.arn
    document_review = aws_lambda_function.document_review.arn
    document_expiry = aws_lambda_function.document_expiry.arn
  }
}

output "lambda_function_names" {
  value = {
    document_upload = aws_lambda_function.document_upload.function_name
    document_review = aws_lambda_function.document_review.function_name
    document_expiry = aws_lambda_function.document_expiry.function_name
  }
}

output "lambda_role_arn" { value = aws_iam_role.compliance_lambda_role.arn }
output "security_group_id" { value = aws_security_group.compliance_lambda_sg.id }
