# SNS topic for operational notifications (if production)
resource "aws_sns_topic" "notifications" {
  count = var.environment == "prod" ? 1 : 0
  name  = "${local.name_prefix}-ops-notifications"

  # Server-side encryption
  kms_master_key_id = var.enable_encryption ? aws_kms_key.notification_service[0].arn : null

  tags = merge(local.common_tags, {
    Name = "Operational Notifications"
    Type = "ops"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "notifications" {
  count = var.environment == "prod" ? 1 : 0
  arn   = aws_sns_topic.notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = "sns:Publish"
        Resource = aws_sns_topic.notifications[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# SNS subscription for email notifications (optional)
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = var.environment == "prod" && var.ses_from_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.ses_from_email
}