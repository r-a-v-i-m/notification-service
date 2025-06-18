# DynamoDB table for subscribers
resource "aws_dynamodb_table" "subscribers" {
  name           = local.table_names.subscribers
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"

  # Provisioned throughput (only used if billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

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

  # Global secondary index for email lookups
  global_secondary_index {
    name     = "email-index"
    hash_key = "email"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
    
    projection_type = "ALL"
  }

  # Global secondary index for phone lookups
  global_secondary_index {
    name     = "phone-index"
    hash_key = "phone"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
    
    projection_type = "ALL"
  }

  # Enable streams for change tracking
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Enable encryption
  server_side_encryption {
    enabled = var.enable_encryption
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.environment == "prod"
  }

  tags = merge(local.common_tags, {
    Name = "Subscribers Table"
    Type = "subscribers"
  })
}

# DynamoDB table for notification templates
resource "aws_dynamodb_table" "templates" {
  name           = local.table_names.templates
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"

  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "name"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  # Global secondary index for name lookups
  global_secondary_index {
    name     = "name-index"
    hash_key = "name"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
    
    projection_type = "ALL"
  }

  # Global secondary index for category-based queries
  global_secondary_index {
    name     = "category-index"
    hash_key = "category"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
    
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled = var.enable_encryption
  }

  point_in_time_recovery {
    enabled = var.environment == "prod"
  }

  tags = merge(local.common_tags, {
    Name = "Templates Table"
    Type = "templates"
  })
}

# DynamoDB table for outbox pattern
resource "aws_dynamodb_table" "outbox" {
  name           = local.table_names.outbox
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"

  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "notificationId"
    type = "S"
  }

  attribute {
    name = "priority"
    type = "S"
  }

  # Global secondary index for status-based queries
  global_secondary_index {
    name     = "status-index"
    hash_key = "status"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
    
    projection_type = "ALL"
  }

  # Global secondary index for notification ID lookups
  global_secondary_index {
    name     = "notificationId-index"
    hash_key = "notificationId"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
    
    projection_type = "ALL"
  }

  # Global secondary index for priority-based processing
  global_secondary_index {
    name     = "priority-index"
    hash_key = "priority"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
    
    projection_type = "ALL"
  }

  # Enable streams for outbox processing
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # TTL for automatic cleanup
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  server_side_encryption {
    enabled = var.enable_encryption
  }

  point_in_time_recovery {
    enabled = var.environment == "prod"
  }

  tags = merge(local.common_tags, {
    Name = "Outbox Table"
    Type = "outbox"
  })
}

# Auto scaling for DynamoDB tables (if enabled and provisioned)
resource "aws_appautoscaling_target" "subscribers_read" {
  count              = var.enable_auto_scaling && var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0
  max_capacity       = 100
  min_capacity       = var.dynamodb_read_capacity
  resource_id        = "table/${aws_dynamodb_table.subscribers.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_target" "subscribers_write" {
  count              = var.enable_auto_scaling && var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0
  max_capacity       = 100
  min_capacity       = var.dynamodb_write_capacity
  resource_id        = "table/${aws_dynamodb_table.subscribers.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "subscribers_read" {
  count              = var.enable_auto_scaling && var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0
  name               = "${local.name_prefix}-subscribers-read-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.subscribers_read[0].resource_id
  scalable_dimension = aws_appautoscaling_target.subscribers_read[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.subscribers_read[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = var.auto_scaling_target_value
  }
}

resource "aws_appautoscaling_policy" "subscribers_write" {
  count              = var.enable_auto_scaling && var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0
  name               = "${local.name_prefix}-subscribers-write-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.subscribers_write[0].resource_id
  scalable_dimension = aws_appautoscaling_target.subscribers_write[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.subscribers_write[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = var.auto_scaling_target_value
  }
}