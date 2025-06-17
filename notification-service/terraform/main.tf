terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "notification-service"
}

variable "ses_from_email" {
  description = "SES verified email for sending notifications"
  type        = string
}

# DynamoDB Tables
resource "aws_dynamodb_table" "subscribers" {
  name           = "${var.environment}-${var.project_name}-subscribers"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  attribute {
    name = "phone"
    type = "S"
  }

  global_secondary_index {
    name     = "email-index"
    hash_key = "email"
  }

  global_secondary_index {
    name     = "phone-index"
    hash_key = "phone"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_dynamodb_table" "notification_templates" {
  name           = "${var.environment}-${var.project_name}-templates"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "name"
    type = "S"
  }

  global_secondary_index {
    name     = "name-index"
    hash_key = "name"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_dynamodb_table" "outbox" {
  name           = "${var.environment}-${var.project_name}-outbox"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {  
    name = "id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name     = "status-index"
    hash_key = "status"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# SQS Dead Letter Queue
resource "aws_sqs_queue" "notification_dlq" {
  name                      = "${var.environment}-${var.project_name}-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.environment}-${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.environment}-${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams"
        ]
        Resource = [
          aws_dynamodb_table.subscribers.arn,
          aws_dynamodb_table.notification_templates.arn,
          aws_dynamodb_table.outbox.arn,
          "${aws_dynamodb_table.subscribers.arn}/*",
          "${aws_dynamodb_table.notification_templates.arn}/*",
          "${aws_dynamodb_table.outbox.arn}/*",
          "${aws_dynamodb_table.outbox.stream_arn}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.notification_dlq.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function for API
resource "aws_lambda_function" "api_handler" {
  filename         = "../notification-service.zip"
  function_name    = "${var.environment}-${var.project_name}-api"
  role            = aws_iam_role.lambda_role.arn
  handler         = "src/handlers/api-handler.handler"
  runtime         = "nodejs18.x"
  timeout         = 30
  memory_size     = 512

  environment {
    variables = {
      SUBSCRIBERS_TABLE = aws_dynamodb_table.subscribers.name
      TEMPLATES_TABLE   = aws_dynamodb_table.notification_templates.name
      OUTBOX_TABLE      = aws_dynamodb_table.outbox.name
      SES_FROM_EMAIL    = var.ses_from_email
      AWS_REGION        = var.aws_region
      ENVIRONMENT       = var.environment
      DLQ_URL           = aws_sqs_queue.notification_dlq.url
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# Lambda function for outbox processor
resource "aws_lambda_function" "outbox_processor" {
  filename         = "../notification-service.zip"
  function_name    = "${var.environment}-${var.project_name}-outbox-processor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "src/handlers/stream-processor.handler"
  runtime         = "nodejs18.x"
  timeout         = 60
  memory_size     = 512

  environment {
    variables = {
      SES_FROM_EMAIL = var.ses_from_email
      AWS_REGION     = var.aws_region
      ENVIRONMENT    = var.environment
      DLQ_URL        = aws_sqs_queue.notification_dlq.url
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# Lambda function for DLQ processor
resource "aws_lambda_function" "dlq_processor" {
  filename         = "../notification-service.zip"
  function_name    = "${var.environment}-${var.project_name}-dlq-processor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "src/handlers/dlq-processor.handler"
  runtime         = "nodejs18.x"
  timeout         = 60
  memory_size     = 512

  environment {
    variables = {
      SES_FROM_EMAIL = var.ses_from_email
      AWS_REGION     = var.aws_region
      ENVIRONMENT    = var.environment
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.environment}-${var.project_name}"
  retention_in_days = 14
}

# DynamoDB Stream Event Source Mapping
resource "aws_lambda_event_source_mapping" "outbox_stream" {
  event_source_arn  = aws_dynamodb_table.outbox.stream_arn
  function_name     = aws_lambda_function.outbox_processor.arn
  starting_position = "LATEST"
  batch_size        = 10
  maximum_batching_window_in_seconds = 5

  depends_on = [aws_iam_role_policy.lambda_policy]
}

# SQS Event Source Mapping for DLQ
resource "aws_lambda_event_source_mapping" "dlq_mapping" {
  event_source_arn = aws_sqs_queue.notification_dlq.arn
  function_name    = aws_lambda_function.dlq_processor.arn
  batch_size       = 10
}

# API Gateway
resource "aws_api_gateway_rest_api" "notification_api" {
  name        = "${var.environment}-${var.project_name}-api"
  description = "Notification Service API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.notification_api.id
  parent_id   = aws_api_gateway_rest_api.notification_api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.notification_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.notification_api.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.notification_api.id
  resource_id   = aws_api_gateway_rest_api.notification_api.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.notification_api.id
  resource_id = aws_api_gateway_method.proxy_root.resource_id
  http_method = aws_api_gateway_method.proxy_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_api_gateway_deployment" "notification_api" {
  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration.lambda_root,
  ]

  rest_api_id = aws_api_gateway_rest_api.notification_api.id
  stage_name  = var.environment
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.notification_api.execution_arn}/*/*"
}

# Outputs
output "api_gateway_url" {
  description = "API Gateway URL"
  value       = aws_api_gateway_deployment.notification_api.invoke_url
}

output "subscribers_table_name" {
  description = "DynamoDB Subscribers Table Name"
  value       = aws_dynamodb_table.subscribers.name
}

output "templates_table_name" {
  description = "DynamoDB Templates Table Name"
  value       = aws_dynamodb_table.notification_templates.name
}

output "outbox_table_name" {
  description = "DynamoDB Outbox Table Name"
  value       = aws_dynamodb_table.outbox.name
}