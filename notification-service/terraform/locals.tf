locals {
  # Naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Terraform   = "true"
    Timestamp   = timestamp()
  })

  # DynamoDB table names
  table_names = {
    subscribers = "${local.name_prefix}-subscribers"
    templates   = "${local.name_prefix}-templates"
    outbox      = "${local.name_prefix}-outbox"
  }

  # Lambda function names
  lambda_names = {
    api_handler     = "${local.name_prefix}-api"
    stream_processor = "${local.name_prefix}-stream-processor"
    dlq_processor   = "${local.name_prefix}-dlq-processor"
  }

  # SQS queue names
  queue_names = {
    dlq = "${local.name_prefix}-dlq"
  }

  # CloudWatch log group names
  log_group_names = {
    api_handler     = "/aws/lambda/${local.lambda_names.api_handler}"
    stream_processor = "/aws/lambda/${local.lambda_names.stream_processor}"
    dlq_processor   = "/aws/lambda/${local.lambda_names.dlq_processor}"
  }

  # IAM role names
  iam_role_names = {
    lambda_execution = "${local.name_prefix}-lambda-execution-role"
  }

  # API Gateway configuration
  api_gateway_name = "${local.name_prefix}-api"
  
  # Environment variables for Lambda functions
  lambda_environment_variables = {
    ENVIRONMENT         = var.environment
    PROJECT_NAME        = var.project_name
    AWS_REGION         = var.aws_region
    SES_FROM_EMAIL     = var.ses_from_email
    SUBSCRIBERS_TABLE  = local.table_names.subscribers
    TEMPLATES_TABLE    = local.table_names.templates
    OUTBOX_TABLE       = local.table_names.outbox
    DLQ_URL           = aws_sqs_queue.notification_dlq.url
    LOG_LEVEL         = var.environment == "prod" ? "info" : "debug"
    POWERTOOLS_SERVICE_NAME = var.project_name
    POWERTOOLS_LOG_LEVEL = var.environment == "prod" ? "INFO" : "DEBUG"
  }

  # Lambda layers
  lambda_layers = var.environment == "prod" ? [
    "arn:aws:lambda:${var.aws_region}:017000801446:layer:AWSLambdaPowertoolsTypeScript:25"
  ] : []

  # VPC configuration
  vpc_config = var.enable_vpc ? {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda[0].id]
  } : null
}