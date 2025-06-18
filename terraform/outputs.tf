# API Gateway outputs
output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = aws_api_gateway_stage.notification_api.invoke_url
}

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.notification_api.id
}

output "api_gateway_execution_arn" {
  description = "API Gateway execution ARN"
  value       = aws_api_gateway_rest_api.notification_api.execution_arn
}

# DynamoDB outputs
output "subscribers_table_name" {
  description = "DynamoDB Subscribers table name"
  value       = aws_dynamodb_table.subscribers.name
}

output "subscribers_table_arn" {
  description = "DynamoDB Subscribers table ARN"
  value       = aws_dynamodb_table.subscribers.arn
}

output "templates_table_name" {
  description = "DynamoDB Templates table name"
  value       = aws_dynamodb_table.templates.name
}

output "templates_table_arn" {
  description = "DynamoDB Templates table ARN"
  value       = aws_dynamodb_table.templates.arn
}

output "outbox_table_name" {
  description = "DynamoDB Outbox table name"
  value       = aws_dynamodb_table.outbox.name
}

output "outbox_table_arn" {
  description = "DynamoDB Outbox table ARN"
  value       = aws_dynamodb_table.outbox.arn
}

output "outbox_stream_arn" {
  description = "DynamoDB Outbox table stream ARN"
  value       = aws_dynamodb_table.outbox.stream_arn
}

# Lambda outputs
output "lambda_functions" {
  description = "Lambda function details"
  value = {
    api_handler = {
      name = aws_lambda_function.api_handler.function_name
      arn  = aws_lambda_function.api_handler.arn
    }
    stream_processor = {
      name = aws_lambda_function.stream_processor.function_name
      arn  = aws_lambda_function.stream_processor.arn
    }
    dlq_processor = {
      name = aws_lambda_function.dlq_processor.function_name
      arn  = aws_lambda_function.dlq_processor.arn
    }
  }
}

# SQS outputs
output "dlq_url" {
  description = "SQS Dead Letter Queue URL"
  value       = aws_sqs_queue.notification_dlq.url
}

output "dlq_arn" {
  description = "SQS Dead Letter Queue ARN"
  value       = aws_sqs_queue.notification_dlq.arn
}

# IAM outputs
output "lambda_execution_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda_execution_role.arn
}

# CloudWatch outputs
output "log_groups" {
  description = "CloudWatch log groups"
  value = {
    for name, log_group in aws_cloudwatch_log_group.lambda_logs : name => {
      name = log_group.name
      arn  = log_group.arn
    }
  }
}

# VPC outputs (if enabled)
output "vpc_info" {
  description = "VPC information"
  value = var.enable_vpc ? {
    vpc_id              = aws_vpc.main[0].id
    vpc_cidr            = aws_vpc.main[0].cidr_block
    public_subnet_ids   = aws_subnet.public[*].id
    private_subnet_ids  = aws_subnet.private[*].id
    nat_gateway_ids     = aws_nat_gateway.main[*].id
    internet_gateway_id = aws_internet_gateway.main[0].id
  } : null
}

# Security outputs
output "kms_key_info" {
  description = "KMS key information"
  value = var.enable_encryption ? {
    key_id    = aws_kms_key.notification_service[0].key_id
    key_arn   = aws_kms_key.notification_service[0].arn
    alias_arn = aws_kms_alias.notification_service[0].arn
  } : null
}

# Monitoring outputs
output "sns_topic_arn" {
  description = "SNS topic ARN for operational notifications"
  value       = var.environment == "prod" ? aws_sns_topic.notifications[0].arn : null
}

# Configuration outputs
output "environment_variables" {
  description = "Environment variables used by Lambda functions"
  value       = local.lambda_environment_variables
  sensitive   = true
}

# Resource naming outputs
output "resource_names" {
  description = "Names of created resources"
  value = {
    project_name   = var.project_name
    environment    = var.environment
    name_prefix    = local.name_prefix
    table_names    = local.table_names
    lambda_names   = local.lambda_names
    queue_names    = local.queue_names
  }
}

# Cost estimation helper
output "billable_resources" {
  description = "Summary of billable resources for cost estimation"
  value = {
    lambda_functions = {
      count          = 3
      memory_size    = var.lambda_memory_size
      timeout        = var.lambda_timeout
      concurrency    = var.lambda_reserved_concurrency
    }
    dynamodb_tables = {
      count        = 3
      billing_mode = var.dynamodb_billing_mode
      has_streams  = 2 # subscribers and outbox tables
    }
    api_gateway = {
      type = "REST"
      throttling = {
        burst_limit = var.api_gateway_throttle_burst_limit
        rate_limit  = var.api_gateway_throttle_rate_limit
      }
    }
    vpc_enabled = var.enable_vpc
    encryption_enabled = var.enable_encryption
    monitoring_enabled = var.enable_detailed_monitoring
  }
}

# Deployment information
output "deployment_info" {
  description = "Deployment information and next steps"
  value = {
    api_base_url = aws_api_gateway_stage.notification_api.invoke_url
    health_check_url = "${aws_api_gateway_stage.notification_api.invoke_url}/health"
    ses_from_email = var.ses_from_email
    environment = var.environment
    deployment_timestamp = timestamp()
    next_steps = [
      "1. Verify SES email address: ${var.ses_from_email}",
      "2. Test health endpoint: ${aws_api_gateway_stage.notification_api.invoke_url}/health",
      "3. Create your first template using POST /templates",
      "4. Add subscribers using POST /subscribers", 
      "5. Send test notification using POST /notifications",
      "6. Monitor CloudWatch logs and metrics",
      "7. Set up CloudWatch alarms for production monitoring"
    ]
  }
}