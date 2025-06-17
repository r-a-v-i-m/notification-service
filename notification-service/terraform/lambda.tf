# Lambda function for API handling
resource "aws_lambda_function" "api_handler" {
  filename         = data.archive_file.lambda_package.output_path
  function_name    = local.lambda_names.api_handler
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "src/handlers/api-handler.handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  # Reserved concurrency to prevent overwhelming downstream services
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  # Environment variables
  environment {
    variables = local.lambda_environment_variables
  }

  # VPC configuration (if enabled)
  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = aws_subnet.private[*].id
      security_group_ids = [aws_security_group.lambda[0].id]
    }
  }

  # X-Ray tracing (if enabled)
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  # Lambda layers (if any)
  layers = local.lambda_layers

  # Dead letter queue configuration
  dead_letter_config {
    target_arn = aws_sqs_queue.notification_dlq.arn
  }

  depends_on = [
    aws_iam_role_policy.lambda_notification_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name = "API Handler Lambda"
    Type = "api"
  })
}

# Lambda function for DynamoDB stream processing
resource "aws_lambda_function" "stream_processor" {
  filename         = data.archive_file.lambda_package.output_path
  function_name    = local.lambda_names.stream_processor
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "src/handlers/stream-processor.handler"
  runtime         = var.lambda_runtime
  timeout         = 60  # Longer timeout for stream processing
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  # Lower concurrency for stream processing to prevent throttling
  reserved_concurrent_executions = 50

  environment {
    variables = local.lambda_environment_variables
  }

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = aws_subnet.private[*].id
      security_group_ids = [aws_security_group.lambda[0].id]
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  layers = local.lambda_layers

  dead_letter_config {
    target_arn = aws_sqs_queue.notification_dlq.arn
  }

  depends_on = [
    aws_iam_role_policy.lambda_notification_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name = "Stream Processor Lambda"
    Type = "stream"
  })
}

# Lambda function for DLQ processing
resource "aws_lambda_function" "dlq_processor" {
  filename         = data.archive_file.lambda_package.output_path
  function_name    = local.lambda_names.dlq_processor
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "src/handlers/dlq-processor.handler"
  runtime         = var.lambda_runtime
  timeout         = 60  # Longer timeout for retry logic
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  # Lower concurrency for DLQ processing
  reserved_concurrent_executions = 25

  environment {
    variables = local.lambda_environment_variables
  }

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = aws_subnet.private[*].id
      security_group_ids = [aws_security_group.lambda[0].id]
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  layers = local.lambda_layers

  depends_on = [
    aws_iam_role_policy.lambda_notification_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name = "DLQ Processor Lambda"
    Type = "dlq"
  })
}

# Event source mapping for DynamoDB stream
resource "aws_lambda_event_source_mapping" "outbox_stream" {
  event_source_arn  = aws_dynamodb_table.outbox.stream_arn
  function_name     = aws_lambda_function.stream_processor.arn
  starting_position = "LATEST"
  batch_size        = 10
  maximum_batching_window_in_seconds = 5

  # Error handling
  maximum_retry_attempts = 3
  maximum_record_age_in_seconds = 3600

  # Parallelization factor
  parallelization_factor = 1

  # Filter criteria for only INSERT events
  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT"]
      })
    }
  }

  depends_on = [aws_iam_role_policy.lambda_notification_policy]
}

# Event source mapping for SQS DLQ
resource "aws_lambda_event_source_mapping" "dlq_mapping" {
  event_source_arn = aws_sqs_queue.notification_dlq.arn
  function_name    = aws_lambda_function.dlq_processor.arn
  batch_size       = 10
  maximum_batching_window_in_seconds = 5

  depends_on = [aws_iam_role_policy.lambda_notification_policy]
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.notification_api.execution_arn}/*/*"
}

# CloudWatch log groups for Lambda functions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = {
    api_handler      = local.lambda_names.api_handler
    stream_processor = local.lambda_names.stream_processor
    dlq_processor    = local.lambda_names.dlq_processor
  }

  name              = "/aws/lambda/${each.value}"
  retention_in_days = var.log_retention_days

  # Encryption
  kms_key_id = var.enable_encryption ? aws_kms_key.notification_service[0].arn : null

  tags = merge(local.common_tags, {
    Name = "${each.key} Log Group"
    Type = "logs"
  })
}

# CloudWatch alarms for Lambda functions
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = {
    api_handler      = aws_lambda_function.api_handler.function_name
    stream_processor = aws_lambda_function.stream_processor.function_name
    dlq_processor    = aws_lambda_function.dlq_processor.function_name
  }

  alarm_name          = "${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors for ${each.key}"
  alarm_actions       = var.environment == "prod" ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    FunctionName = each.value
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = {
    api_handler      = aws_lambda_function.api_handler.function_name
    stream_processor = aws_lambda_function.stream_processor.function_name
    dlq_processor    = aws_lambda_function.dlq_processor.function_name
  }

  alarm_name          = "${each.key}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8 # 80% of timeout
  alarm_description   = "This metric monitors lambda duration for ${each.key}"
  alarm_actions       = var.environment == "prod" ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    FunctionName = each.value
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = {
    api_handler      = aws_lambda_function.api_handler.function_name
    stream_processor = aws_lambda_function.stream_processor.function_name
    dlq_processor    = aws_lambda_function.dlq_processor.function_name
  }

  alarm_name          = "${each.key}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda throttles for ${each.key}"
  alarm_actions       = var.environment == "prod" ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    FunctionName = each.value
  }

  tags = local.common_tags
}