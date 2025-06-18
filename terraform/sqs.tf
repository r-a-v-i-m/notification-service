# SQS Dead Letter Queue for failed notifications
resource "aws_sqs_queue" "notification_dlq" {
  name = local.queue_names.dlq

  # Message retention period (14 days)
  message_retention_seconds = 1209600

  # Visibility timeout should be 6x the Lambda timeout
  visibility_timeout_seconds = var.lambda_timeout * 6

  # Dead letter queue configuration
  max_receive_count = 3

  # Server-side encryption
  kms_master_key_id = var.enable_encryption ? aws_kms_key.notification_service[0].arn : null

  # Redrive policy for messages that fail processing
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notification_dlq_dead.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, {
    Name = "Notification DLQ"
    Type = "dlq"
  })
}

# Dead letter queue for the DLQ (final destination for unprocessable messages)
resource "aws_sqs_queue" "notification_dlq_dead" {
  name = "${local.queue_names.dlq}-dead"

  # Longer retention for manual investigation
  message_retention_seconds = 1209600 # 14 days

  # Server-side encryption
  kms_master_key_id = var.enable_encryption ? aws_kms_key.notification_service[0].arn : null

  tags = merge(local.common_tags, {
    Name = "Notification DLQ Dead Letter"
    Type = "dlq-dead"
  })
}

# SQS queue policy to allow Lambda to access the queue
resource "aws_sqs_queue_policy" "notification_dlq_policy" {
  queue_url = aws_sqs_queue.notification_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.notification_dlq.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# CloudWatch alarms for DLQ monitoring
resource "aws_cloudwatch_metric_alarm" "dlq_messages_visible" {
  alarm_name          = "${local.name_prefix}-dlq-messages-visible"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "This metric monitors the number of visible messages in the DLQ"
  alarm_actions       = var.environment == "prod" ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    QueueName = aws_sqs_queue.notification_dlq.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages_age" {
  alarm_name          = "${local.name_prefix}-dlq-message-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "3600" # 1 hour
  alarm_description   = "This metric monitors the age of the oldest message in the DLQ"
  alarm_actions       = var.environment == "prod" ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    QueueName = aws_sqs_queue.notification_dlq.name
  }

  tags = local.common_tags
}