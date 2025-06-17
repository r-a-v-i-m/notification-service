# API Gateway REST API
resource "aws_api_gateway_rest_api" "notification_api" {
  name        = local.api_gateway_name
  description = "Notification Service API for ${var.environment}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  # API Gateway policy for resource access
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "execute-api:Invoke"
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# API Gateway resource for proxy integration
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.notification_api.id
  parent_id   = aws_api_gateway_rest_api.notification_api.root_resource_id
  path_part   = "{proxy+}"
}

# API Gateway method for proxy resource
resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.notification_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"

  # Request validation
  request_validator_id = aws_api_gateway_request_validator.validator.id
}

# API Gateway method for root resource
resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.notification_api.id
  resource_id   = aws_api_gateway_rest_api.notification_api.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"

  request_validator_id = aws_api_gateway_request_validator.validator.id
}

# API Gateway integration for proxy resource
resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.notification_api.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn

  # Timeout configuration
  timeout_milliseconds = var.lambda_timeout * 1000 - 1000 # API Gateway timeout should be less than Lambda
}

# API Gateway integration for root resource
resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.notification_api.id
  resource_id = aws_api_gateway_method.proxy_root.resource_id
  http_method = aws_api_gateway_method.proxy_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn

  timeout_milliseconds = var.lambda_timeout * 1000 - 1000
}

# CORS support for all resources
resource "aws_api_gateway_method" "options" {
  rest_api_id   = aws_api_gateway_rest_api.notification_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  rest_api_id = aws_api_gateway_rest_api.notification_api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.options.http_method

  type = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.notification_api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.notification_api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = aws_api_gateway_method_response.options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT,DELETE'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Request validator
resource "aws_api_gateway_request_validator" "validator" {
  name                        = "${local.name_prefix}-validator"
  rest_api_id                 = aws_api_gateway_rest_api.notification_api.id
  validate_request_body       = true
  validate_request_parameters = true
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "notification_api" {
  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration.lambda_root,
    aws_api_gateway_integration.options
  ]

  rest_api_id = aws_api_gateway_rest_api.notification_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.lambda.id,
      aws_api_gateway_method.proxy_root.id,
      aws_api_gateway_integration.lambda_root.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "notification_api" {
  deployment_id = aws_api_gateway_deployment.notification_api.id
  rest_api_id   = aws_api_gateway_rest_api.notification_api.id
  stage_name    = var.environment

  # Throttling settings
  throttle_settings {
    burst_limit = var.api_gateway_throttle_burst_limit
    rate_limit  = var.api_gateway_throttle_rate_limit
  }

  # Access logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      responseTime   = "$context.responseTime"
      error          = "$context.error.message"
      integrationError = "$context.integration.error"
    })
  }

  # X-Ray tracing
  xray_tracing_enabled = var.enable_xray_tracing

  tags = local.common_tags
}

# CloudWatch log group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${local.api_gateway_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_encryption ? aws_kms_key.notification_service[0].arn : null

  tags = merge(local.common_tags, {
    Name = "API Gateway Logs"
    Type = "api-gateway"
  })
}

# Method settings for detailed monitoring
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.notification_api.id
  stage_name  = aws_api_gateway_stage.notification_api.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = var.enable_detailed_monitoring
    logging_level      = var.environment == "prod" ? "ERROR" : "INFO"
    data_trace_enabled = var.environment != "prod"

    throttling_burst_limit = var.api_gateway_throttle_burst_limit
    throttling_rate_limit  = var.api_gateway_throttle_rate_limit
  }
}

# CloudWatch alarms for API Gateway
resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_errors" {
  alarm_name          = "${local.name_prefix}-api-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors API Gateway 4XX errors"
  alarm_actions       = var.environment == "prod" ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.notification_api.name
    Stage   = aws_api_gateway_stage.notification_api.stage_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_errors" {
  alarm_name          = "${local.name_prefix}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  alarm_actions       = var.environment == "prod" ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.notification_api.name
    Stage   = aws_api_gateway_stage.notification_api.stage_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_latency" {
  alarm_name          = "${local.name_prefix}-api-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Average"
  threshold           = "5000" # 5 seconds
  alarm_description   = "This metric monitors API Gateway latency"
  alarm_actions       = var.environment == "prod" ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.notification_api.name
    Stage   = aws_api_gateway_stage.notification_api.stage_name
  }

  tags = local.common_tags
}