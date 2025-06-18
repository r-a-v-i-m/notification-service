# AWS Notification Service

A comprehensive, production-grade serverless notification service built on AWS with Terraform infrastructure as code.

## 🚀 Features

- **Multi-Channel Notifications**: Email (SES) and SMS (SNS) support
- **Outbox Pattern**: Ensures reliable message delivery with transactional guarantees
- **Dynamic Templates**: Handlebars-powered templates with variable substitution
- **Retry Mechanism**: Exponential backoff with dead letter queues
- **Production Monitoring**: CloudWatch metrics and comprehensive logging
- **Subscriber Management**: Full CRUD operations for subscriber management
- **Template Management**: Create, update, and manage notification templates
- **Bulk Operations**: Send notifications to multiple recipients efficiently
- **Scheduled Notifications**: Support for delayed notification delivery

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   API Gateway   │───▶│  Lambda (API)    │───▶│   DynamoDB      │
└─────────────────┘    └──────────────────┘    │   - Subscribers │
                                               │   - Templates   │
                                               │   - Outbox      │
                                               └─────────────────┘
                                                       │
                                                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│      SES        │◀───│ Lambda (Stream)  │◀───│ DynamoDB Stream │
│      SNS        │    │    Processor     │    └─────────────────┘
└─────────────────┘    └──────────────────┘           │
                              │                        │
                              ▼                        ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │      SQS        │───▶│ Lambda (DLQ)    │
                       │   (Dead Letter  │    │   Processor     │
                       │     Queue)      │    └─────────────────┘
                       └─────────────────┘
```

## 📋 Prerequisites

- AWS Account with appropriate permissions
- Node.js 18.x or later
- Terraform 1.0 or later
- AWS CLI configured with credentials

## 🔧 Installation & Deployment

### 1. Clone and Setup

```bash
git clone <repository-url>
cd notification-service
npm install
```

### 2. Configure AWS Credentials

```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, and region
```

### 3. Configure Terraform Variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:

```hcl
aws_region = "us-east-1"
environment = "dev"
project_name = "notification-service"
ses_from_email = "your-verified-email@domain.com"
```

### 4. Deploy to AWS

```bash
# Deploy everything
./deploy.sh

# Or step by step:
./deploy.sh build    # Build deployment package
./deploy.sh plan     # Plan Terraform deployment
./deploy.sh          # Full deployment
```

### 5. Verify Deployment

```bash
# Check health endpoint
curl https://your-api-gateway-url/health

# Expected response:
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "version": "1.0.0",
  "environment": "dev"
}
```

## 📖 API Documentation

### Base URL
Your API Gateway URL will be provided after deployment: `https://api-id.execute-api.region.amazonaws.com/dev`

### Authentication
Currently uses API Gateway without authentication. For production, consider adding API keys or AWS Cognito.

### Endpoints

#### Notifications

**Send Single Notification**
```bash
POST /notifications
Content-Type: application/json

{
  "type": "email",
  "recipient": "user@example.com",
  "templateId": "template-uuid",
  "variables": {
    "firstName": "John",
    "lastName": "Doe"
  },
  "priority": "normal",
  "scheduledAt": "2024-01-15T15:30:00Z" // Optional
}
```

**Send Bulk Notifications**
```bash
POST /notifications/bulk
Content-Type: application/json

{
  "notifications": [
    {
      "type": "email",
      "recipient": "user1@example.com",
      "templateId": "template-uuid",
      "variables": { "firstName": "John" }
    },
    {
      "type": "sms",
      "recipient": "+1234567890",
      "templateId": "sms-template-uuid",
      "variables": { "firstName": "Jane" }
    }
  ]
}
```

**Get Notification Status**
```bash
GET /notifications/{notificationId}
```

**Retry Failed Notifications**
```bash
POST /notifications/retry
```

#### Templates

**Create Template**
```bash
POST /templates
Content-Type: application/json

{
  "name": "Welcome Email",
  "description": "Welcome email for new users",
  "type": "email",
  "subject": "Welcome {{firstName}}!",
  "htmlBody": "<h1>Welcome {{firstName}} {{lastName}}!</h1><p>Thanks for joining us on {{currentDate}}!</p>",
  "textBody": "Welcome {{firstName}} {{lastName}}! Thanks for joining us on {{currentDate}}!",
  "category": "onboarding"
}
```

**Get Template**
```bash
GET /templates/{templateId}
```

**Update Template**
```bash
PUT /templates/{templateId}
Content-Type: application/json

{
  "name": "Updated Template Name",
  "subject": "Updated subject with {{variables}}"
}
```

**List Templates**
```bash
GET /templates?limit=50&lastKey=optional-pagination-key
```

**Delete Template**
```bash
DELETE /templates/{templateId}
```

#### Subscribers

**Create Subscriber**
```bash
POST /subscribers
Content-Type: application/json

{
  "email": "user@example.com",
  "phone": "+1234567890",
  "firstName": "John",
  "lastName": "Doe",
  "preferences": {
    "email": true,
    "sms": true,
    "categories": ["newsletter", "alerts"]
  }
}
```

**Get Subscriber**
```bash
GET /subscribers/{subscriberId}
```

**Update Subscriber**
```bash
PUT /subscribers/{subscriberId}
Content-Type: application/json

{
  "preferences": {
    "email": false,
    "sms": true,
    "categories": ["alerts"]
  }
}
```

**List Subscribers**
```bash
GET /subscribers?limit=50&lastKey=optional-pagination-key
```

**Delete Subscriber**
```bash
DELETE /subscribers/{subscriberId}
```

#### System Endpoints

**Health Check**
```bash
GET /health
```

**Get Statistics**
```bash
GET /stats
```

**Get Failed Notifications**
```bash
GET /outbox/failed
```

**Requeue Failed Notification**
```bash
POST /outbox/requeue/{outboxId}
```

## 🎯 Template Variables

Templates support Handlebars syntax with the following built-in variables:

- `{{currentDate}}` - Current date in locale format
- `{{currentTime}}` - Current time in locale format  
- `{{currentYear}}` - Current year
- Any custom variables passed in the notification request

**Example Template:**
```html
<h1>Hello {{firstName}} {{lastName}}!</h1>
<p>Welcome to our service on {{currentDate}}.</p>
<p>Your account ID is: {{accountId}}</p>
```

## 📊 Monitoring & Metrics

### CloudWatch Metrics

The service publishes custom metrics to CloudWatch under the `NotificationService` namespace:

- `notifications.created` - Total notifications created
- `notifications.sent` - Successfully sent notifications
- `notifications.failed` - Failed notifications
- `notifications.permanently_failed` - Permanently failed after max retries
- `api.requests` - API request count
- `api.response_time` - API response times
- `templates.used` - Template usage statistics
- `outbox.processed` - Outbox processing statistics

### Logs

All Lambda functions log to CloudWatch Logs with structured JSON logging:
- `/aws/lambda/dev-notification-service-api`
- `/aws/lambda/dev-notification-service-outbox-processor`
- `/aws/lambda/dev-notification-service-dlq-processor`

## 🔄 Outbox Pattern Implementation

The service implements the outbox pattern to ensure reliable message delivery:

1. **Write to Outbox**: Notifications are first written to the outbox table
2. **Stream Processing**: DynamoDB streams trigger processing of outbox entries
3. **Retry Logic**: Failed notifications are retried with exponential backoff
4. **Dead Letter Queue**: Permanently failed notifications go to DLQ for manual review

## 🧪 Testing

### Local Testing

```bash
# Run tests
npm test

# Run with coverage
npm run test:coverage
```

### Integration Testing

```bash
# Test API endpoints
curl -X POST https://your-api-gateway-url/templates \
  -H "Content-Type: application/json" \
  -d @test-template.json

# Test notification sending
curl -X POST https://your-api-gateway-url/notifications \
  -H "Content-Type: application/json" \
  -d '{
    "type": "email",
    "recipient": "test@example.com", 
    "templateId": "your-template-id",
    "variables": {"name": "Test User"}
  }'
```

## 🚨 Error Handling

The service provides detailed error responses:

```json
{
  "statusCode": 400,
  "error": "Validation Error",
  "message": "Template ID is required",
  "details": [
    {
      "message": "Template ID is required",
      "path": ["templateId"],
      "type": "any.required"
    }
  ]
}
```

Common HTTP status codes:
- `200` - Success
- `201` - Created
- `400` - Bad Request (validation error)
- `404` - Not Found
- `500` - Internal Server Error

## 🔒 Security Considerations

- **IAM Roles**: Lambda functions use least-privilege IAM roles
- **VPC**: Consider deploying Lambda functions in VPC for enhanced security
- **Encryption**: DynamoDB tables support encryption at rest
- **API Gateway**: Add API keys or AWS Cognito for authentication
- **Input Validation**: All inputs are validated using Joi schemas
- **Data Masking**: Sensitive data (emails, phone numbers) are masked in logs

## 📈 Performance Optimization

- **Lambda Concurrency**: Configure reserved concurrency based on SES/SNS limits
- **DynamoDB**: Uses on-demand billing for automatic scaling
- **Template Caching**: Compiled templates are cached in Lambda memory
- **Batch Processing**: Stream processor handles multiple records efficiently
- **Connection Reuse**: AWS SDK clients are reused across invocations

## 🧹 Maintenance

### Regular Tasks

**Cleanup Old Outbox Entries** (automated with TTL):
```bash
# TTL is set to 7 days automatically
# Manual cleanup if needed:
aws dynamodb scan --table-name dev-notification-service-outbox \
  --filter-expression "createdAt < :cutoff" \
  --expression-attribute-values '{":cutoff":{"S":"2024-01-01T00:00:00Z"}}'
```

**Monitor Failed Notifications**:
```bash
curl https://your-api-gateway-url/outbox/failed
```

**Requeue Failed Notifications**:
```bash
curl -X POST https://your-api-gateway-url/outbox/requeue/{outboxId}
```

## 🚀 Scaling Considerations

- **SES Limits**: Default 200 emails/day, request increase from AWS
- **SNS Limits**: Default 100 SMS/day, request increase from AWS  
- **Lambda Concurrency**: Default 1000 concurrent executions per region
- **DynamoDB**: On-demand billing auto-scales, consider provisioned for predictable workloads
- **API Gateway**: Default 10,000 requests/second, request increase if needed

## 🔧 Troubleshooting

### Common Issues

**1. SES Email Not Sending**
- Verify email address is verified in SES console
- Check SES sending limits
- Review CloudWatch logs for errors

**2. SMS Not Sending**
- Verify SNS permissions
- Check phone number format (+1234567890)
- Review SMS spending limits

**3. DynamoDB Throttling**
- Check CloudWatch metrics for throttling
- Consider increasing provisioned capacity
- Review access patterns

**4. Lambda Timeouts**
- Increase timeout in terraform configuration
- Review CloudWatch logs for bottlenecks
- Consider increasing memory allocation

### Debug Commands

```bash
# Check Lambda logs
aws logs tail /aws/lambda/dev-notification-service-api

# Check DynamoDB table status
aws dynamodb describe-table --table-name dev-notification-service-outbox

# Test SES configuration
aws ses get-send-quota
aws ses get-send-statistics
```

## 🧹 Cleanup

To remove all AWS resources:

```bash
./deploy.sh destroy
```

This will:
- Delete all Lambda functions
- Remove DynamoDB tables
- Delete API Gateway
- Remove IAM roles and policies
- Clean up CloudWatch logs

## 📄 License

MIT License - see LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Submit a pull request

## 📞 Support

For issues and questions:
1. Check the troubleshooting section
2. Review CloudWatch logs
3. Open an issue in the repository